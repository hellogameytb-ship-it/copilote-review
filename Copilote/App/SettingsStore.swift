import CopiloteKit
import Foundation

/// User settings (UserDefaults) and the API key (Keychain only, cached in memory once read).
@MainActor
final class SettingsStore: ObservableObject {
    /// "default" leaves the effort parameter out of the request.
    static let effortChoices: [(value: String, label: String)] = [
        ("low", "Low (fastest)"),
        ("medium", "Medium"),
        ("high", "High"),
        ("default", "Model default"),
    ]

    let defaults: UserDefaults

    @Published var model: String {
        didSet { defaults.set(model, forKey: "model") }
    }

    @Published var effort: String {
        didSet { defaults.set(effort, forKey: "effort") }
    }

    /// Who answers: automatic (Codex when installed and logged in), Codex, or Anthropic.
    @Published var provider: String {
        didSet { defaults.set(provider, forKey: "provider") }
    }

    /// Codex model (ChatGPT accounts list gpt-5.6-luna, -sol, -terra).
    @Published var codexModel: String {
        didSet { defaults.set(codexModel, forKey: "codexModel") }
    }

    /// Codex "Fast" service tier: 1.5× speed, uses more of the subscription. Defaults to the
    /// user's own Codex setting (`service_tier = "priority"`).
    @Published var codexFast: Bool {
        didSet { defaults.set(codexFast, forKey: "codexFast") }
    }

    /// The personal base's folder (source of truth), `~/Copilote` by default.
    @Published var baseFolder: String {
        didSet { defaults.set(baseFolder, forKey: "baseFolder") }
    }

    /// Photo folders added by hand (nothing else outside the base is read).
    @Published var basePhotoFolders: [String] {
        didSet { defaults.set(basePhotoFolders, forKey: "basePhotoFolders") }
    }

    /// Personal questions: show the fiche at once, suggest it, or leave everything to the LLM.
    @Published var baseMode: String {
        didSet { defaults.set(baseMode, forKey: "baseMode") }
    }

    /// One-sentence photo captions by the LLM at indexing (sends the photos out): off by default.
    @Published var basePhotoCaptions: Bool {
        didSet { defaults.set(basePhotoCaptions, forKey: "basePhotoCaptions") }
    }

    /// Step 4: the mode a session starts in (Réunion, Technique, Entre potes, Présentation).
    @Published var defaultMode: String {
        didSet { defaults.set(defaultMode, forKey: "defaultMode") }
    }

    /// End-of-meeting notes when listening stops (keeps the whole transcript in memory meanwhile).
    @Published var notesAtEnd: Bool {
        didSet { defaults.set(notesAtEnd, forKey: "notesAtEnd") }
    }

    /// Advice on the user's own phrases after the meeting: off by default.
    @Published var selfReview: Bool {
        didSet { defaults.set(selfReview, forKey: "selfReview") }
    }

    /// Sessions written to disk (transcript included): off by default, as decided at step 2.
    @Published var keepHistory: Bool {
        didSet { defaults.set(keepHistory, forKey: "keepHistory") }
    }

    /// Days a session is kept; 0 = forever.
    @Published var historyRetentionDays: Int {
        didSet { defaults.set(historyRetentionDays, forKey: "historyRetentionDays") }
    }

    @Published var menuBarIcon: Bool {
        didSet { defaults.set(menuBarIcon, forKey: "menuBarIcon") }
    }

    /// Mode furtif: out of the Dock and ⌘Tab (`.accessory`); the overlay stays visible to the user,
    /// excluded from screen sharing as always. On by default (the user, retours 5).
    @Published var stealth: Bool {
        didSet { defaults.set(stealth, forKey: "stealth") }
    }

    /// The welcome's step, kept until it is done: a relaunch asked by macOS resumes it there.
    var onboardingStep: Int {
        get { defaults.integer(forKey: "onboardingStep") }
        set { defaults.set(newValue, forKey: "onboardingStep") }
    }

    @Published var onboardingDone: Bool {
        didSet { defaults.set(onboardingDone, forKey: "onboardingDone") }
    }

    /// Where the pill sits on each screen.
    var placement: OverlayPlacement {
        get { defaults.data(forKey: "placement").flatMap { try? JSONDecoder().decode(OverlayPlacement.self, from: $0) } ?? OverlayPlacement() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "placement") }
    }

    var mode: MeetingMode { MeetingMode(rawValue: defaultMode) ?? .meeting }

    /// Who the user talks to and how to answer, sent with every request (Cluely's custom prompt).
    @Published var answerInstructions: String {
        didSet { defaults.set(answerInstructions, forKey: "answerInstructions") }
    }

    /// The answers' language: the question's own, or always French / English.
    @Published var answerLanguage: String {
        didSet { defaults.set(answerLanguage, forKey: "answerLanguage") }
    }

    var answerPreferences: AnswerPreferences {
        AnswerPreferences(instructions: answerInstructions, language: AnswerPreferences.Language(rawValue: answerLanguage) ?? .english)
    }

    @Published var overlayBackground: OverlayBackgroundMode {
        didSet { defaults.set(overlayBackground.rawValue, forKey: "overlayBackground") }
    }

    /// Background density only; foreground content always stays opaque.
    @Published var overlayOpacity: Double {
        didSet { defaults.set(overlayOpacity, forKey: "overlayOpacity") }
    }

    /// The answer's zoom, 0.8 to 1.6 (⌥⌘= / ⌥⌘-).
    @Published var answerTextScale: Double {
        didSet { defaults.set(answerTextScale, forKey: "answerTextScale") }
    }

    static let opacityRange = 0.7...1.0

    /// Case 1's answer is drafted and shown by itself (a request per new question).
    @Published var autoAnswer: Bool {
        didSet { defaults.set(autoAnswer, forKey: "autoAnswer") }
    }

    @Published private(set) var hasAPIKey: Bool
    private var cachedKey: String?

    init(defaults: UserDefaults = .standard, loadCredentials: Bool = true) {
        self.defaults = defaults
        model = defaults.string(forKey: "model") ?? ModelSettings.defaultModel
        effort = defaults.string(forKey: "effort") ?? Effort.low.rawValue
        autoAnswer = defaults.object(forKey: "autoAnswer") as? Bool ?? true
        provider = defaults.string(forKey: "provider") ?? ProviderChoice.automatic.rawValue
        codexModel = defaults.string(forKey: "codexModel") ?? CodexProvider.defaultModel
        codexFast = defaults.object(forKey: "codexFast") as? Bool
            ?? (loadCredentials ? CodexLaunch.prefersFastTier(userConfig: try? CodexAvailability.userConfig()) : false)
        let savedBase = defaults.string(forKey: "baseFolder")
        baseFolder = savedBase == nil || savedBase == BaseScaffold.defaultRoot.path ? VaultPolicy.defaultRoot.path : savedBase!
        basePhotoFolders = defaults.stringArray(forKey: "basePhotoFolders") ?? []
        baseMode = defaults.string(forKey: "baseMode") ?? PersonalRouter.Mode.show.rawValue
        basePhotoCaptions = defaults.bool(forKey: "basePhotoCaptions")
        defaultMode = defaults.string(forKey: "defaultMode") ?? MeetingMode.meeting.rawValue
        notesAtEnd = defaults.object(forKey: "notesAtEnd") as? Bool ?? true
        selfReview = defaults.bool(forKey: "selfReview")
        keepHistory = defaults.bool(forKey: "keepHistory")
        historyRetentionDays = defaults.object(forKey: "historyRetentionDays") as? Int ?? 30
        menuBarIcon = defaults.bool(forKey: "menuBarIcon")
        onboardingDone = defaults.bool(forKey: "onboardingDone")
        stealth = defaults.object(forKey: "stealth") as? Bool ?? true
        answerInstructions = defaults.string(forKey: "answerInstructions") ?? ""
        if !defaults.bool(forKey: "englishDefaultV1") {
            defaults.set(AnswerPreferences.Language.english.rawValue, forKey: "answerLanguage")
            defaults.set(true, forKey: "englishDefaultV1")
        }
        answerLanguage = defaults.string(forKey: "answerLanguage") ?? AnswerPreferences.Language.english.rawValue
        let isNewAppearance = defaults.string(forKey: "overlayBackground") == nil
        overlayBackground = defaults.string(forKey: "overlayBackground").flatMap(OverlayBackgroundMode.init(rawValue:)) ?? .translucent
        if isNewAppearance {
            // Explicit human request: choose app translucency without changing macOS accessibility.
            defaults.set(OverlayBackgroundMode.translucent.rawValue, forKey: "overlayBackground")
            if (defaults.object(forKey: "overlayOpacity") as? Double ?? 1) == 1 { defaults.set(0.82, forKey: "overlayOpacity") }
        }
        overlayOpacity = (defaults.object(forKey: "overlayOpacity") as? Double)
            .map { min(max($0, Self.opacityRange.lowerBound), Self.opacityRange.upperBound) } ?? 0.82
        answerTextScale = (defaults.object(forKey: "answerTextScale") as? Double).map(TextScale.clamped) ?? 1
        hasAPIKey = loadCredentials && KeychainStore.hasAPIKey()
    }

    var modelSettings: ModelSettings {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return ModelSettings(model: trimmed.isEmpty ? ModelSettings.defaultModel : trimmed, effort: Effort(rawValue: effort))
    }

    var apiKey: String? {
        if cachedKey == nil { cachedKey = KeychainStore.readAPIKey() }
        return cachedKey
    }

    func saveAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, KeychainStore.saveAPIKey(trimmed) else { return false }
        cachedKey = trimmed
        hasAPIKey = true
        return true
    }

    func deleteAPIKey() {
        KeychainStore.deleteAPIKey()
        cachedKey = nil
        hasAPIKey = false
    }
}


enum OverlayBackgroundMode: String, CaseIterable {
    case system, translucent, opaque
    var name: String {
        switch self {
        case .system: return "System"
        case .translucent: return "Translucent"
        case .opaque: return "Opaque"
        }
    }
}
