import SwiftUI
import PhotosUI
import ImageIO

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
    @StateObject private var viewModel = PhotoGalleryViewModel()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingAddPhoto = false
    @State private var isUploading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedPhotoIndex: PhotoIndex?
    @State private var selectionMode = false
    @State private var selectedPhotoIndices: Set<Int> = []
    @State private var showingSaveSuccess = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var savedPhotoCount = 0
    @State private var showingExpandedHeader = false
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
    @State private var uploadProgress: Double = 0.0
    @State private var uploadedCount: Int = 0
    @State private var totalUploadCount: Int = 0
    @State private var showingBatchProgress = false
    @State private var batchProgress: Double = 0.0
    @State private var batchOperationMessage = ""

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

    // Group photos by month/year (using original capture date from metadata)
    private var photosByMonth: [(key: String, photos: [Photo])] {
        let grouped = Dictionary(grouping: filteredPhotos) { photo -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            // Use capturedAt if available, otherwise fall back to createdAt
            let dateToUse = photo.capturedAt ?? photo.createdAt
            return formatter.string(from: dateToUse)
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
                    let date1 = photo1.capturedAt ?? photo1.createdAt
                    let date2 = photo2.capturedAt ?? photo2.createdAt
                    return date1 > date2
                case .oldestFirst:
                    let date1 = photo1.capturedAt ?? photo1.createdAt
                    let date2 = photo2.capturedAt ?? photo2.createdAt
                    return date1 < date2
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

    // Flat array of photos in display order (newest first)
    private var photosInDisplayOrder: [Photo] {
        photosByMonth.flatMap { $0.photos }
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
        ScrollView {
            VStack(spacing: 0) {
                // Expandable header (hidden when collapsed)
                expandableHeader
                    .padding(.horizontal)
                    .padding(.top, 4)

                // Folder navigation bar
                folderNavigationBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Upload progress bar
                if isUploading {
                    uploadProgressBar
                        .padding(.horizontal)
                        .padding(.top, 8)
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
                } else {
                    photoGridView
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
            // Auto-hide header when scrolling down - minimal threshold for instant dismissal
            if showingExpandedHeader && newValue > 1 {
                withAnimation(.spring(response: 0.3)) {
                    showingExpandedHeader = false
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 0)
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

    // MARK: - Upload Progress Bar
    private var uploadProgressBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Uploading photos...")
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                Spacer()
                Text("\(uploadedCount) of \(totalUploadCount)")
                    .font(.caption)
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
            }
            ProgressView(value: uploadProgress, total: 1.0)
                .tint(Color(red: 0.6, green: 0.4, blue: 0.85))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Active Filters Bar
    private var activeFiltersBar: some View {
        HStack(spacing: 8) {
            // Sort indicator
            if sortOption != .newestFirst {
                HStack(spacing: 4) {
                    Image(systemName: sortOption.icon)
                        .font(.caption)
                    Text(sortOption.rawValue)
                        .font(.caption)
                }
                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(red: 0.95, green: 0.9, blue: 1.0))
                .cornerRadius(12)
            }

            // Date filter indicator
            if hasDateFilter {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    if let start = filterStartDate, let end = filterEndDate {
                        Text("\(start, format: .dateTime.month(.abbreviated).day()) - \(end, format: .dateTime.month(.abbreviated).day())")
                            .font(.caption)
                    } else if let start = filterStartDate {
                        Text("From \(start, format: .dateTime.month(.abbreviated).day())")
                            .font(.caption)
                    } else if let end = filterEndDate {
                        Text("Until \(end, format: .dateTime.month(.abbreviated).day())")
                            .font(.caption)
                    }

                    Button(action: {
                        withAnimation {
                            filterStartDate = nil
                            filterEndDate = nil
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                    }
                }
                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(red: 0.95, green: 0.9, blue: 1.0))
                .cornerRadius(12)
            }

            Spacer()

            // Grid size indicator
            HStack(spacing: 4) {
                Image(systemName: "square.grid.\(columnCount)x\(columnCount)")
                    .font(.caption)
            }
            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(red: 0.95, green: 0.93, blue: 0.98))
            .cornerRadius(8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
    }

    // MARK: - Expandable Header (hidden when collapsed)
    private var expandableHeader: some View {
        VStack(spacing: 0) {
            // Expanded content only - no indicators when collapsed
            if showingExpandedHeader {
                VStack(spacing: 16) {
                    // Quick actions row
                    HStack(spacing: 12) {
                        // Add button
                        PhotosPicker(selection: $selectedItems, matching: .images) {
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
                        .font(.title3)
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
            }

            // Current folder title
            if currentFolderView == .allPhotos {
                Button(action: {
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

    private var foldersOverviewView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingFoldersOverview = false
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                    }

                    Text("Folders")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // All Photos
                FolderCard(
                    title: "All Photos",
                    icon: "photo.on.rectangle",
                    count: viewModel.photos.count,
                    color: Color(red: 0.7, green: 0.5, blue: 0.9)
                ) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingFoldersOverview = false
                    }
                }

                // Favorites
                let favoritesCount = viewModel.favoritesCount
                if favoritesCount > 0 {
                    FolderCard(
                        title: "Favorites",
                        icon: "heart.fill",
                        count: favoritesCount,
                        color: Color(red: 0.9, green: 0.4, blue: 0.5)
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingFoldersOverview = false
                            navigateToFolder(.favorites)
                        }
                    }
                }

                // Events (excluding special events to match folder content)
                let eventPhotosCount = viewModel.photos.filter { photo in
                    guard let eventId = photo.eventId else { return false }
                    // Only count photos from non-special events
                    return viewModel.events.first(where: { $0.id == eventId })?.isSpecial == false
                }.count
                if eventPhotosCount > 0 {
                    FolderCard(
                        title: "Events",
                        icon: "calendar",
                        count: eventPhotosCount,
                        color: Color(red: 0.6, green: 0.4, blue: 0.85)
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingFoldersOverview = false
                            navigateToFolder(.events)
                        }
                    }
                }

                // Special Events
                let specialEventPhotosCount = viewModel.photos.filter { photo in
                    guard let eventId = photo.eventId else { return false }
                    return viewModel.events.first(where: { $0.id == eventId })?.isSpecial == true
                }.count
                if specialEventPhotosCount > 0 {
                    FolderCard(
                        title: "Special Events",
                        icon: "star.circle",
                        count: specialEventPhotosCount,
                        color: Color(red: 0.8, green: 0.6, blue: 0.95)
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingFoldersOverview = false
                            navigateToFolder(.specialEvents)
                        }
                    }
                }

                // Custom Folders
                let customFolders = viewModel.folders.filter { $0.type == .custom }
                if !customFolders.isEmpty {
                    Divider()
                        .padding(.horizontal)

                    Text("Custom Folders")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    ForEach(customFolders, id: \.id) { folder in
                        let folderPhotosCount = viewModel.photos.filter { $0.folderId == folder.id }.count
                        FolderCard(
                            title: folder.name,
                            icon: "folder.fill",
                            count: folderPhotosCount,
                            color: Color(red: 0.65, green: 0.45, blue: 0.8)
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
                            // Subtle date header
                            Text(dateGroup.key)
                                .font(.caption)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7).opacity(0.7))
                                .padding(.horizontal, 16)
                                .padding(.top, dateGroup.key == dateGroups.first?.key ? 8 : 16)

                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(Array(dateGroup.photos.enumerated()), id: \.element.id) { _, photo in
                                    let displayIndex = photosInDisplayOrder.firstIndex(where: { $0.id == photo.id }) ?? 0

                                    PhotoGridCell(
                                        photo: photo,
                                        index: displayIndex,
                                        selectionMode: selectionMode,
                                        isSelected: selectedPhotoIndices.contains(displayIndex),
                                        columnCount: columnCount,
                                        onTap: {
                                            if selectionMode {
                                                if selectedPhotoIndices.contains(displayIndex) {
                                                    selectedPhotoIndices.remove(displayIndex)
                                                } else {
                                                    selectedPhotoIndices.insert(displayIndex)
                                                }
                                            } else {
                                                selectedPhotoIndex = PhotoIndex(value: displayIndex)
                                            }
                                        },
                                        onLongPress: {
                                            if !selectionMode {
                                                selectionMode = true
                                                selectedPhotoIndices.insert(displayIndex)
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
        }
        .padding(.top, 8)
    }

    private func navigateToFolder(_ folder: FolderViewType) {
        folderNavStack.append(currentFolderView)
        currentFolderView = folder
    }

    private func monthHeaderView(monthGroup: (key: String, photos: [Photo])) -> some View {
        HStack {
            Text(monthGroup.key)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

            Spacer()

            Text("\(monthGroup.photos.count) photo\(monthGroup.photos.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    var body: some View {
        ZStack {
            NavigationView {
                ZStack {
                    // Background gradient - light periwinkle
                    LinearGradient(
                        colors: [
                            Color(red: 0.8, green: 0.8, blue: 1.0),
                            Color(red: 0.9, green: 0.9, blue: 1.0),
                            Color.white
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    if showingFoldersOverview {
                        foldersOverviewView
                    } else if viewModel.photos.isEmpty && currentFolderView == .allPhotos {
                        VStack(spacing: 20) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 80))
                                .foregroundColor(Color(red: 0.7, green: 0.6, blue: 0.9))

                            Text("No photos yet")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                            Text("Add your first memory together 📸")
                                .font(.subheadline)
                                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                        }
                    } else {
                        contentView
                    }

                }
                .toolbar {
                    if selectionMode {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                selectionMode = false
                                selectedPhotoIndices.removeAll()
                            }
                            .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                        }

                        ToolbarItem(placement: .principal) {
                            Text("\(selectedPhotoIndices.count) selected")
                                .font(.headline)
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack(spacing: 12) {
                                // Favorite button
                                Button(action: toggleFavoritesForSelected) {
                                    Image(systemName: "heart.fill")
                                        .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.5))
                                }
                                .disabled(selectedPhotoIndices.isEmpty)

                                // Move to folder button
                                Button(action: { showingMoveToFolder = true }) {
                                    Image(systemName: "folder.badge.plus")
                                        .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                                }
                                .disabled(selectedPhotoIndices.isEmpty)

                                // Save button
                                Button(action: saveSelectedPhotos) {
                                    Image(systemName: "square.and.arrow.down")
                                        .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                                }
                                .disabled(selectedPhotoIndices.isEmpty)

                                // Delete button
                                Button(action: deleteSelectedPhotos) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .disabled(selectedPhotoIndices.isEmpty)
                            }
                        }
                    }
                }
                .onChange(of: selectedItems) { oldItems, newItems in
                Task {
                    guard !newItems.isEmpty else { return }
                    isUploading = true
                    totalUploadCount = newItems.count
                    uploadedCount = 0
                    uploadProgress = 0.0

                    var uploadErrors: [String] = []

                    for (index, item) in newItems.enumerated() {
                        do {
                            if let data = try await item.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                // Extract original capture date from image metadata
                                let capturedAt = extractCaptureDate(from: data)

                                // Resize and compress the image before upload
                                let resized = uiImage.resized(toMaxDimension: 1920)
                                if let compressedData = resized.compressed(toMaxBytes: 1_000_000) {
                                    try await viewModel.uploadPhoto(imageData: compressedData, capturedAt: capturedAt)
                                    await MainActor.run {
                                        uploadedCount = index + 1
                                        uploadProgress = Double(uploadedCount) / Double(totalUploadCount)
                                    }
                                } else {
                                    uploadErrors.append("Failed to compress image \(index + 1)")
                                }
                            }
                        } catch {
                            uploadErrors.append("Failed to upload photo \(index + 1): \(error.localizedDescription)")
                        }
                    }

                    if !uploadErrors.isEmpty {
                        errorMessage = uploadErrors.joined(separator: "\n")
                        showError = true
                    }

                    // Send push notification for uploaded photos (gallery photos, not event photos)
                    let successfulUploads = newItems.count - uploadErrors.count
                    if successfulUploads > 0 {
                        NotificationManager.shared.notifyPhotosAdded(count: successfulUploads, location: "gallery", eventId: nil)
                    }

                    isUploading = false
                    uploadProgress = 0.0
                    uploadedCount = 0
                    totalUploadCount = 0
                    selectedItems = []
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
                // Create display positions array: maps each position to 1-based numbering (newest = 1)
                let displayPositions = (1...photosInDisplayOrder.count).map { $0 }

                FullScreenPhotoViewer(
                    photoURLs: photosInDisplayOrder.map { $0.imageURL },
                    initialIndex: photoIndex.value,
                    onDismiss: { selectedPhotoIndex = nil },
                    onDelete: { indexToDelete in
                        if indexToDelete < photosInDisplayOrder.count {
                            let photoToDelete = photosInDisplayOrder[indexToDelete]
                            Task {
                                try? await viewModel.deletePhoto(photoToDelete)
                            }
                        }
                    },
                    captureDates: photosInDisplayOrder.map { $0.capturedAt ?? $0.createdAt },
                    chronologicalPositions: displayPositions,
                    favoriteStates: photosInDisplayOrder.map { $0.isFavorite ?? false },
                    onToggleFavorite: { indexToToggle in
                        if indexToToggle < photosInDisplayOrder.count {
                            let photo = photosInDisplayOrder[indexToToggle]
                            if let photoId = photo.id {
                                let newFavoriteState = !(photo.isFavorite ?? false)

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
                    },
                    uploadedByNames: photosInDisplayOrder.map { $0.uploadedBy }
                )
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
    }

    private func saveSelectedPhotos() {
        guard !selectedPhotoIndices.isEmpty else { return }

        let totalCount = selectedPhotoIndices.count

        Task {
            var savedCount = 0
            var errorOccurred = false

            for index in selectedPhotoIndices.sorted() {
                guard index < photosInDisplayOrder.count else { continue }
                let photo = photosInDisplayOrder[index]

                // Load image
                if let cachedImage = ImageCache.shared.get(forKey: photo.imageURL) {
                    let imageSaver = ImageSaver()
                    imageSaver.successHandler = {
                        savedCount += 1
                        if savedCount == totalCount {
                            Task { @MainActor in
                                savedPhotoCount = totalCount
                                showingSaveSuccess = true
                                selectionMode = false
                                selectedPhotoIndices.removeAll()
                            }
                        }
                    }
                    imageSaver.errorHandler = { error in
                        if !errorOccurred {
                            errorOccurred = true
                            Task { @MainActor in
                                saveErrorMessage = "Failed to save some photos: \(error.localizedDescription)"
                                showingSaveError = true
                            }
                        }
                    }
                    imageSaver.writeToPhotoAlbum(image: cachedImage)
                } else if let url = URL(string: photo.imageURL),
                          let data = try? Data(contentsOf: url),
                          let image = UIImage(data: data) {
                    ImageCache.shared.set(image, forKey: photo.imageURL)
                    let imageSaver = ImageSaver()
                    imageSaver.successHandler = {
                        savedCount += 1
                        if savedCount == totalCount {
                            Task { @MainActor in
                                savedPhotoCount = totalCount
                                showingSaveSuccess = true
                                selectionMode = false
                                selectedPhotoIndices.removeAll()
                            }
                        }
                    }
                    imageSaver.errorHandler = { error in
                        if !errorOccurred {
                            errorOccurred = true
                            Task { @MainActor in
                                saveErrorMessage = "Failed to save some photos: \(error.localizedDescription)"
                                showingSaveError = true
                            }
                        }
                    }
                    imageSaver.writeToPhotoAlbum(image: image)
                }
            }
        }
    }

    private func deleteSelectedPhotos() {
        guard !selectedPhotoIndices.isEmpty else { return }

        Task {
            for index in selectedPhotoIndices.sorted().reversed() {
                guard index < photosInDisplayOrder.count else { continue }
                let photo = photosInDisplayOrder[index]
                try? await viewModel.deletePhoto(photo)
            }

            await MainActor.run {
                selectionMode = false
                selectedPhotoIndices.removeAll()
            }
        }
    }

    private func toggleFavoritesForSelected() {
        guard !selectedPhotoIndices.isEmpty else { return }

        Task {
            let selectedPhotos = selectedPhotoIndices.sorted().compactMap { index -> Photo? in
                guard index < photosInDisplayOrder.count else { return nil }
                return photosInDisplayOrder[index]
            }

            let photoIds = selectedPhotos.compactMap { $0.id }

            // Check if all selected photos are already favorited
            let allFavorited = selectedPhotos.allSatisfy { $0.isFavorite == true }

            // If all are favorited, unfavorite them; otherwise favorite them
            let newFavoriteState = !allFavorited

            try? await viewModel.batchToggleFavorites(photoIds, isFavorite: newFavoriteState) { current, total in
                // Could show progress here if needed
            }

            await MainActor.run {
                selectionMode = false
                selectedPhotoIndices.removeAll()
            }
        }
    }

    private func moveSelectedPhotosToFolder(_ folderId: String?) {
        guard !selectedPhotoIndices.isEmpty else { return }

        Task {
            let photoIds = selectedPhotoIndices.sorted().compactMap { index -> String? in
                guard index < photosInDisplayOrder.count else { return nil }
                return photosInDisplayOrder[index].id
            }

            try? await viewModel.movePhotosToFolder(photoIds, folderId: folderId) { current, total in
                // Could show progress here if needed
            }

            await MainActor.run {
                selectionMode = false
                selectedPhotoIndices.removeAll()
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

    // Calculate size based on column count
    private var cellSize: CGFloat {
        let spacing: CGFloat = 8 * CGFloat(columnCount - 1) // spacing between cells
        let padding: CGFloat = 16 // horizontal padding
        return (UIScreen.main.bounds.width - padding - spacing) / CGFloat(columnCount)
    }

    private var cornerRadius: CGFloat {
        columnCount == 2 ? 16 : (columnCount == 3 ? 12 : 8)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CachedAsyncImage(url: URL(string: photo.imageURL), thumbnailSize: cellSize) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
            }
            .frame(width: cellSize, height: cellSize)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Color.black.opacity(0.1), radius: columnCount == 2 ? 4 : 2, x: 0, y: 1)
            .overlay(
                selectionMode ?
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isSelected ? Color(red: 0.8, green: 0.7, blue: 1.0) : Color.clear, lineWidth: 3)
                : nil
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.5, perform: onLongPress)

            // Favorite indicator (bottom right)
            if photo.isFavorite == true && !selectionMode {
                Image(systemName: "heart.fill")
                    .font(columnCount == 2 ? .body : .caption)
                    .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.5))
                    .shadow(radius: 2)
                    .padding(columnCount == 2 ? 10 : 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            // Checkmark overlay
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(columnCount == 2 ? .title : .title2)
                    .foregroundColor(isSelected ? Color(red: 0.8, green: 0.7, blue: 1.0) : .white)
                    .shadow(radius: 3)
                    .padding(columnCount == 2 ? 10 : 8)
                    .allowsHitTesting(false)
            }
        }
        .drawingGroup() // Optimize rendering performance
    }
}

struct FolderCard: View {
    let title: String
    let icon: String
    let count: Int
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.15))
                        .frame(width: 60, height: 60)

                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                    Text("\(count) photo\(count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.8))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

class PhotoGalleryViewModel: ObservableObject {
    @Published var photos: [Photo] = []
    @Published var folders: [PhotoFolder] = []
    @Published var events: [CalendarEvent] = []

    private let firebaseManager = FirebaseManager.shared

    init() {
        loadPhotos()
        loadFolders()
        loadEvents()
    }

    func loadPhotos() {
        Task {
            for try await photos in firebaseManager.getPhotos() {
                await MainActor.run {
                    self.photos = photos
                }
            }
        }
    }

    func loadFolders() {
        Task {
            for try await folders in firebaseManager.getFolders() {
                await MainActor.run {
                    self.folders = folders
                }
            }
        }
    }

    func loadEvents() {
        Task {
            for try await events in firebaseManager.getCalendarEvents() {
                await MainActor.run {
                    self.events = events
                }
            }
        }
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
    }
}

#Preview {
    PhotoGalleryView()
}
