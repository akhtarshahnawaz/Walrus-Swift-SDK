import XCTest
@testable import WalrusSDK

final class WalrusSDKTests: XCTestCase {
    var client: WalrusClient!
    var downloadTestFileURL: URL?
    
    override func setUp() async throws {
        try await super.setUp()
        client = try WalrusClient(
            publisherBaseURL: TestConfig.mockPublisherURL,
            aggregatorBaseURL: TestConfig.mockAggregatorURL,
            timeout: 10
        )
        // Prepare test file and verify it was created
        let testFile = try TestConfig.prepareTestFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))
    }
    
    override func tearDown() {
        // Clean up any test files
        if let downloadURL = downloadTestFileURL {
            try? FileManager.default.removeItem(at: downloadURL)
        }
        XCTAssertNoThrow(try TestConfig.cleanup())
        client = nil
        super.tearDown()
    }
    
    // MARK: - File Upload Tests
    func testFileUpload() async throws {
        // Verify test file exists (should have been created in setUp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: TestConfig.testFileURL.path))
        
        do {
            let response = try await client.putBlobFromFile(
                fileURL: TestConfig.testFileURL,
                encodingType: TestConfig.Params.encodingType
            )
            XCTAssertFalse(response.isEmpty)
        } catch {
            XCTFail("File upload failed: \(error)")
        }
    }
    
    // MARK: - File Download Tests
    func testFileDownload() async throws {
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("walrus-download-test-\(UUID().uuidString).data")
        downloadTestFileURL = destURL  // Store for cleanup in tearDown
        
        // Clean up in case previous test failed
        try? FileManager.default.removeItem(at: destURL)
        
        do {
            try await client.getBlobAsFile(
                blobId: TestConfig.testBlobID,
                destinationURL: destURL
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
        } catch {
            XCTFail("File download failed: \(error)")
            // Clean up immediately if test fails
            try? FileManager.default.removeItem(at: destURL)
            downloadTestFileURL = nil
        }
    }
}
