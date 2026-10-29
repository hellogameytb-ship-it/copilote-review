import Foundation

public struct CodexFailure: Error, Equatable, Sendable {
    public enum Category: String, Codable, Sendable { case rateLimit, usageLimit, authentication, timeout, network, busy, provider }
    public let message: String
    public let category: Category
    public let statusCode: Int?
    public let rpcCode: Int?
    public let providerCode: String?
    public let retryAfter: TimeInterval?
    public init(message: String, category: Category? = nil, statusCode: Int? = nil, retryAfter: TimeInterval? = nil, providerCode: String? = nil, rpcCode: Int? = nil) {
        self.message=message
        self.rpcCode=rpcCode
        self.providerCode=providerCode.flatMap { Self.codes[$0.lowercased()] != nil ? $0.lowercased() : nil }
        let code=statusCode ?? Self.explicitStatus(message)
        self.statusCode=code
        self.category=category ?? (code == 429 ? .rateLimit : [401,403].contains(code ?? 0) ? .authentication : .provider)
        self.retryAfter=retryAfter.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
    public static func rateLimited(retryAfter: TimeInterval?) -> Self {
        Self(message:"Too Many Requests",category:.rateLimit,statusCode:429,retryAfter:retryAfter)
    }
    public var userMessage: String {
        switch category {
        case .rateLimit:
            return "Codex: request limited\(statusCode.map { " (\($0))" } ?? ""). " + (retryAfter.map { "Wait at least \(String(format:"%.0f",ceil($0))) seconds before Retry. " } ?? "Please wait before Retry. ") + "The service did not establish whether this was traffic, account usage or another limit. Your previous answer is kept."
        case .usageLimit: return "Codex: the service reported an account usage limit. Check the current account before trying again. No provider was switched."
        case .authentication: return "Codex: access refused\(statusCode.map { " (\($0))" } ?? ""). Check the current account. No provider was switched."
        case .timeout: return "Codex: response timed out. Your previous answer is kept; retry explicitly when ready."
        case .network: return "Codex: connection interrupted. Your previous answer is kept; check the connection before Retry."
        case .busy: return "Codex: request queue full. Wait for the current answer."
        case .provider: return "Codex: \(message)"
        }
    }
    /// Never classify a naked number (which might be a request ID or token count) as HTTP status.
    static func explicitStatus(_ text:String)->Int? {
        let pattern = #"(?i)\b(?:last\s+status|http(?:\s+status)?|status\s+code)\s*[:=]?\s*(401|403|429|5\d\d)\b"#
        if let range=text.range(of:pattern,options:.regularExpression),let digits=text[range].range(of:#"\d{3}$"#,options:.regularExpression) { return Int(text[digits]) }
        if text.range(of:#"(?i)\btoo many requests\b"#,options:.regularExpression) != nil { return 429 }
        return nil
    }
    private static let codes:[String:Category] = ["usagelimitexceeded":.usageLimit,"insufficient_quota":.usageLimit,"credit_balance_exhausted":.usageLimit,"ratelimitexceeded":.rateLimit,"rate_limit_exceeded":.rateLimit,"rate_limit_error":.rateLimit,"slow_down":.rateLimit,"unauthorized":.authentication,"responsestreamconnectionfailed":.network,"responsestreamdisconnected":.network,"httpconnectionfailed":.network,"responsetoomanyfailedattempts":.network,"contextwindowexceeded":.provider,"badrequest":.provider,"sandboxerror":.provider,"internalservererror":.provider,"other":.provider]
    static func from(_ value: JSONValue?, now:Date = Date()) -> Self {
        var node=value ?? .null
        if let raw=node["message"]?.stringValue,let data=raw.data(using:.utf8),let nested=try? JSONDecoder().decode(JSONValue.self,from:data) {
            node = .object(["outer":node,"body":nested])
        }
        var status:Int?, delay:Double?, providerCode:String?

        func prefer(_ code:String) {
            let rank:[Category:Int]=[.usageLimit:4,.rateLimit:3,.authentication:2,.network:1]
            guard let category=Self.codes[code] else { return }
            if (rank[category] ?? 0) > (providerCode.flatMap { Self.codes[$0] }.flatMap { rank[$0] } ?? -1) { providerCode=code }
        }
        func visit(_ json:JSONValue,depth:Int = 0) {
            guard depth<8,case let .object(fields)=json else { return }
            for (key,value) in fields {
                if Self.codes[key.lowercased()] != nil { prefer(key.lowercased()) }
                if ["code","type","codexErrorInfo"].contains(key),let code=value.stringValue,Self.codes[code.lowercased()] != nil { prefer(code.lowercased()) }
                let normalized=key.lowercased().replacingOccurrences(of:"_",with:"").replacingOccurrences(of:"-",with:"")
                if ["httpstatuscode","statuscode","status"].contains(normalized),let code=value.intValue,code>=400,code<=599 { status=code }
                if ["retryafter","retryafterseconds"].contains(normalized) {
                    var seconds:Double?
                    switch value { case let .int(n): seconds=Double(n);case let .double(n):seconds=n;case let .string(s):
                        seconds=Double(s)
                        if seconds == nil { let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(secondsFromGMT:0);f.dateFormat="EEE, dd MMM yyyy HH:mm:ss z";seconds=f.date(from:s).map { max(0,$0.timeIntervalSince(now)) } }
                    default:break }
                    if let seconds,seconds.isFinite,seconds>=0 { delay=max(delay ?? 0,seconds) }
                }
                if case .object=value { visit(value,depth:depth+1) }
                if ["additionalDetails","message"].contains(key),let raw=value.stringValue,raw.utf8.count<=16384,
                   let nested=try? JSONDecoder().decode(JSONValue.self,from:Data(raw.utf8)) { visit(nested,depth:depth+1) }
            }
        }
        visit(node)
        let message=CodexMessage.readableMessage(value?["message"]?.stringValue)
        let http=status ?? Self.explicitStatus(message)
        let category:Category? = providerCode.flatMap { Self.codes[$0] } == .usageLimit ? .usageLimit : http == 429 ? .rateLimit : [401,403].contains(http ?? 0) ? .authentication : providerCode.flatMap { Self.codes[$0] }
        return Self(message:message,category:category,statusCode:http,retryAfter:delay,providerCode:providerCode,rpcCode:value?["code"]?.intValue)
    }
}
