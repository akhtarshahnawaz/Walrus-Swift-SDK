import Foundation

public final class BlobCache {
    private let fileManager: FileManager
    private let cacheDir: URL
    private let maxSize: Int
    private var cacheIndex: [String: URL] = [:]
    private var accessTimes: [String: TimeInterval] = [:]
    private let cleanupOnExit: Bool
    
    public init(
        cacheDir: URL? = nil,
        maxSize: Int = 100,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        self.maxSize = maxSize
        
        if let cacheDir = cacheDir {
            self.cacheDir = cacheDir
            self.cleanupOnExit = false
        } else {
            let tempDir = fileManager.temporaryDirectory
            let uniqueDir = tempDir.appendingPathComponent("walrus_cache_\(UUID().uuidString)")
            try fileManager.createDirectory(at: uniqueDir, withIntermediateDirectories: true)
            self.cacheDir = uniqueDir
            self.cleanupOnExit = true
        }
        
        try fileManager.createDirectory(at: self.cacheDir, withIntermediateDirectories: true)
    }
    
    deinit {
        if cleanupOnExit {
            try? cleanup()
        }
    }
    
    public func get(blobId: String) -> Data? {
        guard let fileURL = cacheIndex[blobId] else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                accessTimes[blobId] = modificationDate.timeIntervalSinceReferenceDate
            }
            return data
        } catch {
            removeFromCache(blobId: blobId)
            return nil
        }
    }
    
    public func put(blobId: String, data: Data) throws -> URL {
        if cacheIndex.count >= maxSize {
            evictOldest()
        }
        
        let filename = Data(blobId.utf8).sha256().hexString
        let fileURL = cacheDir.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            cacheIndex[blobId] = fileURL
            accessTimes[blobId] = Date().timeIntervalSinceReferenceDate
            return fileURL
        } catch {
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
            throw error
        }
    }
    
    public func cleanup() throws {
        try fileManager.removeItem(at: cacheDir)
    }
    
    private func removeFromCache(blobId: String) {
        if let fileURL = cacheIndex[blobId] {
            try? fileManager.removeItem(at: fileURL)
            cacheIndex.removeValue(forKey: blobId)
            accessTimes.removeValue(forKey: blobId)
        }
    }
    
    private func evictOldest() {
        guard let oldest = accessTimes.min(by: { $0.value < $1.value }) else { return }
        removeFromCache(blobId: oldest.key)
    }
}
