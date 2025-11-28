import SwiftUI
import UIKit
import CommonCrypto

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

    // Wrapper to track access time
    private class CacheEntry {
        let image: UIImage
        var lastAccessed: Date

        init(image: UIImage) {
            self.image = image
            self.lastAccessed = Date()
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
        // Check memory cache first
        if let entry = memoryCache.object(forKey: key as NSString) {
            entry.lastAccessed = Date()
            updateAccessOrder(key)
            return entry.image
        }

        // Check disk cache
        if let image = loadFromDisk(key: key) {
            // Promote to memory cache
            let entry = CacheEntry(image: image)
            memoryCache.setObject(entry, forKey: key as NSString)
            updateAccessOrder(key)
            return image
        }

        return nil
    }

    func set(_ image: UIImage, forKey key: String) {
        let entry = CacheEntry(image: image)
        memoryCache.setObject(entry, forKey: key as NSString)
        updateAccessOrder(key)

        // Also save to disk cache asynchronously
        Task {
            await saveToDisk(image: image, key: key)
        }
    }

    func remove(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        accessQueue.async(flags: .barrier) {
            self.accessOrder.removeAll { $0 == key }
        }

        // Remove from disk too
        let fileURL = diskCacheURL.appendingPathComponent(key.sha256Hash)
        try? FileManager.default.removeItem(at: fileURL)
    }

    func clear() {
        memoryCache.removeAllObjects()
        accessQueue.async(flags: .barrier) {
            self.accessOrder.removeAll()
        }

        // Clear disk cache
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    // MARK: - LRU Management
    private func updateAccessOrder(_ key: String) {
        accessQueue.async(flags: .barrier) {
            self.accessOrder.removeAll { $0 == key }
            self.accessOrder.append(key)

            // Evict LRU items if over limit
            while self.accessOrder.count > self.maxMemoryCount {
                if let oldestKey = self.accessOrder.first {
                    self.accessOrder.removeFirst()
                    self.memoryCache.removeObject(forKey: oldestKey as NSString)
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
    func prefetch(urls: [String]) {
        Task {
            for url in urls {
                // Skip if already cached
                if get(forKey: url) != nil { continue }

                // Download and cache
                guard let imageURL = URL(string: url) else { continue }
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

    // Prefetch with priority (first items get priority)
    func prefetchWithPriority(urls: [String], priority: TaskPriority = .background) {
        Task(priority: priority) {
            for (index, url) in urls.enumerated() {
                // Skip if already cached
                if get(forKey: url) != nil { continue }

                // Rate limit to prevent overwhelming network
                if index > 0 {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
                }

                guard let imageURL = URL(string: url) else { continue }
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
        Task(priority: .userInitiated) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                // Use downsampling for better performance with large images
                if let thumbnailSize = thumbnailSize {
                    if let downsampledImage = downsampleImage(data: data, toSize: thumbnailSize) {
                        ImageCache.shared.set(downsampledImage, forKey: cacheKey)
                        await MainActor.run {
                            self.image = downsampledImage
                            self.isLoading = false
                        }
                    }
                } else if let downloadedImage = UIImage(data: data) {
                    // Cache the full image
                    ImageCache.shared.set(downloadedImage, forKey: cacheKey)
                    await MainActor.run {
                        self.image = downloadedImage
                        self.isLoading = false
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

    // Efficient image downsampling using ImageIO
    private func downsampleImage(data: Data, toSize maxDimension: CGFloat) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return nil
        }

        let scale = UIScreen.main.scale
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

                    Text("\(chronologicalPositions?[currentIndex] ?? (currentIndex + 1)) / \(photoURLs.count)")
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
                VStack(spacing: 12) {
                    // Added by (if available)
                    if let uploadedByNames = uploadedByNames,
                       currentIndex < uploadedByNames.count {
                        Text("Added by \(uploadedByNames[currentIndex])")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.5))
                                    .blur(radius: 10)
                            )
                            .shadow(radius: 2)
                    }

                    // Capture date (if available)
                    if let captureDates = captureDates,
                       currentIndex < captureDates.count,
                       let captureDate = captureDates[currentIndex] {
                        Text(captureDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.5))
                                    .blur(radius: 10)
                            )
                            .shadow(radius: 2)
                    }

                    // Page indicators (max 10 dots)
                    if !isZoomed && photoURLs.count > 1 {
                        let maxDots = 10
                        let showAllDots = photoURLs.count <= maxDots
                        // Use chronological position for dot highlighting, or fall back to current index
                        let dotPosition = chronologicalPositions?[currentIndex] ?? (currentIndex + 1)

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
