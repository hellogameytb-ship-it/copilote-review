import AppKit
import CopiloteKit
import SwiftUI
import WebKit

// `make renders`: every step 3-4 screen as a PNG in docs/renders/, off-screen, fictional data
// only (Camille Ferrand, fixtures/base-demo). The SwiftUI views are drawn in a window that is
// never shown (cacheDisplay renders AppKit controls, ImageRenderer leaves them blank); the
// answer area is the real overlay page in an off-screen WKWebView, snapshotted.

let dark = Color(red: 0.11, green: 0.11, blue: 0.13)
let panelBackground = Color(red: 0.14, green: 0.14, blue: 0.17)

@MainActor
func render<V: View>(_ view: V, width: CGFloat, to name: String, background: Color = dark) throws {
    let host = NSHostingView(rootView: view.frame(width: width).padding(12).background(background).environment(\.colorScheme, .dark))
    host.appearance = NSAppearance(named: .darkAqua)
    let size = host.fittingSize
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let url = output.appendingPathComponent("\(name).png")
    try bitmap.representation(using: .png, properties: [:])?.write(to: url)
    print("→ docs/renders/\(name).png (\(bitmap.pixelsWide)×\(bitmap.pixelsHigh))")
}

struct RenderCheckFailed: Error, CustomStringConvertible {
    let description: String
}

/// The real answer page (Markdown, code highlighting, Mermaid), rendered and snapshotted.
@MainActor
final class AnswerSnapshot: NSObject, WKNavigationDelegate {
    private var loaded: CheckedContinuation<Void, Never>?

    /// `lead`: the opening sentence must lead (true) or there is none, the answer opening on a
    /// heading (false). A light UI test of the page's structural selector: the render fails otherwise.
    /// `extras`: more payload keys, e.g. `notice` or `copy` (as the app sends them).
    func image(markdown: String, size: CGSize, web: URL, lead: Bool? = nil, extras: [String: JSONValue] = [:]) async throws -> NSImage {
        let view = WKWebView(frame: NSRect(origin: .zero, size: size))
        view.navigationDelegate = self
        await withCheckedContinuation { continuation in
            loaded = continuation
            view.loadFileURL(web.appendingPathComponent("index.html"), allowingReadAccessTo: web)
        }
        let segments: [JSONValue] = ResponseSegmenter.segments(of: markdown, isFinal: true).map { segment in
            switch segment {
            case let .markdown(text): return ["kind": "markdown", "text": .string(text)]
            case let .diagram(source, complete): return ["kind": "diagram", "source": .string(source), "complete": .bool(complete)]
            }
        }
        let fields: [String: JSONValue] = ["answerId": 1, "segments": .array(segments)]
        let payload = String(decoding: try JSONEncoder().encode(JSONValue.object(fields.merging(extras) { $1 })), as: UTF8.self)
        // Off screen nothing animates: show the final state at once.
        _ = try await view.evaluateJavaScript("""
        const still = document.createElement('style');
        still.textContent = '*, *::before, *::after { animation: none !important; transition: none !important; }';
        document.head.appendChild(still);
        window.copilote.render(\(payload), true);
        """)
        try await Task.sleep(for: .milliseconds(900))
        if let lead {
            let size = try await view.evaluateJavaScript(
                "(() => { const p = document.querySelector('.chat-response > :first-child > p:first-child'); return p ? getComputedStyle(p).fontSize : 'none'; })()"
            ) as? String
            guard size == (lead ? "15px" : "none") else {
                throw RenderCheckFailed(description: "chapeau de la réponse : \(size ?? "?"), attendu \(lead ? "15px" : "aucun")")
            }
            print(lead ? "✓ la phrase à dire ouvre la réponse (15px)" : "✓ pas de chapeau quand la réponse s'ouvre sur un titre")
        }
        _ = try await view.evaluateJavaScript("document.getElementById('scroller').scrollTop = 0; window.scrollTo(0, 0); 0")
        try await Task.sleep(for: .milliseconds(150))
        return try await view.takeSnapshot(configuration: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }
}

let arguments = CommandLine.arguments
let store = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "build/base-index/base-demo")
let root = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "fixtures/base-demo")
let output = URL(fileURLWithPath: arguments.count > 3 ? arguments[3] : "docs/renders")
let web = URL(fileURLWithPath: "Copilote/Resources/web")

let mathAnswer = #"""
Chaque lancer suit une loi géométrique de paramètre $p = \tfrac{1}{6}$, donc $\mathbb{E}[N] = 1/p = 6$.

$$
\mathbb{E}[N] = \sum_{k \ge 1} k\,(1-p)^{k-1}\,p = \frac{1}{p}
$$

- Variance : \(\operatorname{Var}(N) = \frac{1-p}{p^2} = 30\).
- Le billet coûte $5 et le gain $10 : ces montants restent du texte.
- Formule mal fermée : $\frac{1}{$ s'affiche telle quelle.
"""#
let today = CalendarDay.day(2026, 10, 19)
let now = Date(timeIntervalSince1970: 1_792_419_000)

// MARK: Fictional session

let topics = [
    Topic(id: "t4", title: "Inverser une liste chaînée sans récursion", excerpt: ["Et sans récursion, tu ferais comment ?"], createdAt: now, updatedAt: now),
    Topic(id: "t3", title: "Date de sortie de Revisio", excerpt: ["On garde la sortie au 12 novembre ?"], createdAt: now.addingTimeInterval(-240), updatedAt: now.addingTimeInterval(-200)),
    Topic(id: "t2", title: "Qui gère le support au lancement", excerpt: ["Qui gère le support pendant le lancement ?"], createdAt: now.addingTimeInterval(-420), updatedAt: now.addingTimeInterval(-420), isPinned: true),
    Topic(id: "t1", title: "Retour sur la démo de jeudi", excerpt: ["Tu nous montres la démo jeudi ?"], createdAt: now.addingTimeInterval(-600), updatedAt: now.addingTimeInterval(-600)),
]
let keys = ["⌥1", "⌥2", "⌥3", "⌥4"]
let lines = [
    TranscriptLine(speaker: .them, text: "On garde la sortie au 12 novembre ?", start: 1, end: 3),
    TranscriptLine(speaker: .me, text: "Oui, si on repousse l'export PDF.", start: 4, end: 6),
    TranscriptLine(speaker: .them, text: "Et sans récursion, tu ferais comment pour inverser la liste ?", start: 7, end: 10),
    TranscriptLine(speaker: .me, text: "Euh, en place, avec trois pointeurs je pense.", start: 11, end: 13),
]

let codeAnswer = """
On inverse les pointeurs en un seul passage, sans pile ni récursion.

## Approche
Trois pointeurs : `precedent`, `courant`, `suivant`. À chaque nœud, on retourne la flèche puis on avance.

## Code
```python
def inverser(tete):
    precedent = None
    courant = tete
    while courant:
        suivant = courant.suivant
        courant.suivant = precedent
        precedent, courant = courant, suivant
    return precedent
```

## Complexité
O(n) en temps, O(1) en mémoire.

## Points clés
- En place : aucune allocation.
- Penser à la liste vide et à un seul nœud.
"""

let sayAnswer = """
**À dire :** Oui, on tient le 12 novembre si l'export PDF passe à la version suivante.

## Relances probables
- « Et si un client demande l'export ? » → On lui envoie la version bêta dès décembre.
- « Qui teste avant la sortie ? » → Moi, mercredi, avec la démo.
- « On prévient le support quand ? » → Lundi, avec la liste des questions fréquentes.
"""

let meetingNotes = try MeetingNotesRequest.notes(fromJSON: """
{"titre": "Sortie de Revisio et support",
 "points_cles": [{"texte": "La version web est prête ; l'export PDF reste à faire.", "preuve": "La version web est prête"}],
 "decisions": [{"texte": "Sortie maintenue au 12 novembre.", "preuve": "On garde la sortie au douze novembre"},
               {"texte": "L'export PDF passe à la version suivante.", "preuve": "si on repousse l'export à la version suivante"}],
 "actions": [{"texte": "Préparer la démo de jeudi", "qui": "Moi", "preuve": "Je m'en occupe, je l'envoie mercredi soir"},
             {"texte": "Demander à l'équipe qui gère le support", "qui": "Moi", "preuve": "je demande à l'équipe"}],
 "questions_ouvertes": [{"texte": "Qui gère le support pendant le lancement ?", "preuve": "qui gère le support pendant le lancement"}],
 "suite": [{"texte": "Nouveau point vendredi matin.", "preuve": "On refait un point vendredi matin"}]}
""", transcript: [
    TranscriptLine(speaker: .me, text: "Oui. La version web est prête, il reste l'export des fiches en PDF.", start: 1, end: 2),
    TranscriptLine(speaker: .them, text: "D'accord. On garde la sortie au douze novembre ?", start: 3, end: 4),
    TranscriptLine(speaker: .me, text: "Oui, si on repousse l'export à la version suivante.", start: 5, end: 6),
    TranscriptLine(speaker: .me, text: "Je m'en occupe, je l'envoie mercredi soir.", start: 7, end: 8),
    TranscriptLine(speaker: .them, text: "Il reste à savoir qui gère le support pendant le lancement.", start: 9, end: 10),
    TranscriptLine(speaker: .me, text: "Je n'ai pas encore de réponse, je demande à l'équipe.", start: 11, end: 12),
    TranscriptLine(speaker: .them, text: "Bon. On refait un point vendredi matin.", start: 13, end: 14),
])
let review = SelfReview(
    strengths: ["Tu vas droit au but et tu t'engages sur une échéance.", "Tu reformules la condition de la décision."],
    improvements: ["Donner une date quand tu promets une réponse (« je demande à l'équipe »)."],
    rephrasings: [.init(original: "je demande à l'équipe", better: "Je demande à l'équipe et je te réponds d'ici demain midi.")]
)

@MainActor
func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) { content() }
        .padding(8)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
}

@MainActor
func pill(_ state: PillState) -> some View {
    // The pill's real width (PillPanel.size).
    PillView(state: state)
        .frame(width: 480)
        .background(panelBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
}

@MainActor
func run() async throws {
    _ = NSApplication.shared
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let listening = PillState(isListening: true, elapsed: 724, mode: .meeting, provider: "Codex", providerDetail: "Codex · gpt-5.6-luna")

    // Pill, folded (idle and listening).
    try render(VStack(spacing: 10) {
        pill(PillState(mode: .meeting, provider: "Codex"))
        pill(listening)
        pill({ var paused = listening; paused.isPaused = true; return paused }())
    }, width: 520, to: "pilule-repliee")

    // The ⚙ menu, drawn in a panel of Copilote's (no NSMenu: a system window, seen in shares), an
    // entry reached with the arrows.
    var menu = PillMenuContent.menu(for: PillState(mode: .meeting, provider: "Codex", providerDetail: "Codex · gpt-5.6-luna"))
    for _ in 0..<5 { menu.moveDown() }
    try render(VStack(alignment: .trailing, spacing: 4) {
        pill(PillState(mode: .meeting, provider: "Codex"))
        PillMenuView(menu: menu)
            .background(panelBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .padding(.trailing, 64)
    }, width: 520, to: "pilule-menu")

    // Panel unfolded: 4 cases + structured code answer.
    let code = try await AnswerSnapshot().image(markdown: codeAnswer, size: CGSize(width: 446, height: 560), web: web, lead: true)
    let context = AssistContext(lines: lines, captures: [], extracts: [])
    try render(VStack(spacing: 8) {
        pill({ var state = listening; state.isUnfolded = true; return state }())
        panel {
            CasesList(topics: topics, keys: keys, answeringID: "t4", selectedID: "t4")
            ActionBar(target: topics[0].title, included: context.items.count, total: context.items.count)
            Image(nsImage: code).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(width: 470)
    }, width: 520, to: "panneau-reponse-code")

    // Math (KaTeX): inline, display, an error left in place, and prices that stay text.
    let maths = try await AnswerSnapshot().image(markdown: mathAnswer, size: CGSize(width: 446, height: 420), web: web, lead: true, extras: ["copy": .string(mathAnswer)])
    try render(panel {
        Image(nsImage: maths).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }.frame(width: 470), width: 520, to: "reponse-maths")

    // A failed answer: the error and « Réessayer ».
    let failed = try await AnswerSnapshot().image(
        markdown: "", size: CGSize(width: 446, height: 160), web: web,
        extras: ["notice": ["kind": "error", "text": "Codex ne répond pas : la connexion a été coupée.", "retry": true]]
    )
    try render(panel {
        Image(nsImage: failed).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }.frame(width: 470), width: 520, to: "reponse-erreur")

    // "Que dire".
    if let say = WhatToSay(markdown: sayAnswer) {
        try render(panel {
            ActionBar(target: topics[1].title, included: 3, total: 4)
            WhatToSayCard(say: say)
        }, width: 470, to: "reponse-que-dire")
    }

    // Context with its switches (one phrase and the capture switched off).
    var chosen = AssistContext(
        lines: lines, captures: [CapturedImage(data: Data([1, 2, 3]), mediaType: "image/jpeg", pixelWidth: 1600, pixelHeight: 1000)],
        extracts: [BaseSnippet(source: "Revisio › Chiffres (projets/revisio.md)", text: "5 types de questions, 18 écrans testés.")]
    )
    chosen.toggle(chosen.items[3].id)
    chosen.toggle(chosen.items[4].id)
    try render(panel {
        ActionBar(target: nil, included: chosen.items.filter(\.isIncluded).count, total: chosen.items.count, isContextOpen: true)
        ContextDrawer(items: chosen.items)
        AskField(text: .constant(""))
    }, width: 470, to: "contexte")

    // End-of-meeting notes + email + self-review.
    try render(MeetingNotesCard(report: MeetingReport(notes: meetingNotes, email: meetingNotes.email(mode: .meeting), review: review, stats: SpeechStats(transcript: lines))), width: 470, to: "notes-email")

    // History: list, then a session opened.
    let sessions = [
        SessionSummary(id: UUID(), started: now, duration: 1_920, mode: .meeting, title: "Sortie de Revisio et support"),
        SessionSummary(id: UUID(), started: now.addingTimeInterval(-86_400), duration: 2_700, mode: .technical, title: "Entretien technique · listes chaînées"),
        SessionSummary(id: UUID(), started: now.addingTimeInterval(-3 * 86_400), duration: 900, mode: .friends, title: "Café avec Inès · projets d'été"),
        SessionSummary(id: UUID(), started: now.addingTimeInterval(-8 * 86_400), duration: 3_300, mode: .presentation, title: "Présentation Tram Live au club"),
    ]
    let record = SessionRecord(
        id: sessions[0].id, started: now, duration: 1_920, mode: .meeting, title: sessions[0].title, transcript: lines,
        topics: topics.map { RecordedTopic(title: $0.title, excerpt: $0.excerpt) },
        answers: [RecordedAnswer(label: "Que dire · Date de sortie de Revisio", markdown: sayAnswer)],
        notes: meetingNotes, email: meetingNotes.email(mode: .meeting), review: nil
    )
    try render(HistoryBrowser(isRecording: true, sessions: sessions, query: .constant(""), selection: .constant(nil), opened: nil)
        .frame(height: 420), width: 820, to: "historique-liste")
    try render(HistoryBrowser(isRecording: true, sessions: sessions, query: .constant(""), selection: .constant(sessions[0].id), opened: record)
        .frame(height: 760), width: 900, to: "historique-session")

    // Settings: Réunions.
    let settings = SettingsStore()
    settings.keepHistory = true
    settings.historyRetentionDays = 30
    try render(Form { MeetingSettingsSection(settings: settings) }.formStyle(.grouped).frame(height: 400), width: 460, to: "reglages-reunions")
    settings.answerInstructions = "Entretien de stage SWE chez Hexa Trading (fictif). Réponses courtes, exemples tirés de mes projets."
    settings.answerLanguage = AnswerPreferences.Language.auto.rawValue
    try render(Form { AnswerSettingsSection(settings: settings) }.formStyle(.grouped).frame(height: 420), width: 460, to: "reglages-reponses")

    // The first-launch welcome, step by step: the microphone granted, the screen not yet; Codex
    // ready; an empty base.
    var welcome = Onboarding()
    let status = OnboardingStatus(
        permissions: PermissionState(screen: false, microphone: true), codexReady: true,
        codexDetail: "Codex · gpt-5.6-luna (abonnement ChatGPT)", basePath: "~/Copilote", baseItems: 0, isStealth: true
    )
    for index in 1...Onboarding.count {
        try render(OnboardingStepView(onboarding: welcome, status: status), width: 440, to: "accueil-\(index)")
        welcome.next()
    }

    // Menu bar menu (drawn: an NSMenu can't be rendered off-screen).
    try render(MenuBarMenuPreview(isVisible: true, isListening: true), width: 230, to: "menu-barre")

    // Step 3 fiches, with the diagram opened large on the project card.
    let index = try BaseIndex(url: store.appendingPathComponent("index.sqlite"))
    let embedder: TextEmbedder = await ContextualEmbedder.prepare() ?? NoEmbedder()
    let base = PersonalBase(search: BaseSearch(index: index, embedder: embedder), index: index, root: root)
    var first: Fiche?
    for (name, question) in [("carte-projet", "C'est quoi ton projet d'app de révision ?"), ("grille-photos", "T'étais où cet été ?"), ("extrait-cv", "Tu codes en quoi ?")] {
        guard let found = await base.fiche(for: question, today: today) else {
            print("rien trouvé pour « \(question) » : lance `make index` d'abord")
            continue
        }
        first = first ?? found.fiche
        try render(FicheView(fiche: found.fiche, onAnswer: {}, onClose: {}), width: 446, to: name)
    }
    if let first {
        try render(FicheSuggestion(fiche: first, onShow: {}, onClose: {}), width: 446, to: "suggestion")
    }

    // Step 4b, seen without pressing anything: the case at once, the fiche, the answer drafted by
    // itself under it (Codex's text from `make replay FILE=fixtures/trois-types.wav`).
    let asked = [
        Topic(id: "t3", title: "Projet qui t’a mis sous pression", excerpt: ["Raconte-moi un projet qui t'a mis sous pression."], createdAt: now, updatedAt: now),
        Topic(id: "t2", title: "Président américain préféré", excerpt: ["C'est qui ton président des États-Unis préféré ?"], createdAt: now.addingTimeInterval(-12), updatedAt: now.addingTimeInterval(-12)),
        Topic(id: "t1", title: "Ventes de peluches en 2027", excerpt: ["Parle-moi des ventes de peluches en 2027."], createdAt: now.addingTimeInterval(-24), updatedAt: now.addingTimeInterval(-24)),
    ]
    let unfolded = { var state = listening; state.isUnfolded = true; return state }()
    if let story = await base.fiche(for: "Raconte-moi un projet qui t'a mis sous pression.", today: today) {
        // Under a second: the case and the fiche, open; the answer is on its way.
        try render(VStack(spacing: 8) {
            pill(unfolded)
            panel {
                CasesList(topics: asked, keys: keys, answeringID: "t3")
                ScrollView { FicheView(fiche: story.fiche, onAnswer: {}, onClose: {}) }.frame(height: 240)
                ActionBar(target: asked[0].title, included: 4, total: 4)
                AskPrompt()
            }
            .frame(width: 470)
        }, width: 520, to: "aide-directe-fiche")
        // 3-5 s: the answer has words, the fiche folds to its line, what to say comes first.
        let drafted = try await AnswerSnapshot().image(markdown: storyAnswer, size: CGSize(width: 446, height: 300), web: web, lead: true)
        try render(VStack(spacing: 8) {
            pill(unfolded)
            panel {
                CasesList(topics: asked, keys: keys, answeringID: "t3")
                FicheFoldedLine(fiche: story.fiche, onOpen: {}, onClose: {})
                ActionBar(target: asked[0].title, included: 4, total: 4)
                AskPrompt()
                Image(nsImage: drafted).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(width: 470)
        }, width: 520, to: "aide-directe")
    }

    // An opinion not in avis.md: neutral angles, never an opinion, and the subject to add.
    let angles = try await AnswerSnapshot().image(markdown: anglesAnswer, size: CGSize(width: 446, height: 250), web: web, lead: false)
    try render(panel {
        CasesList(topics: Array(asked.dropFirst()), keys: keys, answeringID: "t2")
        MissingOpinionCard(subject: OpinionLookup.subject(ofTitle: asked[1].title))
        Image(nsImage: angles).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }, width: 470, to: "avis-absent")

    // The instant case (keywords, < 1 s), before the model's title fades in.
    var instant = asked[0]
    instant.title = "Raconte-moi un projet qui t'a mis sous pression"
    instant.isProvisional = true
    try render(panel { CasesList(topics: [instant] + Array(asked.dropFirst()), keys: keys) }, width: 470, to: "case-instantanee")
}

let storyAnswer = """
**Situation :** Trois jours avant la démo de mon projet Revisio, l’import de 30 pages prenait plus de trois minutes. [1]  
**Ce que j’ai fait :** J’ai mesuré chaque étape, déplacé le découpage dans la file de tâches et mis en cache les propositions de questions. [1]  
**Résultat :** Le jour de la démo, le même lot passait en 45 secondes, sans coupure. [1]  
**Ce que j’en retiens :** Il faut mesurer avant d’optimiser et garder une version de secours prête. [1]
"""

let anglesAnswer = """
## Angles possibles
- **L’angle historique** : comparer les présidents selon leur influence durable sur les États-Unis et le monde.
- **L’angle politique** : évaluer leurs décisions selon des critères comme l’économie, les droits civiques ou la politique étrangère.
- **L’angle personnel** : retenir celui dont les valeurs, le style ou les priorités correspondent le mieux à ses propres convictions.
"""

try await run()
