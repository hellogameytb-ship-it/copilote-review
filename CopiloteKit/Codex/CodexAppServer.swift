import Foundation

/// One `codex app-server` process kept warm for the whole app: each request opens an ephemeral
/// thread (see `CodexRPC`), streams the answer, then releases the thread. The ChatGPT login of
/// the CLI is used as is; no token is read or copied by Copilote.
public actor CodexAppServer {
    public struct TurnRequest: Sendable {
        public let model: String
        public let serviceTier: String?
        public let instructions: String
        public let input: [JSONValue]
        public let outputSchema: JSONValue?
        /// The turn fails after this: a stuck answer must not block its caller.
        public let timeout: Duration
        public let work: CodexWork

        public init(
            model: String, serviceTier: String?, instructions: String, input: [JSONValue],
            outputSchema: JSONValue? = nil, timeout: Duration = .seconds(120), work: CodexWork = .manual
        ) {
            self.model = model
            self.serviceTier = serviceTier
            self.instructions = instructions
            self.input = input
            self.outputSchema = outputSchema
            self.timeout = timeout
            self.work = work
        }
    }

    private struct Session {
        var turn = CodexTurn()
        var turnID: String?
        var stoppingError: Error?
        var expiry: Task<Void, Never>?
        var interruptionDeadline: Task<Void, Never>?
        let requestID: UUID
        let request: TurnRequest
        let onText: @Sendable (String) async -> Void
        let completion: CheckedContinuation<String, Error>
    }

    /// The running process. Writes go through a serial queue, off the actor: a large request
    /// (captures) must not keep the actor from reading the process's output.
    private final class Connection: @unchecked Sendable {
        let process: Process
        private let input: FileHandle
        private let writer = DispatchQueue(label: "org.example.copilote.codex-writer")

        init(process: Process, input: FileHandle) {
            self.process = process
            self.input = input
            // A write to a process that just died must fail, not kill Copilote with SIGPIPE.
            _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        }

        func write(_ message: JSONValue) {
            guard let data = try? JSONEncoder().encode(message) else { return }
            writer.async { [input] in try? input.write(contentsOf: data + Data("\n".utf8)) }
        }
    }

    /// For `terminateNow()`, callable from any thread while the app quits.
    private final class ProcessSlot: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?

        func set(_ process: Process?) { lock.withLock { self.process = process } }

        func terminate() {
            lock.withLock {
                guard let process, process.isRunning else { return }
                process.terminate()
                // Its last log lines must land before the private directory is wiped.
                let deadline = Date().addingTimeInterval(0.5)
                while process.isRunning, Date() < deadline { usleep(10_000) }
            }
        }
    }

    private let executable: URL
    private let workingDirectory: URL
    /// Codex's own logs and databases for this process (they hold request text): wiped.
    private let privateDirectory: URL
    private let loadUserConfig: @Sendable () throws -> String?
    private let slot = ProcessSlot()
    private var connection: Connection?
    /// Tells a late termination handler or reader of an old process from the current one.
    private var generation = 0
    private var starting: Task<Void, Error>?
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var rpcDeadlines: [Int:Task<Void,Never>] = [:]
    private var sessions: [String: Session] = [:]
    private let scheduler: CodexRequestScheduler
    private let onDiagnostic: @Sendable (CodexRequestDiagnostic) -> Void
    private var interruptUnconfirmed = false

    /// `loadUserConfig` returns the user's `~/.codex/config.toml`, read at every launch to switch
    /// its MCP servers off; when it throws, Codex is not started.
    public init(
        executable: URL, workingDirectory: URL, privateDirectory: URL,
        loadUserConfig: @escaping @Sendable () throws -> String?,
        scheduler: CodexRequestScheduler = CodexRequestScheduler(),
        onDiagnostic: @escaping @Sendable (CodexRequestDiagnostic) -> Void = { _ in }
    ) {
        self.executable = executable
        self.workingDirectory = workingDirectory
        self.privateDirectory = privateDirectory
        self.loadUserConfig = loadUserConfig
        self.scheduler = scheduler; self.onDiagnostic = onDiagnostic
    }

    // MARK: Turns

    /// Streams one answer; returns its final text. Cancelling the calling task interrupts the turn.
    public func run(_ request: TurnRequest, onText: @escaping @Sendable (String) async -> Void) async throws -> String {
        let id=UUID()
        record(id,request,"queued")
        do {
            let text=try await scheduler.run(work:request.work) {
                await self.record(id,request,"started")
                return try await self.runAdmitted(request,id:id,onText:onText)
            }
            record(id,request,"completed")
            return text
        } catch {
            record(id,request,error is CancellationError ? "cancelled" : "failed",error:error)
            throw error
        }
    }

    private func record(_ id:UUID,_ request:TurnRequest,_ phase:String,error:Error? = nil,retrying:Bool = false) {
        onDiagnostic(CodexRequestDiagnostic(requestID:id,work:request.work,model:request.model,phase:phase,error:error,upstreamRetrying:retrying))
    }

    private func runAdmitted(_ request:TurnRequest,id:UUID,onText:@escaping @Sendable (String) async -> Void) async throws -> String {
        try Task.checkCancellation()
        guard !interruptUnconfirmed else { throw CodexFailure(message:"Waiting for the interrupted Codex process to stop.",category:.busy) }
        try await start()
        try Task.checkCancellation()
        record(id,request,"thread/start")
        let thread = try await call {
            CodexRPC.threadStart(
                id: $0, model: request.model, workingDirectory: workingDirectory.path,
                baseInstructions: request.instructions, serviceTier: request.serviceTier
            )
        }
        guard let threadID = thread["thread"]?["id"]?.stringValue else { throw CodexFailure(message: "thread sans identifiant") }
        if Task.isCancelled { send { CodexRPC.threadUnsubscribe(id:$0,threadID:threadID) }; throw CancellationError() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sessions[threadID] = Session(requestID:id,request:request,onText:onText,completion:continuation)
                Task { await self.startTurn(threadID, request) }
                sessions[threadID]?.expiry = Task {
                    do { try await Task.sleep(for:request.timeout) } catch { return }
                    self.abandon(threadID,with:CodexFailure(message:"Response timed out",category:.timeout))
                }
                if Task.isCancelled { self.abandon(threadID,with:CancellationError()) }
            }
        } onCancel: {
            Task { await self.abandon(threadID, with: CancellationError()) }
        }
    }

    private func startTurn(_ threadID: String, _ request: TurnRequest) async {
        guard let session=sessions[threadID] else { return }
        if let error=session.stoppingError { finish(threadID,with:.failure(error));return }
        do {
            record(session.requestID,request,"turn/start")
            let result = try await call {
                CodexRPC.turnStart(id: $0, threadID: threadID, input: request.input, effort: "low", outputSchema: request.outputSchema)
            }
            let turnID = result["turn"]?["id"]?.stringValue
            if sessions[threadID] != nil {
                sessions[threadID]?.turnID = turnID
                if sessions[threadID]?.stoppingError != nil,let turnID { send { CodexRPC.turnInterrupt(id:$0,threadID:threadID,turnID:turnID) } }
            } else if let turnID {
                // Abandoned before Codex acknowledged the turn: stop it now.
                send { CodexRPC.turnInterrupt(id: $0, threadID: threadID, turnID: turnID) }
            }
        } catch {
            // A lost turn/start acknowledgement may still have started upstream work.
            if (error as? CodexFailure)?.category == .timeout {
                interruptUnconfirmed=true
                connection?.process.terminate()
            }
            finish(threadID, with: .failure(sessions[threadID]?.stoppingError ?? error))
        }
    }

    /// Interruption is best effort. Keep the scheduler slot until terminal notification;
    /// if it never arrives, terminate this owned transport and block new work until it exits.
    private func abandon(_ threadID: String, with error: Error) {
        guard let session=sessions[threadID],session.stoppingError == nil else { return }
        sessions[threadID]?.stoppingError=error
        if let turnID=session.turnID { send { CodexRPC.turnInterrupt(id:$0,threadID:threadID,turnID:turnID) } }
        sessions[threadID]?.interruptionDeadline=Task {
            do { try await Task.sleep(for:.seconds(5)) } catch { return }
            guard self.sessions[threadID] != nil else { return }
            self.interruptUnconfirmed=true
            self.connection?.process.terminate()
            self.finish(threadID,with:.failure(error))
        }
    }

    private func finish(_ threadID: String, with result: Result<String, Error>) {
        guard let session = sessions.removeValue(forKey: threadID) else { return }
        session.expiry?.cancel(); session.interruptionDeadline?.cancel()
        session.completion.resume(with: result)
        send { CodexRPC.threadUnsubscribe(id: $0, threadID: threadID) }
    }

    // MARK: Process

    /// Starts the process and the handshake once; concurrent and later calls share that start.
    public func start() async throws {
        guard !interruptUnconfirmed else { throw CodexFailure(message:"Waiting for interrupted transport to exit",category:.busy) }
        if let starting {
            try await starting.value
            if connection?.process.isRunning == true { return }
        }
        let task = Task { try await launch() }
        starting = task
        do {
            try await task.value
        } catch {
            starting = nil
            throw error
        }
    }

    public func stop() {
        connection?.process.terminate()
        terminated(generation: generation)
    }

    /// Synchronous, for the app's last moments: the process goes, and with it the private logs.
    public nonisolated func terminateNow() {
        slot.terminate()
        try? FileManager.default.removeItem(at: privateDirectory)
    }

    private func launch() async throws {
        let userConfig = try loadUserConfig()
        if let problem = CodexLaunch.problem(inUserConfig: userConfig ?? "") { throw CodexFailure(message: problem) }
        // Leftovers of a previous run (crash) go before starting again.
        try? FileManager.default.removeItem(at: privateDirectory)
        try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = executable
        process.arguments = CodexLaunch.arguments(userConfig: userConfig, privateDirectory: privateDirectory.path)
        process.currentDirectoryURL = workingDirectory
        process.environment = CodexLaunch.environment(
            base: ProcessInfo.processInfo.environment, executable: executable, privateDirectory: privateDirectory.path
        )
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        generation += 1
        let generation = generation
        process.terminationHandler = { [weak self] _ in
            Task { await self?.terminated(generation: generation) }
        }
        try process.run()
        connection = Connection(process: process, input: stdin.fileHandleForWriting)
        slot.set(process)
        Task { [weak self] in
            await Self.readLines(from: stdout.fileHandleForReading) { line in
                await self?.handle(CodexMessage(line: line), generation: generation)
            }
        }
        do {
            _ = try await call { CodexRPC.initialize(id: $0) }
        } catch {
            process.terminate()
            throw error
        }
        connection?.write(CodexRPC.initialized)
    }

    /// Lines end with "\n" only: a JSON string may hold U+2028, which `bytes.lines` splits on.
    private static func readLines(from handle: FileHandle, _ consume: (String) async -> Void) async {
        var line = Data()
        do {
            for try await byte in handle.bytes {
                if byte == UInt8(ascii: "\n") {
                    await consume(String(decoding: line, as: UTF8.self))
                    line.removeAll(keepingCapacity: true)
                } else {
                    line.append(byte)
                }
            }
        } catch {}
    }

    /// Only for the current process: a late handler must not tear down its replacement.
    private func terminated(generation ended: Int) {
        guard ended == generation, connection != nil || starting != nil else { return }
        interruptUnconfirmed=false
        let failure = CodexFailure(message: "the Codex process stopped",category:.network)
        pending.values.forEach { $0.resume(throwing: failure) }
        pending.removeAll()
        rpcDeadlines.values.forEach { $0.cancel() };rpcDeadlines.removeAll()
        sessions.values.forEach { $0.expiry?.cancel();$0.interruptionDeadline?.cancel();$0.completion.resume(throwing:$0.stoppingError ?? failure) }
        sessions.removeAll()
        connection = nil
        starting = nil
        slot.set(nil)
        try? FileManager.default.removeItem(at: privateDirectory)
    }

    // MARK: JSON-RPC

    private func call(timeout: Duration = .seconds(20), _ message: (Int) -> JSONValue) async throws -> JSONValue {
        guard let connection, connection.process.isRunning else { throw CodexFailure(message: "Codex is not running") }
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            connection.write(message(id))
            rpcDeadlines[id]=Task {
                do { try await Task.sleep(for:timeout) } catch { return }
                self.expire(id)
            }
        }
    }

    /// A request whose answer nobody waits for (interrupt, release).
    private func send(_ message: (Int) -> JSONValue) {
        nextID += 1
        connection?.write(message(nextID))
    }

    private func expire(_ id: Int) {
        rpcDeadlines.removeValue(forKey:id)?.cancel()
        pending.removeValue(forKey: id)?.resume(throwing: CodexFailure(message: "Codex is not responding",category:.timeout))
    }

    private func handle(_ message: CodexMessage, generation from: Int) async {
        guard from == generation else { return }
        switch message {
        case let .response(id, result):
            rpcDeadlines.removeValue(forKey:id)?.cancel()
            pending.removeValue(forKey: id)?.resume(returning: result)
        case let .responseError(id, text):
            rpcDeadlines.removeValue(forKey:id)?.cancel()
            pending.removeValue(forKey: id)?.resume(throwing: CodexFailure(message: text))
        case let .providerFailure(threadID, rpcID, failure, retrying, terminal):
            if let rpcID { rpcDeadlines.removeValue(forKey:rpcID)?.cancel();pending.removeValue(forKey:rpcID)?.resume(throwing:failure) }
            if let threadID,let session=sessions[threadID] {
                record(session.requestID,session.request,retrying ? "upstream retry" : "provider error",error:failure,retrying:retrying)
                // A 429 stops upstream retrying at its first observable signal.
                if terminal { finish(threadID,with:.failure(session.stoppingError ?? failure)) }
                else if [.rateLimit,.usageLimit,.authentication].contains(failure.category) { abandon(threadID,with:failure) }
                else if !retrying { abandon(threadID,with:failure) }
            }
        case let .serverRequest(id, _):
            connection?.write(CodexRPC.refusal(of: id))
        case let .agentDelta(threadID, _), let .agentMessageCompleted(threadID, _),
             let .error(threadID, _, _), let .turnCompleted(threadID, _):
            if let error=sessions[threadID]?.stoppingError {
                if case .turnCompleted=message { finish(threadID,with:.failure(error)) }
                return
            }
            if case let .error(_,text,true)=message,let session=sessions[threadID] { record(session.requestID,session.request,"upstream retry",error:CodexFailure(message:text),retrying:true) }
            if let shown = sessions[threadID]?.turn.apply(message), let onText = sessions[threadID]?.onText {
                await onText(shown)
            }
            if let result = sessions[threadID]?.turn.result {
                finish(threadID, with: result.mapError { $0 as Error })
            }
        case .other:
            break
        }
    }
}
