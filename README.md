**WalrusSDK** is a Swift framework designed for seamless uploading, downloading, and caching of binary blobs through configurable publisher and aggregator services. It offers a flexible and secure client, `WalrusClient`, to interact with your backend APIs, handling data transfers and caching efficiently with support for both secure and insecure (non-SSL-validated) connections.

This framework is compatible with **iOS 15.0+** and **macOS 12.0+**.

## Features

- Upload blobs from memory or file with configurable metadata
- Download blobs by ID with automatic caching support
- Retrieve blob metadata via HTTP HEAD requests
- Optionally disable SSL validation for insecure environments
- Timeout configuration for all network operations
- Local blob caching with customizable cache directory and size limits

## Integration Guide

### Step 1: Build the WalrusSDK Framework

1. Open your **WalrusSDK** project in Xcode.
2. Select the `WalrusSDK` framework target.
3. Build the framework (`Product` → `Build` or `Cmd + B`).
4. Locate the built `.framework` bundle in the build folder (e.g., `DerivedData`).

### Step 2: Add WalrusSDK to Your Project

#### Option A: Add as Embedded Framework

1. Drag and drop the `WalrusSDK.framework` file into your app project’s **Frameworks** group.
2. Ensure the framework is added to your app target under **General** → **Frameworks, Libraries, and Embedded Content**.
3. Set embedding option to **Embed & Sign** (for iOS/macOS apps).

#### Option B: Add via Swift Package Manager (Optional)

If you host `WalrusSDK` in a Git repository, you can add it as a Swift package dependency:

- Go to **File** → **Add Packages...**
- Enter the URL of your repository.
- Choose the version or branch.
- Add the package to your app target.

### Step 3: Import WalrusSDK in Your Code

```swift
import WalrusSDK
```

## Usage

### Creating a WalrusClient Instance

```swift

do {
    let publisherURL = URL(string: "https://publisher.example.com")!
    let aggregatorURL = URL(string: "https://aggregator.example.com")!

    let client = try WalrusClient(
        publisherBaseURL: publisherURL,
        aggregatorBaseURL: aggregatorURL,
        timeout: 30,                   // timeout in seconds (default: 30)
        cacheDir: nil,                 // nil uses default cache directory
        cacheMaxSize: 100,             // max cache size in MB
        useSecureConnection: true     // enable SSL validation (recommended)
    )
} catch {
    print("Failed to create WalrusClient:", error)
}
```

### Uploading a Blob

Upload binary data with optional parameters:

```swift
func uploadBlob(client: WalrusClient, data: Data) async {
    do {
        let response = try await client.putBlob(
            data: data,
            epochs: 5,
            deletable: true,
            sendObjectTo: <account address>
        )
        print("Upload succeeded:", response)
    } catch {
        print("Upload failed:", error)
    }
}
```

Upload a blob directly from a file URL:

```swift

func uploadBlobFromFile(client: WalrusClient, fileURL: URL) async {
    do {
        let response = try await client.putBlobFromFile(fileURL: fileURL)
        print("File upload succeeded:", response)
    } catch {
        print("File upload failed:", error)
    }
}
```

### Downloading a Blob

Download blob data by its ID with automatic caching:

```swift

func downloadBlob(client: WalrusClient, blobId: String) async {
    do {
        let data = try await client.getBlob(blobId: blobId)
        print("Blob downloaded, size:", data.count)
    } catch {
        print("Download failed:", error)
    }
}
```

Download blob as a file to a destination URL:

```swift

func downloadBlobAsFile(client: WalrusClient, blobId: String, destinationURL: URL) async {
    do {
        try await client.getBlobAsFile(blobId: blobId, destinationURL: destinationURL)
        print("Blob saved to:", destinationURL.path)
    } catch {
        print("Failed to save blob as file:", error)
    }
}
```

### Fetch Blob Metadata

Retrieve HTTP header metadata of a blob without downloading the content:

```swift

func fetchBlobMetadata(client: WalrusClient, blobId: String) async {
    do {
        let metadata = try await client.getBlobMetadata(blobId: blobId)
        print("Blob metadata:", metadata)
    } catch {
        print("Failed to fetch metadata:", error)
    }
}
```

## Error Handling

`WalrusClient` throws descriptive errors of type `WalrusAPIError` containing:

- `code`: HTTP status code or API error code
- `status`: Error status string
- `message`: Human-readable message
- `details`: Additional error details
- `context`: Custom error context for easier debugging

Use `do-catch` blocks and print or handle errors gracefully.

## Requirements

- Swift 5.5+
- iOS 15.0+ / macOS 12.0+
- Network access to configured publisher and aggregator endpoints
