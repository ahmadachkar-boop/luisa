import SwiftUI
import AVFoundation

// MARK: - Sort Options
enum VoiceMemoSortOption: String, CaseIterable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case recentlyAdded = "Recently Added"
    case longestFirst = "Longest First"
    case shortestFirst = "Shortest First"

    var icon: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        case .recentlyAdded: return "clock.arrow.circlepath"
        case .longestFirst: return "timer"
        case .shortestFirst: return "timer"
        }
    }
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
    @State private var selectedMessageForPlayback: VoiceMessage?

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

    // Filtered and sorted messages
    private var filteredMessages: [VoiceMessage] {
        var messages = viewModel.voiceMessages

        // Apply date filter
        if let startDate = filterStartDate {
            messages = messages.filter { message in
                return message.createdAt >= Calendar.current.startOfDay(for: startDate)
            }
        }
        if let endDate = filterEndDate {
            messages = messages.filter { message in
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate))!
                return message.createdAt < endOfDay
            }
        }

        // Apply sorting
        switch sortOption {
        case .newestFirst:
            messages.sort { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            messages.sort { $0.createdAt < $1.createdAt }
        case .recentlyAdded:
            messages.sort { $0.createdAt > $1.createdAt }
        case .longestFirst:
            messages.sort { $0.duration > $1.duration }
        case .shortestFirst:
            messages.sort { $0.duration < $1.duration }
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
            case .newestFirst, .recentlyAdded, .longestFirst, .shortestFirst:
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

                if viewModel.voiceMessages.isEmpty {
                    emptyStateView
                } else {
                    contentView
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
                        Button(action: deleteSelectedMessages) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .disabled(selectedMessageIds.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingRecorder) {
                VoiceRecorderView { audioData, duration, title in
                    await viewModel.uploadVoiceMessage(
                        audioData: audioData,
                        title: title,
                        duration: duration
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

    // MARK: - Content View
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Expandable header
                expandableHeader
                    .padding(.horizontal)
                    .padding(.top, 4)

                // Navigation bar
                navigationBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Active filters indicator
                if hasDateFilter || sortOption != .newestFirst {
                    activeFiltersBar
                        .padding(.horizontal)
                        .padding(.top, 8)
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
    }

    // MARK: - Expandable Header
    private var expandableHeader: some View {
        VStack(spacing: 0) {
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
        HStack(spacing: 12) {
            Text("Voice Memos")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

            Spacer()

            Text("\(filteredMessages.count) memo\(filteredMessages.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
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
                    // Month header
                    monthHeaderView(monthGroup: monthGroup)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(monthGroup.messages) { message in
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
                                        viewModel.playMessage(message)
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
                                onDelete: {
                                    Task {
                                        await viewModel.deleteMessage(message)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.top, 8)
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
    let onDelete: () -> Void

    @State private var showingDeleteAlert = false

    private var cellHeight: CGFloat {
        columnCount == 1 ? 100 : (columnCount == 2 ? 140 : 120)
    }

    private var cornerRadius: CGFloat {
        columnCount == 1 ? 16 : (columnCount == 2 ? 16 : 12)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: columnCount == 1 ? 0 : 8) {
                if columnCount == 1 {
                    // Horizontal layout for single column
                    HStack(spacing: 15) {
                        // Play button
                        playButton

                        // Info
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

                                Text(message.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                            }
                        }

                        Spacer()

                        if !selectionMode {
                            Button(action: { showingDeleteAlert = true }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                        }
                    }
                    .padding()
                } else {
                    // Vertical layout for grid
                    Spacer()

                    // Waveform visualization
                    waveformView

                    Spacer()

                    // Play button overlay
                    playButton

                    Spacer()

                    // Info at bottom
                    VStack(spacing: 2) {
                        Text(message.title)
                            .font(columnCount == 2 ? .subheadline : .caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))
                            .lineLimit(1)

                        Text(formatDuration(message.duration))
                            .font(.caption2)
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    }
                    .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            )
            .overlay(
                selectionMode ?
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isSelected ? Color(red: 0.8, green: 0.7, blue: 1.0) : Color.clear, lineWidth: 3)
                : nil
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.5, perform: onLongPress)

            // Selection checkmark
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(columnCount == 1 ? .title2 : .title3)
                    .foregroundColor(isSelected ? Color(red: 0.8, green: 0.7, blue: 1.0) : .gray.opacity(0.5))
                    .padding(10)
                    .allowsHitTesting(false)
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
}

// MARK: - Voice Recorder View
struct VoiceRecorderView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var recorder = AudioRecorder()
    @State private var title = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    let onSave: (Data, TimeInterval, String) async -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                TextField("Message title (e.g., 'Good morning!')", text: $title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                // Waveform animation
                HStack(spacing: 4) {
                    ForEach(0..<20, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.8, green: 0.7, blue: 1.0))
                            .frame(width: 3, height: recorder.isRecording ? CGFloat.random(in: 10...60) : 10)
                            .animation(.easeInOut(duration: 0.3).repeatForever(), value: recorder.isRecording)
                    }
                }
                .frame(height: 60)

                if recorder.isRecording {
                    Text(formatTime(recorder.recordingTime))
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .monospacedDigit()
                }

                // Record button
                Button(action: {
                    if recorder.isRecording {
                        recorder.stopRecording()
                    } else {
                        recorder.startRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(recorder.isRecording ? Color.red : Color(red: 0.8, green: 0.7, blue: 1.0))
                            .frame(width: 80, height: 80)

                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 35))
                            .foregroundColor(.white)
                    }
                }

                if recorder.hasRecording {
                    Button("Save Recording") {
                        Task {
                            if let data = recorder.audioData {
                                await onSave(data, recorder.recordingDuration, title.isEmpty ? "Voice Note" : title)
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.8, green: 0.7, blue: 1.0))

                    Button("Discard", role: .destructive) {
                        recorder.deleteRecording()
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Record Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
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

// MARK: - View Model
class VoiceMessagesViewModel: ObservableObject {
    @Published var voiceMessages: [VoiceMessage] = []
    @Published var currentlyPlayingId: String?

    private var audioPlayer: AVAudioPlayer?
    private let firebaseManager = FirebaseManager.shared

    init() {
        loadVoiceMessages()
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

    func uploadVoiceMessage(audioData: Data, title: String, duration: TimeInterval) async {
        do {
            _ = try await firebaseManager.uploadVoiceMessage(
                audioData: audioData,
                title: title,
                duration: duration,
                fromUser: "You"
            )
        } catch {
            print("Error uploading voice message: \(error)")
        }
    }

    func playMessage(_ message: VoiceMessage) {
        guard let url = URL(string: message.audioURL) else { return }

        if currentlyPlayingId == message.id {
            audioPlayer?.pause()
            currentlyPlayingId = nil
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                await MainActor.run {
                    do {
                        audioPlayer = try AVAudioPlayer(data: data)
                        audioPlayer?.play()
                        currentlyPlayingId = message.id
                    } catch {
                        print("Error playing audio: \(error)")
                    }
                }
            } catch {
                print("Error downloading audio: \(error)")
            }
        }
    }

    func deleteMessage(_ message: VoiceMessage) async {
        do {
            try await firebaseManager.deleteVoiceMessage(message)
        } catch {
            print("Error deleting message: \(error)")
        }
    }
}

// MARK: - Audio Recorder
class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var hasRecording = false
    @Published var recordingDuration: TimeInterval = 0

    var audioRecorder: AVAudioRecorder?
    var audioData: Data?
    private var timer: Timer?

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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording.m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()

            isRecording = true
            recordingTime = 0

            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.recordingTime += 0.1
            }
        } catch {
            print("Error starting recording: \(error)")
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()

        isRecording = false
        hasRecording = true
        recordingDuration = recordingTime

        if let url = audioRecorder?.url {
            audioData = try? Data(contentsOf: url)
        }
    }

    func deleteRecording() {
        hasRecording = false
        recordingTime = 0
        recordingDuration = 0
        audioData = nil
    }
}

#Preview {
    VoiceMessagesView()
}
