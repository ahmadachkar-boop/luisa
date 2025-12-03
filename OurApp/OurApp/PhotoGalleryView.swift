import SwiftUI
import PhotosUI
import ImageIO
import AVFoundation
import Combine

// MARK: - Shimmer Effect for Loading Placeholders
struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (phase * geometry.size.width * 2))
                }
            )
            .clipped()
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.2)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

// MARK: - Skeleton Loading Grid
struct SkeletonPhotoGrid: View {
    let columnCount: Int

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
    }

    private var cellSize: CGFloat {
        let spacing: CGFloat = 8 * CGFloat(columnCount - 1)
        let padding: CGFloat = 16
        return (UIScreen.main.bounds.width - padding - spacing) / CGFloat(columnCount)
    }

    private var cornerRadius: CGFloat {
        columnCount == 2 ? 16 : (columnCount == 3 ? 12 : 8)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: cellSize, height: cellSize)
                    .shimmer()
                    .opacity(1.0 - Double(index) * 0.05)
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Animated Upload Progress Bar
struct AnimatedUploadProgressBar: View {
    let progress: Double
    let uploadedCount: Int
    let totalCount: Int

    @State private var stripeOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Uploading media...")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                Spacer()
                Text("\(uploadedCount) of \(totalCount)")
                    .font(.caption.weight(.medium))
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.95, green: 0.92, blue: 1.0))

                    // Animated progress fill
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.7, green: 0.45, blue: 0.95),
                                    Color(red: 0.6, green: 0.4, blue: 0.85),
                                    Color(red: 0.7, green: 0.45, blue: 0.95)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(progress))
                        .overlay(
                            // Animated stripes
                            GeometryReader { progressGeometry in
                                HStack(spacing: 8) {
                                    ForEach(0..<20, id: \.self) { _ in
                                        Rectangle()
                                            .fill(Color.white.opacity(0.2))
                                            .frame(width: 8)
                                            .rotationEffect(.degrees(-45))
                                    }
                                }
                                .offset(x: stripeOffset)
                            }
                            .mask(RoundedRectangle(cornerRadius: 6))
                        )
                        .animation(.spring(response: 0.4), value: progress)
                }
            }
            .frame(height: 12)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .onAppear {
            withAnimation(
                Animation.linear(duration: 0.8)
                    .repeatForever(autoreverses: false)
            ) {
                stripeOffset = 20
            }
        }
    }
}

// MARK: - Haptic Feedback Manager
struct HapticManager {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

// Helper function to extract capture date from image metadata
func extractCaptureDate(from imageData: Data) -> Date? {
    guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
          let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
          let exifDict = imageProperties[kCGImagePropertyExifDictionary as String] as? [String: Any],
          let dateTimeOriginal = exifDict[kCGImagePropertyExifDateTimeOriginal as String] as? String else {
        return nil
    }

    // EXIF date format: "YYYY:MM:DD HH:MM:SS"
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return formatter.date(from: dateTimeOriginal)
}

// Helper function to extract creation date from video metadata
func extractVideoCreationDate(from videoURL: URL) async -> Date? {
    let asset = AVURLAsset(url: videoURL)

    do {
        // Try to get creation date from common metadata
        let metadata = try await asset.load(.commonMetadata)

        // Look for creation date in metadata
        for item in metadata {
            if let key = item.commonKey, key == .commonKeyCreationDate {
                if let dateValue = try await item.load(.dateValue) {
                    return dateValue
                }
                if let stringValue = try await item.load(.stringValue) {
                    // Try parsing ISO 8601 date
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: stringValue) {
                        return date
                    }
                    // Try without fractional seconds
                    formatter.formatOptions = [.withInternetDateTime]
                    if let date = formatter.date(from: stringValue) {
                        return date
                    }
                }
            }
        }

        // Fallback: try creation date metadata key
        let creationDateItems = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierCreationDate)
        if let dateItem = creationDateItems.first {
            if let dateValue = try await dateItem.load(.dateValue) {
                return dateValue
            }
        }

    } catch {
        print("⚠️ [VIDEO METADATA] Failed to load metadata: \(error)")
    }

    // Last resort: check file creation date
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: videoURL.path)
        if let creationDate = attrs[.creationDate] as? Date {
            // Only use file date if it seems reasonable (not today, which would indicate a temp file)
            let calendar = Calendar.current
            if !calendar.isDateInToday(creationDate) {
                return creationDate
            }
        }
    } catch {
        print("⚠️ [VIDEO METADATA] Failed to get file attributes: \(error)")
    }

    return nil
}

// Wrapper to make Int work with .fullScreenCover(item:)
struct PhotoIndex: Identifiable {
    let id = UUID()
    let value: Int
}

// MARK: - Sort Options
enum PhotoSortOption: String, CaseIterable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case recentlyAdded = "Recently Added"

    var icon: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        case .recentlyAdded: return "clock.arrow.circlepath"
        }
    }
}

struct PhotoGalleryView: View {
    @Binding var resetTrigger: Int
    @StateObject private var viewModel = PhotoGalleryViewModel()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingAddPhoto = false
    @State private var isUploading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedPhotoIndex: PhotoIndex?
    @State private var selectionMode = false
    @State private var selectedPhotoIds: Set<String> = []
    @State private var showingSaveSuccess = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var savedPhotoCount = 0
    @State private var showingExpandedHeader = false
    @State private var isResettingScroll = false
    @State private var currentFolderView: FolderViewType = .allPhotos
    @State private var folderNavStack: [FolderViewType] = []
    @State private var showingCreateFolder = false
    @State private var newFolderName = ""
    @State private var showingFoldersOverview = false

    // New feature states
    @State private var sortOption: PhotoSortOption = .newestFirst
    @State private var showingSortOptions = false
    @State private var columnCount: Int = 3
    @State private var showingDateFilter = false
    @State private var filterStartDate: Date? = nil
    @State private var filterEndDate: Date? = nil
    @State private var showingMoveToFolder = false
    @State private var showingAddToEvent = false
    @State private var uploadProgress: Double = 0.0
    @State private var uploadedCount: Int = 0
    @State private var totalUploadCount: Int = 0
    @State private var showingBatchProgress = false
    @State private var batchProgress: Double = 0.0
    @State private var scrollToTopTrigger: Int = 0 // Triggers scroll to top when incremented
    @State private var batchOperationMessage = ""
    @State private var isInitialLoad = true
    @State private var folderTransitionId = UUID() // For folder transition animations

    // Computed columns based on user preference
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
    }

    // Magnification gesture state
    @GestureState private var magnificationScale: CGFloat = 1.0

    // Get photos for current folder view with date filtering
    private var filteredPhotos: [Photo] {
        var photos = viewModel.photos(for: currentFolderView)

        // Apply date filter
        if let startDate = filterStartDate {
            photos = photos.filter { photo in
                let captureDate = photo.capturedAt ?? photo.createdAt
                return captureDate >= Calendar.current.startOfDay(for: startDate)
            }
        }
        if let endDate = filterEndDate {
            photos = photos.filter { photo in
                let captureDate = photo.capturedAt ?? photo.createdAt
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate))!
                return captureDate < endOfDay
            }
        }

        return photos
    }

    // Check if date filter is active
    private var hasDateFilter: Bool {
        filterStartDate != nil || filterEndDate != nil
    }

    // Separate dated photos (with capturedAt) from undated ones (screenshots, etc.)
    private var datedPhotos: [Photo] {
        filteredPhotos.filter { $0.capturedAt != nil }
    }

    private var undatedPhotos: [Photo] {
        let undated = filteredPhotos.filter { $0.capturedAt == nil }
        // Sort by createdAt (upload date) - newest first by default
        return undated.sorted { photo1, photo2 in
            switch sortOption {
            case .newestFirst, .recentlyAdded:
                return photo1.createdAt > photo2.createdAt
            case .oldestFirst:
                return photo1.createdAt < photo2.createdAt
            }
        }
    }

    // Group photos by month/year (using original capture date from metadata)
    // Only includes photos with capturedAt date - undated photos shown separately
    private var photosByMonth: [(key: String, photos: [Photo])] {
        let grouped = Dictionary(grouping: datedPhotos) { photo -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            // Use capturedAt (guaranteed to exist due to datedPhotos filter)
            return formatter.string(from: photo.capturedAt!)
        }

        // Sort months based on current sort option
        let sortedMonths = grouped.sorted { first, second in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            guard let date1 = formatter.date(from: first.key),
                  let date2 = formatter.date(from: second.key) else {
                return first.key > second.key
            }
            switch sortOption {
            case .newestFirst, .recentlyAdded:
                return date1 > date2
            case .oldestFirst:
                return date1 < date2
            }
        }

        return sortedMonths.map { month in
            // Sort photos within each month
            let sortedPhotos = month.value.sorted { photo1, photo2 in
                switch sortOption {
                case .newestFirst:
                    return photo1.capturedAt! > photo2.capturedAt!
                case .oldestFirst:
                    return photo1.capturedAt! < photo2.capturedAt!
                case .recentlyAdded:
                    return photo1.createdAt > photo2.createdAt
                }
            }
            return (key: month.key, photos: sortedPhotos)
        }
    }

    // Group photos by date within each month
    private func photosByDate(for monthPhotos: [Photo]) -> [(key: String, photos: [Photo])] {
        let grouped = Dictionary(grouping: monthPhotos) { photo -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d" // "Monday, January 15"
            let dateToUse = photo.capturedAt ?? photo.createdAt
            return formatter.string(from: dateToUse)
        }

        return grouped.sorted { first, second in
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            guard let date1 = formatter.date(from: first.key),
                  let date2 = formatter.date(from: second.key) else {
                return first.key > second.key
            }
            return date1 > date2
        }.map { (key: $0.key, photos: $0.value) }
    }

    // Cached photos in display order to avoid recomputation
    @State private var cachedPhotosInDisplayOrder: [Photo] = []

    // Flat array of photos in display order - dated photos first, then undated at bottom
    private var photosInDisplayOrder: [Photo] {
        // Return cached value; cache is updated via onChange modifiers
        if !cachedPhotosInDisplayOrder.isEmpty {
            return cachedPhotosInDisplayOrder
        }
        // Fallback for initial load before cache is populated
        return photosByMonth.flatMap { $0.photos } + undatedPhotos
    }

    // Update cache when photos, filters, or sort options change
    private func updatePhotosCache() {
        cachedPhotosInDisplayOrder = photosByMonth.flatMap { $0.photos } + undatedPhotos
    }

    // Current folder title for display
    private var folderTitle: String {
        switch currentFolderView {
        case .allPhotos:
            return "All Photos"
        case .favorites:
            return "Favorites"
        case .events:
            return "Events"
        case .specialEvents:
            return "Special Events"
        case .event(let eventId):
            if let event = viewModel.events.first(where: { $0.id == eventId }) {
                return event.title
            }
            return "Event"
        case .custom(let folderId):
            if let folder = viewModel.folders.first(where: { $0.id == folderId }) {
                return folder.name
            }
            return "Folder"
        }
    }

    private var contentView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Top anchor for scroll-to-top
                    Color.clear
                        .frame(height: 0)
                        .id("photos-top-anchor")

                    // Expandable header (hidden when collapsed)
                    expandableHeader
                        .padding(.horizontal)
                        .padding(.top, 4)

                    // Folder navigation bar
                    folderNavigationBar
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Animated upload progress bar
                    if isUploading {
                        AnimatedUploadProgressBar(
                            progress: uploadProgress,
                            uploadedCount: uploadedCount,
                            totalCount: totalUploadCount
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }

                    // Active filters indicator
                    if hasDateFilter || sortOption != .newestFirst {
                        activeFiltersBar
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Show folders or photos based on current view
                    if currentFolderView == .events || currentFolderView == .specialEvents {
                        folderListView
                            .simultaneousGesture(
                                TapGesture()
                                    .onEnded { _ in
                                        if showingExpandedHeader {
                                            withAnimation(.spring(response: 0.3)) {
                                                showingExpandedHeader = false
                                            }
                                        }
                                    }
                            )
                    } else {
                        photoGridView
                            .simultaneousGesture(
                                TapGesture()
                                    .onEnded { _ in
                                        if showingExpandedHeader {
                                            withAnimation(.spring(response: 0.3)) {
                                                showingExpandedHeader = false
                                            }
                                        }
                                    }
                            )
                    }
                }
            }
            .refreshable {
                // Show the expanded header when user pulls down
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingExpandedHeader = true
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { oldValue, newValue in
                // Auto-hide header when scrolling down - scroll to top with animation
                // Use isResettingScroll to prevent scroll momentum from moving the view
                if showingExpandedHeader && newValue > 1 && !isResettingScroll {
                    isResettingScroll = true
                    withAnimation(.easeOut(duration: 0.25)) {
                        showingExpandedHeader = false
                    }
                    // Delay scroll to top to let momentum settle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            scrollProxy.scrollTo("photos-top-anchor", anchor: .top)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isResettingScroll = false
                        }
                    }
                }
            }
            .onChange(of: scrollToTopTrigger) { _, _ in
                // Scroll to top when tab is tapped while viewing a photo grid
                withAnimation(.easeOut(duration: 0.3)) {
                    scrollProxy.scrollTo("photos-top-anchor", anchor: .top)
                }
            }
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 0)
            }
        }
        .simultaneousGesture(
            MagnificationGesture()
                .updating($magnificationScale) { value, scale, _ in
                    scale = value
                }
                .onEnded { value in
                    // Pinch in (scale < 1) = more columns, pinch out (scale > 1) = fewer columns
                    withAnimation(.spring(response: 0.3)) {
                        if value < 0.8 && columnCount < 4 {
                            columnCount += 1
                        } else if value > 1.2 && columnCount > 2 {
                            columnCount -= 1
                        }
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let horizontalAmount = value.translation.width
                    let verticalAmount = abs(value.translation.height)

                    // Only trigger if it's more horizontal than vertical
                    if abs(horizontalAmount) > 50 && abs(horizontalAmount) > verticalAmount * 2 {
                        if horizontalAmount > 0 {
                            // Swipe right - navigate back
                            if currentFolderView != .allPhotos {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    let previousView = folderNavStack.popLast() ?? .allPhotos

                                    // If navigating back from Events or Special Events parent folders to All Photos,
                                    // show folders overview instead
                                    if (currentFolderView == .events || currentFolderView == .specialEvents) && previousView == .allPhotos {
                                        currentFolderView = .allPhotos
                                        showingFoldersOverview = true
                                    } else {
                                        currentFolderView = previousView
                                    }
                                }
                            }
                        } else if horizontalAmount < 0 {
                            // Swipe left - show folders overview (only from All Photos)
                            if currentFolderView == .allPhotos {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showingFoldersOverview = true
                                }
                            }
                        }
                    }
                }
        )
    }

    // MARK: - Active Filters Bar (Enhanced)
    @State private var filtersBarAppeared = false

    private var activeFilterCount: Int {
        var count = 0
        if sortOption != .newestFirst { count += 1 }
        if hasDateFilter { count += 1 }
        return count
    }

    private var activeFiltersBar: some View {
        HStack(spacing: 8) {
            // Scrollable filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Sort indicator (tappable to show sort options)
                    if sortOption != .newestFirst {
                        Button(action: {
                            HapticManager.light()
                            withAnimation(.spring(response: 0.3)) {
                                showingExpandedHeader = true
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: sortOption.icon)
                                    .font(.caption.weight(.medium))
                                Text(sortOption.rawValue)
                                    .font(.caption.weight(.medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(Color(red: 0.5, green: 0.35, blue: 0.75))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.95, green: 0.9, blue: 1.0))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.2), lineWidth: 1)
                            )
                        }
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                    }

                    // Date filter indicator (tappable to edit)
                    if hasDateFilter {
                        Button(action: {
                            HapticManager.light()
                            showingDateFilter = true
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "calendar")
                                    .font(.caption.weight(.medium))
                                if let start = filterStartDate, let end = filterEndDate {
                                    Text("\(start, format: .dateTime.month(.abbreviated).day()) - \(end, format: .dateTime.month(.abbreviated).day())")
                                        .font(.caption.weight(.medium))
                                } else if let start = filterStartDate {
                                    Text("From \(start, format: .dateTime.month(.abbreviated).day())")
                                        .font(.caption.weight(.medium))
                                } else if let end = filterEndDate {
                                    Text("Until \(end, format: .dateTime.month(.abbreviated).day())")
                                        .font(.caption.weight(.medium))
                                }

                                Button(action: {
                                    HapticManager.light()
                                    withAnimation(.spring(response: 0.3)) {
                                        filterStartDate = nil
                                        filterEndDate = nil
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.6))
                                }
                            }
                            .foregroundColor(Color(red: 0.5, green: 0.35, blue: 0.75))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.95, green: 0.9, blue: 1.0))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.2), lineWidth: 1)
                            )
                        }
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                    }
                }
            }

            // Clear All button (when 2+ filters active)
            if activeFilterCount >= 2 {
                Button(action: {
                    HapticManager.medium()
                    withAnimation(.spring(response: 0.3)) {
                        sortOption = .newestFirst
                        filterStartDate = nil
                        filterEndDate = nil
                    }
                }) {
                    Text("Clear All")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(red: 0.8, green: 0.4, blue: 0.4))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(red: 1.0, green: 0.95, blue: 0.95))
                        )
                }
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // Grid size indicator
            HStack(spacing: 4) {
                Image(systemName: "square.grid.\(columnCount)x\(columnCount)")
                    .font(.caption.weight(.medium))
            }
            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(red: 0.95, green: 0.93, blue: 0.98))
            )
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .opacity(filtersBarAppeared ? 1 : 0)
        .offset(y: filtersBarAppeared ? 0 : -10)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                filtersBarAppeared = true
            }
        }
    }

    // MARK: - Expandable Header (hidden when collapsed)
    private var expandableHeader: some View {
        VStack(spacing: 0) {
            // Expanded content only - no indicators when collapsed
            if showingExpandedHeader {
                VStack(spacing: 16) {
                    // Quick actions row
                    HStack(spacing: 12) {
                        // Add button (photos & videos)
                        PhotosPicker(selection: $selectedItems, matching: .any(of: [.images, .videos])) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body)
                                Text("Add")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.7, green: 0.45, blue: 0.95),
                                        Color(red: 0.55, green: 0.35, blue: 0.85)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(12)
                        }
                        .disabled(isUploading)

                        // Select
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showingExpandedHeader = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                selectionMode = true
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.body)
                                Text("Select")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(Color(red: 0.5, green: 0.35, blue: 0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                            )
                        }

                        // Create Folder
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showingExpandedHeader = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showingCreateFolder = true
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.body)
                                Text("Folder")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(Color(red: 0.5, green: 0.35, blue: 0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                            )
                        }
                    }

                    // Sort and Filter section
                    VStack(spacing: 12) {
                        // Sort options
                        HStack {
                            Text("Sort by")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                            Spacer()

                            Menu {
                                ForEach(PhotoSortOption.allCases, id: \.self) { option in
                                    Button(action: {
                                        withAnimation {
                                            sortOption = option
                                        }
                                    }) {
                                        HStack {
                                            Label(option.rawValue, systemImage: option.icon)
                                            if sortOption == option {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(sortOption.rawValue)
                                        .font(.subheadline)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                }
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                                )
                            }
                        }
                        .padding(.horizontal, 4)

                        // Date filter
                        HStack {
                            Text("Filter by date")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                            Spacer()

                            Button(action: { showingDateFilter = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: hasDateFilter ? "calendar.badge.checkmark" : "calendar")
                                        .font(.subheadline)
                                    Text(hasDateFilter ? "Active" : "None")
                                        .font(.subheadline)
                                }
                                .foregroundColor(hasDateFilter ? .white : Color(red: 0.5, green: 0.4, blue: 0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(hasDateFilter ? Color(red: 0.6, green: 0.4, blue: 0.85) : Color(red: 0.95, green: 0.92, blue: 1.0))
                                )
                            }
                        }
                        .padding(.horizontal, 4)

                        // Clear filter button if active
                        if hasDateFilter {
                            Button(action: {
                                filterStartDate = nil
                                filterEndDate = nil
                            }) {
                                Text("Clear Date Filter")
                                    .font(.subheadline)
                                    .foregroundColor(Color(red: 0.8, green: 0.4, blue: 0.4))
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                    )

                    // Grid size
                    HStack {
                        Text("Grid size")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                        Spacer()

                        HStack(spacing: 8) {
                            ForEach([2, 3, 4], id: \.self) { count in
                                Button(action: {
                                    withAnimation(.spring(response: 0.3)) {
                                        columnCount = count
                                    }
                                }) {
                                    Text("\(count)")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(columnCount == count ? .white : Color(red: 0.5, green: 0.4, blue: 0.8))
                                        .frame(width: 36, height: 36)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(columnCount == count ? Color(red: 0.6, green: 0.4, blue: 0.85) : Color(red: 0.95, green: 0.92, blue: 1.0))
                                        )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.98, green: 0.96, blue: 1.0))
                        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var folderNavigationBar: some View {
        HStack(spacing: 12) {
            // Back button if we're in a subfolder
            if currentFolderView != .allPhotos {
                Button(action: {
                    HapticManager.light()
                    let previousView = folderNavStack.popLast() ?? .allPhotos

                    // If navigating back from Events or Special Events parent folders to All Photos,
                    // show folders overview instead
                    if (currentFolderView == .events || currentFolderView == .specialEvents) && previousView == .allPhotos {
                        currentFolderView = .allPhotos
                        showingFoldersOverview = true
                    } else {
                        currentFolderView = previousView
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.medium))
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
            }

            // Current folder title
            if currentFolderView == .allPhotos {
                Button(action: {
                    HapticManager.light()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingFoldersOverview = true
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(folderTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                    }
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Text(folderTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }

    private var folderListView: some View {
        LazyVStack(spacing: 12) {
            let folders = currentFolderView == .events ?
                viewModel.eventFolders(specialOnly: false) :
                viewModel.eventFolders(specialOnly: true)

            ForEach(folders, id: \.event.id) { eventData in
                Button(action: {
                    if let eventId = eventData.event.id {
                        navigateToFolder(.event(eventId))
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: eventData.event.isSpecial ? "star.circle.fill" : "calendar.circle.fill")
                            .font(.title)
                            .foregroundColor(Color(red: 0.7, green: 0.5, blue: 0.9))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(eventData.event.title)
                                .font(.headline)
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                            Text("\(eventData.photoCount) photo\(eventData.photoCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.8))
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    // Helper to get thumbnail URLs for a folder type
    private func thumbnailURLs(for folderType: FolderViewType, limit: Int = 4) -> [String] {
        return Array(viewModel.photos(for: folderType).prefix(limit).map { $0.imageURL })
    }

    private var foldersOverviewView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Button(action: {
                        HapticManager.light()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingFoldersOverview = false
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.medium))
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                    }

                    Text("Folders")
                        .font(.title.weight(.bold))
                        .foregroundColor(Color(red: 0.25, green: 0.15, blue: 0.45))

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // All Photos with thumbnails
                FolderCard(
                    title: "All Photos",
                    icon: "photo.on.rectangle",
                    count: viewModel.photos.count,
                    color: Color(red: 0.7, green: 0.5, blue: 0.9),
                    thumbnailURLs: thumbnailURLs(for: .allPhotos)
                ) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingFoldersOverview = false
                    }
                }

                // Favorites with thumbnails
                let favoritesCount = viewModel.favoritesCount
                if favoritesCount > 0 {
                    FolderCard(
                        title: "Favorites",
                        icon: "heart.fill",
                        count: favoritesCount,
                        color: Color(red: 0.9, green: 0.4, blue: 0.5),
                        thumbnailURLs: thumbnailURLs(for: .favorites)
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingFoldersOverview = false
                            navigateToFolder(.favorites)
                        }
                    }
                }

                // Events (excluding special events to match folder content)
                let eventPhotos = viewModel.photos.filter { photo in
                    guard let eventId = photo.eventId else { return false }
                    return viewModel.events.first(where: { $0.id == eventId })?.isSpecial == false
                }
                if !eventPhotos.isEmpty {
                    FolderCard(
                        title: "Events",
                        icon: "calendar",
                        count: eventPhotos.count,
                        color: Color(red: 0.6, green: 0.4, blue: 0.85),
                        thumbnailURLs: Array(eventPhotos.prefix(4).map { $0.imageURL })
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingFoldersOverview = false
                            navigateToFolder(.events)
                        }
                    }
                }

                // Special Events with thumbnails
                let specialEventPhotos = viewModel.photos.filter { photo in
                    guard let eventId = photo.eventId else { return false }
                    return viewModel.events.first(where: { $0.id == eventId })?.isSpecial == true
                }
                if !specialEventPhotos.isEmpty {
                    FolderCard(
                        title: "Special Events",
                        icon: "star.circle",
                        count: specialEventPhotos.count,
                        color: Color(red: 0.8, green: 0.6, blue: 0.95),
                        thumbnailURLs: Array(specialEventPhotos.prefix(4).map { $0.imageURL })
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingFoldersOverview = false
                            navigateToFolder(.specialEvents)
                        }
                    }
                }

                // Custom Folders with thumbnails
                let customFolders = viewModel.folders.filter { $0.type == .custom }
                if !customFolders.isEmpty {
                    Divider()
                        .padding(.horizontal)
                        .padding(.vertical, 4)

                    Text("Custom Folders")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)

                    ForEach(customFolders, id: \.id) { folder in
                        let folderPhotos = viewModel.photos.filter { $0.folderId == folder.id }
                        FolderCard(
                            title: folder.name,
                            icon: "folder.fill",
                            count: folderPhotos.count,
                            color: Color(red: 0.65, green: 0.45, blue: 0.8),
                            thumbnailURLs: Array(folderPhotos.prefix(4).map { $0.imageURL })
                        ) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showingFoldersOverview = false
                                if let folderId = folder.id {
                                    navigateToFolder(.custom(folderId))
                                }
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive, action: {
                                HapticManager.medium()
                                Task {
                                    try? await viewModel.deleteFolder(folder)
                                }
                            }) {
                                Label("Delete Folder", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 0)
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    // Swipe right to go back to all photos
                    if value.translation.width > 80 && abs(value.translation.height) < 100 {
                        HapticManager.light()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingFoldersOverview = false
                        }
                    }
                }
        )
    }

    private var photoGridView: some View {
        LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
            ForEach(photosByMonth, id: \.key) { monthGroup in
                Section {
                    // Month header (prominent)
                    monthHeaderView(monthGroup: monthGroup)

                    // Group by date within this month
                    let dateGroups = photosByDate(for: monthGroup.photos)

                    ForEach(dateGroups, id: \.key) { dateGroup in
                        VStack(alignment: .leading, spacing: 8) {
                            // Subtle day header
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.4))
                                    .frame(width: 4, height: 4)
                                Text(dateGroup.key)
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7).opacity(0.8))
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, dateGroup.key == dateGroups.first?.key ? 4 : 14)

                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(dateGroup.photos, id: \.id) { photo in
                                    let photoId = photo.id ?? ""

                                    PhotoGridCell(
                                        photo: photo,
                                        index: 0, // Index no longer used for selection
                                        selectionMode: selectionMode,
                                        isSelected: selectedPhotoIds.contains(photoId),
                                        columnCount: columnCount,
                                        onTap: {
                                            if selectionMode {
                                                if selectedPhotoIds.contains(photoId) {
                                                    selectedPhotoIds.remove(photoId)
                                                } else {
                                                    selectedPhotoIds.insert(photoId)
                                                }
                                            } else {
                                                if let displayIndex = photosInDisplayOrder.firstIndex(where: { $0.id == photo.id }) {
                                                    selectedPhotoIndex = PhotoIndex(value: displayIndex)
                                                }
                                            }
                                        },
                                        onLongPress: {
                                            if !selectionMode {
                                                selectionMode = true
                                                selectedPhotoIds.insert(photoId)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }

            // MARK: - Undated Media Section
            // Shows screenshots, downloads, and other media without capture date metadata
            if !undatedPhotos.isEmpty {
                Section {
                    undatedSectionView
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Undated Section View
    private var undatedSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 12) {
                // "Undated" label with icon
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    Text("Undated")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(Color(red: 0.25, green: 0.15, blue: 0.45))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: Color(red: 0.5, green: 0.4, blue: 0.7).opacity(0.12), radius: 4, x: 0, y: 2)
                )
                .overlay(
                    Capsule()
                        .stroke(Color(red: 0.5, green: 0.4, blue: 0.7).opacity(0.15), lineWidth: 1)
                )

                // Decorative line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.5, green: 0.4, blue: 0.7).opacity(0.3),
                                Color(red: 0.5, green: 0.4, blue: 0.7).opacity(0.05)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1.5)

                // Count badge
                Text("\(undatedPhotos.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.5, green: 0.4, blue: 0.7).opacity(0.08))
                    )
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)

            // Description text
            Text("Screenshots, downloads, and media without date information")
                .font(.caption)
                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7).opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.top, 4)

            // Photo grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(undatedPhotos, id: \.id) { photo in
                    let photoId = photo.id ?? ""

                    PhotoGridCell(
                        photo: photo,
                        index: 0, // Index no longer used for selection
                        selectionMode: selectionMode,
                        isSelected: selectedPhotoIds.contains(photoId),
                        columnCount: columnCount,
                        onTap: {
                            if selectionMode {
                                if selectedPhotoIds.contains(photoId) {
                                    selectedPhotoIds.remove(photoId)
                                } else {
                                    selectedPhotoIds.insert(photoId)
                                }
                            } else {
                                if let displayIndex = photosInDisplayOrder.firstIndex(where: { $0.id == photo.id }) {
                                    selectedPhotoIndex = PhotoIndex(value: displayIndex)
                                }
                            }
                        },
                        onLongPress: {
                            if !selectionMode {
                                selectionMode = true
                                selectedPhotoIds.insert(photoId)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
    }

    private func navigateToFolder(_ folder: FolderViewType) {
        folderNavStack.append(currentFolderView)
        currentFolderView = folder
    }

    private func monthHeaderView(monthGroup: (key: String, photos: [Photo])) -> some View {
        HStack(spacing: 12) {
            // Month name with pill background
            Text(monthGroup.key)
                .font(.subheadline.weight(.bold))
                .foregroundColor(Color(red: 0.25, green: 0.15, blue: 0.45))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.12), radius: 4, x: 0, y: 2)
                )
                .overlay(
                    Capsule()
                        .stroke(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.15), lineWidth: 1)
                )

            // Decorative line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.3),
                            Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.05)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1.5)

            // Photo count badge
            Text("\(monthGroup.photos.count)")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    var body: some View {
        ZStack {
            NavigationView {
                ZStack {
                    // Background gradient
                    AppTheme.backgroundGradient
                        .ignoresSafeArea()

                    if showingFoldersOverview {
                        foldersOverviewView
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    } else if isInitialLoad && viewModel.photos.isEmpty {
                        // Skeleton loading state
                        VStack(spacing: 16) {
                            // Skeleton header
                            HStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 120, height: 24)
                                    .shimmer()
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                            SkeletonPhotoGrid(columnCount: columnCount)
                        }
                        .transition(.opacity)
                    } else if viewModel.photos.isEmpty && currentFolderView == .allPhotos {
                        // Enhanced empty state
                        VStack(spacing: 24) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                                    .frame(width: 140, height: 140)

                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 56, weight: .light))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.7, green: 0.5, blue: 0.95),
                                                Color(red: 0.55, green: 0.35, blue: 0.85)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }

                            VStack(spacing: 8) {
                                Text("No photos yet")
                                    .font(.title2.weight(.bold))
                                    .foregroundColor(Color(red: 0.25, green: 0.15, blue: 0.45))

                                Text("Start capturing your memories together")
                                    .font(.subheadline)
                                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                                    .multilineTextAlignment(.center)
                            }

                            // Quick add button in empty state (photos & videos)
                            PhotosPicker(selection: $selectedItems, matching: .any(of: [.images, .videos])) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.body.weight(.semibold))
                                    Text("Add Photos & Videos")
                                        .font(.body.weight(.semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.7, green: 0.45, blue: 0.95),
                                            Color(red: 0.55, green: 0.35, blue: 0.85)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Capsule())
                                .shadow(color: Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.4), radius: 8, x: 0, y: 4)
                            }
                        }
                        .padding(.horizontal, 32)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        contentView
                            .id(folderTransitionId)
                            .transition(.opacity)
                    }
                }
                .toolbar {
                    if selectionMode {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                HapticManager.light()
                                selectionMode = false
                                selectedPhotoIds.removeAll()
                            }
                            .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                        }

                        ToolbarItem(placement: .principal) {
                            Text("\(selectedPhotoIds.count) selected")
                                .font(.headline)
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack(spacing: 12) {
                                // Favorite button
                                Button(action: {
                                    HapticManager.light()
                                    toggleFavoritesForSelected()
                                }) {
                                    Image(systemName: "heart.fill")
                                        .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.5))
                                }
                                .disabled(selectedPhotoIds.isEmpty)

                                // Move to folder button
                                Button(action: {
                                    HapticManager.light()
                                    showingMoveToFolder = true
                                }) {
                                    Image(systemName: "folder.badge.plus")
                                        .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                                }
                                .disabled(selectedPhotoIds.isEmpty)

                                // Add to event button
                                Button(action: {
                                    HapticManager.light()
                                    showingAddToEvent = true
                                }) {
                                    Image(systemName: "calendar.badge.plus")
                                        .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                                }
                                .disabled(selectedPhotoIds.isEmpty)

                                // Save button
                                Button(action: {
                                    HapticManager.light()
                                    saveSelectedPhotos()
                                }) {
                                    Image(systemName: "square.and.arrow.down")
                                        .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                                }
                                .disabled(selectedPhotoIds.isEmpty)

                                // Delete button
                                Button(action: {
                                    HapticManager.medium()
                                    deleteSelectedPhotos()
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .disabled(selectedPhotoIds.isEmpty)
                            }
                        }
                    }
                }
                .onChange(of: selectedItems) { oldItems, newItems in
                    guard !newItems.isEmpty else { return }

                    print("📸 [GALLERY UPLOAD] Selected \(newItems.count) items for upload")

                    // Immediately update UI on main thread
                    isUploading = true
                    totalUploadCount = newItems.count
                    uploadedCount = 0
                    uploadProgress = 0.0

                    // Start upload task - NOT on MainActor to avoid blocking UI
                    Task {
                        print("📸 [GALLERY UPLOAD] Starting upload task...")

                        // Use background-protected batch for reliable uploads even when app is backgrounded
                        let (batchId, backgroundTaskId) = UploadProgressManager.shared.createBackgroundProtectedBatch(
                            count: newItems.count,
                            type: .photo,
                            eventId: nil // Gallery upload, no event
                        )
                        print("📸 [GALLERY UPLOAD] Created batch \(batchId) with background task protection")

                        var uploadErrors: [String] = []
                        var successCount = 0

                        // Process and upload one item at a time to avoid memory issues
                        for (index, item) in newItems.enumerated() {
                            // Check for task cancellation (app backgrounded)
                            if Task.isCancelled {
                                print("⚠️ [UPLOAD] Task cancelled at index \(index)")
                                break
                            }

                            UploadProgressManager.shared.updateTaskProgress(
                                batchId: batchId,
                                taskIndex: index,
                                progress: 0.1
                            )

                            do {
                                // Check if item is a video
                                let supportedTypes = item.supportedContentTypes
                                let isVideo = supportedTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }

                                if isVideo {
                                    // MARK: - Video Upload Flow
                                    print("🎬 [GALLERY UPLOAD] Processing video \(index + 1)/\(newItems.count)...")

                                    // Load video as transferable Movie type
                                    guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
                                        print("🔴 [GALLERY UPLOAD] Failed to load video \(index + 1)")
                                        UploadProgressManager.shared.failTask(
                                            batchId: batchId,
                                            taskIndex: index,
                                            error: "Failed to load video"
                                        )
                                        uploadErrors.append("Failed to load video \(index + 1)")
                                        continue
                                    }

                                    // Store temp URL for cleanup
                                    let tempVideoURL = movie.url
                                    defer {
                                        // Clean up temp video file after processing
                                        try? FileManager.default.removeItem(at: tempVideoURL)
                                    }

                                    UploadProgressManager.shared.updateTaskProgress(
                                        batchId: batchId,
                                        taskIndex: index,
                                        progress: 0.15
                                    )

                                    // Verify video file exists and is valid
                                    guard FileManager.default.fileExists(atPath: tempVideoURL.path) else {
                                        print("🔴 [GALLERY UPLOAD] Video file not found \(index + 1)")
                                        UploadProgressManager.shared.failTask(
                                            batchId: batchId,
                                            taskIndex: index,
                                            error: "Video file not found"
                                        )
                                        uploadErrors.append("Video file not found \(index + 1)")
                                        continue
                                    }

                                    // Process video, generate thumbnail, and extract metadata in parallel
                                    print("🎬 [GALLERY UPLOAD] Processing video \(index + 1)...")

                                    // Start all operations concurrently
                                    async let thumbnailTask = VideoCompressor.shared.generateThumbnail(from: tempVideoURL)
                                    async let processTask = VideoCompressor.shared.processVideo(from: tempVideoURL)
                                    async let metadataTask = extractVideoCreationDate(from: tempVideoURL)

                                    // Wait for thumbnail first (faster, validates video)
                                    let thumbnail: UIImage
                                    do {
                                        thumbnail = try await thumbnailTask
                                    } catch {
                                        print("🔴 [GALLERY UPLOAD] Failed to generate thumbnail \(index + 1): \(error)")
                                        UploadProgressManager.shared.failTask(
                                            batchId: batchId,
                                            taskIndex: index,
                                            error: "Invalid video format"
                                        )
                                        uploadErrors.append("Invalid video \(index + 1)")
                                        continue
                                    }

                                    let thumbnailResized = thumbnail.resized(toMaxDimension: 1920)
                                    guard let thumbnailData = thumbnailResized.compressed(toMaxBytes: 500_000) else {
                                        print("🔴 [GALLERY UPLOAD] Failed to compress thumbnail \(index + 1)")
                                        UploadProgressManager.shared.failTask(
                                            batchId: batchId,
                                            taskIndex: index,
                                            error: "Thumbnail compression failed"
                                        )
                                        uploadErrors.append("Failed to create thumbnail \(index + 1)")
                                        continue
                                    }

                                    UploadProgressManager.shared.updateTaskProgress(
                                        batchId: batchId,
                                        taskIndex: index,
                                        progress: 0.3
                                    )

                                    // Wait for video processing (may have already completed in parallel)
                                    let processedVideo: VideoCompressor.ProcessedVideo
                                    do {
                                        processedVideo = try await processTask
                                    } catch {
                                        print("🔴 [GALLERY UPLOAD] Failed to process video \(index + 1): \(error)")
                                        UploadProgressManager.shared.failTask(
                                            batchId: batchId,
                                            taskIndex: index,
                                            error: "Video processing failed: \(error.localizedDescription)"
                                        )
                                        uploadErrors.append("Failed to process video \(index + 1)")
                                        continue
                                    }

                                    // Ensure cleanup of temp file after upload
                                    defer {
                                        if processedVideo.needsCleanup {
                                            try? FileManager.default.removeItem(at: processedVideo.fileURL)
                                        }
                                    }

                                    // Get video creation date (already running in parallel)
                                    let videoCapturedAt = await metadataTask
                                    if let date = videoCapturedAt {
                                        print("🎬 [GALLERY UPLOAD] Video \(index + 1) captured at: \(date)")
                                    } else {
                                        print("🎬 [GALLERY UPLOAD] Video \(index + 1) has no capture date metadata")
                                    }

                                    print("🎬 [GALLERY UPLOAD] Video \(index + 1) ready, duration: \(String(format: "%.1f", processedVideo.duration))s")

                                    UploadProgressManager.shared.updateTaskProgress(
                                        batchId: batchId,
                                        taskIndex: index,
                                        progress: 0.5
                                    )

                                    // Check for task cancellation before upload
                                    if Task.isCancelled {
                                        print("⚠️ [GALLERY UPLOAD] Task cancelled, queuing video \(index + 1) for background upload")
                                        OfflineManager.shared.queueVideoUpload(
                                            videoURL: processedVideo.fileURL,
                                            thumbnailData: thumbnailData,
                                            duration: processedVideo.duration,
                                            capturedAt: videoCapturedAt,
                                            eventId: nil,
                                            folderId: nil
                                        )
                                        uploadErrors.append("Video \(index + 1) queued for background")
                                        continue
                                    }

                                    // Upload video using file streaming (faster than loading into memory)
                                    print("🎬 [GALLERY UPLOAD] Uploading video \(index + 1)...")
                                    do {
                                        try await viewModel.uploadVideoFromFile(
                                            videoURL: processedVideo.fileURL,
                                            thumbnailData: thumbnailData,
                                            duration: processedVideo.duration,
                                            capturedAt: videoCapturedAt
                                        )

                                        UploadProgressManager.shared.completeTask(batchId: batchId, taskIndex: index)
                                        successCount += 1
                                        print("🟢 [GALLERY UPLOAD] Uploaded video \(index + 1) successfully")
                                    } catch {
                                        print("🔴 [GALLERY UPLOAD] Failed to upload video \(index + 1): \(error)")
                                        UploadProgressManager.shared.failTask(
                                            batchId: batchId,
                                            taskIndex: index,
                                            error: "Upload failed: \(error.localizedDescription)"
                                        )

                                        // Queue for background retry
                                        OfflineManager.shared.queueVideoUpload(
                                            videoURL: processedVideo.fileURL,
                                            thumbnailData: thumbnailData,
                                            duration: processedVideo.duration,
                                            capturedAt: videoCapturedAt,
                                            eventId: nil,
                                            folderId: nil
                                        )
                                        print("📹 [GALLERY UPLOAD] Queued video \(index + 1) for background retry")
                                        uploadErrors.append("Video \(index + 1) queued for retry")
                                    }

                                } else {
                                    // MARK: - Photo Upload Flow
                                    print("📸 [GALLERY UPLOAD] Processing image \(index + 1)/\(newItems.count)...")

                                    // Load image data
                                    guard let data = try await item.loadTransferable(type: Data.self),
                                          let uiImage = UIImage(data: data) else {
                                        print("🔴 [GALLERY UPLOAD] Failed to load image \(index + 1)")
                                        UploadProgressManager.shared.failTask(
                                            batchId: batchId,
                                            taskIndex: index,
                                            error: "Failed to load image"
                                        )
                                        uploadErrors.append("Failed to load image \(index + 1)")
                                        continue
                                    }

                                    let capturedAt = extractCaptureDate(from: data)

                                    UploadProgressManager.shared.updateTaskProgress(
                                        batchId: batchId,
                                        taskIndex: index,
                                        progress: 0.3
                                    )

                                    // Resize and compress
                                    let resized = uiImage.resized(toMaxDimension: 1920)
                                    guard let compressedData = resized.compressed(toMaxBytes: 1_000_000) else {
                                        print("🔴 [GALLERY UPLOAD] Failed to compress image \(index + 1)")
                                        UploadProgressManager.shared.failTask(
                                            batchId: batchId,
                                            taskIndex: index,
                                            error: "Compression failed"
                                        )
                                        uploadErrors.append("Failed to compress image \(index + 1)")
                                        continue
                                    }

                                    print("📸 [GALLERY UPLOAD] Compressed image \(index + 1): \(compressedData.count) bytes")

                                    UploadProgressManager.shared.updateTaskProgress(
                                        batchId: batchId,
                                        taskIndex: index,
                                        progress: 0.5
                                    )

                                    // Upload immediately
                                    print("📸 [GALLERY UPLOAD] Uploading image \(index + 1)...")
                                    try await viewModel.uploadPhoto(imageData: compressedData, capturedAt: capturedAt)

                                    UploadProgressManager.shared.completeTask(batchId: batchId, taskIndex: index)
                                    successCount += 1
                                    print("🟢 [GALLERY UPLOAD] Uploaded image \(index + 1) successfully")
                                }

                                // Update UI on main thread
                                await MainActor.run {
                                    uploadedCount = successCount
                                    uploadProgress = Double(successCount) / Double(newItems.count)
                                }

                            } catch let uploadError {
                                print("🔴 [GALLERY UPLOAD] Failed item \(index + 1): \(uploadError)")
                                UploadProgressManager.shared.failTask(
                                    batchId: batchId,
                                    taskIndex: index,
                                    error: uploadError.localizedDescription
                                )
                                uploadErrors.append("Item \(index + 1) failed")
                            }
                        }

                        // End background task protection
                        UploadProgressManager.shared.completeBackgroundProtectedBatch(backgroundTaskId)
                        print("📸 [GALLERY UPLOAD] Completed. Success: \(successCount), Errors: \(uploadErrors.count)")

                        // Update UI on main thread
                        await MainActor.run {
                            if !uploadErrors.isEmpty {
                                errorMessage = "Uploaded \(successCount) of \(newItems.count) items.\n\(uploadErrors.count) failed."
                                showError = true
                            }

                            // Send push notification for uploaded items
                            if successCount > 0 {
                                NotificationManager.shared.notifyPhotosAdded(count: successCount, location: "gallery", eventId: nil)
                            }

                            isUploading = false
                            uploadProgress = 0.0
                            uploadedCount = 0
                            totalUploadCount = 0
                            selectedItems = []
                        }
                    }
                }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Saved!", isPresented: $showingSaveSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("\(savedPhotoCount) photo\(savedPhotoCount == 1 ? "" : "s") saved to your library")
            }
            .alert("Error", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
            .fullScreenCover(item: $selectedPhotoIndex) { photoIndex in
                // Use unified media viewer for both photos and videos with swipe navigation
                if photoIndex.value < photosInDisplayOrder.count {
                    FullScreenMediaViewer(
                        mediaItems: photosInDisplayOrder,
                        initialIndex: photoIndex.value,
                        onDismiss: { selectedPhotoIndex = nil },
                        onDelete: { mediaToDelete in
                            Task {
                                try? await viewModel.deletePhoto(mediaToDelete)
                            }
                        },
                        onToggleFavorite: { mediaToToggle in
                            if let photoId = mediaToToggle.id {
                                let newFavoriteState = !(mediaToToggle.isFavorite ?? false)

                                // If we're in the Favorites folder and unfavoriting,
                                // dismiss the viewer to avoid index out of range crash
                                if currentFolderView == .favorites && !newFavoriteState {
                                    selectedPhotoIndex = nil
                                }

                                Task {
                                    try? await FirebaseManager.shared.togglePhotoFavorite(photoId, isFavorite: newFavoriteState)
                                }
                            }
                        }
                    )
                }
            }
            }
        }
        .alert("Create Folder", isPresented: $showingCreateFolder) {
            TextField("Folder Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
            Button("Create") {
                Task {
                    do {
                        _ = try await viewModel.createFolder(name: newFolderName, type: .custom)
                        newFolderName = ""
                    } catch {
                        errorMessage = "Failed to create folder: \(error.localizedDescription)"
                        showError = true
                    }
                }
            }
        } message: {
            Text("Enter a name for your new folder")
        }
        .sheet(isPresented: $showingDateFilter) {
            DateFilterSheet(
                startDate: $filterStartDate,
                endDate: $filterEndDate,
                onApply: { showingDateFilter = false }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingMoveToFolder) {
            MoveToFolderSheet(
                folders: viewModel.folders.filter { $0.type == .custom },
                onSelectFolder: { folderId in
                    moveSelectedPhotosToFolder(folderId)
                    showingMoveToFolder = false
                },
                onRemoveFromFolder: {
                    moveSelectedPhotosToFolder(nil)
                    showingMoveToFolder = false
                },
                onCreateFolder: {
                    showingMoveToFolder = false
                    showingCreateFolder = true
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingAddToEvent) {
            AddToEventSheet(
                events: viewModel.allEvents,
                onSelectEvent: { eventId in
                    assignSelectedPhotosToEvent(eventId)
                    showingAddToEvent = false
                },
                onRemoveFromEvent: {
                    assignSelectedPhotosToEvent(nil)
                    showingAddToEvent = false
                }
            )
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            updatePhotosCache()
            // Initialize prefetch manager with all photo URLs for smart prefetching
            let photoURLs = photosInDisplayOrder.map { $0.imageURL }
            PhotoPrefetchManager.shared.setPhotoURLs(photoURLs)

            // Dismiss initial load state after a short delay if photos exist
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !viewModel.photos.isEmpty {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isInitialLoad = false
                    }
                }
            }
        }
        .onDisappear {
            // Reset prefetch manager when leaving gallery
            PhotoPrefetchManager.shared.reset()
        }
        .onChange(of: viewModel.photos.count) { oldCount, newCount in
            updatePhotosCache()
            // Update prefetch manager when photos change
            let photoURLs = photosInDisplayOrder.map { $0.imageURL }
            PhotoPrefetchManager.shared.setPhotoURLs(photoURLs)

            // Dismiss initial load state when photos arrive
            if newCount > 0 && isInitialLoad {
                withAnimation(.easeOut(duration: 0.3)) {
                    isInitialLoad = false
                }
            }
        }
        .onChange(of: sortOption) { _, _ in
            updatePhotosCache()
        }
        .onChange(of: filterStartDate) { _, _ in
            updatePhotosCache()
        }
        .onChange(of: filterEndDate) { _, _ in
            updatePhotosCache()
        }
        .onChange(of: currentFolderView) { _, _ in
            updatePhotosCache()
            // Animate folder transition
            withAnimation(.easeInOut(duration: 0.25)) {
                folderTransitionId = UUID()
            }
        }
        .onChange(of: selectionMode) { _, newValue in
            // Haptic feedback when entering/exiting selection mode
            if newValue {
                HapticManager.medium()
            } else {
                HapticManager.light()
            }
        }
        .onChange(of: resetTrigger) { _, _ in
            // Smart tab tap behavior:
            // - If viewing folder list (events/specialEvents), go back to All Photos
            // - If viewing any photo grid, scroll to top
            if currentFolderView == .events || currentFolderView == .specialEvents {
                withAnimation {
                    currentFolderView = .allPhotos
                    folderNavStack.removeAll()
                }
            } else {
                // In a photo grid - trigger scroll to top
                scrollToTopTrigger += 1
            }
        }
    }

    private func saveSelectedPhotos() {
        guard !selectedPhotoIds.isEmpty else { return }

        Task {
            var savedCount = 0
            var errorOccurred = false

            let selectedPhotos = photosInDisplayOrder.filter { selectedPhotoIds.contains($0.id ?? "") }

            for photo in selectedPhotos {
                // Load image - try cache first, then async download
                var imageToSave: UIImage?

                if let cachedImage = ImageCache.shared.get(forKey: photo.imageURL) {
                    imageToSave = cachedImage
                } else if let url = URL(string: photo.imageURL) {
                    // Use async URLSession instead of blocking Data(contentsOf:)
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let image = UIImage(data: data) {
                            ImageCache.shared.set(image, forKey: photo.imageURL)
                            imageToSave = image
                        }
                    } catch {
                        print("Failed to download image for saving: \(error)")
                    }
                }

                if let image = imageToSave {
                    // Use continuation to bridge callback-based API to async/await
                    await withCheckedContinuation { continuation in
                        let imageSaver = ImageSaver()
                        imageSaver.successHandler = {
                            savedCount += 1
                            continuation.resume()
                        }
                        imageSaver.errorHandler = { error in
                            if !errorOccurred {
                                errorOccurred = true
                                Task { @MainActor in
                                    saveErrorMessage = "Failed to save some photos: \(error.localizedDescription)"
                                    showingSaveError = true
                                }
                            }
                            continuation.resume()
                        }
                        imageSaver.writeToPhotoAlbum(image: image)
                    }
                }
            }

            // Show success after all photos are processed
            await MainActor.run {
                if savedCount > 0 && !errorOccurred {
                    savedPhotoCount = savedCount
                    showingSaveSuccess = true
                    HapticManager.success()
                }
                selectionMode = false
                selectedPhotoIds.removeAll()
            }
        }
    }

    private func deleteSelectedPhotos() {
        guard !selectedPhotoIds.isEmpty else { return }

        Task {
            let selectedPhotos = photosInDisplayOrder.filter { selectedPhotoIds.contains($0.id ?? "") }

            for photo in selectedPhotos {
                try? await viewModel.deletePhoto(photo)
            }

            await MainActor.run {
                selectionMode = false
                selectedPhotoIds.removeAll()
            }
        }
    }

    private func toggleFavoritesForSelected() {
        guard !selectedPhotoIds.isEmpty else { return }

        Task {
            let selectedPhotos = photosInDisplayOrder.filter { selectedPhotoIds.contains($0.id ?? "") }
            let photoIds = selectedPhotos.compactMap { $0.id }

            // Check if all selected photos are already favorited
            let allFavorited = selectedPhotos.allSatisfy { $0.isFavorite == true }

            // If all are favorited, unfavorite them; otherwise favorite them
            let newFavoriteState = !allFavorited

            try? await viewModel.batchToggleFavorites(photoIds, isFavorite: newFavoriteState) { current, total in
                // Could show progress here if needed
            }

            await MainActor.run {
                HapticManager.success()
                selectionMode = false
                selectedPhotoIds.removeAll()
            }
        }
    }

    private func moveSelectedPhotosToFolder(_ folderId: String?) {
        guard !selectedPhotoIds.isEmpty else { return }

        Task {
            let selectedPhotos = photosInDisplayOrder.filter { selectedPhotoIds.contains($0.id ?? "") }
            let photoIds = selectedPhotos.compactMap { $0.id }

            try? await viewModel.movePhotosToFolder(photoIds, folderId: folderId) { current, total in
                // Could show progress here if needed
            }

            await MainActor.run {
                HapticManager.success()
                selectionMode = false
                selectedPhotoIds.removeAll()
            }
        }
    }

    private func assignSelectedPhotosToEvent(_ eventId: String?) {
        guard !selectedPhotoIds.isEmpty else { return }

        Task {
            // Get both photo IDs and URLs for the selected photos
            let selectedPhotos = photosInDisplayOrder.filter { selectedPhotoIds.contains($0.id ?? "") }
            let photoIds = selectedPhotos.compactMap { $0.id }
            let photoURLs = selectedPhotos.map { $0.imageURL }

            // Update the photos' eventId
            try? await viewModel.assignPhotosToEvent(photoIds, eventId: eventId) { current, total in
                // Could show progress here if needed
            }

            // Also update the event's photoURLs array
            if let eventId = eventId {
                // Adding photos to an event - append to event's photoURLs
                if let event = viewModel.events.first(where: { $0.id == eventId }) {
                    var updatedEvent = event
                    // Add new URLs that aren't already in the event
                    let newURLs = photoURLs.filter { !updatedEvent.photoURLs.contains($0) }
                    updatedEvent.photoURLs.append(contentsOf: newURLs)
                    try? await FirebaseManager.shared.updateCalendarEvent(updatedEvent)
                    print("📸 [ASSIGN TO EVENT] Added \(newURLs.count) photos to event '\(event.title)'")
                }
            } else {
                // Removing photos from events - remove from each photo's previous event
                for photo in selectedPhotos {
                    if let previousEventId = photo.eventId,
                       let previousEvent = viewModel.events.first(where: { $0.id == previousEventId }) {
                        var updatedEvent = previousEvent
                        updatedEvent.photoURLs.removeAll { $0 == photo.imageURL }
                        try? await FirebaseManager.shared.updateCalendarEvent(updatedEvent)
                        print("📸 [REMOVE FROM EVENT] Removed photo from event '\(previousEvent.title)'")
                    }
                }
            }

            await MainActor.run {
                HapticManager.success()
                selectionMode = false
                selectedPhotoIds.removeAll()
            }
        }
    }
}

struct PhotoDetailView: View {
    let photo: Photo
    let onDelete: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var showingDeleteAlert = false
    @State private var showingShareSheet = false
    @State private var showingSaveSuccess = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                CachedAsyncImage(url: URL(string: photo.imageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .onAppear {
                            // Convert to UIImage for saving/sharing
                            if let uiImage = ImageCache.shared.get(forKey: photo.imageURL) {
                                loadedImage = uiImage
                            }
                        }
                } placeholder: {
                    ProgressView()
                }

                if !photo.caption.isEmpty {
                    Text(photo.caption)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        .padding()
                }

                HStack(spacing: 20) {
                    // Save to Photos button
                    Button(action: saveToPhotoLibrary) {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                    }

                    // Share button
                    Button(action: { showingShareSheet = true }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                .padding(.top, 8)

                Text("Added by \(photo.uploadedBy)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    .padding(.top, 4)

                Text(photo.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .alert("Delete Photo?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("This photo will be removed for both of you.")
        }
        .alert("Saved!", isPresented: $showingSaveSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Photo saved to your photo library")
        }
        .alert("Error", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = loadedImage {
                ShareSheet(items: [image])
            }
        }
    }

    private func saveToPhotoLibrary() {
        guard let image = loadedImage else {
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

struct PhotoGridCell: View {
    let photo: Photo
    let index: Int
    let selectionMode: Bool
    let isSelected: Bool
    let columnCount: Int
    let onTap: () -> Void
    let onLongPress: () -> Void

    // Animation states
    @State private var isPressed = false
    @State private var hasAppeared = false
    @State private var checkmarkScale: CGFloat = 0.5

    // Calculate size based on column count
    private var cellSize: CGFloat {
        let spacing: CGFloat = 8 * CGFloat(columnCount - 1) // spacing between cells
        let padding: CGFloat = 16 // horizontal padding
        return (UIScreen.main.bounds.width - padding - spacing) / CGFloat(columnCount)
    }

    private var cornerRadius: CGFloat {
        columnCount == 2 ? 16 : (columnCount == 3 ? 12 : 8)
    }

    // Staggered animation delay based on index
    private var appearDelay: Double {
        Double(index % 12) * 0.03
    }

    // Format video duration
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CachedAsyncImage(url: URL(string: photo.imageURL), thumbnailSize: cellSize) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(
                        // Inner shadow/vignette for depth
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.15),
                                        Color.clear,
                                        Color.clear,
                                        Color.black.opacity(0.08)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.5
                            )
                            .blendMode(.multiply)
                    )
            } placeholder: {
                // Shimmer loading placeholder
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.92, green: 0.90, blue: 0.96),
                                Color(red: 0.88, green: 0.86, blue: 0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shimmer()
            }
            .frame(width: cellSize, height: cellSize)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Color.black.opacity(0.12), radius: columnCount == 2 ? 6 : 3, x: 0, y: 2)
            // Pre-cache video when cell appears
            .onAppear {
                if photo.isVideo, let videoURLString = photo.videoURL, let videoURL = URL(string: videoURLString) {
                    // Check if not already cached, then start background caching
                    if VideoCache.shared.getCachedVideoURL(for: videoURLString) == nil {
                        Task.detached(priority: .background) {
                            _ = await VideoCache.shared.downloadAndCache(from: videoURL)
                        }
                    }
                }
            }
            // Video overlay - play button and gradient
            .overlay(
                Group {
                    if photo.isVideo {
                        ZStack {
                            // Bottom gradient for duration visibility
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(0.5)
                                ],
                                startPoint: .center,
                                endPoint: .bottom
                            )

                            // Play button in center
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: columnCount == 2 ? 48 : 36, height: columnCount == 2 ? 48 : 36)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(columnCount == 2 ? .title3 : .caption)
                                        .foregroundColor(.white)
                                        .offset(x: 2) // Optical centering
                                )
                                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)

                            // Duration badge (bottom left)
                            if let duration = photo.duration, duration > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: columnCount == 2 ? 9 : 7, weight: .semibold))
                                    Text(formatDuration(duration))
                                        .font(.system(size: columnCount == 2 ? 11 : 9, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, columnCount == 2 ? 8 : 6)
                                .padding(.vertical, columnCount == 2 ? 4 : 3)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.6))
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                .padding(columnCount == 2 ? 8 : 6)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    }
                }
            )
            // Selection overlay wash
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(selectionMode && isSelected ? 0.15 : 0))
            )
            // Selection border
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        selectionMode && isSelected ? Color(red: 0.7, green: 0.5, blue: 0.95) : Color.clear,
                        lineWidth: 3
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            // Press animation
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .brightness(isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            // Staggered fade-in animation
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.9)
            .onTapGesture {
                HapticManager.light()
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isPressed = pressing
                }
            }, perform: {
                HapticManager.medium()
                onLongPress()
            })

            // Favorite indicator (bottom right) with animation - only for photos or when no duration badge
            if photo.isFavorite == true && !selectionMode && !photo.isVideo {
                Image(systemName: "heart.fill")
                    .font(columnCount == 2 ? .body : .caption)
                    .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.5))
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .padding(columnCount == 2 ? 10 : 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.scale.combined(with: .opacity))
            }

            // For videos, show favorite heart in top left if favorited
            if photo.isFavorite == true && !selectionMode && photo.isVideo {
                Image(systemName: "heart.fill")
                    .font(columnCount == 2 ? .body : .caption)
                    .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.5))
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .padding(columnCount == 2 ? 10 : 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.scale.combined(with: .opacity))
            }

            // Checkmark overlay
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(columnCount == 2 ? .title : .title2)
                    .foregroundStyle(
                        isSelected ?
                            AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.8, green: 0.6, blue: 1.0),
                                        Color(red: 0.6, green: 0.4, blue: 0.85)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            ) :
                            AnyShapeStyle(Color.white.opacity(0.9))
                    )
                    .background(
                        Circle()
                            .fill(isSelected ? Color.clear : Color.black.opacity(0.3))
                            .frame(width: columnCount == 2 ? 28 : 24, height: columnCount == 2 ? 28 : 24)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 1)
                    .padding(columnCount == 2 ? 10 : 8)
                    .allowsHitTesting(false)
            }
        }
        .drawingGroup() // Optimize rendering performance
        .onAppear {
            // Notify prefetch manager that this photo is visible for smart prefetching
            PhotoPrefetchManager.shared.photoDidAppear(at: index)

            // Staggered fade-in animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(appearDelay)) {
                hasAppeared = true
            }
        }
    }
}

struct FolderCard: View {
    let title: String
    let icon: String
    let count: Int
    let color: Color
    let action: () -> Void
    var thumbnailURLs: [String] = [] // Optional thumbnail URLs for preview grid

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            HapticManager.light()
            action()
        }) {
            HStack(spacing: 16) {
                // Thumbnail preview grid or icon
                ZStack {
                    if thumbnailURLs.isEmpty {
                        // Fallback to icon
                        RoundedRectangle(cornerRadius: 12)
                            .fill(color.opacity(0.15))
                            .frame(width: 70, height: 70)

                        Image(systemName: icon)
                            .font(.system(size: 28))
                            .foregroundColor(color)
                    } else {
                        // 2x2 thumbnail grid
                        FolderThumbnailGrid(
                            thumbnailURLs: thumbnailURLs,
                            color: color
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(Color(red: 0.25, green: 0.15, blue: 0.45))
                    Text("\(count) photo\(count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body.weight(.medium))
                    .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.8))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(color.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal)
        }
        .buttonStyle(FolderCardButtonStyle())
    }
}

// MARK: - Folder Thumbnail Grid (2x2 preview)
struct FolderThumbnailGrid: View {
    let thumbnailURLs: [String]
    let color: Color

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.08))
                .frame(width: 70, height: 70)

            // 2x2 grid of thumbnails
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    thumbnailCell(index: 0)
                    thumbnailCell(index: 1)
                }
                HStack(spacing: 2) {
                    thumbnailCell(index: 2)
                    thumbnailCell(index: 3)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func thumbnailCell(index: Int) -> some View {
        if index < thumbnailURLs.count {
            CachedAsyncImage(url: URL(string: thumbnailURLs[index]), thumbnailSize: 32) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(color.opacity(0.15))
                    .shimmer()
            }
            .frame(width: 30, height: 30)
            .clipped()
        } else {
            Rectangle()
                .fill(color.opacity(0.1))
                .frame(width: 30, height: 30)
        }
    }
}

// MARK: - Folder Card Button Style
struct FolderCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

class PhotoGalleryViewModel: ObservableObject {
    // Use shared data store instead of duplicate listeners
    private let sharedStore = SharedDataStore.shared

    @Published var photos: [Photo] = []
    @Published var folders: [PhotoFolder] = []
    @Published var events: [CalendarEvent] = []

    private let firebaseManager = FirebaseManager.shared

    init() {
        // Subscribe to shared store changes - no duplicate Firestore listeners
        sharedStore.$photos
            .assign(to: &$photos)
        sharedStore.$folders
            .assign(to: &$folders)
        sharedStore.$events
            .assign(to: &$events)
    }

    func uploadPhoto(imageData: Data, capturedAt: Date? = nil, eventId: String? = nil, folderId: String? = nil) async throws {
        _ = try await firebaseManager.uploadPhoto(
            imageData: imageData,
            caption: "",
            uploadedBy: UserIdentityManager.shared.currentUserName,
            capturedAt: capturedAt,
            eventId: eventId,
            folderId: folderId
        )
    }

    func uploadVideo(videoData: Data, thumbnailData: Data, duration: TimeInterval, capturedAt: Date? = nil, eventId: String? = nil, folderId: String? = nil) async throws {
        _ = try await firebaseManager.uploadVideo(
            videoData: videoData,
            thumbnailData: thumbnailData,
            duration: duration,
            caption: "",
            uploadedBy: UserIdentityManager.shared.currentUserName,
            capturedAt: capturedAt,
            eventId: eventId,
            folderId: folderId
        )
    }

    /// Optimized video upload using file streaming
    func uploadVideoFromFile(videoURL: URL, thumbnailData: Data, duration: TimeInterval, capturedAt: Date? = nil, eventId: String? = nil, folderId: String? = nil) async throws {
        _ = try await firebaseManager.uploadVideoFromFile(
            videoURL: videoURL,
            thumbnailData: thumbnailData,
            duration: duration,
            caption: "",
            uploadedBy: UserIdentityManager.shared.currentUserName,
            capturedAt: capturedAt,
            eventId: eventId,
            folderId: folderId
        )
    }

    func deletePhoto(_ photo: Photo) async throws {
        try await firebaseManager.deletePhoto(photo)
    }

    func createFolder(name: String, type: PhotoFolder.FolderType) async throws -> String {
        return try await firebaseManager.createFolder(name: name, type: type)
    }

    func deleteFolder(_ folder: PhotoFolder) async throws {
        try await firebaseManager.deleteFolder(folder)
    }

    // Get photos for a specific folder
    func photos(for folderType: FolderViewType) -> [Photo] {
        switch folderType {
        case .allPhotos:
            return photos
        case .favorites:
            return photos.filter { $0.isFavorite == true }
        case .events:
            return photos.filter { $0.eventId != nil }
        case .specialEvents:
            return photos.filter { photo in
                guard let eventId = photo.eventId else { return false }
                return events.first(where: { $0.id == eventId })?.isSpecial == true
            }
        case .event(let eventId):
            return photos.filter { $0.eventId == eventId }
        case .custom(let folderId):
            return photos.filter { $0.folderId == folderId }
        }
    }

    // Get event folders (auto-created from calendar events with photos)
    func eventFolders(specialOnly: Bool = false) -> [(event: CalendarEvent, photoCount: Int)] {
        let relevantEvents = events.filter { event in
            guard let eventId = event.id else { return false }
            let hasPhotos = photos.contains(where: { $0.eventId == eventId })
            // If specialOnly is true, only show special events
            // If specialOnly is false, only show non-special events (to avoid duplication)
            return hasPhotos && (specialOnly ? event.isSpecial : !event.isSpecial)
        }

        // Sort by date (latest/newest first)
        let sortedEvents = relevantEvents.sorted { $0.date > $1.date }

        return sortedEvents.map { event in
            let count = photos.filter { $0.eventId == event.id }.count
            return (event: event, photoCount: count)
        }
    }

    // MARK: - Favorites
    var favoritesCount: Int {
        photos.filter { $0.isFavorite == true }.count
    }

    func toggleFavorite(_ photo: Photo) async throws {
        guard let photoId = photo.id else { return }
        let newFavoriteState = !(photo.isFavorite ?? false)
        try await firebaseManager.togglePhotoFavorite(photoId, isFavorite: newFavoriteState)
    }

    func batchToggleFavorites(_ photoIds: [String], isFavorite: Bool, progressHandler: ((Int, Int) -> Void)? = nil) async throws {
        try await firebaseManager.batchToggleFavorites(photoIds, isFavorite: isFavorite, progressHandler: progressHandler)
    }

    // MARK: - Move to Folder
    func movePhotosToFolder(_ photoIds: [String], folderId: String?, progressHandler: ((Int, Int) -> Void)? = nil) async throws {
        try await firebaseManager.batchUpdatePhotoFolders(photoIds, folderId: folderId, progressHandler: progressHandler)
    }

    // MARK: - Add to Event
    func assignPhotosToEvent(_ photoIds: [String], eventId: String?, progressHandler: ((Int, Int) -> Void)? = nil) async throws {
        try await firebaseManager.batchUpdatePhotoEvents(photoIds, eventId: eventId, progressHandler: progressHandler)
    }

    // Get all events (not just those with photos) sorted by date descending
    var allEvents: [CalendarEvent] {
        events.sorted { $0.date > $1.date }
    }

    // MARK: - Batch Delete
    func batchDeletePhotos(_ photos: [Photo], progressHandler: ((Int, Int) -> Void)? = nil) async throws {
        try await firebaseManager.batchDeletePhotos(photos, progressHandler: progressHandler)
    }
}

// Folder view types for navigation
enum FolderViewType: Hashable {
    case allPhotos
    case favorites // Favorited photos
    case events // Parent category
    case specialEvents // Parent category
    case event(String) // Specific event folder
    case custom(String) // Custom folder
}

// MARK: - Date Filter Sheet
struct DateFilterSheet: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    let onApply: () -> Void
    @Environment(\.dismiss) var dismiss

    @State private var tempStartDate: Date = Date()
    @State private var tempEndDate: Date = Date()
    @State private var useStartDate: Bool = false
    @State private var useEndDate: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Start Date
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $useStartDate) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                            Text("From Date")
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                        }
                    }
                    .tint(Color(red: 0.6, green: 0.4, blue: 0.85))

                    if useStartDate {
                        DatePicker("Start", selection: $tempStartDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.95, green: 0.93, blue: 0.98))
                )

                // End Date
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $useEndDate) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                            Text("To Date")
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                        }
                    }
                    .tint(Color(red: 0.6, green: 0.4, blue: 0.85))

                    if useEndDate {
                        DatePicker("End", selection: $tempEndDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.95, green: 0.93, blue: 0.98))
                )

                Spacer()

                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        startDate = useStartDate ? tempStartDate : nil
                        endDate = useEndDate ? tempEndDate : nil
                        onApply()
                    }) {
                        Text("Apply Filter")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.6, green: 0.4, blue: 0.85),
                                        Color(red: 0.5, green: 0.3, blue: 0.75)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                    }

                    if startDate != nil || endDate != nil {
                        Button(action: {
                            startDate = nil
                            endDate = nil
                            useStartDate = false
                            useEndDate = false
                            onApply()
                        }) {
                            Text("Clear Filter")
                                .fontWeight(.medium)
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Filter by Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
            }
            .onAppear {
                if let start = startDate {
                    tempStartDate = start
                    useStartDate = true
                }
                if let end = endDate {
                    tempEndDate = end
                    useEndDate = true
                }
            }
        }
    }
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Move to Folder Sheet
struct MoveToFolderSheet: View {
    let folders: [PhotoFolder]
    let onSelectFolder: (String) -> Void
    let onRemoveFromFolder: () -> Void
    let onCreateFolder: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Remove from folder option
                    Button(action: onRemoveFromFolder) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 50, height: 50)
                                Image(systemName: "folder.badge.minus")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            }

                            Text("Remove from Folder")
                                .fontWeight(.medium)
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                        )
                    }

                    if !folders.isEmpty {
                        Divider()
                            .padding(.vertical, 8)

                        Text("Move to Folder")
                            .font(.headline)
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(folders, id: \.id) { folder in
                            Button(action: {
                                if let folderId = folder.id {
                                    onSelectFolder(folderId)
                                }
                            }) {
                                HStack(spacing: 16) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.15))
                                            .frame(width: 50, height: 50)
                                        Image(systemName: "folder.fill")
                                            .font(.title2)
                                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                                    }

                                    Text(folder.name)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                                )
                            }
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // Create new folder
                    Button(action: onCreateFolder) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.9, green: 0.85, blue: 1.0))
                                    .frame(width: 50, height: 50)
                                Image(systemName: "folder.badge.plus")
                                    .font(.title2)
                                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                            }

                            Text("Create New Folder")
                                .fontWeight(.semibold)
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))

                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color(red: 0.6, green: 0.4, blue: 0.85), lineWidth: 2)
                        )
                    }
                }
                .padding()
            }
            .background(Color(red: 0.96, green: 0.94, blue: 0.98).ignoresSafeArea())
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - Add to Event Sheet
struct AddToEventSheet: View {
    let events: [CalendarEvent]
    let onSelectEvent: (String) -> Void
    let onRemoveFromEvent: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""

    private var filteredEvents: [CalendarEvent] {
        if searchText.isEmpty {
            return events
        }
        return events.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                        TextField("", text: $searchText, prompt: Text("Search events...").foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7)))
                            .textFieldStyle(.plain)
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                    )

                    // Remove from event option
                    Button(action: onRemoveFromEvent) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 50, height: 50)
                                Image(systemName: "calendar.badge.minus")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            }

                            Text("Remove from Event")
                                .fontWeight(.medium)
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                        )
                    }

                    if !filteredEvents.isEmpty {
                        Divider()
                            .padding(.vertical, 8)

                        Text("Add to Event")
                            .font(.headline)
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(filteredEvents, id: \.id) { event in
                            Button(action: {
                                if let eventId = event.id {
                                    onSelectEvent(eventId)
                                }
                            }) {
                                HStack(spacing: 16) {
                                    ZStack {
                                        Circle()
                                            .fill(event.isSpecial ?
                                                Color(red: 0.9, green: 0.4, blue: 0.6).opacity(0.15) :
                                                Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.15))
                                            .frame(width: 50, height: 50)
                                        Image(systemName: event.isSpecial ? "star.fill" : "calendar")
                                            .font(.title2)
                                            .foregroundColor(event.isSpecial ?
                                                Color(red: 0.9, green: 0.4, blue: 0.6) :
                                                Color(red: 0.6, green: 0.4, blue: 0.85))
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title)
                                            .fontWeight(.medium)
                                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                                            .lineLimit(1)

                                        Text(dateFormatter.string(from: event.date))
                                            .font(.caption)
                                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                                )
                            }
                        }
                    } else if events.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 50))
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.5))

                            Text("No Events")
                                .font(.headline)
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                            Text("Create events in the Calendar tab to add photos to them")
                                .font(.subheadline)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 40)
                    } else if filteredEvents.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.5))

                            Text("No matching events")
                                .font(.subheadline)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                        }
                        .padding(.vertical, 30)
                    }
                }
                .padding()
            }
            .background(Color(red: 0.96, green: 0.94, blue: 0.98).ignoresSafeArea())
            .navigationTitle("Add to Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    PhotoGalleryView(resetTrigger: .constant(0))
}
