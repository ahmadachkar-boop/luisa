import SwiftUI
import UIKit
import CommonCrypto
import AVKit

// MARK: - Array Extension for Safe Subscripting
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - View Extension for Conditional Modifiers
extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Image Cache Manager with LRU and Disk Caching
class ImageCache {
    static let shared = ImageCache()
    private var memoryCache = NSCache<NSString, CacheEntry>()
    private var accessOrder: [String] = [] // Track access order for LRU
    private let accessQueue = DispatchQueue(label: "com.ourapp.imagecache.access", attributes: .concurrent)
    private let diskCacheURL: URL
    private let maxMemoryCount = 100
    private let maxMemoryBytes = 100 * 1024 * 1024 // 100 MB
    private let maxDiskBytes = 500 * 1024 * 1024 // 500 MB for disk cache

    // Thread-safe lock for memory cache operations
    private let cacheLock = NSLock()

    // Wrapper to track access time
    private class CacheEntry {
        let image: UIImage
        private let accessLock = NSLock()
        private var _lastAccessed: Date

        var lastAccessed: Date {
            get {
                accessLock.lock()
                defer { accessLock.unlock() }
                return _lastAccessed
            }
            set {
                accessLock.lock()
                defer { accessLock.unlock() }
                _lastAccessed = newValue
            }
        }

        init(image: UIImage) {
            self.image = image
            self._lastAccessed = Date()
        }
    }

    private init() {
        memoryCache.countLimit = maxMemoryCount
        memoryCache.totalCostLimit = maxMemoryBytes

        // Setup disk cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = cacheDir.appendingPathComponent("ImageCache", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        // Clean up disk cache on init if too large
        Task {
            await cleanupDiskCacheIfNeeded()
        }
    }

    func get(forKey key: String) -> UIImage? {
        // Thread-safe memory cache access
        cacheLock.lock()
        let entry = memoryCache.object(forKey: key as NSString)
        cacheLock.unlock()

        if let entry = entry {
            entry.lastAccessed = Date()
            updateAccessOrder(key)
            return entry.image
        }

        // Check disk cache
        if let image = loadFromDisk(key: key) {
            // Promote to memory cache with thread safety
            let entry = CacheEntry(image: image)
            cacheLock.lock()
            memoryCache.setObject(entry, forKey: key as NSString)
            cacheLock.unlock()
            updateAccessOrder(key)
            return image
        }

        return nil
    }

    func set(_ image: UIImage, forKey key: String) {
        let entry = CacheEntry(image: image)
        cacheLock.lock()
        memoryCache.setObject(entry, forKey: key as NSString)
        cacheLock.unlock()
        updateAccessOrder(key)

        // Also save to disk cache asynchronously
        Task {
            await saveToDisk(image: image, key: key)
        }
    }

    func remove(forKey key: String) {
        cacheLock.lock()
        memoryCache.removeObject(forKey: key as NSString)
        cacheLock.unlock()
        accessQueue.async(flags: .barrier) {
            self.accessOrder.removeAll { $0 == key }
        }

        // Remove from disk too
        let fileURL = diskCacheURL.appendingPathComponent(key.sha256Hash)
        try? FileManager.default.removeItem(at: fileURL)
    }

    func clear() {
        cacheLock.lock()
        memoryCache.removeAllObjects()
        cacheLock.unlock()
        accessQueue.async(flags: .barrier) {
            self.accessOrder.removeAll()
        }

        // Clear disk cache
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    // MARK: - LRU Management
    private func updateAccessOrder(_ key: String) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.accessOrder.removeAll { $0 == key }
            self.accessOrder.append(key)

            // Evict LRU items if over limit
            while self.accessOrder.count > self.maxMemoryCount {
                if let oldestKey = self.accessOrder.first {
                    self.accessOrder.removeFirst()
                    self.cacheLock.lock()
                    self.memoryCache.removeObject(forKey: oldestKey as NSString)
                    self.cacheLock.unlock()
                }
            }
        }
    }

    // MARK: - Disk Cache Operations
    private func diskCacheKey(for key: String) -> String {
        return key.sha256Hash
    }

    private func saveToDisk(image: UIImage, key: String) async {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let fileURL = diskCacheURL.appendingPathComponent(diskCacheKey(for: key))

        do {
            try data.write(to: fileURL)
        } catch {
            print("Failed to save image to disk cache: \(error)")
        }
    }

    private func loadFromDisk(key: String) -> UIImage? {
        let fileURL = diskCacheURL.appendingPathComponent(diskCacheKey(for: key))

        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        // Update access date
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return image
    }

    private func cleanupDiskCacheIfNeeded() async {
        let fileManager = FileManager.default

        guard let files = try? fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return
        }

        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, size: Int64, date: Date)] = []

        for file in files {
            guard let attrs = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = attrs.fileSize,
                  let date = attrs.contentModificationDate else {
                continue
            }
            totalSize += Int64(size)
            fileInfos.append((url: file, size: Int64(size), date: date))
        }

        // If over limit, delete oldest files
        if totalSize > maxDiskBytes {
            // Sort by date, oldest first
            fileInfos.sort { $0.date < $1.date }

            for fileInfo in fileInfos {
                try? fileManager.removeItem(at: fileInfo.url)
                totalSize -= fileInfo.size
                if totalSize <= Int64(Double(maxDiskBytes) * 0.8) { // Clean to 80%
                    break
                }
            }
        }
    }

    // MARK: - Prefetching

    /// Maximum concurrent prefetch downloads
    private static let maxConcurrentPrefetch = 4

    func prefetch(urls: [String]) {
        prefetchWithPriority(urls: urls, priority: .background)
    }

    // Prefetch with priority and proper rate limiting
    func prefetchWithPriority(urls: [String], priority: TaskPriority = .background) {
        Task(priority: priority) {
            // Filter out already cached URLs
            let urlsToFetch = urls.filter { get(forKey: $0) == nil }

            // Process in batches with concurrency limit
            let batchSize = ImageCache.maxConcurrentPrefetch
            for batchStart in stride(from: 0, to: urlsToFetch.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, urlsToFetch.count)
                let batch = Array(urlsToFetch[batchStart..<batchEnd])

                // Download batch concurrently
                await withTaskGroup(of: Void.self) { group in
                    for url in batch {
                        group.addTask {
                            guard let imageURL = URL(string: url) else { return }
                            do {
                                let (data, _) = try await URLSession.shared.data(from: imageURL)
                                if let image = UIImage(data: data) {
                                    await MainActor.run {
                                        self.set(image, forKey: url)
                                    }
                                }
                            } catch {
                                // Silently fail prefetch
                            }
                        }
                    }
                }

                // Small delay between batches to avoid overwhelming network
                if batchEnd < urlsToFetch.count {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms between batches
                }
            }
        }
    }
}

// MARK: - String Extension for Hashing
extension String {
    var sha256Hash: String {
        guard let data = self.data(using: .utf8) else { return self }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Photo Prefetch Manager (Gradual Loading with Smart Prefetching)
/// Manages intelligent prefetching of photos for smooth gallery scrolling.
/// Automatically loads visible photos first, then prefetches ahead of scroll direction.
class PhotoPrefetchManager: ObservableObject {
    static let shared = PhotoPrefetchManager()

    // Configuration
    private let visiblePrefetchCount = 6      // Initial visible photos to load immediately
    private let aheadPrefetchCount = 12       // Number of photos to prefetch ahead
    private let behindPrefetchCount = 4       // Number of photos to keep prefetched behind

    // State
    private var allPhotoURLs: [String] = []
    private var currentVisibleRange: Range<Int> = 0..<0
    private var prefetchTask: Task<Void, Never>?
    private let lock = NSLock()
    private var lastScrollDirection: ScrollDirection = .down

    enum ScrollDirection {
        case up, down
    }

    private init() {}

    /// Set the full list of photo URLs for the gallery
    func setPhotoURLs(_ urls: [String]) {
        lock.lock()
        allPhotoURLs = urls
        lock.unlock()

        // Prefetch initial visible photos immediately
        prefetchInitialPhotos()
    }

    /// Called when visible range changes (e.g., on scroll)
    func updateVisibleRange(start: Int, end: Int) {
        let newRange = start..<end

        lock.lock()
        let previousStart = currentVisibleRange.lowerBound
        currentVisibleRange = newRange
        lastScrollDirection = start >= previousStart ? .down : .up
        let urls = allPhotoURLs
        let direction = lastScrollDirection
        lock.unlock()

        // Cancel previous prefetch and start new one
        prefetchTask?.cancel()
        prefetchTask = Task {
            await prefetchAroundVisible(range: newRange, urls: urls, direction: direction)
        }
    }

    /// Called when a specific photo becomes visible
    func photoDidAppear(at index: Int) {
        lock.lock()
        let urls = allPhotoURLs
        lock.unlock()

        guard index >= 0 && index < urls.count else { return }

        // Update visible range
        let start = max(0, index - 2)
        let end = min(urls.count, index + 3)
        updateVisibleRange(start: start, end: end)
    }

    // MARK: - Private Methods

    private func prefetchInitialPhotos() {
        lock.lock()
        let urls = allPhotoURLs
        lock.unlock()

        guard !urls.isEmpty else { return }

        // Immediately prefetch the first batch of visible photos
        let initialBatch = Array(urls.prefix(visiblePrefetchCount))
        ImageCache.shared.prefetchWithPriority(urls: initialBatch, priority: .userInitiated)
    }

    private func prefetchAroundVisible(range: Range<Int>, urls: [String], direction: ScrollDirection) async {
        guard !urls.isEmpty else { return }

        // Prioritize prefetching based on scroll direction
        var urlsToFetch: [String] = []

        // First, ensure visible photos are cached
        let visibleURLs = urls[safe: range]
        urlsToFetch.append(contentsOf: visibleURLs)

        // Then prefetch ahead in scroll direction
        let aheadRange: Range<Int>
        let behindRange: Range<Int>

        switch direction {
        case .down:
            aheadRange = range.upperBound..<min(urls.count, range.upperBound + aheadPrefetchCount)
            behindRange = max(0, range.lowerBound - behindPrefetchCount)..<range.lowerBound
        case .up:
            aheadRange = max(0, range.lowerBound - aheadPrefetchCount)..<range.lowerBound
            behindRange = range.upperBound..<min(urls.count, range.upperBound + behindPrefetchCount)
        }

        // Add ahead URLs (higher priority)
        urlsToFetch.append(contentsOf: urls[safe: aheadRange])
        // Add behind URLs (lower priority, for back-scrolling)
        urlsToFetch.append(contentsOf: urls[safe: behindRange])

        // Remove already cached URLs
        let uncachedURLs = urlsToFetch.filter { ImageCache.shared.get(forKey: $0) == nil }

        guard !uncachedURLs.isEmpty else { return }

        // Check for cancellation
        if Task.isCancelled { return }

        // Prefetch with appropriate priority
        ImageCache.shared.prefetchWithPriority(urls: uncachedURLs, priority: .medium)
    }

    /// Force prefetch specific URLs (e.g., when tab first appears)
    func prefetchImmediate(urls: [String]) {
        ImageCache.shared.prefetchWithPriority(urls: urls, priority: .high)
    }

    /// Clear prefetch state (e.g., when leaving gallery)
    func reset() {
        prefetchTask?.cancel()
        lock.lock()
        allPhotoURLs = []
        currentVisibleRange = 0..<0
        lock.unlock()
    }
}

// MARK: - Safe Array Subscript Extension
extension Array {
    subscript(safe range: Range<Int>) -> [Element] {
        let clampedLower = Swift.max(range.lowerBound, 0)
        let clampedUpper = Swift.min(range.upperBound, count)
        guard clampedLower < clampedUpper else { return [] }
        return Array(self[clampedLower..<clampedUpper])
    }
}

// MARK: - Cached Async Image View
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    let thumbnailSize: CGFloat? // Optional: set to nil for full resolution

    @State private var image: UIImage?
    @State private var isLoading = false

    init(
        url: URL?,
        thumbnailSize: CGFloat? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.thumbnailSize = thumbnailSize
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
    }

    private func loadImage() {
        guard let url = url, !isLoading else { return }

        // Use different cache keys for thumbnails vs full resolution
        let cacheKey = thumbnailSize != nil ? "\(url.absoluteString)_thumb_\(Int(thumbnailSize!))" : url.absoluteString

        // Check cache first
        if let cachedImage = ImageCache.shared.get(forKey: cacheKey) {
            self.image = cachedImage
            return
        }

        // Download image
        isLoading = true

        // Capture screen scale on main thread before going to background
        let screenScale = UIScreen.main.scale

        Task(priority: .userInitiated) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                // Use ImageProcessor actor for background processing (off main thread)
                if let thumbnailSize = thumbnailSize {
                    // Process thumbnail on background thread via actor
                    if let downsampledImage = await ImageProcessor.shared.downsampleImage(
                        data: data,
                        toSize: thumbnailSize,
                        scale: screenScale
                    ) {
                        ImageCache.shared.set(downsampledImage, forKey: cacheKey)
                        await MainActor.run {
                            self.image = downsampledImage
                            self.isLoading = false
                        }
                    } else {
                        await MainActor.run {
                            self.isLoading = false
                        }
                    }
                } else {
                    // Process full image on background thread via actor
                    if let downloadedImage = await ImageProcessor.shared.createImage(from: data) {
                        ImageCache.shared.set(downloadedImage, forKey: cacheKey)
                        await MainActor.run {
                            self.image = downloadedImage
                            self.isLoading = false
                        }
                    } else {
                        await MainActor.run {
                            self.isLoading = false
                        }
                    }
                }
            } catch {
                print("Error loading image: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Background Image Processing Actor
actor ImageProcessor {
    static let shared = ImageProcessor()

    private init() {}

    /// Efficient image downsampling using ImageIO - runs on background thread
    func downsampleImage(data: Data, toSize maxDimension: CGFloat, scale: CGFloat) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return nil
        }

        let maxDimensionInPixels = maxDimension * scale

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary

        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: downsampledImage)
    }

    /// Process full-size image on background thread
    func createImage(from data: Data) -> UIImage? {
        return UIImage(data: data)
    }
}

// MARK: - Image Compression
extension UIImage {
    /// Compresses the image to a target size in bytes
    func compressed(toMaxBytes maxBytes: Int = 1_000_000) -> Data? {
        var compression: CGFloat = 0.9
        var imageData = self.jpegData(compressionQuality: compression)

        while let data = imageData, data.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            imageData = self.jpegData(compressionQuality: compression)
        }

        return imageData
    }

    /// Resizes the image to a maximum dimension while maintaining aspect ratio
    func resized(toMaxDimension maxDimension: CGFloat = 1920) -> UIImage {
        let size = self.size

        // Already smaller than max
        if size.width <= maxDimension && size.height <= maxDimension {
            return self
        }

        let aspectRatio = size.width / size.height
        var newSize: CGSize

        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage ?? self
    }
}

// MARK: - Image Saver
class ImageSaver: NSObject {
    var successHandler: (() -> Void)?
    var errorHandler: ((Error) -> Void)?

    func writeToPhotoAlbum(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted), nil)
    }

    @objc func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            errorHandler?(error)
        } else {
            successHandler?()
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Video Cache Manager
class VideoCache {
    static let shared = VideoCache()
    private let diskCacheURL: URL
    private let maxDiskBytes = 1_000 * 1024 * 1024 // 1GB for video cache

    private init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = cacheDir.appendingPathComponent("VideoCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        // Clean up disk cache on init if too large
        Task {
            await cleanupDiskCacheIfNeeded()
        }
    }

    func getCachedVideoURL(for remoteURL: String) -> URL? {
        let fileURL = diskCacheURL.appendingPathComponent(remoteURL.sha256Hash + ".mp4")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // Update access date
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
            return fileURL
        }
        return nil
    }

    func cacheVideo(data: Data, for remoteURL: String) async -> URL? {
        let fileURL = diskCacheURL.appendingPathComponent(remoteURL.sha256Hash + ".mp4")
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to cache video: \(error)")
            return nil
        }
    }

    func downloadAndCache(from url: URL) async -> URL? {
        // Check if already cached
        if let cachedURL = getCachedVideoURL(for: url.absoluteString) {
            return cachedURL
        }

        // Download video
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return await cacheVideo(data: data, for: url.absoluteString)
        } catch {
            print("Failed to download video: \(error)")
            return nil
        }
    }

    private func cleanupDiskCacheIfNeeded() async {
        let fileManager = FileManager.default

        guard let files = try? fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return
        }

        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, size: Int64, date: Date)] = []

        for file in files {
            guard let attrs = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = attrs.fileSize,
                  let date = attrs.contentModificationDate else {
                continue
            }
            totalSize += Int64(size)
            fileInfos.append((url: file, size: Int64(size), date: date))
        }

        // If over limit, delete oldest files
        if totalSize > maxDiskBytes {
            fileInfos.sort { $0.date < $1.date }

            for fileInfo in fileInfos {
                try? fileManager.removeItem(at: fileInfo.url)
                totalSize -= fileInfo.size
                if totalSize <= Int64(Double(maxDiskBytes) * 0.8) {
                    break
                }
            }
        }
    }
}

// MARK: - Video Transferable for PhotosPicker
import AVFoundation
import Photos
import UniformTypeIdentifiers

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // Copy to temporary directory to ensure we have access
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString).mov")

            do {
                // Remove existing file if any
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.copyItem(at: received.file, to: tempURL)
                return VideoTransferable(url: tempURL)
            } catch {
                print("Failed to copy video: \(error)")
                throw error
            }
        }
    }
}

// MARK: - Video Compression Utilities

class VideoCompressor {
    static let shared = VideoCompressor()
    private init() {}

    /// Maximum file size for uploaded videos (100MB for high quality)
    private let maxUploadSizeBytes: Int64 = 100_000_000

    /// Compress video with adaptive quality based on file size
    /// Uses highest quality possible while keeping file size reasonable
    func compressVideo(from inputURL: URL, maxFileSizeBytes: Int = 100_000_000) async throws -> (data: Data, duration: TimeInterval) {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration).seconds

        // Get original file size to determine compression strategy
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: inputURL.path)
        let originalSize = fileAttributes[.size] as? Int64 ?? 0

        // Choose quality preset based on original size
        // For small videos, use highest quality; for large videos, use adaptive compression
        let presetName: String
        if originalSize < 20_000_000 { // Under 20MB - use highest quality
            presetName = AVAssetExportPresetHighestQuality
        } else if originalSize < 50_000_000 { // 20-50MB - use 1080p
            presetName = AVAssetExportPreset1920x1080
        } else if originalSize < 150_000_000 { // 50-150MB - use 720p for reasonable size
            presetName = AVAssetExportPreset1280x720
        } else { // Very large files - use medium quality
            presetName = AVAssetExportPresetMediumQuality
        }

        print("🎬 [VIDEO COMPRESS] Original size: \(originalSize / 1_000_000)MB, using preset: \(presetName)")

        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            // Fallback to passthrough if preferred preset not available
            guard let fallbackSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw VideoError.exportSessionCreationFailed
            }
            return try await exportWithSession(fallbackSession, duration: duration)
        }

        return try await exportWithSession(exportSession, duration: duration)
    }

    private func exportWithSession(_ exportSession: AVAssetExportSession, duration: TimeInterval) async throws -> (data: Data, duration: TimeInterval) {
        // Create temp output URL
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("\(UUID().uuidString).mp4")

        // Clean up any existing file
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Export with progress monitoring
        await exportSession.export()

        switch exportSession.status {
        case .completed:
            let data = try Data(contentsOf: outputURL)
            print("🎬 [VIDEO COMPRESS] Compressed size: \(data.count / 1_000_000)MB")

            // Clean up temp file
            try? FileManager.default.removeItem(at: outputURL)
            return (data, duration)

        case .failed:
            try? FileManager.default.removeItem(at: outputURL)
            if let error = exportSession.error {
                print("🔴 [VIDEO COMPRESS] Export failed: \(error)")
                throw error
            }
            throw VideoError.exportFailed

        case .cancelled:
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoError.exportCancelled

        default:
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoError.exportFailed
        }
    }

    /// Generate a high-quality thumbnail from video
    /// Captures frame at 1 second or 10% through video (whichever is less)
    func generateThumbnail(from url: URL, at time: CMTime? = nil) async throws -> UIImage {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)

        // Default to 1 second or 10% of video duration (whichever is smaller)
        let captureTime: CMTime
        if let time = time {
            captureTime = time
        } else {
            let tenPercent = CMTimeMultiplyByFloat64(duration, multiplier: 0.1)
            let oneSecond = CMTime(seconds: 1.0, preferredTimescale: 600)
            captureTime = tenPercent < oneSecond ? tenPercent : oneSecond
        }

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 1920, height: 1920) // High quality thumbnail
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        do {
            let cgImage = try await imageGenerator.image(at: captureTime).image
            return UIImage(cgImage: cgImage)
        } catch {
            // Fallback to first frame if specific time fails
            print("⚠️ [VIDEO THUMBNAIL] Failed at \(captureTime.seconds)s, trying first frame")
            let cgImage = try await imageGenerator.image(at: .zero).image
            return UIImage(cgImage: cgImage)
        }
    }

    /// Extract video metadata including duration
    func getVideoDuration(from url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }

    /// Get video resolution
    func getVideoResolution(from url: URL) async throws -> CGSize {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return .zero
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)

        // Apply transform to get correct orientation
        let transformedSize = size.applying(transform)
        return CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
    }
}

enum VideoError: LocalizedError {
    case exportSessionCreationFailed
    case exportFailed
    case exportCancelled
    case thumbnailGenerationFailed
    case invalidVideoFile

    var errorDescription: String? {
        switch self {
        case .exportSessionCreationFailed:
            return "Failed to create video export session"
        case .exportFailed:
            return "Video export failed"
        case .exportCancelled:
            return "Video export was cancelled"
        case .thumbnailGenerationFailed:
            return "Failed to generate video thumbnail"
        case .invalidVideoFile:
            return "Invalid or corrupted video file"
        }
    }
}

// MARK: - Video Saver
class VideoSaver: NSObject {
    var successHandler: (() -> Void)?
    var errorHandler: ((Error) -> Void)?
    private var tempFileURL: URL?

    func saveVideoToPhotoLibrary(from url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self?.errorHandler?(NSError(domain: "VideoSaver", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]))
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.successHandler?()
                    } else if let error = error {
                        self?.errorHandler?(error)
                    }
                }
            }
        }
    }

    func saveVideoDataToPhotoLibrary(data: Data) {
        // Write to temp file first
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        self.tempFileURL = tempURL

        do {
            try data.write(to: tempURL)
            saveVideoToPhotoLibrary(from: tempURL)
        } catch {
            errorHandler?(error)
        }
    }

    deinit {
        // Clean up temp file
        if let tempURL = tempFileURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
}

// MARK: - Photo Library Permission Helper
class PhotoLibraryPermission {
    static func requestAddOnlyPermission() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    static func checkAddOnlyPermission() -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .authorized || status == .limited
    }
}

// MARK: - Updated Image Saver with Permission Check
extension ImageSaver {
    func writeToPhotoAlbumWithPermission(image: UIImage) {
        Task {
            let hasPermission = await PhotoLibraryPermission.requestAddOnlyPermission()
            await MainActor.run {
                if hasPermission {
                    self.writeToPhotoAlbum(image: image)
                } else {
                    self.errorHandler?(NSError(domain: "ImageSaver", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied. Please enable in Settings."]))
                }
            }
        }
    }
}

// MARK: - Full Screen Photo Viewer (Completely Rewritten)
struct FullScreenPhotoViewer: View {
    let photoURLs: [String]
    let initialIndex: Int
    let onDismiss: () -> Void
    let onDelete: ((Int) -> Void)?
    let captureDates: [Date?]? // Optional capture dates for each photo
    let chronologicalPositions: [Int]? // Optional chronological position (1-based) for each photo
    let favoriteStates: [Bool]? // Optional favorite states for each photo
    let onToggleFavorite: ((Int) -> Void)? // Optional callback to toggle favorite
    let uploadedByNames: [String]? // Optional names of who uploaded each photo

    // Use a unique ID to force complete view recreation
    @State private var viewID = UUID()
    @State private var currentIndex: Int
    @State private var isZoomed = false
    @State private var dragOffset: CGFloat = 0
    @State private var showingSaveSuccess = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showingShareSheet = false
    @State private var currentImage: UIImage?
    @State private var showingDeleteAlert = false
    @State private var selectionMode = false
    @State private var selectedIndices: Set<Int> = []
    @State private var loadedImages: [Int: UIImage] = [:]
    @State private var localFavoriteStates: [Bool] = []

    init(photoURLs: [String], initialIndex: Int, onDismiss: @escaping () -> Void, onDelete: ((Int) -> Void)? = nil, captureDates: [Date?]? = nil, chronologicalPositions: [Int]? = nil, favoriteStates: [Bool]? = nil, onToggleFavorite: ((Int) -> Void)? = nil, uploadedByNames: [String]? = nil) {
        self.photoURLs = photoURLs
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self.onDelete = onDelete
        self.captureDates = captureDates
        self.chronologicalPositions = chronologicalPositions
        self.favoriteStates = favoriteStates
        self.onToggleFavorite = onToggleFavorite
        self.uploadedByNames = uploadedByNames

        // Initialize directly with the index we want
        let safeIndex = max(0, min(initialIndex, photoURLs.count - 1))
        _currentIndex = State(initialValue: safeIndex)
        // Initialize local favorite states
        _localFavoriteStates = State(initialValue: favoriteStates ?? Array(repeating: false, count: photoURLs.count))
    }

    // MARK: - Safe Array Access Helpers
    /// Safe access to chronological position with bounds checking to avoid crashes
    private func safeChronologicalPosition(at index: Int) -> Int {
        guard let positions = chronologicalPositions,
              index >= 0 && index < positions.count else {
            return index + 1 // Default to 1-based index
        }
        return positions[index]
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(1.0 - abs(dragOffset) / 400.0)

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .shadow(radius: 3)
                    }

                    Spacer()

                    Text("\(safeChronologicalPosition(at: currentIndex)) / \(photoURLs.count)")
                        .foregroundColor(.white)
                        .font(.subheadline)
                        .shadow(radius: 3)

                    Spacer()

                    Menu {
                        Button(action: saveCurrentPhoto) {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }

                        Button(action: { showingShareSheet = true }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        if onDelete != nil {
                            Button(role: .destructive, action: { showingDeleteAlert = true }) {
                                Label("Delete Photo", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .shadow(radius: 3)
                    }
                }
                .padding()
                .opacity(dragOffset == 0 ? 1 : 0)

                // Photo display area
                GeometryReader { geometry in
                    // Display current photo only
                    if currentIndex >= 0 && currentIndex < photoURLs.count {
                        SinglePhotoView(
                            photoURL: photoURLs[currentIndex],
                            isZoomed: $isZoomed,
                            onImageLoaded: { image in
                                currentImage = image
                            }
                        )
                        .id("\(currentIndex)-\(viewID)")
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .offset(y: dragOffset)
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onChanged { value in
                                    if !isZoomed {
                                        // Only track vertical drag for dismiss gesture
                                        if abs(value.translation.height) > abs(value.translation.width) {
                                            dragOffset = value.translation.height
                                        }
                                    }
                                }
                                .onEnded { value in
                                    if !isZoomed {
                                        let horizontal = value.translation.width
                                        let vertical = value.translation.height

                                        // Vertical dismiss
                                        if abs(dragOffset) > 100 {
                                            onDismiss()
                                            return
                                        }

                                        // Horizontal swipe navigation
                                        if abs(horizontal) > abs(vertical) && abs(horizontal) > 50 {
                                            if horizontal > 0 && currentIndex > 0 {
                                                // Swipe right - previous photo
                                                goToPrevious()
                                            } else if horizontal < 0 && currentIndex < photoURLs.count - 1 {
                                                // Swipe left - next photo
                                                goToNext()
                                            }
                                        }

                                        // Reset vertical offset
                                        withAnimation(.spring(response: 0.3)) {
                                            dragOffset = 0
                                        }
                                    }
                                }
                        )
                    }
                }

                // Bottom info area
                VStack(spacing: 8) {
                    // Added by (if available)
                    if let uploadedByNames = uploadedByNames,
                       currentIndex < uploadedByNames.count {
                        Text("Added by \(uploadedByNames[currentIndex])")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                            )
                    }

                    // Capture date (if available)
                    if let captureDates = captureDates,
                       currentIndex < captureDates.count,
                       let captureDate = captureDates[currentIndex] {
                        Text(captureDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.4))
                            )
                    }

                    // Page indicators (max 10 dots)
                    if !isZoomed && photoURLs.count > 1 {
                        let maxDots = 10
                        let showAllDots = photoURLs.count <= maxDots
                        // Use chronological position for dot highlighting, or fall back to current index
                        // Safe bounds check to avoid array index out of range
                        let dotPosition = safeChronologicalPosition(at: currentIndex)

                        if showAllDots {
                            // Show all dots if count is <= max
                            HStack(spacing: 8) {
                                // Highlight based on chronological position (1-based)
                                ForEach(1...photoURLs.count, id: \.self) { position in
                                    Circle()
                                        .fill(position == dotPosition ? Color.white : Color.white.opacity(0.5))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.bottom, 20)
                        } else {
                            // Show limited dots with scrolling highlighted dot
                            ZStack(alignment: .leading) {
                                // Background dots (always visible, dimmed)
                                HStack(spacing: 8) {
                                    ForEach(0..<maxDots, id: \.self) { index in
                                        Circle()
                                            .fill(Color.white.opacity(0.3))
                                            .frame(width: 6, height: 6)
                                    }
                                }

                                // Highlighted dot that moves based on position
                                // Map position (1 to count) to dot range (0 to maxDots-1)
                                let progress = CGFloat(dotPosition - 1) / CGFloat(photoURLs.count - 1)
                                let dotOffset = progress * CGFloat((maxDots - 1)) * 14.0 // 6px dot + 8px gap

                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 10, height: 10)
                                    .offset(x: dotOffset)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 20)
                        }
                    }
                }
                .opacity(dragOffset == 0 ? 1 : 0)
            }

            // Heart button overlay in bottom right
            if onToggleFavorite != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            // Toggle local state for immediate visual feedback
                            if currentIndex < localFavoriteStates.count {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    localFavoriteStates[currentIndex].toggle()
                                }
                            }
                            // Call the callback
                            onToggleFavorite?(currentIndex)
                        }) {
                            let isFavorite = currentIndex < localFavoriteStates.count ? localFavoriteStates[currentIndex] : false
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 28))
                                .foregroundColor(isFavorite ? .red : .white)
                                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
                                .scaleEffect(isFavorite ? 1.1 : 1.0)
                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 80)
                    }
                }
                .opacity(dragOffset == 0 ? 1 : 0)
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            // Reset to initialIndex every time view appears
            // This fixes the issue where .fullScreenCover reuses view instances
            currentIndex = max(0, min(initialIndex, photoURLs.count - 1))
            viewID = UUID() // Force view recreation
            dragOffset = 0
            isZoomed = false
            // Sync local favorite states
            localFavoriteStates = favoriteStates ?? Array(repeating: false, count: photoURLs.count)
        }
        .alert("Saved!", isPresented: $showingSaveSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Photo saved to your library")
        }
        .alert("Error", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .alert("Delete Photo?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?(currentIndex)
                onDismiss()
            }
        } message: {
            Text("This photo will be permanently deleted")
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = currentImage {
                ShareSheet(items: [image])
            }
        }
    }

    private func goToNext() {
        guard currentIndex < photoURLs.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentIndex += 1
            viewID = UUID() // Force view recreation
        }
    }

    private func goToPrevious() {
        guard currentIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentIndex -= 1
            viewID = UUID() // Force view recreation
        }
    }

    private func saveCurrentPhoto() {
        guard let image = currentImage else {
            saveErrorMessage = "Image not loaded yet. Please try again."
            showingSaveError = true
            return
        }

        let imageSaver = ImageSaver()
        imageSaver.successHandler = {
            showingSaveSuccess = true
        }
        imageSaver.errorHandler = { error in
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
        imageSaver.writeToPhotoAlbum(image: image)
    }
}

// MARK: - Single Photo View with Zoom
struct SinglePhotoView: View {
    let photoURL: String
    @Binding var isZoomed: Bool
    let onImageLoaded: (UIImage) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            CachedAsyncImage(url: URL(string: photoURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                let newScale = scale * delta
                                scale = min(max(newScale, 1), 4)
                                isZoomed = scale > 1.01
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                if scale < 1 {
                                    withAnimation(.spring(response: 0.3)) {
                                        scale = 1
                                        offset = .zero
                                        lastOffset = .zero
                                        isZoomed = false
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.3)) {
                                    if scale > 1 {
                                        scale = 1
                                        offset = .zero
                                        lastOffset = .zero
                                        isZoomed = false
                                    } else {
                                        scale = 2.5
                                        isZoomed = true
                                    }
                                }
                            }
                    )
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard scale > 1.01 else { return }

                                let imageWidth = geometry.size.width * scale
                                let imageHeight = geometry.size.height * scale

                                let maxOffsetX = max(0, (imageWidth - geometry.size.width) / 2)
                                let maxOffsetY = max(0, (imageHeight - geometry.size.height) / 2)

                                let newOffsetX = lastOffset.width + value.translation.width
                                let newOffsetY = lastOffset.height + value.translation.height

                                offset = CGSize(
                                    width: min(max(newOffsetX, -maxOffsetX), maxOffsetX),
                                    height: min(max(newOffsetY, -maxOffsetY), maxOffsetY)
                                )
                            }
                            .onEnded { _ in
                                if scale > 1.01 {
                                    lastOffset = offset
                                }
                            },
                        including: scale > 1.01 ? .all : .none
                    )
            } placeholder: {
                ZStack {
                    Color.black
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }
            }
            .onAppear {
                // Load image and notify parent
                Task {
                    if let cachedImage = ImageCache.shared.get(forKey: photoURL) {
                        onImageLoaded(cachedImage)
                    } else {
                        if let url = URL(string: photoURL),
                           let (data, _) = try? await URLSession.shared.data(from: url),
                           let image = UIImage(data: data) {
                            ImageCache.shared.set(image, forKey: photoURL)
                            await MainActor.run {
                                onImageLoaded(image)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Full Screen Video Player
struct FullScreenVideoPlayer: View {
    let videoURL: String
    let thumbnailURL: String
    let duration: TimeInterval
    let onDismiss: () -> Void
    let onDelete: (() -> Void)?
    let uploadedBy: String?
    let captureDate: Date?

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var isLoading = true
    @State private var dragOffset: CGFloat = 0
    @State private var showingDeleteAlert = false
    @State private var showingSaveSuccess = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showingShareSheet = false
    @State private var isSeeking = false
    @State private var showControls = true
    @State private var hideControlsTimer: Timer?

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(1.0 - abs(dragOffset) / 400.0)

            VStack(spacing: 0) {
                // Top bar
                if showControls {
                    HStack {
                        Button(action: {
                            player?.pause()
                            onDismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(radius: 3)
                        }

                        Spacer()

                        Menu {
                            Button(action: saveVideo) {
                                Label("Save to Photos", systemImage: "square.and.arrow.down")
                            }

                            Button(action: { showingShareSheet = true }) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }

                            if onDelete != nil {
                                Button(role: .destructive, action: { showingDeleteAlert = true }) {
                                    Label("Delete Video", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(radius: 3)
                        }
                    }
                    .padding()
                    .transition(.opacity)
                }

                // Video player area
                GeometryReader { geometry in
                    ZStack {
                        // Thumbnail placeholder while loading
                        if isLoading {
                            CachedAsyncImage(url: URL(string: thumbnailURL)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                Color.black
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height)

                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.5)
                        }

                        // Video player
                        if let player = player {
                            VideoPlayerView(player: player)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showControls.toggle()
                                    }
                                    resetHideControlsTimer()
                                }
                        }

                        // Center play/pause button
                        if showControls && !isLoading {
                            Button(action: togglePlayPause) {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 70, height: 70)
                                    .overlay(
                                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                            .font(.title)
                                            .foregroundColor(.white)
                                            .offset(x: isPlaying ? 0 : 3)
                                    )
                                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .transition(.opacity)
                        }
                    }
                    .offset(y: dragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 50)
                            .onChanged { value in
                                if abs(value.translation.height) > abs(value.translation.width) {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if abs(dragOffset) > 100 {
                                    player?.pause()
                                    onDismiss()
                                    return
                                }
                                withAnimation(.spring(response: 0.3)) {
                                    dragOffset = 0
                                }
                            }
                    )
                }

                // Bottom controls
                if showControls {
                    VStack(spacing: 12) {
                        // Progress bar
                        HStack(spacing: 12) {
                            Text(formatDuration(currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.white)
                                .frame(width: 40, alignment: .leading)

                            Slider(
                                value: Binding(
                                    get: { currentTime },
                                    set: { newValue in
                                        currentTime = newValue
                                        isSeeking = true
                                        let time = CMTime(seconds: newValue, preferredTimescale: 600)
                                        player?.seek(to: time) { _ in
                                            isSeeking = false
                                        }
                                    }
                                ),
                                in: 0...max(duration, 1)
                            )
                            .tint(Color(red: 0.7, green: 0.5, blue: 0.95))

                            Text(formatDuration(duration))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 40, alignment: .trailing)
                        }
                        .padding(.horizontal)

                        // Info row
                        if let uploadedBy = uploadedBy {
                            HStack {
                                Text("Added by \(uploadedBy)")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))

                                if let date = captureDate {
                                    Text("•")
                                        .foregroundColor(.white.opacity(0.5))
                                    Text(date, style: .date)
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 20)
                    .background(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .transition(.opacity)
                }
            }
        }
        .onAppear {
            setupPlayer()
            resetHideControlsTimer()
        }
        .onDisappear {
            player?.pause()
            hideControlsTimer?.invalidate()
        }
        .alert("Delete Video?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                player?.pause()
                onDelete?()
                onDismiss()
            }
        } message: {
            Text("This video will be permanently deleted")
        }
        .alert("Saved!", isPresented: $showingSaveSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Video saved to your library")
        }
        .alert("Error", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }

    private func setupPlayer() {
        guard let url = URL(string: videoURL) else { return }

        // Check cache first
        Task {
            let localURL: URL
            if let cachedURL = VideoCache.shared.getCachedVideoURL(for: videoURL) {
                localURL = cachedURL
            } else if let downloadedURL = await VideoCache.shared.downloadAndCache(from: url) {
                localURL = downloadedURL
            } else {
                localURL = url // Fallback to streaming
            }

            await MainActor.run {
                let playerItem = AVPlayerItem(url: localURL)
                player = AVPlayer(playerItem: playerItem)
                player?.actionAtItemEnd = .pause

                // Observe time updates
                player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
                    if !isSeeking {
                        currentTime = time.seconds
                    }
                }

                // Observe when video is ready
                NotificationCenter.default.addObserver(forName: AVPlayerItem.newAccessLogEntryNotification, object: playerItem, queue: .main) { _ in
                    isLoading = false
                }

                // Also check if video is already ready
                if playerItem.status == .readyToPlay {
                    isLoading = false
                }

                // Short delay then check loading status
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isLoading = false
                }

                // Auto-play
                player?.play()
                isPlaying = true
            }
        }
    }

    private func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            // If at end, restart
            if currentTime >= duration - 0.5 {
                player?.seek(to: .zero)
                currentTime = 0
            }
            player?.play()
        }
        isPlaying.toggle()
        resetHideControlsTimer()
    }

    private func resetHideControlsTimer() {
        hideControlsTimer?.invalidate()
        if isPlaying {
            hideControlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    showControls = false
                }
            }
        }
    }

    private func saveVideo() {
        Task {
            guard let url = URL(string: videoURL) else {
                await MainActor.run {
                    saveErrorMessage = "Invalid video URL"
                    showingSaveError = true
                }
                return
            }

            // Get local URL (cached or download)
            let localURL: URL
            if let cachedURL = VideoCache.shared.getCachedVideoURL(for: videoURL) {
                localURL = cachedURL
            } else if let downloadedURL = await VideoCache.shared.downloadAndCache(from: url) {
                localURL = downloadedURL
            } else {
                await MainActor.run {
                    saveErrorMessage = "Failed to download video"
                    showingSaveError = true
                }
                return
            }

            let videoSaver = VideoSaver()
            videoSaver.successHandler = {
                Task { @MainActor in
                    showingSaveSuccess = true
                }
            }
            videoSaver.errorHandler = { error in
                Task { @MainActor in
                    saveErrorMessage = error.localizedDescription
                    showingSaveError = true
                }
            }
            videoSaver.saveVideoToPhotoLibrary(from: localURL)
        }
    }
}

// MARK: - AVPlayer SwiftUI Wrapper
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
