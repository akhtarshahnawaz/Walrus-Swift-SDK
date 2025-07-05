import Foundation

@available(macOS 12.0, iOS 15.0, *)
public final class WalrusClient: NSObject, URLSessionDelegate {
    public let publisherBaseURL: URL
    public let aggregatorBaseURL: URL
    public let timeout: TimeInterval
    public let cache: BlobCache
    private let fileManager = FileManager.default
    
    private let useSecureConnection: Bool
    private var jwtToken: String? // Stores the JWT token for authenticated requests
    
    private lazy var session: URLSession = {
        if useSecureConnection {
            return URLSession.shared
        } else {
            let config = URLSessionConfiguration.default
            return URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }
    }()
    
    public init(
        publisherBaseURL: URL,
        aggregatorBaseURL: URL,
        timeout: TimeInterval = 30,
        cacheDir: URL? = nil,
        cacheMaxSize: Int = 100,
        useSecureConnection: Bool = false,
        jwtToken: String? = nil
    ) throws {
        self.publisherBaseURL = publisherBaseURL
        self.aggregatorBaseURL = aggregatorBaseURL
        self.timeout = timeout
        self.cache = try BlobCache(cacheDir: cacheDir, maxSize: cacheMaxSize)
        self.useSecureConnection = useSecureConnection
        self.jwtToken = jwtToken
        super.init()
    }
    
    // MARK: - Authentication Methods
    
    /// Sets or updates the JWT token for authenticated requests
    public func setJWTToken(_ token: String) {
        self.jwtToken = token
    }
    
    /// Clears the current JWT token
    public func clearJWTToken() {
        self.jwtToken = nil
    }
    
    // URLSessionDelegate method to disable SSL validation if insecure mode is on
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if !useSecureConnection {
            // Insecure mode: accept any certificate
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        } else {
            // Default behavior
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    // MARK: - Upload Methods
    
    @available(macOS 12.0, iOS 15.0, *)
    public func putBlob(
        data: Data,
        encodingType: String? = nil,
        epochs: Int? = nil,
        deletable: Bool? = nil,
        sendObjectTo: String? = nil,
        jwtToken: String? = nil
    ) async throws -> [String: Any] {
        let url = publisherBaseURL.appendingPathComponent("v1/blobs")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = buildQueryItems(
            epochs: epochs,
            deletable: deletable,
            sendObjectTo: sendObjectTo
        )
        
        guard let requestUrl = components?.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        
        // Add JWT token if provided (either through method parameter or instance property)
        if let token = jwtToken ?? self.jwtToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, _) = try await executeRequest(request: request, context: "Error uploading blob")
        return try parseJSONResponse(data: data)
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    public func putBlobFromFile(
        fileURL: URL,
        encodingType: String? = nil,
        epochs: Int? = nil,
        deletable: Bool? = nil,
        sendObjectTo: String? = nil,
        jwtToken: String? = nil
    ) async throws -> [String: Any] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        
        let data = try Data(contentsOf: fileURL)
        return try await putBlob(
            data: data,
            epochs: epochs,
            deletable: deletable,
            sendObjectTo: sendObjectTo,
            jwtToken: jwtToken
        )
    }
    
    // MARK: - Streaming Upload
    
    @available(macOS 12.0, iOS 15.0, *)
    public func putBlobStreaming(
        fileURL: URL,
        encodingType: String? = nil,
        epochs: Int? = nil,
        deletable: Bool? = nil,
        sendObjectTo: String? = nil,
        jwtToken: String? = nil
    ) async throws -> [String: Any] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        
        let url = publisherBaseURL.appendingPathComponent("v1/blobs")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = buildQueryItems(epochs: epochs, deletable: deletable, sendObjectTo: sendObjectTo)
        
        guard let requestUrl = components?.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        
        // Add JWT token if provided (either through method parameter or instance property)
        if let token = jwtToken ?? self.jwtToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Wrap URLSessionUploadTask with continuation for async/await
        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = session.uploadTask(with: request, fromFile: fileURL) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode,
                      let data = data else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                do {
                    let json = try self.parseJSONResponse(data: data)
                    continuation.resume(returning: json)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            uploadTask.resume()
        }
    }
    
    // MARK: - Download Methods
    @available(macOS 12.0, iOS 15.0, *)
    public func getBlobByObjectId(objectId: String) async throws -> Data {
        let url = aggregatorBaseURL.appendingPathComponent("/v1/blobs/\(objectId)")
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        
        let (data, _) = try await executeRequest(request: request, context: "Error retrieving blob by object ID: \(objectId)")
        return data
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    public func getBlob(blobId: String) async throws -> Data {
        if let cachedData = cache.get(blobId: blobId) {
            return cachedData
        }
        
        let url = aggregatorBaseURL.appendingPathComponent("/v1/blobs/\(blobId)")
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        
        let (data, _) = try await executeRequest(request: request, context: "Error retrieving blob by blob ID: \(blobId)")
        
        // Cache the result (ignore errors)
        _ = try? cache.put(blobId: blobId, data: data)
        return data
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    public func getBlobAsFile(blobId: String, destinationURL: URL) async throws {
        if let cachedData = cache.get(blobId: blobId) {
            try cachedData.write(to: destinationURL)
            return
        }
        
        let url = aggregatorBaseURL.appendingPathComponent("/v1/blobs/\(blobId)")
        let (tempURL, response) = try await session.download(from: url)
        defer { try? fileManager.removeItem(at: tempURL) }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WalrusAPIError(
                code: 500,
                status: "INVALID_RESPONSE",
                message: "Invalid response from server"
            )
        }
        
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorData = try? Data(contentsOf: tempURL)
            throw try handleErrorResponse(
                data: errorData,
                response: httpResponse,
                context: "Error retrieving blob as file by blob ID: \(blobId)"
            )
        }
        
        // Cache the result (ignore errors)
        if let data = try? Data(contentsOf: tempURL) {
            _ = try? cache.put(blobId: blobId, data: data)
        }
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
    }
    
    
    
    @available(macOS 12.0, iOS 15.0, *)
    public func getBlobMetadata(blobId: String) async throws -> [AnyHashable: Any] {
        let url = aggregatorBaseURL.appendingPathComponent("/v1/blobs/\(blobId)")
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WalrusAPIError(
                code: 500,
                status: "INVALID_RESPONSE",
                message: "Invalid response from server"
            )
        }
        
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw try handleErrorResponse(
                data: nil,
                response: httpResponse,
                context: "Error retrieving metadata for blob ID: \(blobId)"
            )
        }
        
        return httpResponse.allHeaderFields
    }


    @available(macOS 12.0, iOS 15.0, *)
    public func getBlobAsFileStreaming(
        blobId: String,
        destinationURL: URL
    ) async throws {
        // Check cache first
        if let cachedData = cache.get(blobId: blobId) {
            try cachedData.write(to: destinationURL)
            return
        }
        
        let url = aggregatorBaseURL.appendingPathComponent("/v1/blobs/\(blobId)")
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        
        // Use URLSession downloadTask with continuation to await
        let (tempURL, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
            let downloadTask = session.downloadTask(with: request) { tempURL, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL = tempURL, let response = response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (tempURL, response))
            }
            downloadTask.resume()
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WalrusAPIError(
                code: 500,
                status: "INVALID_RESPONSE",
                message: "Invalid response from server"
            )
        }
        
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorData = try? Data(contentsOf: tempURL)
            throw try handleErrorResponse(
                data: errorData,
                response: httpResponse,
                context: "Error retrieving blob as file by blob ID: \(blobId)"
            )
        }
        
        // Cache the blob if possible
        if let data = try? Data(contentsOf: tempURL) {
            _ = try? cache.put(blobId: blobId, data: data)
        }
        
        // Move downloaded file to destination
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
    }
    // MARK: - Private Helpers
    
    private func buildQueryItems(
        epochs: Int?,
        deletable: Bool?,
        sendObjectTo: String?
    ) -> [URLQueryItem] {
        var items = [URLQueryItem]()
        
        if let epochs = epochs {
            items.append(URLQueryItem(name: "epochs", value: String(epochs)))
        }
        if let deletable = deletable {
            items.append(URLQueryItem(name: "deletable", value: deletable ? "true" : "false"))
        }
        if let sendObjectTo = sendObjectTo {
            items.append(URLQueryItem(name: "send_object_to", value: sendObjectTo))
        }
        
        return items
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    private func executeRequest(request: URLRequest, context: String) async throws -> (Data, URLResponse) {
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WalrusAPIError(
                code: 500,
                status: "INVALID_RESPONSE",
                message: "Invalid response from server"
            )
        }
        
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw try handleErrorResponse(
                data: data,
                response: httpResponse,
                context: context
            )
        }
        
        return (data, response)
    }
    
    private func parseJSONResponse(data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WalrusAPIError(
                code: 500,
                status: "INVALID_RESPONSE",
                message: "Failed to parse response JSON"
            )
        }
        return json
    }
    
    private func handleErrorResponse(
        data: Data?,
        response: HTTPURLResponse,
        context: String
    ) throws -> WalrusAPIError {
        if let data = data {
            do {
                if let errorJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorDict = errorJson["error"] as? [String: Any] {
                    let code = errorDict["code"] as? Int ?? response.statusCode
                    let status = errorDict["status"] as? String ?? "UNKNOWN"
                    let message = errorDict["message"] as? String ?? ""
                    let details = errorDict["details"] as? [Any] ?? []
                    return WalrusAPIError(
                        code: code,
                        status: status,
                        message: message,
                        details: details,
                        context: context
                    )
                }
            } catch {
                // Fall through to generic error handling
            }
        }
        
        return WalrusAPIError(
            code: response.statusCode,
            status: response.statusCode >= 500 ? "SERVER_ERROR" : "CLIENT_ERROR",
            message: HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
            context: context
        )
    }
}
