import os, time
import hashlib
from typing import Dict, Optional, Any, BinaryIO, IO, Union
import requests
from requests.exceptions import RequestException
from functools import lru_cache
import tempfile
import atexit
import shutil

class WalrusClient:
    """
    Client for interacting with the Walrus API with caching and streaming support.
    """
    
    def __init__(
        self,
        publisher_base_url: str,
        aggregator_base_url: str,
        timeout: int = 30,
        cache_enabled: bool = True,
        cache_dir: Optional[str] = None,
        cache_max_size: int = 1024 * 1024 * 1024,  # 1GB default
        cache_ttl: int = 3600  # 1 hour default
    ):
        """
        Initialize the Walrus client with optional caching.

        Args:
            publisher_base_url: Base URL for the publisher service
            aggregator_base_url: Base URL for the aggregator service
            timeout: Request timeout in seconds
            cache_enabled: Whether to enable caching
            cache_dir: Directory to store cached files (None for temp dir)
            cache_max_size: Maximum cache size in bytes
            cache_ttl: Cache time-to-live in seconds
        """
        self.publisher_base_url = publisher_base_url.rstrip("/")
        self.aggregator_base_url = aggregator_base_url.rstrip("/")
        self.timeout = timeout
        self.cache_enabled = cache_enabled
        self.cache_max_size = cache_max_size
        self.cache_ttl = cache_ttl
        
        # Set up cache directory
        if cache_dir:
            self.cache_dir = cache_dir
            os.makedirs(cache_dir, exist_ok=True)
        else:
            self.cache_dir = tempfile.mkdtemp(prefix="walrus_cache_")
            atexit.register(self._cleanup_temp_cache)
            
        # Track cache usage
        self._cache_size = 0
        self._cache_entries = {}  # {blob_id: (size, timestamp)}
        
    def _cleanup_temp_cache(self):
        """Clean up temporary cache directory on exit."""
        if hasattr(self, 'cache_dir') and not hasattr(self, '_user_provided_cache_dir'):
            shutil.rmtree(self.cache_dir, ignore_errors=True)
    
    def _get_cache_path(self, blob_id: str) -> str:
        """Get filesystem path for a cached blob."""
        safe_id = hashlib.md5(blob_id.encode()).hexdigest()
        return os.path.join(self.cache_dir, f"blob_{safe_id}")
    
    def _check_cache(self, blob_id: str) -> Optional[bytes]:
        """Check if blob is in cache and return it if valid."""
        if not self.cache_enabled:
            return None
            
        cache_path = self._get_cache_path(blob_id)
        
        # Check if exists and not expired
        if os.path.exists(cache_path):
            mtime = os.path.getmtime(cache_path)
            if (time.time() - mtime) < self.cache_ttl:
                with open(cache_path, 'rb') as f:
                    return f.read()
            # Cache expired, remove it
            os.remove(cache_path)
            self._cache_size -= self._cache_entries.pop(blob_id, (0, 0))[0]
        return None
    
    def _add_to_cache(self, blob_id: str, data: bytes):
        """Add blob data to cache with size management."""
        if not self.cache_enabled or len(data) > self.cache_max_size:
            return
            
        # Check if we need to make space
        while self._cache_size + len(data) > self.cache_max_size and self._cache_entries:
            # Remove oldest entry
            oldest_id = min(self._cache_entries.items(), key=lambda x: x[1][1])[0]
            self._cache_size -= self._cache_entries[oldest_id][0]
            os.remove(self._get_cache_path(oldest_id))
            self._cache_entries.pop(oldest_id)
            
        # Add new entry
        cache_path = self._get_cache_path(blob_id)
        with open(cache_path, 'wb') as f:
            f.write(data)
            
        self._cache_entries[blob_id] = (len(data), time.time())
        self._cache_size += len(data)
    
    # Modified get_blob method with caching
    def get_blob(self, blob_id: str, skip_cache: bool = False) -> bytes:
        """
        Retrieve a blob from the aggregator by its blob ID with optional caching.

        Args:
            blob_id: The blob ID
            skip_cache: If True, bypass cache and always fetch from network

        Returns:
            Binary content of the blob
        """
        # Check cache first
        if not skip_cache:
            cached_data = self._check_cache(blob_id)
            if cached_data is not None:
                return cached_data
                
        # Not in cache or cache disabled, fetch from network
        url = f"{self.aggregator_base_url}/v1/blobs/{blob_id}"
        
        try:
            response = requests.get(url, timeout=self.timeout)
            response.raise_for_status()
            data = response.content
            
            # Add to cache if successful
            if not skip_cache:
                self._add_to_cache(blob_id, data)
                
            return data
        except RequestException as e:
            self._handle_request_error(e, f"Error retrieving blob by blob ID: {blob_id}")


    # Enhanced streaming methods
    def put_blob_from_stream(
        self,
        stream: BinaryIO,
        encoding_type: Optional[str] = None,
        epochs: Optional[int] = None,
        deletable: Optional[bool] = None,
        send_object_to: Optional[str] = None,
        chunk_size: int = 8192,
        progress_callback: Optional[callable] = None
    ) -> Dict[str, Any]:
        """
        Enhanced streaming upload with progress tracking.

        Args:
            stream: Binary stream to upload
            encoding_type: Encoding type for the blob
            epochs: Number of epochs ahead to store
            deletable: Whether blob is deletable
            send_object_to: Sui address to send object to
            chunk_size: Size of chunks to upload
            progress_callback: Callback for progress (bytes_sent, total_bytes)

        Returns:
            JSON response from server
        """
        if not stream.readable():
            raise ValueError("Provided stream is not readable")

        url = f"{self.publisher_base_url}/v1/blobs"
        headers = {"Content-Type": "application/octet-stream"}
        params = self._build_query_params(
            encoding_type, epochs, deletable, send_object_to
        )

        # Get total size if possible
        total_size = None
        if hasattr(stream, 'seekable') and stream.seekable():
            try:
                pos = stream.tell()
                stream.seek(0, 2)  # Seek to end
                total_size = stream.tell() - pos
                stream.seek(pos)  # Seek back
            except (AttributeError, IOError):
                pass

        # Generator for streaming upload
        def generate():
            bytes_sent = 0
            while True:
                chunk = stream.read(chunk_size)
                if not chunk:
                    break
                bytes_sent += len(chunk)
                if progress_callback and total_size:
                    progress_callback(bytes_sent, total_size)
                yield chunk

        try:
            response = requests.put(
                url,
                data=generate(),
                headers=headers,
                params=params,
                timeout=self.timeout,
                stream=True
            )
            response.raise_for_status()
            return response.json()
        except RequestException as e:
            self._handle_request_error(e, "Error uploading blob from stream")

    def get_blob_as_stream(
        self,
        blob_id: str,
        chunk_size: int = 8192,
        progress_callback: Optional[callable] = None
    ) -> IO[bytes]:
        """
        Enhanced streaming download with progress tracking.

        Args:
            blob_id: The blob ID
            chunk_size: Size of chunks to download
            progress_callback: Callback for progress (bytes_received, total_bytes)

        Returns:
            A file-like object for reading the blob data
        """
        url = f"{self.aggregator_base_url}/v1/blobs/{blob_id}"
        
        try:
            response = requests.get(
                url,
                stream=True,
                timeout=self.timeout,
                headers={'Accept-Encoding': None}  # Disable compression for progress tracking
            )
            response.raise_for_status()
            
            total_size = int(response.headers.get('content-length', 0))
            bytes_received = 0
            
            def generate():
                nonlocal bytes_received
                for chunk in response.iter_content(chunk_size=chunk_size):
                    if chunk:  # filter out keep-alive chunks
                        bytes_received += len(chunk)
                        if progress_callback and total_size:
                            progress_callback(bytes_received, total_size)
                        yield chunk
            
            # Create a file-like object from the generator
            class StreamReader:
                def __init__(self, generator):
                    self.generator = generator
                    self.buffer = b''
                
                def read(self, size=-1):
                    if size < 0:
                        return b''.join(self.generator)
                    
                    while len(self.buffer) < size:
                        try:
                            self.buffer += next(self.generator)
                        except StopIteration:
                            break
                    
                    data = self.buffer[:size]
                    self.buffer = self.buffer[size:]
                    return data
                
                def close(self):
                    response.close()
            
            return StreamReader(generate())
        except RequestException as e:
            self._handle_request_error(
                e, f"Error retrieving blob as stream by blob ID: {blob_id}"
            )