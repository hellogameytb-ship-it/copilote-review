import CopiloteKit
import Foundation

// `make index DIR=…` / `make search Q=…`: the personal base without the app.
//
//   copilote-index index <dir> --store <dir> [--photos <dir>]… [--provider codex|anthropic|none]
//                  [--web <folder>] [--captions] [--offline]
//   copilote-index search --store <dir> [--today AAAA-MM-JJ] [--mode show|suggest|off] "question"

nonisolated(unsafe) var codexServer: CodexAppServer?

func quit(_ status: Int32) -> Never {
    codexServer?.terminateNow()
    exit(status)
}

func value(_ option: String, in arguments: [String]) -> String? {
    arguments.firstIndex(of: option).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
}

func values(_ option: String, in arguments: [String]) -> [String] {
    arguments.indices.filter { arguments[$0] == option && arguments.indices.contains($0 + 1) }.map { arguments[$0 + 1] }
}

/// The last argument that is neither an option nor an option's value.
func positional(_ arguments: [String], options: Set<String>) -> String? {
    arguments.indices.last { index in
        !arguments[index].hasPrefix("--") && !(index > 0 && options.contains(arguments[index - 1]))
    }.map { arguments[$0] }
}

func makeProvider(_ name: String) -> (any LLMProvider)? {
    switch name {
    case "none":
        return nil
    case "anthropic":
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else { return nil }
        return AnthropicProvider(client: AnthropicClient(), apiKey: key, settings: ModelSettings(model: ModelSettings.defaultModel))
    default:
        guard let executable = CodexAvailability.locate(), CodexAvailability.isReady(executable: executable) else { return nil }
        let server = CodexAppServer(
            executable: executable, workingDirectory: CodexAvailability.workingDirectory,
            privateDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("copilote-index-codex-private"),
            loadUserConfig: { try CodexAvailability.userConfig() }
        )
        codexServer = server
        return CodexProvider(server: server, answerModel: CodexProvider.defaultModel, topicModel: CodexProvider.defaultModel, serviceTier: "priority")
    }
}

func embedder() async -> TextEmbedder {
    if let model = await ContextualEmbedder.prepare() { return model }
    print("(vecteurs désactivés : modèle NaturalLanguage indisponible)")
    return NoEmbedder()
}

func ms(_ duration: Duration) -> String {
    String(format: "%.0f ms", Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15)
}

func index(_ arguments: [String]) async throws {
    let options: Set<String> = ["--store", "--photos", "--provider", "--web"]
    guard let dir = positional(arguments, options: options), let store = value("--store", in: arguments) else {
        print("usage: copilote-index index <dossier> --store <dossier>"); quit(2)
    }
    let offline = arguments.contains("--offline")
    let providerName = offline ? "none" : value("--provider", in: arguments) ?? "codex"
    let provider = makeProvider(providerName)
    let web = URL(fileURLWithPath: value("--web", in: arguments) ?? "Copilote/Resources/web")
    let storeURL = URL(fileURLWithPath: store)
    let base = try BaseIndex(url: storeURL.appendingPathComponent("index.sqlite"))
    let indexer = BaseIndexer(
        index: base, embedder: await embedder(), store: storeURL,
        places: offline ? nil : GeocoderPlaceNamer(), labeler: VisionLabeler(),
        captioner: arguments.contains("--captions") ? provider.map(LLMPhotoCaptioner.init) : nil,
        diagrams: provider.map { LLMDiagramMaker(provider: $0, webFolder: web) }
    )
    print("Indexation de \(dir) → \(store)")
    print("Diagrammes : \(provider.map { $0.label } ?? "désactivés (\(offline ? "--offline" : "aucun fournisseur prêt"))") · lieux : \(offline ? "désactivés" : "géocodage inverse, mis en cache")")
    let report = try await indexer.run(BaseSource(
        root: URL(fileURLWithPath: dir), photoFolders: values("--photos", in: arguments).map { URL(fileURLWithPath: $0) }
    ))
    print("Fichiers : \(report.scannedFiles) lus, \(report.changedFiles) (ré)indexés, \(report.removedFiles) retirés")
    print("Éléments : \(report.items) dont \(report.photos) photos · \(ms(report.elapsed))")
    for (project, status) in report.diagrams.sorted(by: { $0.key < $1.key }) {
        print("Diagramme \(project) : \(status.rawValue)")
    }
    for problem in report.problems { print("Problème : \(problem)") }
}

func search(_ arguments: [String]) async throws {
    let options: Set<String> = ["--store", "--today", "--mode"]
    guard let question = positional(arguments, options: options), let store = value("--store", in: arguments) else {
        print("usage: copilote-index search --store <dossier> \"question\""); quit(2)
    }
    let today = value("--today", in: arguments).flatMap(CalendarDay.init(iso:)) ?? .today()
    let mode = value("--mode", in: arguments).flatMap(PersonalRouter.Mode.init(rawValue:)) ?? .show
    let base = try BaseIndex(url: URL(fileURLWithPath: store).appendingPathComponent("index.sqlite"))
    let embedder = await embedder()
    let search = BaseSearch(index: base, embedder: embedder)
    await search.warmUp()  // as the app does at launch
    let result = try await search.search(question, today: today)
    let decision = result.decision(mode: mode)
    let intent = result.intent
    print("« \(question) » · \(base.itemCount) éléments · aujourd'hui \(today)")
    print("Intention : \(intent.isPersonal ? "perso" : "pas perso") · types \(intent.kinds.map(\.rawValue).sorted().joined(separator: ", ").ifEmpty("tous"))"
        + (intent.period.map { " · période \($0.start) → \($0.end)" } ?? "")
        + " · mots \(intent.terms.map(\.word).joined(separator: ", ").ifEmpty("—"))")
    for (rank, hit) in result.hits.prefix(5).enumerated() {
        print(String(format: "  %d. %@ [%@] · confiance %.2f", rank + 1, hit.item.label, hit.item.kind.rawValue, hit.confidence))
    }
    let verdict: String
    switch decision.action {
    case .show: verdict = "FICHE DIRECTE"
    case .suggest: verdict = "suggestion de fiche (le LLM répond si on choisit la case)"
    case .llm: verdict = "chemin LLM"
    }
    print("Décision : \(verdict) · recherche \(ms(result.elapsed))")
    if let item = decision.item, decision.action != .llm, item.kind == .trip {
        let photos = try await search.photos(for: item)
        print("  Grille : \(photos.count) photos (\(photos.compactMap(\.place).uniqued().joined(separator: ", ")))")
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch arguments.first {
    case "index": try await index(Array(arguments.dropFirst()))
    case "search": try await search(Array(arguments.dropFirst()))
    default: print("usage: copilote-index index|search …"); quit(2)
    }
    quit(0)
} catch {
    print("échec : \((error as? CodexFailure)?.userMessage ?? "\(error)")")
    quit(1)
}
