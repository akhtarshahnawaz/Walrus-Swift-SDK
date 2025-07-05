import os
from typing import Dict, Optional, Any, BinaryIO, IO
import requests
from requests.exceptions import RequestException
import hashlib
import tempfile
import atexit
import shutil


class BlobCache:
    """
    A cache for storing downloaded blobs to avoid repeated downloads.
    
    Uses blob_id as the cache key and stores files in a temporary directory.
    """

    def __init__(self, cache_dir: Optional[str] = None, max_size: int = 100):
        """
        Initialize the blob cache.
        
        Args:
            cache_dir: Directory to store cached files. If None, uses a temporary directory.
            max_size: Maximum number of files to keep in the cache.
        """
        self.cache_dir = cache_dir or tempfile.mkdtemp(prefix="walrus_cache_")
        self.max_size = max_size
        self._cache_index = {}  # blob_id -> file_path
        self._access_times = {}  # blob_id -> last access time
        
        # Ensure cache directory exists
        os.makedirs(self.cache_dir, exist_ok=True)
        
        # Register cleanup on program exit
        if cache_dir is None:  # Only clean up if we created a temp dir
            atexit.register(self.cleanup)

    def get(self, blob_id: str) -> Optional[bytes]:
        """
        Retrieve a blob from cache if it exists.
        
        Args:
            blob_id: The blob ID to look up
            
        Returns:
            The cached blob data if found, None otherwise
        """
        if blob_id not in self._cache_index:
            return None
            
        file_path = self._cache_index[blob_id]
        
        try:
            with open(file_path, "rb") as f:
                data = f.read()
            self._access_times[blob_id] = os.path.getmtime(file_path)
            return data
        except (IOError, OSError):
            self._remove_from_cache(blob_id)
            return None

    def put(self, blob_id: str, data: bytes) -> str:
        """
        Store a blob in the cache.
        
        Args:
            blob_id: The blob ID to store
            data: The blob data to cache
            
        Returns:
            Path to the cached file
        """
        # Clean up if cache is full
        if len(self._cache_index) >= self.max_size:
            self._evict_oldest()
            
        # Create a unique filename based on blob_id
        filename = hashlib.sha256(blob_id.encode()).hexdigest()
        file_path = os.path.join(self.cache_dir, filename)
        
        try:
            with open(file_path, "wb") as f:
                f.write(data)
            
            self._cache_index[blob_id] = file_path
            self._access_times[blob_id] = os.path.getmtime(file_path)
            return file_path
        except (IOError, OSError):
            # If writing fails, remove the file if it was created
            if os.path.exists(file_path):
                try:
                    os.remove(file_path)
                except OSError:
                    pass
            raise

    def _remove_from_cache(self, blob_id: str) -> None:
        """Remove a blob from the cache."""
        if blob_id in self._cache_index:
            file_path = self._cache_index[blob_id]
            try:
                os.remove(file_path)
            except OSError:
                pass
            del self._cache_index[blob_id]
            if blob_id in self._access_times:
                del self._access_times[blob_id]

    def _evict_oldest(self) -> None:
        """Evict the least recently accessed blob from the cache."""
        if not self._access_times:
            return
            
        oldest_blob_id = min(self._access_times.items(), key=lambda x: x[1])[0]
        self._remove_from_cache(oldest_blob_id)

    def cleanup(self) -> None:
        """Clean up the cache directory."""
        try:
            shutil.rmtree(self.cache_dir)
        except OSError:
            pass


class WalrusAPIError(RequestException):
    """Exception raised for errors in the Walrus API responses."""

    def __init__(
        self, code: int, status: str, message: str, details: list, context: str = ""
    ):
        self.code = code
        self.status = status
        self.message = message
        self.details = details
        error_msg = f"{context}: HTTP {code} - {status}: {message}" + (
            f" (Details: {details})" if details else ""
        )
        super().__init__(error_msg)

    def __str__(self) -> str:
        return f"HTTP {self.code} - {self.status}: {self.message}" + (
            f" (Details: {self.details})" if self.details else ""
        )


class WalrusClient:
    """
    Client for interacting with the Walrus API.

    Provides methods for uploading and retrieving binary blobs from publisher and aggregator endpoints.
    """

    def __init__(
        self,
        publisher_base_url: str,
        aggregator_base_url: str,
        timeout: int = 30,
        cache_dir: Optional[str] = None,
        cache_max_size: int = 100,
    ):
        """
        Initialize the Walrus client.

        Args:
            publisher_base_url: Base URL for the publisher service
            aggregator_base_url: Base URL for the aggregator service
            timeout: Request timeout in seconds
            cache_dir: Directory to store cached blobs. If None, uses a temporary directory.
            cache_max_size: Maximum number of blobs to cache.
        """
        self.publisher_base_url = publisher_base_url.rstrip("/")
        self.aggregator_base_url = aggregator_base_url.rstrip("/")
        self.timeout = timeout
        self.cache = BlobCache(cache_dir, cache_max_size)

    def put_blob(
        self,
        data: bytes,
        encoding_type: Optional[str] = None,
        epochs: Optional[int] = None,
        deletable: Optional[bool] = None,
        send_object_to: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Upload binary data (a blob) to a publisher.

        Args:
            data: Binary data to upload
            encoding_type: The encoding type to use for the blob
            epochs: Number of epochs ahead of the current one to store the blob
            deletable: If true, creates a deletable blob instead of a permanent one
            send_object_to: If specified, sends the Blob object to this Sui address

        Returns:
            JSON response from the server

        Raises:
            WalrusAPIError: If the API request fails
        """
        url = f"{self.publisher_base_url}/v1/blobs"
        headers = {"Content-Type": "application/octet-stream"}
        params = self._build_query_params(
            encoding_type, epochs, deletable, send_object_to
        )

        try:
            response = requests.put(
                url, data=data, headers=headers, params=params, timeout=self.timeout
            )
            response.raise_for_status()
            return response.json()
        except RequestException as e:
            self._handle_request_error(e, "Error uploading blob")

    def put_blob_from_file(
        self,
        file_path: str,
        encoding_type: Optional[str] = None,
        epochs: Optional[int] = None,
        deletable: Optional[bool] = None,
        send_object_to: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Upload a blob from a file to the publisher.

        Args:
            file_path: Path to the file to upload
            encoding_type: The encoding type to use for the blob
            epochs: Number of epochs ahead of the current one to store the blob
            deletable: If true, creates a deletable blob instead of a permanent one
            send_object_to: If specified, sends the Blob object to this Sui address

        Returns:
            JSON response from the server

        Raises:
            FileNotFoundError: If the file does not exist
            WalrusAPIError: If the API request fails
        """
        if not os.path.isfile(file_path):
            raise FileNotFoundError(f"File not found: {file_path}")

        with open(file_path, "rb") as file:
            data = file.read()

        return self.put_blob(data, encoding_type, epochs, deletable, send_object_to)

    def put_blob_from_stream(
        self,
        stream: BinaryIO,
        encoding_type: Optional[str] = None,
        epochs: Optional[int] = None,
        deletable: Optional[bool] = None,
        send_object_to: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Upload a blob from a binary stream to the publisher.

        Args:
            stream: Binary stream to upload (must be in binary mode)
            encoding_type: The encoding type to use for the blob
            epochs: Number of epochs ahead of the current one to store the blob
            deletable: If true, creates a deletable blob instead of a permanent one
            send_object_to: If specified, sends the Blob object to this Sui address

        Returns:
            JSON response from the server

        Raises:
            ValueError: If the stream is not readable
            WalrusAPIError: If the API request fails
        """
        if not stream.readable():
            raise ValueError("Provided stream is not readable")

        url = f"{self.publisher_base_url}/v1/blobs"
        headers = {"Content-Type": "application/octet-stream"}
        params = self._build_query_params(
            encoding_type, epochs, deletable, send_object_to
        )

        try:
            response = requests.put(
                url, data=stream, headers=headers, params=params, timeout=self.timeout
            )
            response.raise_for_status()
            return response.json()
        except RequestException as e:
            self._handle_request_error(e, "Error uploading blob from stream")

    def get_blob_by_object_id(self, object_id: str) -> bytes:
        """
        Retrieve a blob from the aggregator by its object ID.

        Args:
            object_id: The object ID of the blob

        Returns:
            Binary content of the blob

        Raises:
            WalrusAPIError: If the API request fails
        """
        url = f"{self.aggregator_base_url}/v1/blobs/by-object-id/{object_id}"

        try:
            response = requests.get(url, timeout=self.timeout)
            response.raise_for_status()
            return response.content
        except RequestException as e:
            self._handle_request_error(
                e, f"Error retrieving blob by object ID: {object_id}"
            )

    def get_blob(self, blob_id: str) -> bytes:
        """
        Retrieve a blob from the aggregator by its blob ID.

        First checks the cache, and if not found, downloads from the server and caches it.

        Args:
            blob_id: The blob ID

        Returns:
            Binary content of the blob

        Raises:
            WalrusAPIError: If the API request fails
        """
        # Try to get from cache first
        cached_data = self.cache.get(blob_id)
        if cached_data is not None:
            return cached_data

        # Not in cache, download from server
        url = f"{self.aggregator_base_url}/v1/blobs/{blob_id}"

        try:
            response = requests.get(url, timeout=self.timeout)
            response.raise_for_status()
            data = response.content
            
            # Cache the downloaded data
            try:
                self.cache.put(blob_id, data)
            except Exception:
                pass  # Cache failure shouldn't break the operation
                
            return data
        except RequestException as e:
            self._handle_request_error(
                e, f"Error retrieving blob by blob ID: {blob_id}"
            )

    def get_blob_as_stream(self, blob_id: str) -> IO[bytes]:
        """
        Retrieve a blob from the aggregator as a stream by its blob ID.

        Args:
            blob_id: The blob ID

        Returns:
            A file-like object (stream) for reading the blob data

        Raises:
            WalrusAPIError: If the API request fails
        """
        url = f"{self.aggregator_base_url}/v1/blobs/{blob_id}"
        try:
            response = requests.get(url, stream=True, timeout=self.timeout)
            response.raise_for_status()
            return response.raw
        except RequestException as e:
            self._handle_request_error(
                e, f"Error retrieving blob as stream by blob ID: {blob_id}"
            )

    def get_blob_as_file(self, blob_id: str, file_path: str) -> None:
        """
        Retrieve a blob from the aggregator by its blob ID and save it to a file.

        Args:
            blob_id: The blob ID
            file_path: The destination file path where the blob will be saved

        Raises:
            WalrusAPIError: If the API request fails
        """
        # Try to get from cache first
        cached_data = self.cache.get(blob_id)
        if cached_data is not None:
            with open(file_path, "wb") as f:
                f.write(cached_data)
            return

        # Not in cache, download from server
        url = f"{self.aggregator_base_url}/v1/blobs/{blob_id}"
        try:
            with requests.get(url, stream=True, timeout=self.timeout) as response:
                response.raise_for_status()
                
                # Write to file and cache simultaneously
                temp_file = tempfile.NamedTemporaryFile(delete=False)
                try:
                    for chunk in response.iter_content(chunk_size=8192):
                        if chunk:
                            temp_file.write(chunk)
                    temp_file.close()
                    
                    # Cache the downloaded file
                    try:
                        with open(temp_file.name, "rb") as f:
                            data = f.read()
                        self.cache.put(blob_id, data)
                    except Exception:
                        pass  # Cache failure shouldn't break the operation
                    
                    # Move the temp file to the destination
                    shutil.move(temp_file.name, file_path)
                except Exception:
                    temp_file.close()
                    if os.path.exists(temp_file.name):
                        os.remove(temp_file.name)
                    raise
        except RequestException as e:
            self._handle_request_error(
                e, f"Error retrieving blob as file by blob ID: {blob_id}"
            )

    def get_blob_metadata(self, blob_id: str) -> Dict[str, str]:
        """
        Retrieve metadata for a blob from the aggregator by making a HEAD request.

        Args:
            blob_id: The blob ID

        Returns:
            Dictionary containing the response headers

        Raises:
            WalrusAPIError: If the API request fails
        """
        url = f"{self.aggregator_base_url}/v1/blobs/{blob_id}"

        try:
            response = requests.head(url, timeout=self.timeout)
            response.raise_for_status()
            return dict(response.headers)
        except RequestException as e:
            self._handle_request_error(
                e, f"Error retrieving metadata for blob ID: {blob_id}"
            )

    def _build_query_params(
        self,
        encoding_type: Optional[str] = None,
        epochs: Optional[int] = None,
        deletable: Optional[bool] = None,
        send_object_to: Optional[str] = None,
    ) -> Dict[str, str]:
        """Build query parameters for blob upload requests."""
        params = {}
        if encoding_type is not None:
            params["encoding_type"] = encoding_type
        if epochs is not None:
            params["epochs"] = str(epochs)
        if deletable is not None:
            params["deletable"] = "true" if deletable else "false"
        if send_object_to is not None:
            params["send_object_to"] = send_object_to
        return params

    def _handle_request_error(self, exception: RequestException, context: str) -> None:
        """Handle request exceptions by extracting structured error information."""
        if hasattr(exception, "response") and exception.response is not None:
            try:
                if exception.response.content:
                    error_json = exception.response.json()
                    if isinstance(error_json, dict) and "error" in error_json:
                        err = error_json["error"]
                        code = err.get("code", exception.response.status_code)
                        status = err.get("status", "UNKNOWN")
                        message = err.get("message", "")
                        details = err.get("details", [])
                        raise WalrusAPIError(
                            code, status, message, details, context=context
                        ) from exception

                # Fall back to HTTP response info
                code = exception.response.status_code
                status = exception.response.reason or "UNKNOWN"
                message = f"HTTP {code}: {status}"
                raise WalrusAPIError(
                    code, status, message, [], context=context
                ) from exception

            except (ValueError, requests.exceptions.JSONDecodeError):
                code = exception.response.status_code
                status = exception.response.reason or "UNKNOWN"
                message = f"HTTP {code}: {status}"
                raise WalrusAPIError(
                    code, status, message, [], context=context
                ) from exception
        else:
            # No response available - network error, timeout, etc.
            raise WalrusAPIError(
                500, "REQUEST_FAILED", str(exception), [], context=context
            ) from exception