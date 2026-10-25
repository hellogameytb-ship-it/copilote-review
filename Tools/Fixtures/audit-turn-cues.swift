import Foundation
import CopiloteKit

let cases = [
    "Pourquoi ?", "Et pourquoi ?", "Why?", "And why?",
    "Tu en penses quoi", "Tu en penses quoi ?", "Qu'est-ce que tu en penses",
    "Tu choisirais lequel", "Tu choisirais lequel ?", "Comment tu ferais",
    "Et après", "Et après ?", "Explique-moi ça", "What do you think",
    "C'était sympa de discuter", "Je veux comprendre pourquoi"
]
let known = Topic(id:"context",title:"Choosing a holiday destination",excerpt:["Quelle destination choisir pour les vacances ?"],createdAt:Date(),updatedAt:Date())
let rows:[[String:Any]] = cases.map { text in
    var assembler = TurnAssembler(speaker:.them)
    assembler.handle(.speechStarted(at:0)); assembler.addFinal(text,start:0,end:2.9); assembler.handle(.speechEnded(at:3))
    var time:Double?
    for tick in 1...350 { let now = 3 + Double(tick)/100; if !assembler.advance(to:now).isEmpty { time = now-3; break } }
    let turn = Turn(speaker:.them,text:text,start:0,end:3)
    let decision = LexicalTopicSegmenter().decision(for:turn,topics:[known])
    return ["text":text,"complete":TurnCompletion.isComplete(text),"requestsAutomaticAnswer":TurnCompletion.requestsAnswer(text),
            "simulatedEndToTurnSeconds":time ?? -1,"kind":QuestionKind(question:text).rawValue,"lexicalDecision":String(describing:decision)]
}
let data = try JSONSerialization.data(withJSONObject:["candidateFramework":CommandLine.arguments[2],"rows":rows,"audioUsed":false,"liveAIRequests":0],options:[.prettyPrinted,.sortedKeys])
try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
print("Audited \(rows.count) synthetic FR/EN phrases; no audio or model calls.")
