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
    @State private var showingToolDrawer = false
    @State private var currentFolderView: FolderViewType = .allPhotos
    @State private var folderNavStack: [FolderViewType] = []
    @State private var showingCreateFolder = false
    @State private var newFolderName = ""
    @State private var showingFoldersOverview = false

    let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    // Get photos for current folder view
    private var filteredPhotos: [Photo] {
        viewModel.photos(for: currentFolderView)
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

        // Sort by date (newest first)
        return grouped.sorted { first, second in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            guard let date1 = formatter.date(from: first.key),
                  let date2 = formatter.date(from: second.key) else {
                return first.key > second.key
            }
            return date1 > date2
        }.map { (key: $0.key, photos: $0.value) }
    }

    // Current folder title for display
    private var folderTitle: String {
        switch currentFolderView {
        case .allPhotos:
            return "All Photos"
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
                // Folder navigation bar
                folderNavigationBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Show folders or photos based on current view
                if currentFolderView == .events || currentFolderView == .specialEvents {
                    folderListView
                } else {
                    photoGridView
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 0)
        }
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
                                    currentFolderView = folderNavStack.popLast() ?? .allPhotos
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

    private var folderNavigationBar: some View {
        HStack(spacing: 12) {
            // Back button if we're in a subfolder
            if currentFolderView != .allPhotos {
                Button(action: {
                    currentFolderView = folderNavStack.popLast() ?? .allPhotos
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

            // Folder menu button
            Menu {
                Button(action: { currentFolderView = .allPhotos; folderNavStack.removeAll() }) {
                    Label("All Photos", systemImage: "photo.on.rectangle")
                }
                Button(action: { navigateToFolder(.events) }) {
                    Label("Events", systemImage: "calendar")
                }
                Button(action: { navigateToFolder(.specialEvents) }) {
                    Label("Special Events", systemImage: "star.circle")
                }

                if !viewModel.folders.filter({ $0.type == .custom }).isEmpty {
                    Divider()
                    ForEach(viewModel.folders.filter { $0.type == .custom }, id: \.id) { folder in
                        Button(action: { navigateToFolder(.custom(folder.id!)) }) {
                            Label(folder.name, systemImage: "folder")
                        }
                    }
                }
            } label: {
                Image(systemName: "folder.badge.gearshape")
                    .font(.title3)
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
            }
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

                // Events
                let eventPhotosCount = viewModel.photos.filter { $0.eventId != nil }.count
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
                    }
                }
            }
            .padding(.vertical)
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 0)
        }
    }

    private var photoGridView: some View {
        LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
            ForEach(photosByMonth, id: \.key) { monthGroup in
                Section {
                    // Month header (not pinned anymore)
                    monthHeaderView(monthGroup: monthGroup)

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(monthGroup.photos.enumerated()), id: \.element.id) { _, photo in
                            let globalIndex = viewModel.photos.firstIndex(where: { $0.id == photo.id }) ?? 0

                            PhotoGridCell(
                                photo: photo,
                                index: globalIndex,
                                selectionMode: selectionMode,
                                isSelected: selectedPhotoIndices.contains(globalIndex),
                                onTap: {
                                    if selectionMode {
                                        if selectedPhotoIndices.contains(globalIndex) {
                                            selectedPhotoIndices.remove(globalIndex)
                                        } else {
                                            selectedPhotoIndices.insert(globalIndex)
                                        }
                                    } else {
                                        selectedPhotoIndex = PhotoIndex(value: globalIndex)
                                    }
                                },
                                onLongPress: {
                                    if !selectionMode {
                                        selectionMode = true
                                        selectedPhotoIndices.insert(globalIndex)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
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
                    // Background gradient
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.9, blue: 1.0),
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
                .blur(radius: showingToolDrawer ? 3 : 0)
                .allowsHitTesting(!showingToolDrawer)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            // Pull down from top to open drawer
                            if value.translation.height > 50 && value.startLocation.y < 100 {
                                withAnimation(.spring(response: 0.3)) {
                                    showingToolDrawer = true
                                }
                            }
                        }
                )
                .toolbar {
                    if selectionMode {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                selectionMode = false
                                selectedPhotoIndices.removeAll()
                            }
                            .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack(spacing: 16) {
                                Button(action: saveSelectedPhotos) {
                                    Image(systemName: "square.and.arrow.down")
                                        .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                                }
                                .disabled(selectedPhotoIndices.isEmpty)

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

                    isUploading = false
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
                FullScreenPhotoViewer(
                    photoURLs: viewModel.photos.map { $0.imageURL },
                    initialIndex: photoIndex.value,
                    onDismiss: { selectedPhotoIndex = nil },
                    onDelete: { indexToDelete in
                        if indexToDelete < viewModel.photos.count {
                            let photoToDelete = viewModel.photos[indexToDelete]
                            Task {
                                try? await viewModel.deletePhoto(photoToDelete)
                            }
                        }
                    },
                    captureDates: viewModel.photos.map { $0.capturedAt ?? $0.createdAt }
                )
            }
            }

            // TOOL DRAWER OVERLAY
            if showingToolDrawer {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            showingToolDrawer = false
                        }
                    }

                VStack(spacing: 0) {
                    PhotoToolDrawerView(
                        selectedItems: $selectedItems,
                        isUploading: isUploading,
                        selectionMode: $selectionMode,
                        showingCreateFolder: $showingCreateFolder,
                        onClose: {
                            withAnimation(.spring(response: 0.3)) {
                                showingToolDrawer = false
                            }
                        }
                    )
                    .padding(.top, 50)
                    .transition(.move(edge: .top).combined(with: .opacity))

                    Spacer()
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
    }

    private func saveSelectedPhotos() {
        guard !selectedPhotoIndices.isEmpty else { return }

        let totalCount = selectedPhotoIndices.count

        Task {
            var savedCount = 0
            var errorOccurred = false

            for index in selectedPhotoIndices.sorted() {
                guard index < viewModel.photos.count else { continue }
                let photo = viewModel.photos[index]

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
                guard index < viewModel.photos.count else { continue }
                let photo = viewModel.photos[index]
                try? await viewModel.deletePhoto(photo)
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
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CachedAsyncImage(url: URL(string: photo.imageURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        ProgressView()
                    }
            }
            .frame(width: (UIScreen.main.bounds.width - 32) / 3, height: (UIScreen.main.bounds.width - 32) / 3)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            .overlay(
                selectionMode ?
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color(red: 0.8, green: 0.7, blue: 1.0) : Color.clear, lineWidth: 3)
                : nil
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.5, perform: onLongPress)

            // Checkmark overlay
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? Color(red: 0.8, green: 0.7, blue: 1.0) : .white)
                    .shadow(radius: 3)
                    .padding(8)
                    .allowsHitTesting(false)
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
            uploadedBy: "You",
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

        return relevantEvents.map { event in
            let count = photos.filter { $0.eventId == event.id }.count
            return (event: event, photoCount: count)
        }
    }
}

// Folder view types for navigation
enum FolderViewType: Hashable {
    case allPhotos
    case events // Parent category
    case specialEvents // Parent category
    case event(String) // Specific event folder
    case custom(String) // Custom folder
}

struct PhotoToolDrawerView: View {
    @Binding var selectedItems: [PhotosPickerItem]
    let isUploading: Bool
    @Binding var selectionMode: Bool
    @Binding var showingCreateFolder: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 8)

            VStack(spacing: 16) {
                // ADD PHOTOS BUTTON (top priority)
                PhotosPicker(selection: $selectedItems, matching: .images) {
                    HStack {
                        if isUploading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        Text(isUploading ? "Uploading..." : "Add Photos")
                            .font(.headline)
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.7, green: 0.4, blue: 0.95),
                                Color(red: 0.55, green: 0.3, blue: 0.85)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                }
                .disabled(isUploading)

                Divider()
                    .background(Color.white.opacity(0.3))

                // QUICK ACTIONS
                HStack(spacing: 12) {
                    // Select Photos button
                    Button(action: {
                        onClose()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            selectionMode = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text("Select")
                                .font(.subheadline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                    }

                    // Create Folder button
                    Button(action: {
                        onClose()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingCreateFolder = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                            Text("Folder")
                                .font(.subheadline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(
            ZStack {
                // Frosted glass effect
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.95),
                                Color(red: 0.5, green: 0.3, blue: 0.75).opacity(0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            }
        )
        .padding(.horizontal, 16)
    }
}

#Preview {
    PhotoGalleryView()
}
