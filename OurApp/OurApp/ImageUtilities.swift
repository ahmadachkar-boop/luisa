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

// MARK: - Full Screen Photo Viewer (Completely Rewritten)
struct FullScreenPhotoViewer: View {
    let photoURLs: [String]
    let initialIndex: Int
    let onDismiss: () -> Void

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

    init(photoURLs: [String], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.photoURLs = photoURLs
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss

        // Initialize directly with the index we want
        _currentIndex = State(initialValue: max(0, min(initialIndex, photoURLs.count - 1)))
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

                    Text("\(currentIndex + 1) / \(photoURLs.count)")
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
                    ZStack {
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
                                DragGesture(minimumDistance: 30)
                                    .onChanged { value in
                                        if !isZoomed {
                                            if abs(value.translation.height) > abs(value.translation.width) {
                                                dragOffset = value.translation.height
                                            } else if value.translation.width > 50 {
                                                // Swipe right - go to previous
                                                goToPrevious()
                                            } else if value.translation.width < -50 {
                                                // Swipe left - go to next
                                                goToNext()
                                            }
                                        }
                                    }
                                    .onEnded { value in
                                        if !isZoomed {
                                            if abs(dragOffset) > 100 {
                                                onDismiss()
                                            } else {
                                                withAnimation(.spring(response: 0.3)) {
                                                    dragOffset = 0
                                                }
                                            }
                                        }
                                    }
                            )
                        }

                        // Navigation buttons (when not zoomed)
                        if !isZoomed && photoURLs.count > 1 {
                            HStack {
                                // Previous button
                                if currentIndex > 0 {
                                    Button(action: goToPrevious) {
                                        Image(systemName: "chevron.left.circle.fill")
                                            .font(.system(size: 44))
                                            .foregroundColor(.white.opacity(0.7))
                                            .shadow(radius: 3)
                                    }
                                    .padding(.leading, 20)
                                }

                                Spacer()

                                // Next button
                                if currentIndex < photoURLs.count - 1 {
                                    Button(action: goToNext) {
                                        Image(systemName: "chevron.right.circle.fill")
                                            .font(.system(size: 44))
                                            .foregroundColor(.white.opacity(0.7))
                                            .shadow(radius: 3)
                                    }
                                    .padding(.trailing, 20)
                                }
                            }
                        }
                    }
                }

                // Page indicators
                if !isZoomed && photoURLs.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(0..<photoURLs.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentIndex ? Color.white : Color.white.opacity(0.5))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.bottom, 20)
                    .opacity(dragOffset == 0 ? 1 : 0)
                }
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
                    .gesture(
                        DragGesture()
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
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
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
                    } else if let url = URL(string: photoURL),
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
