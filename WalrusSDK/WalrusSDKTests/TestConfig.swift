import Foundation

enum TestConfig {
    // MARK: - Server URLs
    static let mockPublisherURL = URL(string: "https://walrus-testnet-publisher.starduststaking.com")!
    static let mockAggregatorURL = URL(string: "https://agg.test.walrus.eosusa.io")!
    
    // MARK: - Test Data
    static let testBlobID = "__7swun-DDZycpiChavVe3p6gBuKO-C5R9S8EexlzR0"
    static let testBlobData = Data("Test blob content".utf8)
    
    // MARK: - File Handling
    private static let testFileName = "walrus-test-file.data"
    static var testFileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(testFileName)
    }
    
    // MARK: - Test Parameters
    enum Params {
        static let encodingType = "test-encoding"
        static let epochs = 3
        static let sendObjectTo = "test-address"
    }
    
    // MARK: - Setup Helpers
    @discardableResult
    static func prepareTestFile() throws -> URL {
        try testBlobData.write(to: testFileURL)
        return testFileURL
    }
    
    static func cleanup() throws {
        if FileManager.default.fileExists(atPath: testFileURL.path) {
            try FileManager.default.removeItem(at: testFileURL)
        }
    }
}
