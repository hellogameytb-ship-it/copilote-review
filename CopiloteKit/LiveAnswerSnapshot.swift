import Foundation

public struct ProvisionalSpeech: Equatable, Sendable {
    public let speaker: Speaker
    public let text: String
    public init(speaker: Speaker, text: String) { self.speaker = speaker; self.text = text }
}

/// Immutable speech focus captured by an explicit Answer gesture. Session context stays separate.
public struct LiveAnswerSnapshot: Equatable, Sendable {
    public let recentLines: [TranscriptLine]
    /// All included fragments overlapping the two-minute working window, never a fragment count.
    public let workingLines: [TranscriptLine]
    public let capturedAt: TimeInterval
    public var precedingLines: [TranscriptLine] { recentLines.filter { $0.end < capturedAt - 120 } }
    public let provisional: [ProvisionalSpeech]
    /// Search only for a current interviewer request or an explicit, finalized candidate restatement.
    private let hasInterviewerRequest: Bool
    public var lookupText: String { restatedStory ?? (hasInterviewerRequest ? focusText : "") }
    public let restatedStory: String?

    public init?(lines: [TranscriptLine], context: AssistContext, provisional: [ProvisionalSpeech], capturedAt: TimeInterval? = nil) {
        let included = context.includedLines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let excluded = context.excludedLineTexts
        self.provisional = provisional.filter { fragment in
            let text = fragment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !included.contains(where: { $0.speaker == fragment.speaker && $0.text == text }),
                  !excluded.contains(where: { !($0.isEmpty) && text.localizedCaseInsensitiveContains($0) }) else { return false }
            // Do not reintroduce excluded speech through an overlapping interim result.
            if let last = lines.last(where: { $0.speaker == fragment.speaker }), excluded.contains(last.text) { return false }
            return true
        }
        let cutoff = capturedAt ?? lines.map(\.end).max() ?? 0
        self.capturedAt = cutoff
        recentLines = included.filter { $0.end >= cutoff - 300 && $0.start <= cutoff }
        workingLines = recentLines.filter { $0.end >= cutoff - 120 }
        guard !workingLines.isEmpty || !self.provisional.isEmpty else { return nil }
        let interviewer = workingLines.filter { $0.speaker == .them }.map(\.text)
            + self.provisional.filter { $0.speaker == .them }.map(\.text)
        hasInterviewerRequest = interviewer.contains(where: { !Self.isSocial($0) })
        if hasInterviewerRequest {
            restatedStory = nil
        } else {
            let latest = workingLines.lastIndex { !Self.isSocial($0.text) }
            let pending = self.provisional.contains { $0.speaker == .me && !Self.isSocial($0.text) }
            var restatement: String?
            if !pending, let latest, workingLines[latest].speaker == .me {
                let last = workingLines[latest]
                restatement = Self.storyRestatement(last.text)
                // ASR can finalize the confirmation frame and its subject separately.
                if restatement == nil, latest > 0 {
                    let prior = workingLines[latest - 1]
                    if prior.speaker == .me, last.start - prior.end <= 3,
                       let position = lines.lastIndex(of: last), position > 0, lines[position - 1] == prior {
                        let combined = prior.text + " " + last.text
                        if Self.storyRestatement(prior.text) == nil {
                            restatement = Self.storyRestatement(combined)
                        }
                    }
                }
            }
            restatedStory = restatement
        }
    }

    static func isSocial(_ text: String) -> Bool {
        let words = BaseText.tokens(of: text).joined(separator: " ")
        let greetings = ["bonjour", "salut", "bonsoir", "comment ca va", "comment allez vous", "ca va",
                         "hello", "hi", "hey", "good morning", "good afternoon", "how are you", "how are you doing"]
        let acknowledgements = ["ok", "okay", "yes", "right", "thanks", "thank you", "oui", "merci", "d accord"]
        return words.isEmpty || greetings.contains(words) || acknowledgements.contains(words)
    }

    private static func storyRestatement(_ text: String) -> String? {
        let words = BaseText.tokens(of: text).joined(separator: " ")
        let opening = #"^(?:(?:so|donc|alors|si je comprends bien|if i understand correctly|just to confirm) )*(?:(?:(?:est ce que )?(?:vous voulez|tu veux|vous souhaitez)|voulez vous|souhaitez vous) que je (?:vous |te )?(?:parle|raconte|decrive|donne un exemple)|(?:vous me demandez|tu me demandes) de (?:vous |te )?(?:parler|raconter|decrire)|(?:do you want|you want|you would like|you d like|would you like|you re asking|you are asking) me to (?:talk about|tell you about|describe|explain|give (?:you )?an example of)) "#
        guard let prefix = words.range(of: opening, options: .regularExpression) else { return nil }
        let subject = String(words[prefix.upperBound...])
        let pastEpisode = #"^(?:(?:d |de )?(?:une |la |cette )?(?:fois|situation|occasion) (?:ou |dans laquelle )?(?:j ai|nous avons|on a) (?:rencontre|eu|resolu|affronte|surmonte|gere|du resoudre) |(?:d |de )?(?:un|une) .+? que (?:j ai|nous avons) (?:rencontre|resolu|surmonte|gere)e?s?\b|(?:a |the )?(?:time|situation|occasion) (?:where |when )?(?:i|we) (?:faced|encountered|had|solved|handled|overcame|dealt with|ran into) |(?:a|an|the) .+? (?:that )?(?:i|we) (?:faced|encountered|solved|handled|overcame)\b)"#
        guard subject.range(of: pastEpisode, options: .regularExpression) != nil else { return nil }
        guard subject.range(of: #"\b(?:hypothetical|hypothetique|imagine|imaginaire|fictional|fictif|would|could)\b"#, options: .regularExpression) == nil else { return nil }
        let challenge = #"\b(?:probleme|problem|challenge|defi|difficulte|obstacle|incident|failure|echec|conflict|conflit|setback|pression|pressure)\b"#
        guard subject.range(of: challenge, options: .regularExpression) != nil else { return nil }
        let technical = subject.range(of: #"\b(?:technical|technique)\b"#, options: .regularExpression) != nil
        return "Tell me about a time you faced a " + (technical ? "technical challenge. " : "challenge. ") + subject
    }

    public var focusText: String {
        (workingLines.map(\.labeled) + provisional.map { "\($0.speaker.name) (provisional): \($0.text)" }).joined(separator: "\n")
    }
}
