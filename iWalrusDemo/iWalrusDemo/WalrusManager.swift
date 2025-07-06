import Foundation
import WalrusSDK

class WalrusManager {
    static let shared = WalrusManager()

    lazy var client: WalrusClient = {
        return try! WalrusClient(
            publisherBaseURL: URL(string: "http://walrus-testnet-publisher.starduststaking.com")!,
            aggregatorBaseURL: URL(string: "http://agg.test.walrus.eosusa.io")!,
            timeout: 30,
            cacheDir: nil,
            cacheMaxSize: 100
        )
    }()

    private init() {}
}
