import Foundation

public enum CodexWork: Equatable, Sendable {
    case manual, ask, notes, shortAnswer, followUps, completion
    case automaticAnswer
    case grouping
    public var label: String {
        switch self { case .manual: return "Manual Answer"; case .ask:return "Ask";case .notes:return "Session notes / review";case .shortAnswer:return "Short answer";case .followUps:return "Follow-up suggestions";case .completion:return "Completion"; case .automaticAnswer: return "Automatic answer"; case .grouping: return "Topic grouping" }
    }
    var isBackground: Bool { self == .automaticAnswer || self == .grouping }
}

public enum CodexRequestContext {
    @TaskLocal public static var work: CodexWork = .manual
}

/// One upstream turn at a time across grouping, automatic drafts, answers and completions.
/// Rejected turns are never automatically replayed. Cooldown gates subsequent explicit attempts.
public actor CodexRequestScheduler {
    private struct Job {
        let id: UUID
        let work: CodexWork
        let enqueuedAt:TimeInterval
        let operation: @Sendable () async throws -> String
        let completion: CheckedContinuation<String, Error>
    }
    private var queue: [Job] = []
    private var active: (job: Job, task: Task<Void, Never>)?
    private var cancelled = Set<UUID>()
    private var wake: Task<Void, Never>?
    private var nextStart: TimeInterval = 0
    private var nextBackground: TimeInterval = 0
    private var cooldownUntil: TimeInterval = 0
    private var failures = 0
    private var cooldownFailure = CodexFailure.rateLimited(retryAfter:nil)
    private var accountFailure: CodexFailure?
    private let now: @Sendable () -> TimeInterval
    private let spacing: TimeInterval
    private let backgroundSpacing: TimeInterval
    private let jitter: @Sendable () -> TimeInterval

    public init(spacing: TimeInterval = 1, backgroundSpacing: TimeInterval = 10,
                now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                jitter: @escaping @Sendable () -> TimeInterval = { Double.random(in:0...3) }) {
        self.spacing=spacing; self.backgroundSpacing=backgroundSpacing; self.now=now; self.jitter=jitter
    }

    public func run(work: CodexWork, operation: @escaping @Sendable () async throws -> String) async throws -> String {
        try Task.checkCancellation()
        let id=UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { completion in
                guard !Task.isCancelled else { completion.resume(throwing:CancellationError());return }
                let remaining=cooldownUntil-now()
                guard remaining <= 0 else { completion.resume(throwing:CodexFailure(message:cooldownFailure.message,category:.rateLimit,statusCode:cooldownFailure.statusCode,retryAfter:remaining,providerCode:cooldownFailure.providerCode,rpcCode:cooldownFailure.rpcCode));return }
                if work.isBackground,let accountFailure { completion.resume(throwing:accountFailure);return }
                if work.isBackground {
                    let replaced=queue.filter { $0.work == work }
                    queue.removeAll { $0.work == work }
                    replaced.forEach { $0.completion.resume(throwing:CancellationError()) }
                }
                guard queue.count < 6 else { completion.resume(throwing:CodexFailure(message:"Request queue full. Wait for the current answer.",category:.busy));return }
                queue.append(Job(id:id,work:work,enqueuedAt:now(),operation:operation,completion:completion))
                if !work.isBackground, let active, active.job.work.isBackground {
                    cancelled.insert(active.job.id);active.task.cancel()
                }
                pump()
            }
        } onCancel: { Task { await self.cancel(id) } }
    }

    private func cancel(_ id: UUID) {
        if let index=queue.firstIndex(where:{$0.id == id}) {
            queue.remove(at:index).completion.resume(throwing:CancellationError());pump()
        } else if active?.job.id == id {
            cancelled.insert(id);active?.task.cancel()
        }
    }

    private func pump() {
        wake?.cancel();wake=nil
        guard active == nil, !queue.isEmpty else { return }
        let index=queue.firstIndex(where:{!$0.work.isBackground}) ?? 0
        let job=queue[index]
        if job.work.isBackground,now()-job.enqueuedAt>20 {
            queue.remove(at:index).completion.resume(throwing:CancellationError());pump();return
        }
        let delay=max(nextStart,job.work.isBackground ? nextBackground : 0)-now()
        if delay > 0 {
            wake=Task { do { try await Task.sleep(for:.seconds(delay)); self.pump() } catch {} }
            return
        }
        queue.remove(at:index)
        nextStart=now()+spacing
        if job.work.isBackground { nextBackground=now()+backgroundSpacing }
        let task=Task {
            let result:Result<String,Error>
            do { try Task.checkCancellation(); result = .success(try await job.operation()) }
            catch { result = .failure(error) }
            self.finished(job,result)
        }
        active=(job,task)
    }

    private func finished(_ job: Job, _ result: Result<String, Error>) {
        guard active?.job.id == job.id else { return }
        active=nil
        var delivered=result
        if case let .failure(error)=result, let failure=error as? CodexFailure, failure.category == .rateLimit {
            failures=min(failures+1,5)
            let delay=max(failure.retryAfter ?? 0,min(300,30*pow(2,Double(failures-1))))+max(0,jitter())
            cooldownUntil=now()+delay
            let limited=CodexFailure(message:failure.message,category:.rateLimit,statusCode:failure.statusCode,retryAfter:delay,providerCode:failure.providerCode,rpcCode:failure.rpcCode)
            cooldownFailure=limited
            delivered = .failure(limited)
            let waiting=queue;queue=[]
            waiting.forEach { $0.completion.resume(throwing:limited) }
        } else if case let .failure(error)=result,let failure=error as? CodexFailure,[.authentication,.usageLimit].contains(failure.category) {
            accountFailure=failure
            let waiting=queue;queue=[]
            waiting.forEach { $0.completion.resume(throwing:failure) }
        } else if case .success=result, !cancelled.contains(job.id) { failures=0;accountFailure=nil }
        if cancelled.remove(job.id) != nil { job.completion.resume(throwing:CancellationError()) }
        else { job.completion.resume(with:delivered) }
        pump()
    }
}
