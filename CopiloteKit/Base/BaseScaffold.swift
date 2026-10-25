import Foundation

/// `~/Copilote/`, the source of truth: Markdown fiches and files the user drops in. Copilote
/// creates the folders and commented templates once and never overwrites a file.
public enum BaseScaffold {
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Copilote", isDirectory: true)
    }

    public static let folders = ["projets", "voyages", "notes", "reference", "photos"]
    /// The user's opinions: the only source of an opinion answer.
    public static let opinionsFile = "avis.md"

    /// Relative path → content. Files starting with `_` are models to copy; they are not indexed.
    public static let templates: [(path: String, content: String)] = [
        ("LISEZMOI.md", readme),
        ("cv.md", cv),
        ("bio.md", bio),
        (opinionsFile, opinions),
        ("projets/_modele.md", project),
        ("voyages/_modele.md", trip),
    ]

    /// Returns what was created or updated (relative paths of files). A model left exactly as an
    /// earlier version wrote it gets the current one; anything else the user wrote stays.
    @discardableResult
    public static func create(at root: URL) throws -> [String] {
        let files = FileManager.default
        for folder in folders {
            try files.createDirectory(at: root.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
        }
        var changed: [String] = []
        for (path, content) in templates {
            let url = root.appendingPathComponent(path)
            if files.fileExists(atPath: url.path) {
                let existing = try? String(contentsOf: url, encoding: .utf8)
                guard let existing, earlierVersions[path]?.contains(existing) == true else { continue }
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
            changed.append(path)
        }
        return changed
    }

    /// Models as earlier versions of Copilote wrote them, word for word.
    static let earlierVersions: [String: [String]] = [
        "LISEZMOI.md": [readmeStep3, readmeStep4b],
        "projets/_modele.md": [projectStep3],
    ]

    /// « Ajouter à avis.md »: an empty section for the subject, to fill in after the meeting
    /// (avis.md is created from its model if missing). Nothing is written for the user.
    @discardableResult
    public static func addOpinion(_ subject: String, at root: URL) throws -> URL {
        let url = root.appendingPathComponent(opinionsFile)
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? opinions
        let heading = "## \(subject)"
        guard !text.components(separatedBy: "\n").contains(heading) else { return url }
        if !text.hasSuffix("\n") { text += "\n" }
        text += "\n\(heading)\n<!-- Ton avis en 2-3 lignes, et pourquoi. -->\n"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: Templates (French: the user fills them)

    static let readme = """
    # Ta base Copilote

    Ce dossier est la source de vérité de Copilote : quand on te pose une question perso en
    réunion (« t'étais où cet été ? », « c'est quoi ton projet ? »), Copilote affiche la fiche
    correspondante en moins d'une seconde, sans attendre le LLM.

    - `cv.md` : ton parcours, découpé par expérience (titres `###`) et par section (`##`).
    - `bio.md` : ce que tu dirais pour te présenter.
    - `avis.md` : tes avis (« ton livre préféré ? », « tu penses quoi du télétravail ? »), une section `##`
      par sujet. Copilote ne répond à une question d'avis qu'avec ce qui est écrit ici ; sinon il te
      propose des angles neutres et ne choisit jamais à ta place.
    - `projets/` : une fiche par projet. Copie `projets/_modele.md` sous `projets/<nom-court>.md`.
      Sa section `## Histoires` (pression, échec, conflit, fierté) sert aux questions d'entretien
      « raconte-moi une fois où… » : Copilote en tire une réponse prête à dire.
    - `voyages/` : une fiche par voyage. Copie `voyages/_modele.md`.
    - `notes/` : tes notes en Markdown, libres.
    - `reference/` : PDF, DOCX ou TXT déposés tels quels (lettres, relevés, articles).
    - `photos/` : tes photos, en sous-dossiers libres. La date et le lieu viennent de l'EXIF.

    Les fichiers qui commencent par `_` sont des modèles : ils ne sont pas indexés.
    Tout reste sur ton Mac. L'index est dans `~/Library/Application Support/Copilote/` ; il se
    met à jour tout seul quand un fichier change. Afficher une fiche n'appelle ni le réseau ni
    le LLM. Ce qui part au LLM : les extraits utiles à une réponse rédigée, celle que Copilote
    écrit tout seul pour la case 1 (réglage « Rédiger la réponse de la case 1 toute seule »,
    activé) ou celle que tu demandes (le raccourci d'une case, « Rédiger une réponse ») ; une fois par état du repo,
    le README, l'arborescence et quelques fichiers clés (secrets masqués) d'un projet qui cite son
    `repo`, pour dessiner son diagramme ; les photos, seulement si tu actives leurs légendes.
    """

    static let cv = """
    # CV
    <!-- Copilote découpe ce fichier par expérience (chaque titre ###) et par section (##).
         Mets les dates dans le titre, entre parenthèses : (juin 2024 – août 2024), (2021–2024),
         (sept. 2025 – aujourd'hui). Une fiche courte s'affiche quand on te demande ton
         parcours ou tes compétences. -->

    ## Expériences
    <!-- ### Poste — Entreprise, Ville (début – fin)
         Deux ou trois lignes : ce que tu as fait, avec un chiffre clé. -->

    ## Formation
    <!-- ### Diplôme — École (début – fin) -->

    ## Compétences
    <!-- - Langages : …
         - Outils : …
         - Langues : … -->
    """

    static let bio = """
    # Bio
    <!-- Ce que tu dirais si on te demande « présente-toi » ou « tu viens d'où ? ».
         Une section ## par sujet : chaque section devient une fiche. -->

    ## En bref

    ## D'où je viens

    ## Centres d'intérêt
    """

    static let project = """
    ---
    nom:          # Nom du projet
    pitch:        # Une phrase : ce que ça fait, pour qui
    stack: []     # ex. [Swift, Next.js, Supabase]
    debut:        # ex. 2025-09 (ou 2025-09-15)
    fin:          # vide si en cours
    liens: []     # ex. [https://…]
    repo:         # dossier local, ex. ~/Projects/mon-app (lu seulement : README, arborescence, fichiers clés)
    captures: []  # images à côté de cette fiche, ex. [captures/mon-app.png]
    ---
    <!-- Copie ce fichier sous projets/<nom-court>.md (sans le « _ ») pour créer une fiche.
         Le texte avant la première section s'affiche sous le pitch. Avec un repo, Copilote
         prépare une fois un diagramme d'architecture (refait seulement si le repo change). -->

    ## Le problème

    ## Ce que j'ai construit

    ## Chiffres

    ## Ce que j'ai appris

    ## Histoires
    <!-- Pour « raconte-moi un projet qui t'a mis sous pression », « un échec », « un conflit »…
         Remplace chaque commentaire par 3-4 lignes. Laisse vide ce que tu n'as pas vécu. -->

    ### Pression / deadline
    <!-- Contexte : la deadline et ce qui était en jeu.
         Ce que j'ai fait : tes décisions, concrètement.
         Résultat : un chiffre si possible, et ce que tu en retiens. -->

    ### Échec et ce que j'ai appris
    <!-- Contexte : ce qui a raté.
         Ce que j'ai fait : comment tu as réagi.
         Résultat : ce que tu as changé depuis. -->

    ### Conflit ou désaccord
    <!-- Contexte : le désaccord et avec qui (un rôle suffit, pas de nom).
         Ce que j'ai fait : comment vous avez tranché.
         Résultat : la décision prise, et ce que tu en retiens. -->

    ### Fierté
    <!-- Contexte : ce que tu as réussi.
         Ce que j'ai fait : ta part à toi.
         Résultat : ce que ça a changé, un chiffre si possible. -->
    """

    static let opinions = """
    # Mes avis
    <!-- Une section ## par sujet : ton avis en 2-3 lignes, et pourquoi. Copilote ne répond à une
         question d'avis (« ton livre préféré ? », « ton président préféré ? ») qu'avec ce qui est écrit
         ici, en le citant. Si le sujet n'y est pas, il te propose 2-3 angles neutres pour que tu
         choisisses toi-même, et un bouton pour l'ajouter ici. -->

    ## Livre préféré

    ## Ville où vivre
    """

    static let trip = """
    ---
    lieu:     # Ville, Pays
    debut:    # ex. 2025-07-04
    fin:      # ex. 2025-07-18
    photos:   # dossier de photos lié, ex. photos/portugal-2025
    ---
    <!-- Copie ce fichier sous voyages/<nom-court>.md. Les photos du dossier lié, ou prises
         pendant ces dates, s'affichent en grille. -->

    ## Résumé

    ## Moments forts
    """

    // MARK: Earlier versions (step 3), to update them when untouched

    static let readmeStep3 = """
    # Ta base Copilote

    Ce dossier est la source de vérité de Copilote : quand on te pose une question perso en
    réunion (« t'étais où cet été ? », « c'est quoi ton projet ? »), Copilote affiche la fiche
    correspondante en moins d'une seconde, sans attendre le LLM.

    - `cv.md` : ton parcours, découpé par expérience (titres `###`) et par section (`##`).
    - `bio.md` : ce que tu dirais pour te présenter.
    - `projets/` : une fiche par projet. Copie `projets/_modele.md` sous `projets/<nom-court>.md`.
    - `voyages/` : une fiche par voyage. Copie `voyages/_modele.md`.
    - `notes/` : tes notes en Markdown, libres.
    - `reference/` : PDF, DOCX ou TXT déposés tels quels (lettres, relevés, articles).
    - `photos/` : tes photos, en sous-dossiers libres. La date et le lieu viennent de l'EXIF.

    Les fichiers qui commencent par `_` sont des modèles : ils ne sont pas indexés.
    Tout reste sur ton Mac. L'index est dans `~/Library/Application Support/Copilote/` ; il se
    met à jour tout seul quand un fichier change. Afficher une fiche n'appelle ni le réseau ni
    le LLM. Ce qui part au LLM : les extraits utiles quand tu demandes une réponse rédigée (⌥1-4
    sur un sujet perso, « Rédiger une réponse ») ; une fois par état du repo, le README,
    l'arborescence et quelques fichiers clés (secrets masqués) d'un projet qui cite son `repo`,
    pour dessiner son diagramme ; les photos, seulement si tu actives leurs légendes.
    """

    static let projectStep3 = """
    ---
    nom:          # Nom du projet
    pitch:        # Une phrase : ce que ça fait, pour qui
    stack: []     # ex. [Swift, Next.js, Supabase]
    debut:        # ex. 2025-09 (ou 2025-09-15)
    fin:          # vide si en cours
    liens: []     # ex. [https://…]
    repo:         # dossier local, ex. ~/Projects/mon-app (lu seulement : README, arborescence, fichiers clés)
    captures: []  # images à côté de cette fiche, ex. [captures/mon-app.png]
    ---
    <!-- Copie ce fichier sous projets/<nom-court>.md (sans le « _ ») pour créer une fiche.
         Le texte avant la première section s'affiche sous le pitch. Avec un repo, Copilote
         prépare une fois un diagramme d'architecture (refait seulement si le repo change). -->

    ## Le problème

    ## Ce que j'ai construit

    ## Chiffres

    ## Ce que j'ai appris
    """

    static let readmeStep4b = """
    # Ta base Copilote

    Ce dossier est la source de vérité de Copilote : quand on te pose une question perso en
    réunion (« t'étais où cet été ? », « c'est quoi ton projet ? »), Copilote affiche la fiche
    correspondante en moins d'une seconde, sans attendre le LLM.

    - `cv.md` : ton parcours, découpé par expérience (titres `###`) et par section (`##`).
    - `bio.md` : ce que tu dirais pour te présenter.
    - `avis.md` : tes avis (« ton livre préféré ? », « tu penses quoi du télétravail ? »), une section `##`
      par sujet. Copilote ne répond à une question d'avis qu'avec ce qui est écrit ici ; sinon il te
      propose des angles neutres et ne choisit jamais à ta place.
    - `projets/` : une fiche par projet. Copie `projets/_modele.md` sous `projets/<nom-court>.md`.
      Sa section `## Histoires` (pression, échec, conflit, fierté) sert aux questions d'entretien
      « raconte-moi une fois où… » : Copilote en tire une réponse prête à dire.
    - `voyages/` : une fiche par voyage. Copie `voyages/_modele.md`.
    - `notes/` : tes notes en Markdown, libres.
    - `reference/` : PDF, DOCX ou TXT déposés tels quels (lettres, relevés, articles).
    - `photos/` : tes photos, en sous-dossiers libres. La date et le lieu viennent de l'EXIF.

    Les fichiers qui commencent par `_` sont des modèles : ils ne sont pas indexés.
    Tout reste sur ton Mac. L'index est dans `~/Library/Application Support/Copilote/` ; il se
    met à jour tout seul quand un fichier change. Afficher une fiche n'appelle ni le réseau ni
    le LLM. Ce qui part au LLM : les extraits utiles à une réponse rédigée, celle que Copilote
    écrit tout seul pour la case 1 (réglage « Rédiger la réponse de la case 1 toute seule »,
    activé) ou celle que tu demandes (⌥1-4, « Rédiger une réponse ») ; une fois par état du repo,
    le README, l'arborescence et quelques fichiers clés (secrets masqués) d'un projet qui cite son
    `repo`, pour dessiner son diagramme ; les photos, seulement si tu actives leurs légendes.
    """
}
