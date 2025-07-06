**iWalrusSDK** is an iOS SDK built to enable smooth uploading, downloading, publisher authentication, caching of binary blobs, and streaming via customizable publisher and aggregator services through the Walrus HTTP API. Designed to work seamlessly with Walrus—a decentralized blob storage service—it features a versatile and secure client, `WalrusClient`, that facilitates efficient interaction with backend APIs by managing data transfers and caching intelligently, while supporting both secure and insecure (non-SSL-validated) connections.

This SDK is compatible with **iOS 15.0+** and **macOS 12.0+**.

## Features

- Upload blobs from memory or file with configurable metadata, ensuring flexibility in how data is sent to the storage backend.
- Download blobs by ID with automatic caching support, reducing redundant network calls and improving performance through local storage.
- Advanced local blob caching with customizable cache directory and size limits, allowing precise control over storage footprint and retrieval speed.
- Streaming support for large blobs through configurable publisher and aggregator services, enabling efficient, chunked data transfer without exhausting device memory.
- Publisher authentication to securely identify and authorize both upload and download operations, protecting data integrity and access.
- Retrieve blob metadata via HTTP HEAD requests to check existence or versioning without transferring full content.
- Optionally disable SSL validation for insecure or testing environments when needed.
- Timeout configuration for all network operations, ensuring resilience against unstable network conditions.
- Seamless integration with Walrus, a decentralized blob storage service, providing distributed and fault-tolerant data storage infrastructure.

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

## Authentication

The `WalrusClient` supports JWT (JSON Web Token) authentication for secure API requests. You can set, update, or clear the authentication token as needed.

#### Setting the JWT Token

If your API requires authentication, set the JWT token before making requests:

```swift
// Set or update the JWT token
client.setJWTToken("your.jwt.token.here")
```

The token will be included in the `Authorization` header for all subsequent requests as:

```
Authorization: Bearer your.jwt.token.here
```

#### Per-Request Token Override

For individual requests, you can pass a token directly to methods that support it (overriding the client-wide token):

```swift
let response = try await client.putBlob(
    data: data,
    jwtToken: "temporary.token.here"  // Used only for this request
)
```

#### Clearing the Token

To remove authentication (e.g., during logout):

```swift
client.clearJWTToken()
```

#### Notes:

1. **Secure Connections**: When `useSecureConnection: true` (recommended), all requests (including authenticated ones) are encrypted via HTTPS.
2. **Token Storage**: The SDK does not persist tokens – manage token storage/refresh in your app layer.
3. **Error Handling**: Expired/invalid tokens will result in `WalrusAPIError` with HTTP 401/403 status codes.

## Requirements

- Swift 5.5+
- iOS 15.0+ / macOS 12.0+
- Network access to configured publisher and aggregator endpoints
