import Foundation

enum TestConfig {
    // MARK: - Server URLs
    static let mockPublisherURL = URL(string: "https://test-publisher.mock/api")!
    static let mockAggregatorURL = URL(string: "https://test-aggregator.mock/api")!
    
    // MARK: - Test Data
    static let testBlobID = "test-blob-123"
    static let testObjectID = "test-obj-456"
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
