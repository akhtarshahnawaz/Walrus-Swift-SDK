import Foundation

public struct WalrusAPIError: Error, CustomStringConvertible {
    public let code: Int
    public let status: String
    public let message: String
    public let details: [Any]
    public let context: String
    
    public init(
        code: Int,
        status: String,
        message: String,
        details: [Any] = [],
        context: String = ""
    ) {
        self.code = code
        self.status = status
        self.message = message
        self.details = details
        self.context = context
    }
    
    public var description: String {
        var desc = "HTTP \(code) - \(status): \(message)"
        if !details.isEmpty {
            desc += " (Details: \(details))"
        }
        if !context.isEmpty {
            desc = "\(context): \(desc)"
        }
        return desc
    }
}
