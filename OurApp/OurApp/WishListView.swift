import SwiftUI

// MARK: - Sort Options
enum WishSortOption: String, CaseIterable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case alphabetical = "A-Z"
    case category = "By Category"
}

// MARK: - Filter Options
enum WishFilterOption: String, CaseIterable {
    case all = "All"
    case pending = "Pending"
    case completed = "Completed"
}

struct WishListView: View {
    @StateObject private var viewModel = WishListViewModel()
    @State private var showingAddItem = false
    @State private var showingExpandedHeader = false
    @State private var showingSettings = false

    // Search
    @State private var searchText = ""

    // Filter & Sort
    @State private var sortOption: WishSortOption = .newestFirst
    @State private var filterOption: WishFilterOption = .all
    @State private var selectedCategory: String? = nil

    // View options
    @State private var columnCount: Int = 1
    @GestureState private var magnificationScale: CGFloat = 1.0

    // Categories expanded
    @State private var isCategoriesExpanded = false

    private var filteredItems: [WishListItem] {
        var items = viewModel.items

        // Search filter
        if !searchText.isEmpty {
            items = items.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Status filter
        switch filterOption {
        case .all:
            break
        case .pending:
            items = items.filter { !$0.isCompleted }
        case .completed:
            items = items.filter { $0.isCompleted }
        }

        // Category filter
        if let category = selectedCategory {
            items = items.filter { $0.category == category }
        }

        // Sort
        switch sortOption {
        case .newestFirst:
            items = items.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            items = items.sorted { $0.createdAt < $1.createdAt }
        case .alphabetical:
            items = items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .category:
            items = items.sorted { $0.category < $1.category }
        }

        return items
    }

    private var hasActiveFilters: Bool {
        filterOption != .all || selectedCategory != nil || !searchText.isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.88, green: 0.88, blue: 1.0),
                        Color(red: 0.92, green: 0.92, blue: 1.0),
                        Color(red: 0.96, green: 0.96, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if viewModel.items.isEmpty && viewModel.categories.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .sheet(isPresented: $showingAddItem) {
                AddWishListItemView(categories: viewModel.categories) { item in
                    await viewModel.addItem(item)
                }
            }
            .sheet(isPresented: $showingSettings) {
                WishListSettingsView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(Color(red: 0.7, green: 0.6, blue: 0.9))

            Text("No wishes yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

            Text("Add places and experiences you want to share together")
                .font(.subheadline)
                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: { showingAddItem = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add First Wish")
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

            Button(action: { showingSettings = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                    Text("Create Categories First")
                }
                .font(.subheadline)
                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content View
    private var contentView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Top anchor
                    Color.clear
                        .frame(height: 0)
                        .id("wishlist-top-anchor")

                    // Expandable header
                    expandableHeader
                        .padding(.horizontal)
                        .padding(.top, 4)

                    // Navigation bar
                    navigationBar
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Active filters indicator
                    if hasActiveFilters {
                        activeFiltersBar
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Categories section
                    if !viewModel.categories.isEmpty {
                        categoriesSection
                            .padding(.top, 12)
                    }

                    // Wishes grid/list
                    if filteredItems.isEmpty {
                        emptySearchResultsView
                    } else {
                        wishesGridView
                    }
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
                if showingExpandedHeader && newValue > 1 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showingExpandedHeader = false
                        scrollProxy.scrollTo("wishlist-top-anchor", anchor: .top)
                    }
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
                        if value < 0.8 && columnCount < 2 {
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
                    // Search bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))

                        TextField("Search wishes...", text: $searchText)
                            .font(.body)
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                    )

                    // Quick actions row
                    HStack(spacing: 12) {
                        // Add Wish
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showingExpandedHeader = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showingAddItem = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body)
                                Text("Add")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
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

                        // Filter
                        Menu {
                            ForEach(WishFilterOption.allCases, id: \.self) { option in
                                Button(action: { filterOption = option }) {
                                    HStack {
                                        Text(option.rawValue)
                                        if filterOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.body)
                                Text("Filter")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(Color(red: 0.5, green: 0.35, blue: 0.75))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                            )
                        }

                        // Sort
                        Menu {
                            ForEach(WishSortOption.allCases, id: \.self) { option in
                                Button(action: { sortOption = option }) {
                                    HStack {
                                        Text(option.rawValue)
                                        if sortOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.arrow.down.circle")
                                    .font(.body)
                                Text("Sort")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(Color(red: 0.5, green: 0.35, blue: 0.75))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                            )
                        }

                        Spacer()

                        // Settings
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showingExpandedHeader = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showingSettings = true
                            }
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.body)
                                .foregroundColor(Color(red: 0.5, green: 0.35, blue: 0.75))
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
                                )
                        }
                    }

                    // View toggle
                    HStack(spacing: 12) {
                        Text("View:")
                            .font(.subheadline)
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))

                        Button(action: { withAnimation { columnCount = 1 } }) {
                            Image(systemName: "list.bullet")
                                .font(.body)
                                .foregroundColor(columnCount == 1 ? .white : Color(red: 0.5, green: 0.35, blue: 0.75))
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(columnCount == 1 ? Color(red: 0.6, green: 0.4, blue: 0.85) : Color(red: 0.95, green: 0.92, blue: 1.0))
                                )
                        }

                        Button(action: { withAnimation { columnCount = 2 } }) {
                            Image(systemName: "square.grid.2x2")
                                .font(.body)
                                .foregroundColor(columnCount == 2 ? .white : Color(red: 0.5, green: 0.35, blue: 0.75))
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(columnCount == 2 ? Color(red: 0.6, green: 0.4, blue: 0.85) : Color(red: 0.95, green: 0.92, blue: 1.0))
                                )
                        }

                        Spacer()
                    }
                }
                .padding(16)
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
            Text("Wish List")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

            Spacer()

            Text("\(filteredItems.count) wish\(filteredItems.count == 1 ? "" : "es")")
                .font(.subheadline)
                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
        }
    }

    // MARK: - Active Filters Bar
    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !searchText.isEmpty {
                    filterChip(text: "Search: \(searchText)", onRemove: { searchText = "" })
                }

                if filterOption != .all {
                    filterChip(text: filterOption.rawValue, onRemove: { filterOption = .all })
                }

                if let category = selectedCategory {
                    filterChip(text: category, onRemove: { selectedCategory = nil })
                }

                Button(action: {
                    searchText = ""
                    filterOption = .all
                    selectedCategory = nil
                }) {
                    Text("Clear All")
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                }
            }
        }
    }

    private func filterChip(text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(red: 0.95, green: 0.92, blue: 1.0))
        )
    }

    // MARK: - Categories Section
    private var categoriesSection: some View {
        VStack(spacing: 0) {
            // Expandable toggle
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isCategoriesExpanded.toggle()
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
                        Text("Categories")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                        Text("\(viewModel.categories.count) categor\(viewModel.categories.count == 1 ? "y" : "ies")")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    }

                    Spacer()

                    if selectedCategory != nil {
                        Text("Filtered")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.6, green: 0.4, blue: 0.85))
                            )
                    }

                    Image(systemName: isCategoriesExpanded ? "chevron.up" : "chevron.down")
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
            .padding(.horizontal)

            // Expanded categories
            if isCategoriesExpanded {
                VStack(spacing: 8) {
                    // All wishes option
                    Button(action: { selectedCategory = nil }) {
                        HStack(spacing: 10) {
                            Image(systemName: "star.fill")
                                .font(.subheadline)
                                .foregroundColor(Color(red: 0.9, green: 0.7, blue: 0.3))

                            Text("All Wishes")
                                .font(.subheadline)
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                            Spacer()

                            Text("\(viewModel.items.count)")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color(red: 0.9, green: 0.7, blue: 0.3).opacity(0.15))
                                )

                            if selectedCategory == nil {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedCategory == nil ? Color(red: 0.95, green: 0.92, blue: 1.0) : Color.white)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Category list
                    ForEach(viewModel.categories) { category in
                        let count = viewModel.items.filter { $0.category == category.name }.count
                        Button(action: { selectedCategory = category.name }) {
                            HStack(spacing: 10) {
                                Image(systemName: category.icon)
                                    .font(.subheadline)
                                    .foregroundColor(Color(hex: category.colorHex) ?? Color(red: 0.6, green: 0.4, blue: 0.85))

                                Text(category.name)
                                    .font(.subheadline)
                                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                                Spacer()

                                if count > 0 {
                                    Text("\(count)")
                                        .font(.caption)
                                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill((Color(hex: category.colorHex) ?? Color(red: 0.6, green: 0.4, blue: 0.85)).opacity(0.15))
                                        )
                                }

                                if selectedCategory == category.name {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedCategory == category.name ? Color(red: 0.95, green: 0.92, blue: 1.0) : Color.white)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Empty Search Results
    private var emptySearchResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.8))

            Text("No wishes found")
                .font(.headline)
                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Wishes Grid View
    private var wishesGridView: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount),
            spacing: 12
        ) {
            ForEach(filteredItems) { item in
                WishListItemCard(
                    item: item,
                    category: viewModel.categories.first { $0.name == item.category },
                    isCompact: columnCount > 1,
                    onToggleComplete: {
                        Task {
                            await viewModel.toggleComplete(item)
                        }
                    },
                    onDelete: {
                        Task {
                            await viewModel.deleteItem(item)
                        }
                    }
                )
            }
        }
        .padding()
    }
}

// MARK: - Wish List Item Card
struct WishListItemCard: View {
    let item: WishListItem
    let category: WishCategory?
    let isCompact: Bool
    let onToggleComplete: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteAlert = false

    private var categoryColor: Color {
        if let hex = category?.colorHex, let color = Color(hex: hex) {
            return color
        }
        return Color(red: 0.6, green: 0.4, blue: 0.85)
    }

    private var categoryIcon: String {
        category?.icon ?? "sparkles"
    }

    var body: some View {
        if isCompact {
            compactCard
        } else {
            fullCard
        }
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: categoryIcon)
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(
                            item.isCompleted ?
                                LinearGradient(colors: [Color.green.opacity(0.7), Color.green.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                LinearGradient(colors: [categoryColor, categoryColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    )

                Spacer()

                Button(action: onToggleComplete) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(item.isCompleted ? .green : Color(red: 0.6, green: 0.4, blue: 0.8))
                }
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))
                .strikethrough(item.isCompleted)
                .lineLimit(2)

            if !item.description.isEmpty {
                Text(item.description)
                    .font(.caption)
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    .lineLimit(2)
            }

            Spacer()

            Text(item.category)
                .font(.caption2)
                .foregroundColor(categoryColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(categoryColor.opacity(0.15))
                .cornerRadius(6)
        }
        .padding(12)
        .frame(minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .contextMenu {
            Button(action: onToggleComplete) {
                Label(item.isCompleted ? "Mark as Pending" : "Mark as Complete", systemImage: item.isCompleted ? "circle" : "checkmark.circle")
            }
            Button(role: .destructive, action: { showingDeleteAlert = true }) {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Wish?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This will remove '\(item.title)' from your wish list")
        }
    }

    private var fullCard: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: categoryIcon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                    Circle().fill(
                        item.isCompleted ?
                            LinearGradient(colors: [Color.green.opacity(0.7), Color.green.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LinearGradient(colors: [categoryColor, categoryColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                )
                .shadow(radius: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))
                        .strikethrough(item.isCompleted)

                    if item.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.subheadline)
                        .foregroundColor(Color(red: 0.35, green: 0.25, blue: 0.55))
                        .lineLimit(2)
                }

                Text(item.category)
                    .font(.caption)
                    .foregroundColor(categoryColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(categoryColor.opacity(0.15))
                    .cornerRadius(8)

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                    Text(item.addedBy)
                        .font(.caption2)
                }
                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.8))
                .padding(.top, 2)

                if item.isCompleted, let completedDate = item.completedDate {
                    Text("Completed \(completedDate, style: .date)")
                        .font(.caption2)
                        .italic()
                        .foregroundColor(.green.opacity(0.8))
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: onToggleComplete) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(item.isCompleted ? .green : Color(red: 0.6, green: 0.4, blue: 0.8))
                }

                Button(action: { showingDeleteAlert = true }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red.opacity(0.7))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .alert("Delete Wish?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This will remove '\(item.title)' from your wish list")
        }
    }
}

// MARK: - Add Wish List Item View
struct AddWishListItemView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var selectedCategory = ""

    let categories: [WishCategory]
    let onSave: (WishListItem) async -> Void

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title (e.g., 'Paris', 'Cooking Class')", text: $title)
                        .font(.body)

                    TextField("Why do you want to do this?", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body)
                } header: {
                    Text("Wish Details")
                }

                Section {
                    if categories.isEmpty {
                        Text("No categories yet. Create some in Settings.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Picker("Category", selection: $selectedCategory) {
                            Text("Select a category").tag("")
                            ForEach(categories) { category in
                                HStack {
                                    Image(systemName: category.icon)
                                    Text(category.name)
                                }
                                .tag(category.name)
                            }
                        }
                        .tint(Color(red: 0.6, green: 0.4, blue: 0.8))
                    }
                } header: {
                    Text("Category")
                }
            }
            .navigationTitle("Add Wish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        Task {
                            let item = WishListItem(
                                title: title,
                                description: description,
                                addedBy: UserIdentityManager.shared.currentUserName,
                                createdAt: Date(),
                                isCompleted: false,
                                completedDate: nil,
                                category: selectedCategory.isEmpty ? "Uncategorized" : selectedCategory
                            )
                            await onSave(item)
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty)
                    .foregroundColor(title.isEmpty ? .gray : Color(red: 0.6, green: 0.3, blue: 0.8))
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Wish List Settings View
struct WishListSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: WishListViewModel
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryIcon = "sparkles"
    @State private var newCategoryColor = Color(red: 0.6, green: 0.4, blue: 0.85)

    let iconOptions = ["sparkles", "star.fill", "heart.fill", "location.fill", "fork.knife", "film.fill", "airplane", "gift.fill", "cart.fill", "book.fill", "music.note", "gamecontroller.fill", "camera.fill", "paintbrush.fill"]

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(viewModel.categories) { category in
                        HStack(spacing: 12) {
                            Image(systemName: category.icon)
                                .font(.title3)
                                .foregroundColor(Color(hex: category.colorHex) ?? Color(red: 0.6, green: 0.4, blue: 0.85))
                                .frame(width: 30)

                            Text(category.name)
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                            Spacer()

                            let count = viewModel.items.filter { $0.category == category.name }.count
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let category = viewModel.categories[index]
                            Task {
                                await viewModel.deleteCategory(category)
                            }
                        }
                    }

                    Button(action: { showingAddCategory = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                            Text("Add Category")
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                        }
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Swipe left on a category to delete it. Wishes in deleted categories will become 'Uncategorized'.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddCategory) {
                NavigationView {
                    Form {
                        Section {
                            TextField("Category Name", text: $newCategoryName)
                        } header: {
                            Text("Name")
                        }

                        Section {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                                ForEach(iconOptions, id: \.self) { icon in
                                    Button(action: { newCategoryIcon = icon }) {
                                        Image(systemName: icon)
                                            .font(.title3)
                                            .foregroundColor(newCategoryIcon == icon ? .white : Color(red: 0.5, green: 0.4, blue: 0.7))
                                            .frame(width: 40, height: 40)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(newCategoryIcon == icon ? Color(red: 0.6, green: 0.4, blue: 0.85) : Color(red: 0.95, green: 0.92, blue: 1.0))
                                            )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        } header: {
                            Text("Icon")
                        }

                        Section {
                            ColorPicker("Category Color", selection: $newCategoryColor)
                        } header: {
                            Text("Color")
                        }

                        Section {
                            HStack(spacing: 12) {
                                Image(systemName: newCategoryIcon)
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle().fill(newCategoryColor)
                                    )

                                Text(newCategoryName.isEmpty ? "Category Name" : newCategoryName)
                                    .font(.headline)
                                    .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        } header: {
                            Text("Preview")
                        }
                    }
                    .navigationTitle("New Category")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showingAddCategory = false
                                resetNewCategory()
                            }
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Add") {
                                Task {
                                    let category = WishCategory(
                                        name: newCategoryName,
                                        icon: newCategoryIcon,
                                        colorHex: newCategoryColor.toHex() ?? "#9966DD",
                                        createdAt: Date()
                                    )
                                    await viewModel.addCategory(category)
                                    showingAddCategory = false
                                    resetNewCategory()
                                }
                            }
                            .disabled(newCategoryName.isEmpty)
                            .foregroundColor(newCategoryName.isEmpty ? .gray : Color(red: 0.6, green: 0.3, blue: 0.8))
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }

    private func resetNewCategory() {
        newCategoryName = ""
        newCategoryIcon = "sparkles"
        newCategoryColor = Color(red: 0.6, green: 0.4, blue: 0.85)
    }
}

// MARK: - View Model
class WishListViewModel: ObservableObject {
    @Published var items: [WishListItem] = []
    @Published var categories: [WishCategory] = []

    private let firebaseManager = FirebaseManager.shared

    init() {
        loadItems()
        loadCategories()
    }

    func loadItems() {
        Task {
            for try await items in firebaseManager.getWishListItems() {
                await MainActor.run {
                    self.items = items
                }
            }
        }
    }

    func loadCategories() {
        Task {
            for try await categories in firebaseManager.getWishCategories() {
                await MainActor.run {
                    self.categories = categories
                }
            }
        }
    }

    func addItem(_ item: WishListItem) async {
        do {
            try await firebaseManager.addWishListItem(item)
        } catch {
            print("Error adding wish list item: \(error)")
        }
    }

    func toggleComplete(_ item: WishListItem) async {
        var updatedItem = item
        updatedItem.isCompleted.toggle()
        updatedItem.completedDate = updatedItem.isCompleted ? Date() : nil

        do {
            try await firebaseManager.updateWishListItem(updatedItem)
        } catch {
            print("Error updating wish list item: \(error)")
        }
    }

    func deleteItem(_ item: WishListItem) async {
        do {
            try await firebaseManager.deleteWishListItem(item)
        } catch {
            print("Error deleting wish list item: \(error)")
        }
    }

    func addCategory(_ category: WishCategory) async {
        do {
            try await firebaseManager.addWishCategory(category)
        } catch {
            print("Error adding category: \(error)")
        }
    }

    func deleteCategory(_ category: WishCategory) async {
        do {
            try await firebaseManager.deleteWishCategory(category)
        } catch {
            print("Error deleting category: \(error)")
        }
    }
}

// MARK: - Color Extensions
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

#Preview {
    WishListView()
}
