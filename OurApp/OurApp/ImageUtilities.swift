import SwiftUI
import UIKit

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

// MARK: - Image Cache Manager
class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100 // Limit to 100 images
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    func get(forKey key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

// MARK: - Cached Async Image View
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
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

        let cacheKey = url.absoluteString

        // Check cache first
        if let cachedImage = ImageCache.shared.get(forKey: cacheKey) {
            self.image = cachedImage
            return
        }

        // Download image
        isLoading = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let downloadedImage = UIImage(data: data) {
                    // Cache the image
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

// MARK: - Full Screen Photo Viewer with Zoom
struct FullScreenPhotoViewer: View {
    let photoURLs: [String]
    let initialIndex: Int
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var horizontalOffset: CGFloat = 0
    @State private var verticalOffset: CGFloat = 0
    @State private var isDraggingHorizontal = false
    @State private var isDraggingVertical = false
    @State private var isAnyPhotoZoomed = false
    @State private var showingSaveSuccess = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showingShareSheet = false
    @State private var currentImage: UIImage?

    init(photoURLs: [String], initialIndex: Int = 0, onDismiss: @escaping () -> Void) {
        self.photoURLs = photoURLs
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss

        let safeIndex = max(0, min(initialIndex, photoURLs.count - 1))
        _currentIndex = State(initialValue: safeIndex)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .opacity(CGFloat(1) - abs(verticalOffset) / CGFloat(500))
                    .ignoresSafeArea()

                // Custom horizontal pager - show previous, current, and next photos
                HStack(spacing: 0) {
                    ForEach(visibleIndices, id: \.self) { index in
                        ZoomablePhotoView(
                            photoURL: photoURLs[index],
                            isAnyPhotoZoomed: $isAnyPhotoZoomed,
                            onImageLoaded: { image in
                                if index == currentIndex {
                                    currentImage = image
                                }
                            }
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .offset(x: horizontalPagerOffset(width: geometry.size.width), y: verticalOffset)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            // Only allow navigation gestures when not zoomed
                            guard !isAnyPhotoZoomed else { return }

                            let horizontal = abs(value.translation.width)
                            let vertical = abs(value.translation.height)

                            // Determine gesture direction on first significant movement
                            if !isDraggingHorizontal && !isDraggingVertical {
                                if horizontal > vertical {
                                    isDraggingHorizontal = true
                                } else {
                                    isDraggingVertical = true
                                }
                            }

                            // Apply appropriate offset
                            if isDraggingHorizontal {
                                horizontalOffset = value.translation.width
                            } else if isDraggingVertical {
                                verticalOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            guard !isAnyPhotoZoomed else { return }

                            if isDraggingHorizontal {
                                handleHorizontalDragEnd(translation: value.translation.width, width: geometry.size.width)
                            } else if isDraggingVertical {
                                handleVerticalDragEnd(translation: value.translation.height)
                            }

                            isDraggingHorizontal = false
                            isDraggingVertical = false
                        }
                )

                // Top toolbar
                VStack {
                    HStack {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(radius: 3)
                        }

                        Spacer()

                        Text("\(currentIndex + 1) / \(photoURLs.count)")
                            .foregroundColor(.white)
                            .font(.subheadline)
                            .shadow(radius: 3)

                        Spacer()

                        Menu {
                            Button(action: saveToPhotoLibrary) {
                                Label("Save to Photos", systemImage: "square.and.arrow.down")
                            }

                            Button(action: { showingShareSheet = true }) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(radius: 3)
                        }
                    }
                    .padding()
                    .opacity(isDraggingVertical ? 0 : 1)

                    Spacer()
                }

                // Page indicators (only when not zoomed)
                if !isAnyPhotoZoomed && photoURLs.count > 1 {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(0..<photoURLs.count, id: \.self) { index in
                                Circle()
                                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.5))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            // Reset to initial index every time view appears
            let safeIndex = max(0, min(initialIndex, photoURLs.count - 1))
            currentIndex = safeIndex
            loadCurrentImage()
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
        .sheet(isPresented: $showingShareSheet) {
            if let image = currentImage {
                ShareSheet(items: [image])
            }
        }
    }

    // Calculate which photo indices should be visible (previous, current, next)
    private var visibleIndices: [Int] {
        var indices: [Int] = []

        // Previous photo
        if currentIndex > 0 {
            indices.append(currentIndex - 1)
        }

        // Current photo
        indices.append(currentIndex)

        // Next photo
        if currentIndex < photoURLs.count - 1 {
            indices.append(currentIndex + 1)
        }

        return indices
    }

    // Calculate horizontal offset for the pager
    private func horizontalPagerOffset(width: CGFloat) -> CGFloat {
        let baseOffset: CGFloat
        if currentIndex == 0 {
            // First photo - no previous
            baseOffset = 0
        } else {
            // Show previous photo to the left
            baseOffset = -width
        }
        return baseOffset + horizontalOffset
    }

    private func handleHorizontalDragEnd(translation: CGFloat, width: CGFloat) {
        let threshold = width * 0.3

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if translation < -threshold && currentIndex < photoURLs.count - 1 {
                // Swipe left - next photo
                currentIndex += 1
                loadCurrentImage()
            } else if translation > threshold && currentIndex > 0 {
                // Swipe right - previous photo
                currentIndex -= 1
                loadCurrentImage()
            }

            horizontalOffset = 0
        }
    }

    private func handleVerticalDragEnd(translation: CGFloat) {
        if abs(translation) > 100 {
            onDismiss()
        } else {
            withAnimation(.spring(response: 0.3)) {
                verticalOffset = 0
            }
        }
    }

    private func loadCurrentImage() {
        guard currentIndex >= 0 && currentIndex < photoURLs.count else { return }
        currentImage = ImageCache.shared.get(forKey: photoURLs[currentIndex])
    }

    private func saveToPhotoLibrary() {
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

// MARK: - Zoomable Photo View
struct ZoomablePhotoView: View {
    let photoURL: String
    @Binding var isAnyPhotoZoomed: Bool
    let onImageLoaded: (UIImage) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var imageSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            CachedAsyncImage(url: URL(string: photoURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .background(
                        GeometryReader { imageGeometry in
                            Color.clear
                                .onAppear {
                                    imageSize = imageGeometry.size
                                }
                                .onChange(of: imageGeometry.size) { _, newSize in
                                    imageSize = newSize
                                }
                        }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                let newScale = scale * delta
                                scale = min(max(newScale, 1), 4)

                                // Update zoom state
                                isAnyPhotoZoomed = scale > 1.05
                            }
                            .onEnded { _ in
                                lastScale = 1.0

                                withAnimation(.spring(response: 0.3)) {
                                    if scale < 1 {
                                        scale = 1
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }

                                // Update zoom state after animation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isAnyPhotoZoomed = scale > 1.05
                                }
                            }
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Only handle pan when zoomed
                                guard scale > 1.05 else { return }

                                // Calculate max offset to keep image within bounds
                                let maxOffsetX = max(0, (imageSize.width * scale - geometry.size.width) / 2)
                                let maxOffsetY = max(0, (imageSize.height * scale - geometry.size.height) / 2)

                                let newOffsetX = lastOffset.width + value.translation.width
                                let newOffsetY = lastOffset.height + value.translation.height

                                offset = CGSize(
                                    width: min(max(newOffsetX, -maxOffsetX), maxOffsetX),
                                    height: min(max(newOffsetY, -maxOffsetY), maxOffsetY)
                                )
                            }
                            .onEnded { _ in
                                if scale > 1.05 {
                                    lastOffset = offset
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3)) {
                            if scale > 1 {
                                // Zoom out
                                scale = 1
                                offset = .zero
                                lastOffset = .zero
                                isAnyPhotoZoomed = false
                            } else {
                                // Zoom in
                                scale = 2.5
                                isAnyPhotoZoomed = true
                            }
                        }
                    }
            } placeholder: {
                ProgressView()
                    .tint(.white)
            }
            .onAppear {
                // Load and cache image, notify parent
                if let cachedImage = ImageCache.shared.get(forKey: photoURL) {
                    onImageLoaded(cachedImage)
                } else {
                    // Try loading from URL
                    Task {
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
        .onChange(of: photoURL) { _, _ in
            // Reset zoom state when photo changes
            withAnimation(.easeOut(duration: 0.2)) {
                scale = 1.0
                lastScale = 1.0
                offset = .zero
                lastOffset = .zero
                isAnyPhotoZoomed = false
            }
        }
    }
}
