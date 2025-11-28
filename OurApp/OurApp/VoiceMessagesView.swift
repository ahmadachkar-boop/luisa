import SwiftUI
import AVFoundation
import UIKit

// MARK: - Sort Options
enum VoiceMemoSortOption: String, CaseIterable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case longestFirst = "Longest First"
    case shortestFirst = "Shortest First"
    case alphabetical = "Alphabetical"

    var icon: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        case .longestFirst: return "timer"
        case .shortestFirst: return "timer"
        case .alphabetical: return "textformat.abc"
        }
    }
}

// MARK: - Folder View Type
enum VoiceMemoFolderViewType: Hashable {
    case categorySelection // Main view showing Ahmad/Luisa categories
    case allMemos(String) // All memos for a user (Ahmad or Luisa)
    case favorites(String) // Favorites for a user
    case folder(String, String) // Custom folder (folderId, forUser)
}

// MARK: - Playback Index Wrapper
struct VoiceMemoPlaybackIndex: Identifiable {
    let id = UUID()
    let value: Int
}

struct VoiceMessagesView: View {
    @StateObject private var viewModel = VoiceMessagesViewModel()
    @State private var showingRecorder = false
    @State private var showingExpandedHeader = false
    @State private var selectionMode = false
    @State private var selectedMessageIds: Set<String> = []
    @State private var columnCount: Int = 2
    @State private var sortOption: VoiceMemoSortOption = .newestFirst
    @State private var showingDateFilter = false
    @State private var filterStartDate: Date? = nil
    @State private var filterEndDate: Date? = nil
    @State private var currentFolderView: VoiceMemoFolderViewType = .categorySelection
    @State private var folderNavStack: [VoiceMemoFolderViewType] = []
    @State private var showingCreateFolder = false
    @State private var newFolderName = ""
    @State private var currentUserCategory: String = "Ahmad" // Track which user we're recording for
    @State private var showingMoveToFolder = false
    @State private var selectedPlaybackIndex: VoiceMemoPlaybackIndex?

    // Search state
    @State private var searchText: String = ""
    @State private var isSearchActive: Bool = false

    // Share state
    @State private var shareMessage: VoiceMessage?
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false

    // Magnification gesture state
    @GestureState private var magnificationScale: CGFloat = 1.0

    // Computed columns based on user preference
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
    }

    // Check if date filter is active
    private var hasDateFilter: Bool {
        filterStartDate != nil || filterEndDate != nil
    }

    // Get current user from folder view
    private var currentUser: String? {
        switch currentFolderView {
        case .categorySelection:
            return nil
        case .allMemos(let user), .favorites(let user):
            return user
        case .folder(_, let user):
            return user
        }
    }

    // Current folder title
    private var folderTitle: String {
        switch currentFolderView {
        case .categorySelection:
            return "Voice Memos"
        case .allMemos(let user):
            return "From \(user)"
        case .favorites(let user):
            return "\(user)'s Favorites"
        case .folder(let folderId, _):
            if let folder = viewModel.folders.first(where: { $0.id == folderId }) {
                return folder.name
            }
            return "Folder"
        }
    }

    // Check if search is active with text
    private var hasSearchFilter: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Filtered and sorted messages for current view
    private var filteredMessages: [VoiceMessage] {
        var messages: [VoiceMessage]

        switch currentFolderView {
        case .categorySelection:
            messages = []
        case .allMemos(let user):
            messages = viewModel.voiceMessages.filter { $0.fromUser == user }
        case .favorites(let user):
            messages = viewModel.voiceMessages.filter { $0.fromUser == user && $0.isFavorite == true }
        case .folder(let folderId, let user):
            messages = viewModel.voiceMessages.filter { $0.fromUser == user && $0.folderId == folderId }
        }

        // Apply search filter
        if hasSearchFilter {
            let searchLower = searchText.lowercased()
            messages = messages.filter { message in
                message.title.lowercased().contains(searchLower) ||
                message.fromUser.lowercased().contains(searchLower)
            }
        }

        // Apply date filter
        if let startDate = filterStartDate {
            messages = messages.filter { $0.createdAt >= Calendar.current.startOfDay(for: startDate) }
        }
        if let endDate = filterEndDate {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate))!
            messages = messages.filter { $0.createdAt < endOfDay }
        }

        // Apply sorting
        switch sortOption {
        case .newestFirst:
            messages.sort { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            messages.sort { $0.createdAt < $1.createdAt }
        case .longestFirst:
            messages.sort { $0.duration > $1.duration }
        case .shortestFirst:
            messages.sort { $0.duration < $1.duration }
        case .alphabetical:
            messages.sort { $0.title.lowercased() < $1.title.lowercased() }
        }

        return messages
    }

    // Group messages by month
    private var messagesByMonth: [(key: String, messages: [VoiceMessage])] {
        let grouped = Dictionary(grouping: filteredMessages) { message -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: message.createdAt)
        }

        let sortedMonths = grouped.sorted { first, second in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            guard let date1 = formatter.date(from: first.key),
                  let date2 = formatter.date(from: second.key) else {
                return first.key > second.key
            }
            switch sortOption {
            case .newestFirst, .longestFirst, .shortestFirst, .alphabetical:
                return date1 > date2
            case .oldestFirst:
                return date1 < date2
            }
        }

        return sortedMonths.map { (key: $0.key, messages: $0.value) }
    }

    var body: some View {
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

                VStack(spacing: 0) {
                    if currentFolderView == .categorySelection {
                        categorySelectionView
                    } else if filteredMessages.isEmpty && !viewModel.voiceMessages.isEmpty {
                        emptyFolderView
                    } else if viewModel.voiceMessages.isEmpty {
                        emptyStateView
                    } else {
                        contentView
                    }

                    // Mini Player
                    if viewModel.currentlyPlayingMessage != nil {
                        miniPlayerView
                    }
                }

                // Floating Record Button (when in a category view)
                if currentFolderView != .categorySelection && !selectionMode {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { showingRecorder = true }) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.7, green: 0.45, blue: 0.95),
                                                    Color(red: 0.55, green: 0.35, blue: 0.85)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 60, height: 60)
                                        .shadow(color: Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.4), radius: 8, x: 0, y: 4)

                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, viewModel.currentlyPlayingMessage != nil ? 90 : 20)
                        }
                    }
                }
            }
            .toolbar {
                if selectionMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            selectionMode = false
                            selectedMessageIds.removeAll()
                        }
                        .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                    }

                    ToolbarItem(placement: .principal) {
                        Text("\(selectedMessageIds.count) selected")
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
                            .disabled(selectedMessageIds.isEmpty)

                            // Move to folder button
                            Button(action: { showingMoveToFolder = true }) {
                                Image(systemName: "folder.badge.plus")
                                    .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                            }
                            .disabled(selectedMessageIds.isEmpty)

                            // Delete button
                            Button(action: deleteSelectedMessages) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .disabled(selectedMessageIds.isEmpty)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingRecorder) {
                VoiceRecorderView(fromUser: currentUserCategory) { audioData, duration, title in
                    await viewModel.uploadVoiceMessage(
                        audioData: audioData,
                        title: title,
                        duration: duration,
                        fromUser: currentUserCategory
                    )
                }
            }
            .sheet(isPresented: $showingDateFilter) {
                VoiceMemoDateFilterSheet(
                    startDate: $filterStartDate,
                    endDate: $filterEndDate,
                    onApply: { showingDateFilter = false }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingMoveToFolder) {
                VoiceMemoMoveToFolderSheet(
                    folders: viewModel.folders.filter { $0.forUser == currentUser },
                    onSelectFolder: { folderId in
                        moveSelectedMemosToFolder(folderId)
                        showingMoveToFolder = false
                    },
                    onRemoveFromFolder: {
                        moveSelectedMemosToFolder(nil)
                        showingMoveToFolder = false
                    },
                    onCreateFolder: {
                        showingMoveToFolder = false
                        showingCreateFolder = true
                    }
                )
                .presentationDetents([.medium])
            }
            .alert("Create Folder", isPresented: $showingCreateFolder) {
                TextField("Folder Name", text: $newFolderName)
                Button("Cancel", role: .cancel) {
                    newFolderName = ""
                }
                Button("Create") {
                    if let user = currentUser {
                        Task {
                            _ = try? await viewModel.createFolder(name: newFolderName, forUser: user)
                            newFolderName = ""
                        }
                    }
                }
            } message: {
                Text("Enter a name for your new folder")
            }
            .fullScreenCover(item: $selectedPlaybackIndex) { playbackIndex in
                FullScreenVoiceMemoPlayer(
                    memos: filteredMessages,
                    initialIndex: playbackIndex.value,
                    viewModel: viewModel,
                    onDismiss: { selectedPlaybackIndex = nil }
                )
            }
            .sheet(isPresented: $showingShareSheet) {
                if !shareItems.isEmpty {
                    ShareSheet(items: shareItems)
                }
            }
            .onChange(of: shareMessage) { oldValue, newValue in
                if let message = newValue {
                    prepareShareItems(for: message)
                }
            }
        }
    }

    // MARK: - Share Functionality
    private func prepareShareItems(for message: VoiceMessage) {
        Task {
            guard let url = URL(string: message.audioURL) else {
                shareMessage = nil
                return
            }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                // Create a temporary file
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "\(message.title.replacingOccurrences(of: " ", with: "_")).m4a"
                let tempFileURL = tempDir.appendingPathComponent(fileName)

                try data.write(to: tempFileURL)

                await MainActor.run {
                    shareItems = [tempFileURL]
                    showingShareSheet = true
                    shareMessage = nil
                }
            } catch {
                print("Error preparing share: \(error)")
                await MainActor.run {
                    shareMessage = nil
                }
            }
        }
    }

    // MARK: - Category Selection View
    private var categorySelectionView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Voice Memos")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // From Ahmad Category
                CategoryCard(
                    title: "From Ahmad",
                    icon: "person.circle.fill",
                    count: viewModel.voiceMessages.filter { $0.fromUser == "Ahmad" }.count,
                    favoritesCount: viewModel.voiceMessages.filter { $0.fromUser == "Ahmad" && $0.isFavorite == true }.count,
                    color: Color(red: 0.4, green: 0.6, blue: 0.9)
                ) {
                    navigateToFolder(.allMemos("Ahmad"))
                    currentUserCategory = "Ahmad"
                }

                // From Luisa Category
                CategoryCard(
                    title: "From Luisa",
                    icon: "person.circle.fill",
                    count: viewModel.voiceMessages.filter { $0.fromUser == "Luisa" }.count,
                    favoritesCount: viewModel.voiceMessages.filter { $0.fromUser == "Luisa" && $0.isFavorite == true }.count,
                    color: Color(red: 0.9, green: 0.5, blue: 0.6)
                ) {
                    navigateToFolder(.allMemos("Luisa"))
                    currentUserCategory = "Luisa"
                }

                // All Favorites
                let totalFavorites = viewModel.voiceMessages.filter { $0.isFavorite == true }.count
                if totalFavorites > 0 {
                    Divider()
                        .padding(.horizontal)

                    Text("Quick Access")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    // All Favorites card (shows both)
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.title2)
                            .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.5))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("All Favorites")
                                .font(.headline)
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                            Text("\(totalFavorites) memo\(totalFavorites == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                        }

                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(Color(red: 0.7, green: 0.6, blue: 0.9))

            Text("No voice memos yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

            Text("Record your first voice memo")
                .font(.subheadline)
                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

            Button(action: { showingRecorder = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                    Text("Record")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
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
                .cornerRadius(16)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty Folder View
    private var emptyFolderView: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder")
                .font(.system(size: 60))
                .foregroundColor(Color(red: 0.7, green: 0.6, blue: 0.9))

            Text("No memos here")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

            Text("Add memos to this folder or record a new one")
                .font(.subheadline)
                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content View
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Expandable header
                expandableHeader
                    .padding(.horizontal)
                    .padding(.top, 4)

                // Search bar
                searchBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Navigation bar
                navigationBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Active filters indicator
                if hasDateFilter || sortOption != .newestFirst || hasSearchFilter {
                    activeFiltersBar
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Folders section (when in allMemos view and not searching)
                if case .allMemos(let user) = currentFolderView, !hasSearchFilter {
                    foldersSection(forUser: user)
                        .padding(.top, 12)
                }

                // Voice memo grid
                voiceMemoGridView
            }
        }
        .refreshable {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showingExpandedHeader = true
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { oldValue, newValue in
            if showingExpandedHeader && newValue > 50 {
                withAnimation(.spring(response: 0.3)) {
                    showingExpandedHeader = false
                }
            }
        }
        .simultaneousGesture(
            MagnificationGesture()
                .updating($magnificationScale) { value, scale, _ in
                    scale = value
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.3)) {
                        if value < 0.8 && columnCount < 3 {
                            columnCount += 1
                        } else if value > 1.2 && columnCount > 1 {
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
                            withAnimation(.easeInOut(duration: 0.3)) {
                                let previousView = folderNavStack.popLast() ?? .categorySelection
                                currentFolderView = previousView
                            }
                        } else if horizontalAmount < 0 {
                            // Swipe left - switch to other user (only from allMemos view)
                            if case .allMemos(let currentUserName) = currentFolderView {
                                let otherUser = currentUserName == "Ahmad" ? "Luisa" : "Ahmad"
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentFolderView = .allMemos(otherUser)
                                    currentUserCategory = otherUser
                                }
                            }
                        }
                    }
                }
        )
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))

                TextField("Search memos...", text: $searchText)
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                    .onSubmit {
                        isSearchActive = !searchText.isEmpty
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        withAnimation {
                            searchText = ""
                            isSearchActive = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
            )
        }
    }

    // MARK: - Folders Section
    private func foldersSection(forUser user: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Favorites
            let favoritesCount = viewModel.voiceMessages.filter { $0.fromUser == user && $0.isFavorite == true }.count
            if favoritesCount > 0 {
                Button(action: { navigateToFolder(.favorites(user)) }) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(red: 0.9, green: 0.4, blue: 0.5).opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "heart.fill")
                                .font(.title3)
                                .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.5))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Favorites")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                            Text("\(favoritesCount) memo\(favoritesCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.8))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Custom folders
            let userFolders = viewModel.folders.filter { $0.forUser == user }
            ForEach(userFolders, id: \.id) { folder in
                let folderCount = viewModel.voiceMessages.filter { $0.folderId == folder.id }.count
                Button(action: {
                    if let folderId = folder.id {
                        navigateToFolder(.folder(folderId, user))
                    }
                }) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "folder.fill")
                                .font(.title3)
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                            Text("\(folderCount) memo\(folderCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.8))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
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
        .padding(.horizontal)
    }

    // MARK: - Expandable Header (hidden when collapsed)
    private var expandableHeader: some View {
        VStack(spacing: 0) {
            // Expanded content only - no indicators when collapsed
            if showingExpandedHeader {
                VStack(spacing: 16) {
                    // Quick actions row
                    HStack(spacing: 12) {
                        // Record
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showingExpandedHeader = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showingRecorder = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "mic.fill")
                                    .font(.body)
                                Text("Record")
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
                        if case .allMemos(_) = currentFolderView {
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
                                ForEach(VoiceMemoSortOption.allCases, id: \.self) { option in
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
                            ForEach([1, 2, 3], id: \.self) { count in
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

    // MARK: - Navigation Bar
    private var navigationBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Back button
                if currentFolderView != .categorySelection {
                    Button(action: {
                        let previousView = folderNavStack.popLast() ?? .categorySelection
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentFolderView = previousView
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                    }
                }

                Text(folderTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                Spacer()

                Text("\(filteredMessages.count) memo\(filteredMessages.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
            }

            // Swipe indicator for switching between Ahmad/Luisa
            if case .allMemos(let user) = currentFolderView {
                HStack(spacing: 16) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentFolderView = .allMemos("Ahmad")
                            currentUserCategory = "Ahmad"
                        }
                    }) {
                        HStack(spacing: 4) {
                            if user == "Ahmad" {
                                Image(systemName: "chevron.left")
                                    .font(.caption2)
                            }
                            Text("Ahmad")
                                .font(.caption.weight(user == "Ahmad" ? .bold : .regular))
                        }
                        .foregroundColor(user == "Ahmad" ? Color(red: 0.4, green: 0.6, blue: 0.9) : Color(red: 0.5, green: 0.4, blue: 0.7))
                    }

                    // Swipe indicator
                    HStack(spacing: 4) {
                        Image(systemName: "hand.draw.fill")
                            .font(.caption2)
                        Text("swipe")
                            .font(.caption2)
                    }
                    .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.8).opacity(0.6))

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentFolderView = .allMemos("Luisa")
                            currentUserCategory = "Luisa"
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("Luisa")
                                .font(.caption.weight(user == "Luisa" ? .bold : .regular))
                            if user == "Luisa" {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                        }
                        .foregroundColor(user == "Luisa" ? Color(red: 0.9, green: 0.5, blue: 0.6) : Color(red: 0.5, green: 0.4, blue: 0.7))
                    }
                }
                .padding(.top, 4)
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

    // MARK: - Active Filters Bar
    private var activeFiltersBar: some View {
        HStack(spacing: 8) {
            // Search filter indicator
            if hasSearchFilter {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                    Text("\"\(searchText)\"")
                        .font(.caption)
                        .lineLimit(1)

                    Button(action: {
                        withAnimation {
                            searchText = ""
                            isSearchActive = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                    }
                }
                .foregroundColor(Color(red: 0.4, green: 0.6, blue: 0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(red: 0.9, green: 0.95, blue: 1.0))
                .cornerRadius(12)
            }

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

            HStack(spacing: 4) {
                Image(systemName: columnCount == 1 ? "rectangle.grid.1x2" : "square.grid.\(columnCount)x\(columnCount)")
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

    // MARK: - Voice Memo Grid View
    private var voiceMemoGridView: some View {
        LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
            ForEach(messagesByMonth, id: \.key) { monthGroup in
                Section {
                    monthHeaderView(monthGroup: monthGroup)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(monthGroup.messages.enumerated()), id: \.element.id) { index, message in
                            let displayIndex = filteredMessages.firstIndex(where: { $0.id == message.id }) ?? 0

                            VoiceMemoGridCell(
                                message: message,
                                isPlaying: viewModel.currentlyPlayingId == message.id,
                                selectionMode: selectionMode,
                                isSelected: selectedMessageIds.contains(message.id ?? ""),
                                columnCount: columnCount,
                                onTap: {
                                    if selectionMode {
                                        if let id = message.id {
                                            if selectedMessageIds.contains(id) {
                                                selectedMessageIds.remove(id)
                                            } else {
                                                selectedMessageIds.insert(id)
                                            }
                                        }
                                    } else {
                                        selectedPlaybackIndex = VoiceMemoPlaybackIndex(value: displayIndex)
                                    }
                                },
                                onLongPress: {
                                    if !selectionMode {
                                        selectionMode = true
                                        if let id = message.id {
                                            selectedMessageIds.insert(id)
                                        }
                                    }
                                },
                                onToggleFavorite: {
                                    Task {
                                        await viewModel.toggleFavorite(message)
                                    }
                                },
                                onDelete: {
                                    Task {
                                        await viewModel.deleteMessage(message)
                                    }
                                },
                                onShare: {
                                    shareMessage = message
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, viewModel.currentlyPlayingMessage != nil ? 80 : 0)
    }

    private func monthHeaderView(monthGroup: (key: String, messages: [VoiceMessage])) -> some View {
        HStack {
            Text(monthGroup.key)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

            Spacer()

            Text("\(monthGroup.messages.count) memo\(monthGroup.messages.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Mini Player View
    private var miniPlayerView: some View {
        Group {
            if let message = viewModel.currentlyPlayingMessage {
                HStack(spacing: 12) {
                    // Waveform indicator
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.8, green: 0.7, blue: 1.0))
                                .frame(width: 3, height: viewModel.isPlaying ? CGFloat.random(in: 8...20) : 8)
                                .animation(.easeInOut(duration: 0.3).repeatForever(), value: viewModel.isPlaying)
                        }
                    }
                    .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))
                            .lineLimit(1)

                        Text("From \(message.fromUser)")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    }

                    Spacer()

                    // Play/Pause
                    Button(action: {
                        viewModel.togglePlayPause()
                    }) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                    }

                    // Close
                    Button(action: {
                        viewModel.stopPlayback()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: -2)
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .onTapGesture {
                    if let index = filteredMessages.firstIndex(where: { $0.id == message.id }) {
                        selectedPlaybackIndex = VoiceMemoPlaybackIndex(value: index)
                    }
                }
            }
        }
    }

    // MARK: - Helper Functions
    private func navigateToFolder(_ folder: VoiceMemoFolderViewType) {
        folderNavStack.append(currentFolderView)
        withAnimation(.easeInOut(duration: 0.3)) {
            currentFolderView = folder
        }
    }

    private func deleteSelectedMessages() {
        guard !selectedMessageIds.isEmpty else { return }

        Task {
            for id in selectedMessageIds {
                if let message = viewModel.voiceMessages.first(where: { $0.id == id }) {
                    await viewModel.deleteMessage(message)
                }
            }

            await MainActor.run {
                selectionMode = false
                selectedMessageIds.removeAll()
            }
        }
    }

    private func toggleFavoritesForSelected() {
        guard !selectedMessageIds.isEmpty else { return }

        Task {
            let selectedMemos = selectedMessageIds.compactMap { id in
                viewModel.voiceMessages.first(where: { $0.id == id })
            }

            let allFavorited = selectedMemos.allSatisfy { $0.isFavorite == true }
            let newFavoriteState = !allFavorited

            try? await viewModel.batchToggleFavorites(Array(selectedMessageIds), isFavorite: newFavoriteState)

            await MainActor.run {
                selectionMode = false
                selectedMessageIds.removeAll()
            }
        }
    }

    private func moveSelectedMemosToFolder(_ folderId: String?) {
        guard !selectedMessageIds.isEmpty else { return }

        Task {
            try? await viewModel.batchUpdateFolders(Array(selectedMessageIds), folderId: folderId)

            await MainActor.run {
                selectionMode = false
                selectedMessageIds.removeAll()
            }
        }
    }
}

// MARK: - Category Card
struct CategoryCard: View {
    let title: String
    let icon: String
    let count: Int
    let favoritesCount: Int
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 70, height: 70)

                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                    Text("\(count) memo\(count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))

                    if favoritesCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.5))
                            Text("\(favoritesCount) favorite\(favoritesCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.8))
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Voice Memo Grid Cell
struct VoiceMemoGridCell: View {
    let message: VoiceMessage
    let isPlaying: Bool
    let selectionMode: Bool
    let isSelected: Bool
    let columnCount: Int
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void

    @State private var showingDeleteAlert = false
    @State private var swipeOffset: CGFloat = 0
    @State private var isSwipeActive = false

    private var cellHeight: CGFloat {
        columnCount == 1 ? 100 : (columnCount == 2 ? 150 : 130)
    }

    private var cornerRadius: CGFloat {
        columnCount == 1 ? 16 : (columnCount == 2 ? 16 : 12)
    }

    // Swipe action thresholds
    private let swipeThreshold: CGFloat = 80
    private let maxSwipe: CGFloat = 160

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Swipe action background (only for single column layout)
            if columnCount == 1 && !selectionMode {
                HStack(spacing: 0) {
                    // Left swipe actions (revealed when swiping right)
                    HStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                swipeOffset = 0
                            }
                            onToggleFavorite()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: message.isFavorite == true ? "heart.slash.fill" : "heart.fill")
                                    .font(.title3)
                                Text(message.isFavorite == true ? "Unfavorite" : "Favorite")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .frame(width: 80, height: cellHeight)
                            .background(Color(red: 0.9, green: 0.4, blue: 0.5))
                        }
                    }
                    .frame(width: max(0, swipeOffset))
                    .clipped()

                    Spacer()

                    // Right swipe actions (revealed when swiping left)
                    HStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                swipeOffset = 0
                            }
                            onShare()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title3)
                                Text("Share")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .frame(width: 80, height: cellHeight)
                            .background(Color(red: 0.6, green: 0.4, blue: 0.85))
                        }

                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                swipeOffset = 0
                            }
                            showingDeleteAlert = true
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                    .font(.title3)
                                Text("Delete")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .frame(width: 80, height: cellHeight)
                            .background(Color.red)
                        }
                    }
                    .frame(width: max(0, -swipeOffset))
                    .clipped()
                }
                .frame(height: cellHeight)
                .cornerRadius(cornerRadius)
            }

            // Main content
            VStack(spacing: columnCount == 1 ? 0 : 8) {
                if columnCount == 1 {
                    // Horizontal layout for single column
                    HStack(spacing: 15) {
                        playButton

                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.title)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))
                                .lineLimit(1)

                            HStack {
                                Text(formatDuration(message.duration))
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                                Text("•")
                                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                                Text(timeAgo(from: message.createdAt))
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                            }
                        }

                        Spacer()

                        if !selectionMode {
                            // Favorite button
                            Button(action: onToggleFavorite) {
                                Image(systemName: message.isFavorite == true ? "heart.fill" : "heart")
                                    .foregroundColor(message.isFavorite == true ? Color(red: 0.9, green: 0.4, blue: 0.5) : Color(red: 0.6, green: 0.5, blue: 0.8))
                            }

                            Button(action: { showingDeleteAlert = true }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                        }
                    }
                    .padding()
                } else {
                    // Vertical layout for grid - all content contained within card
                    VStack(spacing: columnCount == 2 ? 6 : 4) {
                        Spacer(minLength: 4)

                        waveformView

                        playButton

                        VStack(spacing: 2) {
                            Text(message.title)
                                .font(columnCount == 2 ? .subheadline : .caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))
                                .lineLimit(columnCount == 2 ? 2 : 1)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)

                            Text(formatDuration(message.duration))
                                .font(.caption2)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))

                            if columnCount == 2 {
                                Text(timeAgo(from: message.createdAt))
                                    .font(.caption2)
                                    .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.8))
                            }
                        }
                        .padding(.horizontal, 8)

                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                selectionMode ?
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isSelected ? Color(red: 0.8, green: 0.7, blue: 1.0) : Color.clear, lineWidth: 3)
                : nil
            )
            .offset(x: columnCount == 1 && !selectionMode ? swipeOffset : 0)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .gesture(
                columnCount == 1 && !selectionMode ?
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            let translation = value.translation.width
                            // Limit swipe distance
                            if translation > 0 {
                                swipeOffset = min(swipeThreshold, translation * 0.6)
                            } else {
                                swipeOffset = max(-maxSwipe, translation * 0.6)
                            }
                        }
                        .onEnded { value in
                            let translation = value.translation.width
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if translation > swipeThreshold * 0.6 {
                                    // Snap to favorite action
                                    swipeOffset = swipeThreshold
                                } else if translation < -swipeThreshold * 0.6 {
                                    // Snap to share/delete actions
                                    swipeOffset = -maxSwipe
                                } else {
                                    swipeOffset = 0
                                }
                            }
                        }
                : nil
            )
            .onTapGesture {
                if swipeOffset != 0 {
                    withAnimation(.spring(response: 0.3)) {
                        swipeOffset = 0
                    }
                } else {
                    onTap()
                }
            }
            .onLongPressGesture(minimumDuration: 0.5, perform: onLongPress)

            // Favorite indicator (grid view only)
            if columnCount > 1 && message.isFavorite == true && !selectionMode {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.5))
                    .padding(8)
            }

            // Selection checkmark
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(columnCount == 1 ? .title2 : .title3)
                    .foregroundColor(isSelected ? Color(red: 0.8, green: 0.7, blue: 1.0) : .gray.opacity(0.5))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            Button(action: onToggleFavorite) {
                Label(message.isFavorite == true ? "Remove from Favorites" : "Add to Favorites", systemImage: message.isFavorite == true ? "heart.slash" : "heart")
            }

            Button(action: onShare) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive, action: { showingDeleteAlert = true }) {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Voice Memo?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This voice memo will be permanently deleted.")
        }
    }

    private var playButton: some View {
        ZStack {
            Circle()
                .fill(
                    isPlaying ?
                        Color(red: 0.9, green: 0.4, blue: 0.5) :
                        Color(red: 0.8, green: 0.7, blue: 1.0)
                )
                .frame(width: columnCount == 1 ? 50 : 44, height: columnCount == 1 ? 50 : 44)

            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: columnCount == 1 ? 20 : 18))
                .foregroundColor(.white)
                .offset(x: isPlaying ? 0 : 2)
        }
    }

    private var waveformView: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        isPlaying ?
                            Color(red: 0.9, green: 0.4, blue: 0.5) :
                            Color(red: 0.8, green: 0.7, blue: 1.0)
                    )
                    .frame(width: 3, height: waveformHeight(for: index))
            }
        }
        .frame(height: 20)
    }

    private func waveformHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [8, 16, 12, 20, 14, 18, 10]
        return heights[index % heights.count]
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 3600 {
            let minutes = Int(interval / 60)
            return minutes <= 1 ? "Just now" : "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if interval < 172800 {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Full Screen Voice Memo Player
struct FullScreenVoiceMemoPlayer: View {
    let memos: [VoiceMessage]
    @State var currentIndex: Int
    @ObservedObject var viewModel: VoiceMessagesViewModel
    let onDismiss: () -> Void

    @State private var playbackProgress: Double = 0
    @State private var playbackSpeed: Double = 1.0
    @State private var isDraggingProgress = false
    @GestureState private var dragOffset: CGFloat = 0
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var isPreparingShare = false

    init(memos: [VoiceMessage], initialIndex: Int, viewModel: VoiceMessagesViewModel, onDismiss: @escaping () -> Void) {
        self.memos = memos
        self._currentIndex = State(initialValue: initialIndex)
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    private var currentMemo: VoiceMessage? {
        guard currentIndex >= 0 && currentIndex < memos.count else { return nil }
        return memos[currentIndex]
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.15, blue: 0.35),
                    Color(red: 0.1, green: 0.08, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.down")
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    if let memo = currentMemo {
                        HStack(spacing: 20) {
                            // Share button
                            Button(action: {
                                shareMemo(memo)
                            }) {
                                if isPreparingShare {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                            }
                            .disabled(isPreparingShare)

                            // Favorite button
                            Button(action: {
                                Task {
                                    await viewModel.toggleFavorite(memo)
                                }
                            }) {
                                Image(systemName: memo.isFavorite == true ? "heart.fill" : "heart")
                                    .font(.title2)
                                    .foregroundColor(memo.isFavorite == true ? Color(red: 0.9, green: 0.4, blue: 0.5) : .white)
                            }
                        }
                    }
                }
                .padding()

                Spacer()

                if let memo = currentMemo {
                    // Large waveform visualization
                    HStack(spacing: 4) {
                        ForEach(0..<30, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.8, green: 0.7, blue: 1.0),
                                            Color(red: 0.6, green: 0.4, blue: 0.85)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 6, height: waveformHeight(for: index))
                                .opacity(Double(index) / 30.0 <= playbackProgress ? 1.0 : 0.4)
                        }
                    }
                    .frame(height: 120)
                    .padding(.horizontal, 20)

                    Spacer()

                    // Title and info
                    VStack(spacing: 8) {
                        Text(memo.title)
                            .font(.title2.weight(.bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        Text("From \(memo.fromUser)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))

                        Text(memo.createdAt, style: .date)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 40)

                    // Progress bar
                    VStack(spacing: 8) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.3))
                                    .frame(height: 6)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(red: 0.8, green: 0.7, blue: 1.0))
                                    .frame(width: geometry.size.width * playbackProgress, height: 6)
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isDraggingProgress = true
                                        playbackProgress = max(0, min(1, value.location.x / geometry.size.width))
                                    }
                                    .onEnded { _ in
                                        isDraggingProgress = false
                                        viewModel.seekTo(progress: playbackProgress)
                                    }
                            )
                        }
                        .frame(height: 6)

                        HStack {
                            Text(formatTime(memo.duration * playbackProgress))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text(formatTime(memo.duration))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 30)

                    // Playback controls
                    HStack(spacing: 40) {
                        // Skip back 15s
                        Button(action: { viewModel.skipBackward(seconds: 15) }) {
                            Image(systemName: "gobackward.15")
                                .font(.title)
                                .foregroundColor(.white)
                        }

                        // Previous
                        Button(action: {
                            if currentIndex > 0 {
                                currentIndex -= 1
                                playMemo()
                            }
                        }) {
                            Image(systemName: "backward.fill")
                                .font(.title2)
                                .foregroundColor(currentIndex > 0 ? .white : .white.opacity(0.3))
                        }
                        .disabled(currentIndex == 0)

                        // Play/Pause
                        Button(action: {
                            if viewModel.currentlyPlayingId == memo.id {
                                viewModel.togglePlayPause()
                            } else {
                                viewModel.playMessage(memo)
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.8, green: 0.7, blue: 1.0))
                                    .frame(width: 80, height: 80)

                                Image(systemName: viewModel.currentlyPlayingId == memo.id && viewModel.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(Color(red: 0.2, green: 0.15, blue: 0.35))
                                    .offset(x: viewModel.currentlyPlayingId == memo.id && viewModel.isPlaying ? 0 : 3)
                            }
                        }

                        // Next
                        Button(action: {
                            if currentIndex < memos.count - 1 {
                                currentIndex += 1
                                playMemo()
                            }
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.title2)
                                .foregroundColor(currentIndex < memos.count - 1 ? .white : .white.opacity(0.3))
                        }
                        .disabled(currentIndex >= memos.count - 1)

                        // Skip forward 15s
                        Button(action: { viewModel.skipForward(seconds: 15) }) {
                            Image(systemName: "goforward.15")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.top, 30)

                    // Speed control
                    HStack(spacing: 16) {
                        ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { speed in
                            Button(action: {
                                playbackSpeed = speed
                                viewModel.setPlaybackSpeed(speed)
                            }) {
                                Text("\(speed, specifier: speed == 1.0 || speed == 2.0 ? "%.0f" : "%.1f")x")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(playbackSpeed == speed ? .white : .white.opacity(0.5))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(playbackSpeed == speed ? Color(red: 0.6, green: 0.4, blue: 0.85) : Color.white.opacity(0.1))
                                    )
                            }
                        }
                    }
                    .padding(.top, 20)
                }

                Spacer()

                // Navigation indicator
                HStack(spacing: 6) {
                    ForEach(0..<min(memos.count, 10), id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? Color(red: 0.8, green: 0.7, blue: 1.0) : Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                    if memos.count > 10 {
                        Text("...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.width
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.width > threshold && currentIndex > 0 {
                        withAnimation {
                            currentIndex -= 1
                            playMemo()
                        }
                    } else if value.translation.width < -threshold && currentIndex < memos.count - 1 {
                        withAnimation {
                            currentIndex += 1
                            playMemo()
                        }
                    }
                }
        )
        .onAppear {
            playMemo()
        }
        .onReceive(viewModel.$playbackProgress) { progress in
            if !isDraggingProgress {
                playbackProgress = progress
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if !shareItems.isEmpty {
                ShareSheet(items: shareItems)
            }
        }
    }

    private func playMemo() {
        if let memo = currentMemo {
            viewModel.playMessage(memo)
        }
    }

    private func shareMemo(_ memo: VoiceMessage) {
        guard let url = URL(string: memo.audioURL) else { return }

        isPreparingShare = true

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "\(memo.title.replacingOccurrences(of: " ", with: "_")).m4a"
                let tempFileURL = tempDir.appendingPathComponent(fileName)

                try data.write(to: tempFileURL)

                await MainActor.run {
                    shareItems = [tempFileURL]
                    showingShareSheet = true
                    isPreparingShare = false
                }
            } catch {
                print("Error preparing share: \(error)")
                await MainActor.run {
                    isPreparingShare = false
                }
            }
        }
    }

    private func waveformHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [30, 60, 45, 80, 55, 70, 40, 90, 65, 50, 75, 45, 85, 55, 60, 70, 50, 80, 45, 65, 55, 75, 40, 90, 60, 50, 70, 45, 80, 55]
        return heights[index % heights.count]
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Voice Recorder View
struct VoiceRecorderView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var recorder = AudioRecorder()
    @State private var title = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingQualityPicker = false
    let fromUser: String

    let onSave: (Data, TimeInterval, String) async -> Void

    var body: some View {
        NavigationView {
            ZStack {
                backgroundGradient
                mainContent
            }
            .navigationTitle("Record Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if recorder.isRecording {
                            recorder.stopRecording()
                        }
                        dismiss()
                    }
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingQualityPicker) {
                RecordingQualityPicker(selectedQuality: $recorder.quality)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.9, blue: 1.0),
                Color.white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: 24) {
            headerSection
            titleField
            qualitySelector
            waveformVisualization
            timerDisplay
            recordingControls
            postRecordingActions
            Spacer()
        }
        .padding()
    }

    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            Text("Recording as")
                .font(.subheadline)
                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
            Text(fromUser)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
        }
        .padding(.top)
    }

    // MARK: - Title Field
    private var titleField: some View {
        TextField("Message title (e.g., 'Good morning!')", text: $title)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.horizontal)
            .disabled(recorder.isRecording)
    }

    // MARK: - Quality Selector
    @ViewBuilder
    private var qualitySelector: some View {
        if !recorder.isRecording && !recorder.hasRecording {
            Button(action: { showingQualityPicker = true }) {
                HStack(spacing: 8) {
                    Image(systemName: recorder.quality.icon)
                        .font(.subheadline)
                    Text(recorder.quality.rawValue)
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .foregroundColor(Color(red: 0.5, green: 0.35, blue: 0.75))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                )
            }
        }
    }

    // MARK: - Waveform Visualization
    private var waveformVisualization: some View {
        VStack(spacing: 8) {
            waveformBars
            recordingStatusIndicator
        }
    }

    private var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach(Array(recorder.audioLevels.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(waveformGradient)
                    .frame(width: 6, height: max(8, level * 80))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(height: 90)
        .padding(.horizontal)
    }

    private var waveformGradient: LinearGradient {
        recorder.isRecording && !recorder.isPaused
            ? LinearGradient(
                colors: [
                    Color(red: 0.9, green: 0.4, blue: 0.5),
                    Color(red: 0.8, green: 0.7, blue: 1.0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            : LinearGradient(
                colors: [Color(red: 0.8, green: 0.7, blue: 1.0)],
                startPoint: .bottom,
                endPoint: .top
            )
    }

    @ViewBuilder
    private var recordingStatusIndicator: some View {
        if recorder.isRecording {
            HStack(spacing: 8) {
                Circle()
                    .fill(recorder.isPaused ? Color.orange : Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(recorder.isPaused ? 1 : (recorder.recordingTime.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.3))
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: recorder.recordingTime)

                Text(recorder.isPaused ? "Paused" : "Recording")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(recorder.isPaused ? .orange : .red)
            }
        }
    }

    // MARK: - Timer Display
    private var timerDisplay: some View {
        Text(formatTime(recorder.recordingTime))
            .font(.system(size: 56, weight: .light, design: .rounded))
            .monospacedDigit()
            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
    }

    // MARK: - Recording Controls
    private var recordingControls: some View {
        HStack(spacing: 30) {
            pauseResumeButton
            mainRecordButton
            cancelRecordingButton
        }
    }

    @ViewBuilder
    private var pauseResumeButton: some View {
        if recorder.isRecording {
            Button(action: {
                if recorder.isPaused {
                    recorder.resumeRecording()
                } else {
                    recorder.pauseRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                        .frame(width: 56, height: 56)

                    Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
            }
        }
    }

    private var mainRecordButton: some View {
        Button(action: {
            if recorder.isRecording {
                recorder.stopRecording()
            } else {
                recorder.startRecording()
            }
        }) {
            ZStack {
                Circle()
                    .fill(mainRecordButtonFill)
                    .frame(width: 80, height: 80)
                    .shadow(color: recorder.isRecording ? Color.red.opacity(0.4) : Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.4), radius: 10)

                if recorder.isRecording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 35))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private var mainRecordButtonFill: some ShapeStyle {
        recorder.isRecording
            ? AnyShapeStyle(Color.red)
            : AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.7, green: 0.45, blue: 0.95),
                    Color(red: 0.55, green: 0.35, blue: 0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
    }

    @ViewBuilder
    private var cancelRecordingButton: some View {
        if recorder.isRecording {
            Button(action: {
                recorder.stopRecording()
                recorder.deleteRecording()
            }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                        .frame(width: 56, height: 56)

                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.red.opacity(0.8))
                }
            }
        }
    }

    // MARK: - Post Recording Actions
    @ViewBuilder
    private var postRecordingActions: some View {
        if recorder.hasRecording && !recorder.isRecording {
            VStack(spacing: 16) {
                recordingCompleteIndicator
                saveDiscardButtons
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var recordingCompleteIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Recording complete")
                .font(.subheadline)
                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
            Text("(\(formatTime(recorder.recordingDuration)))")
                .font(.caption)
                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.green.opacity(0.1))
        )
    }

    private var saveDiscardButtons: some View {
        HStack(spacing: 16) {
            discardButton
            saveButton
        }
    }

    private var discardButton: some View {
        Button(action: {
            recorder.deleteRecording()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                Text("Discard")
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(.red)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
            )
        }
    }

    private var saveButton: some View {
        Button(action: {
            Task {
                if let data = recorder.audioData {
                    await onSave(data, recorder.recordingDuration, title.isEmpty ? "Voice Note" : title)
                    dismiss()
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                Text("Save")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.7, green: 0.45, blue: 0.95),
                        Color(red: 0.55, green: 0.35, blue: 0.85)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
        }
    }

    // MARK: - Helpers
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Recording Quality Picker
struct RecordingQualityPicker: View {
    @Binding var selectedQuality: RecordingQuality
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(RecordingQuality.allCases, id: \.self) { quality in
                        Button(action: {
                            selectedQuality = quality
                            dismiss()
                        }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(selectedQuality == quality
                                            ? Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.15)
                                            : Color(red: 0.95, green: 0.93, blue: 0.98))
                                        .frame(width: 50, height: 50)

                                    Image(systemName: quality.icon)
                                        .font(.title3)
                                        .foregroundColor(selectedQuality == quality
                                            ? Color(red: 0.6, green: 0.4, blue: 0.85)
                                            : Color(red: 0.5, green: 0.4, blue: 0.7))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(quality.rawValue)
                                        .font(.headline)
                                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                                    Text(quality.description)
                                        .font(.caption)
                                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                                }

                                Spacer()

                                if selectedQuality == quality {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white)
                                    .shadow(color: selectedQuality == quality
                                        ? Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.2)
                                        : Color.black.opacity(0.05),
                                        radius: selectedQuality == quality ? 8 : 4,
                                        x: 0,
                                        y: 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedQuality == quality
                                        ? Color(red: 0.6, green: 0.4, blue: 0.85).opacity(0.5)
                                        : Color.clear,
                                        lineWidth: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .background(Color(red: 0.96, green: 0.94, blue: 0.98).ignoresSafeArea())
            .navigationTitle("Recording Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
            }
        }
    }
}

// MARK: - Date Filter Sheet
struct VoiceMemoDateFilterSheet: View {
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

// MARK: - Move to Folder Sheet
struct VoiceMemoMoveToFolderSheet: View {
    let folders: [VoiceMemoFolder]
    let onSelectFolder: (String) -> Void
    let onRemoveFromFolder: () -> Void
    let onCreateFolder: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
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

// MARK: - View Model
class VoiceMessagesViewModel: ObservableObject {
    @Published var voiceMessages: [VoiceMessage] = []
    @Published var folders: [VoiceMemoFolder] = []
    @Published var currentlyPlayingId: String?
    @Published var currentlyPlayingMessage: VoiceMessage?
    @Published var isPlaying: Bool = false
    @Published var playbackProgress: Double = 0

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private let firebaseManager = FirebaseManager.shared

    init() {
        loadVoiceMessages()
        loadFolders()
    }

    func loadVoiceMessages() {
        Task {
            for try await messages in firebaseManager.getVoiceMessages() {
                await MainActor.run {
                    self.voiceMessages = messages
                }
            }
        }
    }

    func loadFolders() {
        Task {
            for try await folders in firebaseManager.getVoiceMemoFolders() {
                await MainActor.run {
                    self.folders = folders
                }
            }
        }
    }

    func uploadVoiceMessage(audioData: Data, title: String, duration: TimeInterval, fromUser: String) async {
        do {
            _ = try await firebaseManager.uploadVoiceMessage(
                audioData: audioData,
                title: title,
                duration: duration,
                fromUser: fromUser
            )
        } catch {
            print("Error uploading voice message: \(error)")
        }
    }

    func playMessage(_ message: VoiceMessage) {
        guard let url = URL(string: message.audioURL) else { return }

        // If same message, toggle play/pause
        if currentlyPlayingId == message.id {
            togglePlayPause()
            return
        }

        // Stop current playback
        stopPlayback()

        currentlyPlayingId = message.id
        currentlyPlayingMessage = message

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                await MainActor.run {
                    do {
                        audioPlayer = try AVAudioPlayer(data: data)
                        audioPlayer?.play()
                        isPlaying = true
                        startProgressTimer()
                    } catch {
                        print("Error playing audio: \(error)")
                    }
                }
            } catch {
                print("Error downloading audio: \(error)")
            }
        }
    }

    func togglePlayPause() {
        if isPlaying {
            audioPlayer?.pause()
            progressTimer?.invalidate()
        } else {
            audioPlayer?.play()
            startProgressTimer()
        }
        isPlaying.toggle()
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        progressTimer?.invalidate()
        currentlyPlayingId = nil
        currentlyPlayingMessage = nil
        isPlaying = false
        playbackProgress = 0
    }

    func seekTo(progress: Double) {
        guard let player = audioPlayer else { return }
        player.currentTime = player.duration * progress
    }

    func skipForward(seconds: Double) {
        guard let player = audioPlayer else { return }
        player.currentTime = min(player.duration, player.currentTime + seconds)
    }

    func skipBackward(seconds: Double) {
        guard let player = audioPlayer else { return }
        player.currentTime = max(0, player.currentTime - seconds)
    }

    func setPlaybackSpeed(_ speed: Double) {
        audioPlayer?.rate = Float(speed)
        audioPlayer?.enableRate = true
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            Task { @MainActor in
                self.playbackProgress = player.currentTime / player.duration
                if player.currentTime >= player.duration {
                    self.stopPlayback()
                }
            }
        }
    }

    func toggleFavorite(_ message: VoiceMessage) async {
        guard let id = message.id else { return }
        let newState = !(message.isFavorite ?? false)
        try? await firebaseManager.toggleVoiceMemoFavorite(id, isFavorite: newState)
    }

    func batchToggleFavorites(_ ids: [String], isFavorite: Bool) async throws {
        try await firebaseManager.batchToggleVoiceMemoFavorites(ids, isFavorite: isFavorite)
    }

    func batchUpdateFolders(_ ids: [String], folderId: String?) async throws {
        try await firebaseManager.batchUpdateVoiceMemoFolders(ids, folderId: folderId)
    }

    func createFolder(name: String, forUser: String) async throws -> String {
        return try await firebaseManager.createVoiceMemoFolder(name: name, forUser: forUser)
    }

    func deleteFolder(_ folder: VoiceMemoFolder) async throws {
        try await firebaseManager.deleteVoiceMemoFolder(folder)
    }

    func deleteMessage(_ message: VoiceMessage) async {
        do {
            try await firebaseManager.deleteVoiceMessage(message)
        } catch {
            print("Error deleting message: \(error)")
        }
    }
}

// MARK: - Recording Quality
enum RecordingQuality: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case lossless = "Lossless"

    var description: String {
        switch self {
        case .low: return "64 kbps - Smaller files"
        case .medium: return "128 kbps - Balanced"
        case .high: return "256 kbps - Better quality"
        case .lossless: return "Uncompressed - Best quality"
        }
    }

    var icon: String {
        switch self {
        case .low: return "waveform.badge.minus"
        case .medium: return "waveform"
        case .high: return "waveform.badge.plus"
        case .lossless: return "waveform.circle.fill"
        }
    }

    var settings: [String: Any] {
        switch self {
        case .low:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22050,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.low.rawValue,
                AVEncoderBitRateKey: 64000
            ]
        case .medium:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                AVEncoderBitRateKey: 128000
            ]
        case .high:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 256000
            ]
        case .lossless:
            return [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        }
    }

    var fileExtension: String {
        switch self {
        case .lossless: return "wav"
        default: return "m4a"
        }
    }
}

// MARK: - Audio Recorder
class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingTime: TimeInterval = 0
    @Published var hasRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevels: [CGFloat] = Array(repeating: 0.1, count: 30)
    @Published var currentLevel: CGFloat = 0
    @Published var quality: RecordingQuality = .high

    var audioRecorder: AVAudioRecorder?
    var audioData: Data?
    private var timer: Timer?
    private var levelTimer: Timer?
    private var levelHistory: [CGFloat] = []

    override init() {
        super.init()
        setupAudioSession()
    }

    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)
    }

    func startRecording() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording.\(quality.fileExtension)")

        // Remove existing file if any
        try? FileManager.default.removeItem(at: url)

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: quality.settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isRecording = true
            isPaused = false
            recordingTime = 0
            levelHistory = []
            audioLevels = Array(repeating: 0.1, count: 30)

            startTimers()
        } catch {
            print("Error starting recording: \(error)")
        }
    }

    func pauseRecording() {
        guard isRecording && !isPaused else { return }
        audioRecorder?.pause()
        isPaused = true
        timer?.invalidate()
        levelTimer?.invalidate()
    }

    func resumeRecording() {
        guard isRecording && isPaused else { return }
        audioRecorder?.record()
        isPaused = false
        startTimers()
    }

    private func startTimers() {
        timer?.invalidate()
        levelTimer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingTime += 0.1
        }

        // Audio level metering timer
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateAudioLevels()
        }
    }

    private func updateAudioLevels() {
        guard let recorder = audioRecorder, isRecording && !isPaused else { return }

        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)

        // Convert dB to linear scale (0-1)
        // Average power typically ranges from -160 to 0 dB
        let normalizedLevel = max(0, (averagePower + 60) / 60)
        let level = CGFloat(pow(10, normalizedLevel) - 1) / 9 // Logarithmic scaling for better visualization

        DispatchQueue.main.async {
            self.currentLevel = min(1.0, max(0.05, level * 1.5))

            // Update waveform history
            self.levelHistory.append(self.currentLevel)
            if self.levelHistory.count > 30 {
                self.levelHistory.removeFirst()
            }

            // Smooth the levels for display
            self.audioLevels = self.levelHistory.count >= 30
                ? self.levelHistory
                : Array(repeating: 0.1, count: 30 - self.levelHistory.count) + self.levelHistory
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()
        levelTimer?.invalidate()

        isRecording = false
        isPaused = false
        hasRecording = true
        recordingDuration = recordingTime

        if let url = audioRecorder?.url {
            audioData = try? Data(contentsOf: url)
        }
    }

    func deleteRecording() {
        if let url = audioRecorder?.url {
            try? FileManager.default.removeItem(at: url)
        }
        hasRecording = false
        recordingTime = 0
        recordingDuration = 0
        audioData = nil
        audioLevels = Array(repeating: 0.1, count: 30)
        levelHistory = []
    }
}

#Preview {
    VoiceMessagesView()
}
