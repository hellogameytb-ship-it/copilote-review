import Foundation

/// The latest substantive interview request, including a short clarification of the same question.
struct InterviewFocus {
    enum Subject { case models, imbalance, databases, languages, pipeline, obstacle, ownership, workflow, verification, graduation, schedule, eligibility, placement, logistics, candidateQuestions, closing }
    let subject: Subject
    let question: String
    let context: String

    static func resolve(heard: [String], conversation: [TranscriptLine]) -> InterviewFocus? {
        let marked = heard.joined(separator: "\n").components(separatedBy: .newlines)
        let spoken = marked.compactMap { line in
            ["Them : ", "Them (provisional): "].first(where: line.hasPrefix).map { String(line.dropFirst($0.count)) }
        }
        let turns = spoken.isEmpty ? heard : spoken
        let relevant = turns.filter { !LiveAnswerSnapshot.isSocial($0) && BaseText.tokens(of: $0).count >= 2 }
        guard let last = relevant.last else { return nil }
        let latest = normalized(last)
        if spoken.isEmpty, !heard.contains(where: { $0.hasPrefix("Them") }) {
            let unaddressed = Set(BaseText.tokens(of: last)).isDisjoint(with: ["you", "your", "my", "me", "tu", "ton", "tes", "vous", "vos", "mon", "mes"])
            if unaddressed && !isContinuation(latest) { return nil }
        }
        guard !spoken.isEmpty || heard.allSatisfy({ !$0.hasPrefix("Me : ") }) else { return nil }
        if isClosing(latest) { return .init(subject: .closing, question: last, context: "") }
        if !spoken.isEmpty && classify(latest) == nil && !TurnCompletion.requestsAnswer(last),
           let prior = relevant.dropLast().last, isClosing(normalized(prior)) {
            return .init(subject: .closing, question: prior, context: "")
        }
        // STT often omits punctuation on the tail of a multipart question or transcribes
        // an acknowledgement as a partial word. Never cross a distinct substantive request.
        var request = last
        var subject = classify(latest)
        if subject == nil && (isContinuation(latest) || (!spoken.isEmpty && !TurnCompletion.requestsAnswer(last) && BaseText.tokens(of: latest).count <= 7)) {
            var before = Array(relevant.dropLast().suffix(4))
            if spoken.isEmpty && before.isEmpty {
                before = conversation.suffix(16).filter { $0.speaker == .them && $0.text != last }.map(\.text)
            }
            for previous in before.reversed() {
                let words = normalized(previous)
                if let kind = classify(words) { subject = kind; request = previous + " " + last; break }
                if isClosing(words) || (TurnCompletion.requestsAnswer(previous) && !isContinuation(words)) { break }
            }
        }
        // Some ASR fragments truncate the real question on the other channel. Use its
        // matching echo only to recover the topic, never as a personal fact.
        if !spoken.isEmpty, subject == nil || subject == .graduation {
            let echoed = conversation.suffix(20).filter { $0.speaker == .me && TurnCompletion.requestsAnswer($0.text) }
            if let echo = echoed.last, let tail = spoken.last,
               !TurnCompletion.requestsAnswer(tail), BaseText.tokens(of: tail).count >= 3,
               !Set(BaseText.tokens(of: tail)).intersection(BaseText.tokens(of: echo.text)).subtracting(QueryIntent.stopWords).isEmpty,
               let kind = classify(normalized(echo.text)) {
                request = echo.text; subject = kind
            }
        }
        if subject == .graduation, spoken.contains(where: { normalized($0).contains("start date") }),
           BaseText.tokens(of: last).count < 5 {
            subject = .schedule
            request = spoken.suffix(8).filter { line in
                let words = normalized(line)
                return words.contains("start date") || words.contains("monday") || words.contains("graduation")
            }.joined(separator: " ")
        }
        guard let subject else { return nil }
        let normalizedRequest = normalized(request)
        if ["how would you design", "what is a ", "explain how ", "implement a ", "how do databases work"].contains(where: normalizedRequest.hasPrefix) { return nil }
        // Only included, nearby speech can identify the current project. The answer prompt
        // still contains the intact exchange with speaker labels.
        let nearby = conversation.suffix(30).map(\.text).joined(separator: " ")
        return InterviewFocus(subject: subject, question: request, context: nearby)
    }

    static func normalized(_ text: String) -> String { BaseText.tokens(of: text).joined(separator: " ") }

    private static func isContinuation(_ s: String) -> Bool {
        ["specific example", "what approach", "what appro ", "what have you worked with", "any of those", "how did you handle",
         "what have you built", "what kinds of projects", "what would that be", "what were the results",
         "which aspects of these languages", "which component", "ran into when", "the scoring logic",
         "how you design that", "what did you say", "were you responsible", "made the key decisions"].contains(where: s.contains)
    }

    static func isClosing(_ s: String) -> Bool {
        if !s.hasPrefix("what i can tell you"), ["what ", "when ", "why ", "how ", "could you ", "can you ", "will you "].contains(where: s.hasPrefix) { return false }
        return ["end the interview", "end our interview", "session will be finalized", "feedback will go to",
         "team will cover with you", "hiring team will be able", "specifics of what a typical day",
         "they have way more color", "rest of the process", "team will reach out", "thank you for your time",
         "thanks for your time", "goodbye", "we can end", "redirig", "fin de l entretien"].contains(where: s.contains)
    }

    private static func classify(_ s: String) -> Subject? {
        func has(_ cues: [String]) -> Bool { cues.contains(where: s.contains) }
        if has(["other questions", "anything else i can help", "what questions", "questions for us"]) { return .candidateQuestions }
        if has(["questioned", "suspect", "doubted", "hallucinat", "remis en question", "verify an ai", "verify ai", "validate ai", "challenged an ai"]) { return .verification }
        if has(["coding workflow", "engineering workflow", "engineering or coding", "ai tools", "working with large language models", "use ai to cod", "utilises l ia", "use ai for coding"]) { return .workflow }
        if has(["imbalance", "imbalanced", "desequilibre", "minority class", "class weighting"]) { return .imbalance }
        if has(["database system", "databases", "database experience", "data storage", "bases de donnees", "row level security", "postgres"]) { return .databases }
        if has(["ownership", "own end to end", "own from start", "responsible for the whole", "pris en charge"]) { return .ownership }
        if has(["biggest", "hardest", "principal obstacle", "plus gros obstacle", "main obstacle", "most challenging"]) && has(["challenge", "obstacle", "difficul", "pipeline", "probl"]) { return .obstacle }
        if has(["machine learning", "deep learning", "ml project", "classifier", "apprentissage automatique"]) { return .models }
        if has(["pipeline"]) && has(["design", "built", "building", "app", "project", "projet"]) { return .pipeline }
        if has(["experience with python", "experience with java", "experience with c", "programming languages", "golang", "langages de programmation"]) { return .languages }
        if has(["start date", "date de debut", "start on", "date de demarrage"]) { return .schedule }
        if has(["graduating", "graduation", "graduate", "diplomation", "fin des etudes"]) && !has(["master", "start date"]) { return .graduation }
        if has(["visa", "work authorization", "work permit", "require sponsorship", "autorisation de travail"]) { return .eligibility }
        if has(["mandatory", "voluntary", "obligatoire", "volontaire"]) { return .placement }
        if has(["master", "planningters", "sponsor", "right to work", "relocate", "availability", "available for"]) { return .logistics }
        return nil
    }

    var evidenceTerms: [String] {
        switch subject {
        case .models: return ["classifier", "predicted", "model training", "neural", "backpropagation", "trained"]
        case .imbalance: return ["imbalance", "weighted", "weighting", "recall", "minority", "rarest", "resampling"]
        case .databases: return ["postgres", "sql", "database", "row level security", "multi tenant", "schema"]
        case .pipeline, .obstacle, .ownership: return ["pipeline", "deployment", "deployed", "ingestion", "ingests", "deduplicat", "ownership"]
        case .languages: return ["implemented", "developed", "built", "python", "java", "c++"]
        default: return []
        }
    }

    func score(title: String, passage: String) -> Int {
        let words = Self.normalized(passage)
        if subject == .languages {
            let actions = ["built", "implemented", "developed", "predicted", "modeled", "pipeline", "deployed", "wrote", "trained"]
            guard actions.contains(where: words.contains) else { return 0 }
        }
        let hits = evidenceTerms.filter { words.contains($0) }.count
        guard hits > 0 else { return 0 }
        let nearby = Set(BaseText.tokens(of: context))
        let name = Set(BaseText.tokens(of: title))
        let overlap = nearby.intersection(name).subtracting(QueryIntent.stopWords).filter { $0.count > 3 }.count
        let detail = Set(BaseText.tokens(of: question)).intersection(BaseText.tokens(of: passage)).subtracting(QueryIntent.stopWords).count
        if [.obstacle, .ownership].contains(subject) && overlap == 0 && detail < 2 { return 0 }
        return hits * 7 + min(overlap, 6) * 2 + min(detail, 6) * 2
    }

    var guidance: String {
        switch subject {
        case .models, .imbalance: return "Continue the actual model project identified by the candidate. Give its documented task, method and evaluation as applicable. Preserve classes versus score, team attribution and validation setting. Do not offer alternative techniques as things that happened."
        case .databases: return "Lead with concrete database work, naming the documented database, managed service and access-control mechanism when supplied. Distinguish application use from DBA responsibility. Treat data-frame cleaning as a separate experience. Do not downgrade documented work to limited exposure."
        case .languages: return "Lead with one concrete language and a documented implementation. Answer a preference only if actually asked and supported."
        case .pipeline, .obstacle: return "Keep the named project. Separate design and implementation from an experienced obstacle. A component or an interviewer's list of choices does not establish what was hardest. Use the candidate's clear account if available. If the obstacle remains unknown, say briefly that the specific difficulty needs confirmation."
        case .ownership: return "Name the individual component the candidate actually described. Start with that component, e.g. the ingestion pipeline, in a first-person sentence. Do not open by accepting an interviewer’s suggestion of owning the entire project. Do not expand a described component to the entire application, database or architecture. Describe only actions personally attributed by the candidate or source. Team membership and a stack are not proof of end-to-end ownership. Use a short conditional role option only if ownership is uncertain."
        case .workflow: return "Answer about the engineer's own practice with AI. Use the candidate's described specification, tool use, checks and corrections only where supported. Product features alone cannot establish how the engineer worked. Keep uncertain tool names out."
        case .verification: return "Before composing, identify the exact content of a particular disputed output in the candidate's words. A request for a story is not evidence of an incident. If no specific disputed claim is identifiable, respond in SIMPLE PRESENT throughout. Begin with the candidate's actual check, e.g. I ask for the source. Describe only their stated verification routine, including what they compare. Omit One time, Once, I questioned, I asked and all reconstructed events. Do not substitute confidentiality or hosting for verification."
        case .eligibility: return "State only the candidate's explicitly confirmed personal work status. Citizenship alone does not confirm the answer. When the words are tentative or garbled, lead with a short promise to verify the authorization status. Do not introduce sponsorship, eligibility determinations or legal advice."
        case .placement: return "For mandatory versus voluntary placement, inspect the candidate's final words for uncertainty, including imperfect transcription. If uncertain, state only the uncertainty and the next verification step in one sentence. Do not give either classification as the answer. A prior classification followed by doubt is unresolved."
        case .schedule: return "Speak about the start date. Preserve the employer’s exact recurring calendar rule stated in the exchange, even if the month is unclear. If the date was corrected or garbled, omit every unconfirmed year, month and day; say you need to confirm the intended month. Avoid declaring availability in any inferred year. Ask for the intended month if necessary. If a graduation date was also corrected unclearly, do not present an older CV date as current."
        case .graduation, .logistics: return "Answer the precise logistics question. Keep dates, months, minimum duration and calendar rules exact. Distinguish graduation from start date and a possible master's from confirmed enrollment. Do not mention a master's unless the current question asks about it. Considering is weaker than planning. A clear recent correction prevails; a garbled one means the current value needs confirmation. Lead with uncertainty when the candidate expresses doubt. Never infer visa, sponsorship or program requirements from citizenship or preferences."
        case .candidateQuestions: return "The interviewer invites a question from the candidate. Use the candidate's actual interest if given, and phrase at most one short question. If the interviewer already answered it or deferred details to the team, acknowledge instead of asking it again."
        case .closing: return "The interviewer has explained or closed this point. For this explicit action write only the short words the candidate can say to thank the interviewer. No analysis, headings, or explanation of whether a question was asked. Do not repeat answered questions, propose a new topic or pitch the candidate."
        }
    }
}
