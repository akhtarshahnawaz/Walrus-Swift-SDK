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
            
            print("RESPONSE: \(response)")
            // Extract blobId from nested response dictionary
            
            if let blobId = findBlobId(in: response) {
                do {
                    let response = try await client.getBlobByObjectId(
                        objectId: blobId
                    )
                    XCTAssertFalse(response.isEmpty)
                    print("Retrieved Content: \(response)")
                } catch {
                    XCTFail("File re-retrieval after upload using getBlobByObjectId  failed: \(error)")
                }
            } else {
                XCTFail("Failed to extract blobId from response")
            }
            
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

func findBlobId(in json: Any) -> String? {
    if let dict = json as? [String: Any] {
        for (key, value) in dict {
            if key == "blobId", let blobId = value as? String {
                return blobId
            }
            // Recursively search nested dictionaries or arrays
            if let found = findBlobId(in: value) {
                return found
            }
        }
    } else if let array = json as? [Any] {
        for item in array {
            if let found = findBlobId(in: item) {
                return found
            }
        }
    }
    return nil
}

