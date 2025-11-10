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
    @State private var showingSaveSuccess = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showingShareSheet = false
    @State private var currentImage: UIImage?
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingToDismiss = false
    @State private var isZoomed = false
    @State private var isGestureActive = false // Track active gestures to prevent conflicts
    @State private var hasInitialized = false // Track if TabView has initialized

    init(photoURLs: [String], initialIndex: Int = 0, onDismiss: @escaping () -> Void) {
        self.photoURLs = photoURLs
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(CGFloat(1) - abs(dragOffset) / CGFloat(500))
                .ignoresSafeArea()

            // Use explicit selection binding to prevent TabView from resetting
            TabView(selection: Binding(
                get: { currentIndex },
                set: { newValue in
                    // Allow initial setup, then only update if not zoomed to prevent accidental navigation
                    if !hasInitialized {
                        currentIndex = newValue
                        // Mark as initialized IMMEDIATELY to block subsequent sets
                        hasInitialized = true
                    } else if !isZoomed && !isGestureActive {
                        currentIndex = newValue
                    }
                }
            )) {
                ForEach(Array(photoURLs.enumerated()), id: \.offset) { index, photoURL in
                    ZoomablePhotoView(
                        photoURL: photoURL,
                        isZoomed: $isZoomed,
                        isGestureActive: $isGestureActive
                    )
                    .tag(index)
                    .id(photoURL) // Force view recreation when photo changes
                }
            }
            .tabViewStyle(.page(indexDisplayMode: isZoomed ? .never : .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .offset(y: dragOffset)
            // Note: Don't use .allowsHitTesting(false) - it blocks ALL child gestures including zoom/pan!
            // The custom Binding above prevents navigation when zoomed
            .onAppear {
                // Ensure TabView starts at the correct index
                // Use async to ensure this happens after TabView initializes
                DispatchQueue.main.async {
                    if currentIndex != initialIndex {
                        currentIndex = initialIndex
                    }
                }
            }
            .onChange(of: currentIndex) { newIndex in
                // Immediately and synchronously reset all zoom states when changing photos
                isZoomed = false
                isGestureActive = false

                // Load the new current image for save/share
                if newIndex < photoURLs.count {
                    let photoURL = photoURLs[newIndex]
                    currentImage = ImageCache.shared.get(forKey: photoURL)
                }
            }
            .if(!isZoomed && !isGestureActive) { view in
                view.gesture(
                    DragGesture(minimumDistance: 30) // Increased threshold to prevent accidental triggers
                        .onChanged { value in
                            // Only allow vertical drag to dismiss when not zoomed or actively gesturing
                            if abs(value.translation.height) > abs(value.translation.width) * 1.5 {
                                isDraggingToDismiss = true
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if isDraggingToDismiss && abs(dragOffset) > 100 {
                                onDismiss()
                            } else {
                                withAnimation(.spring(response: 0.3)) {
                                    dragOffset = 0
                                }
                            }
                            isDraggingToDismiss = false
                        }
                )
            }

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
                .opacity(isDraggingToDismiss ? 0 : 1)

                Spacer()
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            // Load initial image
            if initialIndex < photoURLs.count {
                currentImage = ImageCache.shared.get(forKey: photoURLs[initialIndex])
            }
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
    @Binding var isZoomed: Bool
    @Binding var isGestureActive: Bool

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
                            Color.clear.onAppear {
                                imageSize = imageGeometry.size
                            }
                        }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                // Mark gesture as active immediately to block TabView navigation
                                isGestureActive = true

                                let delta = value / lastScale
                                lastScale = value
                                let newScale = scale * delta
                                scale = min(max(newScale, 1), 4)
                                isZoomed = scale > 1.01
                            }
                            .onEnded { _ in
                                lastScale = 1.0

                                // Small delay before allowing navigation to prevent immediate swipes
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isGestureActive = false
                                }

                                withAnimation(.spring(response: 0.3)) {
                                    if scale < 1 {
                                        scale = 1
                                        offset = .zero
                                        lastOffset = .zero
                                        isZoomed = false
                                    }
                                }
                            }
                    )
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                // Only handle drag when already zoomed
                                if scale > 1.05 {
                                    // Mark as active to prevent navigation during pan
                                    isGestureActive = true

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
                            }
                            .onEnded { _ in
                                if scale > 1.01 {
                                    lastOffset = offset
                                }

                                // Small delay before allowing navigation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    isGestureActive = false
                                }
                            },
                        including: scale > 1.05 ? .all : .none
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3)) {
                            if scale > 1 {
                                scale = 1
                                offset = .zero
                                lastOffset = .zero
                                isZoomed = false
                                isGestureActive = false
                            } else {
                                scale = 2
                                isZoomed = true
                                // Don't set gesture active for tap, it's instant
                            }
                        }
                    }
            } placeholder: {
                ProgressView()
                    .tint(.white)
            }
        }
        .onChange(of: scale) { newScale in
            isZoomed = newScale > 1.01
        }
        .onChange(of: photoURL) { _ in
            // Reset all zoom and gesture state when photo changes
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
            imageSize = .zero
            isZoomed = false
            isGestureActive = false
        }
    }
}
