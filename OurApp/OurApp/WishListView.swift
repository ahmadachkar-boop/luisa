import SwiftUI

// MARK: - Wish View Type
enum WishViewType: Hashable {
    case categorySelection // Main view showing all categories
    case categoryDetail(String) // Detail view for a specific category
}

// MARK: - Default Categories
struct DefaultWishCategories {
    static let categories: [(name: String, icon: String, colorHex: String)] = [
        ("Dates", "heart.circle.fill", "#E57373"),
        ("Places to Visit", "map.fill", "#4FC3F7"),
        ("Cooking", "fork.knife", "#FFB74D"),
        ("Activities", "figure.run", "#81C784"),
        ("Trips", "airplane", "#BA68C8"),
        ("Shows/Movies", "film.fill", "#F06292")
    ]
}

struct WishListView: View {
    @StateObject private var viewModel = WishListViewModel()
    @State private var currentView: WishViewType = .categorySelection
    @State private var viewNavStack: [WishViewType] = []
    @State private var showingSettings = false
    @State private var showingExpandedHeader = false
    @State private var isResettingScroll = false

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

                switch currentView {
                case .categorySelection:
                    categorySelectionView
                case .categoryDetail(let categoryName):
                    WishCategoryDetailView(
                        categoryName: categoryName,
                        category: viewModel.categories.first { $0.name == categoryName },
                        viewModel: viewModel,
                        onBack: { navigateBack() }
                    )
                }
            }
            .sheet(isPresented: $showingSettings) {
                WishListSettingsView(viewModel: viewModel)
            }
        }
        .onAppear {
            viewModel.initializeDefaultCategoriesIfNeeded()
        }
    }

    // MARK: - Navigation
    private func navigateToCategory(_ categoryName: String) {
        viewNavStack.append(currentView)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentView = .categoryDetail(categoryName)
        }
    }

    private func navigateBack() {
        if let previousView = viewNavStack.popLast() {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                currentView = previousView
            }
        }
    }

    // MARK: - Category Selection View
    private var categorySelectionView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 16) {
                    // Top anchor
                    Color.clear
                        .frame(height: 0)
                        .id("wishlist-top-anchor")

                    // Expandable header
                    expandableHeader
                        .padding(.horizontal)
                        .padding(.top, 4)

                    // Header
                    HStack {
                        Text("Wish List")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Category Cards
                    ForEach(viewModel.categories) { category in
                        let itemsInCategory = viewModel.items.filter { $0.category == category.name }
                        let pendingCount = itemsInCategory.filter { !$0.isCompleted }.count
                        let completedCount = itemsInCategory.filter { $0.isCompleted }.count
                        let plannedCount = itemsInCategory.filter { $0.plannedDate != nil && !$0.isCompleted }.count

                        WishCategoryCard(
                            category: category,
                            pendingCount: pendingCount,
                            completedCount: completedCount,
                            plannedCount: plannedCount,
                            action: { navigateToCategory(category.name) }
                        )
                    }

                    // Empty state if no categories
                    if viewModel.categories.isEmpty {
                        emptyStateView
                    }
                }
                .padding(.vertical)
            }
            .refreshable {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingExpandedHeader = true
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { oldValue, newValue in
                // Use isResettingScroll to prevent scroll momentum from moving the view
                if showingExpandedHeader && newValue > 1 && !isResettingScroll {
                    isResettingScroll = true
                    withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                        showingExpandedHeader = false
                    }
                    // Delay scroll to top to let momentum settle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
                            scrollProxy.scrollTo("wishlist-top-anchor", anchor: .top)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isResettingScroll = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Expandable Header
    private var expandableHeader: some View {
        VStack(spacing: 0) {
            if showingExpandedHeader {
                VStack(spacing: 16) {
                    // Stats overview
                    HStack(spacing: 20) {
                        StatBox(
                            value: "\(viewModel.items.filter { !$0.isCompleted }.count)",
                            label: "Pending",
                            color: Color(red: 0.6, green: 0.4, blue: 0.85)
                        )

                        StatBox(
                            value: "\(viewModel.items.filter { $0.plannedDate != nil && !$0.isCompleted }.count)",
                            label: "Planned",
                            color: Color(red: 0.4, green: 0.6, blue: 0.9)
                        )

                        StatBox(
                            value: "\(viewModel.items.filter { $0.isCompleted }.count)",
                            label: "Done",
                            color: Color.green
                        )
                    }

                    Divider()

                    // Quick actions
                    HStack(spacing: 12) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showingExpandedHeader = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showingSettings = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body)
                                Text("Add Category")
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

                        Spacer()

                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showingExpandedHeader = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showingSettings = true
                            }
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundColor(Color(red: 0.5, green: 0.35, blue: 0.75))
                                .padding(10)
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                )
                        }
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

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(Color(red: 0.7, green: 0.6, blue: 0.9))

            Text("No categories yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

            Text("Categories are being set up...")
                .font(.subheadline)
                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Stat Box
struct StatBox: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Wish Category Card
struct WishCategoryCard: View {
    let category: WishCategory
    let pendingCount: Int
    let completedCount: Int
    let plannedCount: Int
    let action: () -> Void

    private var categoryColor: Color {
        Color(hex: category.colorHex) ?? Color(red: 0.6, green: 0.4, blue: 0.85)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 70, height: 70)

                    Image(systemName: category.icon)
                        .font(.system(size: 32))
                        .foregroundColor(categoryColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(category.name)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                    Text("\(pendingCount) pending")
                        .font(.subheadline)
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))

                    HStack(spacing: 12) {
                        if plannedCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.4, green: 0.6, blue: 0.9))
                                Text("\(plannedCount) planned")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                            }
                        }

                        if completedCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Text("\(completedCount) done")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                            }
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

// MARK: - Category Detail View
struct WishCategoryDetailView: View {
    let categoryName: String
    let category: WishCategory?
    @ObservedObject var viewModel: WishListViewModel
    let onBack: () -> Void

    @State private var showingAddItem = false
    @State private var showingExpandedHeader = false
    @State private var isResettingScroll = false
    @State private var searchText = ""
    @State private var isCompletedExpanded = false
    @State private var itemToPlan: WishListItem? = nil
    @State private var itemToEditDate: WishListItem? = nil
    @State private var showingDateOptions = false
    @State private var dragOffset: CGFloat = 0

    private var categoryColor: Color {
        if let hex = category?.colorHex, let color = Color(hex: hex) {
            return color
        }
        return Color(red: 0.6, green: 0.4, blue: 0.85)
    }

    private var pendingItems: [WishListItem] {
        let items = viewModel.items.filter { $0.category == categoryName && !$0.isCompleted }
        if searchText.isEmpty {
            return items.sorted { $0.createdAt > $1.createdAt }
        }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private var completedItems: [WishListItem] {
        let items = viewModel.items.filter { $0.category == categoryName && $0.isCompleted }
        if searchText.isEmpty {
            return items.sorted { ($0.completedDate ?? $0.createdAt) > ($1.completedDate ?? $1.createdAt) }
        }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }.sorted { ($0.completedDate ?? $0.createdAt) > ($1.completedDate ?? $1.createdAt) }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Top anchor
                    Color.clear
                        .frame(height: 0)
                        .id("category-top-anchor")

                    // Expandable header
                    expandableHeader
                        .padding(.horizontal)
                        .padding(.top, 4)

                    // Navigation header
                    HStack(spacing: 12) {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.medium))
                                Text("Back")
                                    .font(.body)
                            }
                            .foregroundColor(categoryColor)
                        }

                        Spacer()

                        Text(categoryName)
                            .font(.headline)
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                        Spacer()

                        // Balance the back button
                        Color.clear
                            .frame(width: 60)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)

                    // Category header with icon
                    categoryHeader
                        .padding(.top, 16)

                    // Pending items
                    if pendingItems.isEmpty && completedItems.isEmpty {
                        emptyItemsView
                    } else {
                        // Pending items section
                        if !pendingItems.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Pending")
                                    .font(.headline)
                                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                                    .padding(.horizontal)

                                ForEach(pendingItems) { item in
                                    WishItemRow(
                                        item: item,
                                        categoryColor: categoryColor,
                                        onToggleComplete: {
                                            Task { await viewModel.toggleComplete(item) }
                                        },
                                        onPlan: {
                                            itemToPlan = item
                                        },
                                        onEditDate: {
                                            itemToEditDate = item
                                            showingDateOptions = true
                                        },
                                        onDelete: {
                                            Task { await viewModel.deleteItem(item) }
                                        }
                                    )
                                }
                            }
                            .padding(.top, 16)
                        }

                        // Completed items section (expandable)
                        if !completedItems.isEmpty {
                            completedSection
                                .padding(.top, 20)
                        }
                    }

                    Spacer(minLength: 100)
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
                // Use isResettingScroll to prevent scroll momentum from moving the view
                if showingExpandedHeader && newValue > 1 && !isResettingScroll {
                    isResettingScroll = true
                    withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                        showingExpandedHeader = false
                    }
                    // Delay scroll to top to let momentum settle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
                            scrollProxy.scrollTo("category-top-anchor", anchor: .top)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isResettingScroll = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddWishItemView(categoryName: categoryName, categoryColor: categoryColor) { item in
                await viewModel.addItem(item)
            }
        }
        .sheet(item: $itemToPlan) { item in
            PlanWishItemView(item: item, categoryColor: categoryColor) { updatedItem, calendarEvent in
                await viewModel.planItem(updatedItem, createEvent: calendarEvent)
            }
        }
        .sheet(item: $itemToEditDate) { item in
            EditPlannedDateView(item: item, categoryColor: categoryColor) { updatedItem in
                await viewModel.updateItemDate(updatedItem)
            }
        }
        .offset(x: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only allow dragging from left edge (start location within 30pt of left edge)
                    if value.startLocation.x < 30 && value.translation.width > 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    // If dragged more than 100pt, go back
                    if value.startLocation.x < 30 && value.translation.width > 100 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = UIScreen.main.bounds.width
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onBack()
                            dragOffset = 0
                        }
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
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

                        TextField("Search in \(categoryName)...", text: $searchText)
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

                    // Quick actions
                    HStack(spacing: 12) {
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
                                Text("Add Wish")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [categoryColor, categoryColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(12)
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

    // MARK: - Category Header
    private var categoryHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: category?.icon ?? "sparkles")
                    .font(.system(size: 36))
                    .foregroundColor(categoryColor)
            }

            HStack(spacing: 20) {
                VStack {
                    Text("\(pendingItems.count)")
                        .font(.title3.weight(.bold))
                        .foregroundColor(categoryColor)
                    Text("Pending")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                }

                VStack {
                    Text("\(pendingItems.filter { $0.plannedDate != nil }.count)")
                        .font(.title3.weight(.bold))
                        .foregroundColor(Color(red: 0.4, green: 0.6, blue: 0.9))
                    Text("Planned")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                }

                VStack {
                    Text("\(completedItems.count)")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.green)
                    Text("Done")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Empty Items View
    private var emptyItemsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 50))
                .foregroundColor(categoryColor.opacity(0.5))

            Text("No wishes in \(categoryName) yet")
                .font(.headline)
                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

            Text("Pull down to add your first wish!")
                .font(.subheadline)
                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))

            Button(action: { showingAddItem = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Wish")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [categoryColor, categoryColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Completed Section
    private var completedSection: some View {
        VStack(spacing: 0) {
            // Expandable toggle
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isCompletedExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Completed")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))
                        Text("\(completedItems.count) item\(completedItems.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    }

                    Spacer()

                    Image(systemName: isCompletedExpanded ? "chevron.up" : "chevron.down")
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

            // Expanded items
            if isCompletedExpanded {
                VStack(spacing: 8) {
                    ForEach(completedItems) { item in
                        CompletedWishItemRow(
                            item: item,
                            categoryColor: categoryColor,
                            onUncomplete: {
                                Task { await viewModel.toggleComplete(item) }
                            },
                            onDelete: {
                                Task { await viewModel.deleteItem(item) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Wish Item Row
struct WishItemRow: View {
    let item: WishListItem
    let categoryColor: Color
    let onToggleComplete: () -> Void
    let onPlan: () -> Void
    let onEditDate: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteAlert = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Complete button
            Button(action: onToggleComplete) {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundColor(categoryColor.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))

                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.subheadline)
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                        .lineLimit(2)
                }

                // Planned date badge - tappable to edit
                if let plannedDate = item.plannedDate {
                    Button(action: onEditDate) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption)
                            Text(plannedDate, style: .date)
                                .font(.caption)
                            Image(systemName: "pencil")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(Color(red: 0.4, green: 0.6, blue: 0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.4, green: 0.6, blue: 0.9).opacity(0.15))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Added by and date
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                    Text(item.addedBy)
                        .font(.caption2)
                    Text("•")
                        .font(.caption2)
                    Text(item.createdAt, style: .date)
                        .font(.caption2)
                }
                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.8))
            }

            Spacer()

            // Action buttons
            VStack(spacing: 8) {
                if item.plannedDate == nil {
                    Button(action: onPlan) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.body)
                            .foregroundColor(Color(red: 0.4, green: 0.6, blue: 0.9))
                    }
                }

                Button(action: { showingDeleteAlert = true }) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.red.opacity(0.7))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        )
        .padding(.horizontal)
        .alert("Delete Wish?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This will remove '\(item.title)' from your wish list")
        }
    }
}

// MARK: - Completed Wish Item Row
struct CompletedWishItemRow: View {
    let item: WishListItem
    let categoryColor: Color
    let onUncomplete: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteAlert = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onUncomplete) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.5))
                    .strikethrough()

                if let completedDate = item.completedDate {
                    Text("Completed \(completedDate, style: .date)")
                        .font(.caption2)
                        .foregroundColor(.green.opacity(0.8))
                }
            }

            Spacer()

            Button(action: { showingDeleteAlert = true }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.green.opacity(0.05))
        )
        .alert("Delete Wish?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Add Wish Item View
struct AddWishItemView: View {
    @Environment(\.dismiss) var dismiss
    let categoryName: String
    let categoryColor: Color
    let onSave: (WishListItem) async -> Void

    @State private var title = ""
    @State private var description = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("What do you want to do?", text: $title)
                        .font(.body)

                    TextField("Why? (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body)
                } header: {
                    Text("Wish Details")
                }

                Section {
                    HStack {
                        Text("Category")
                        Spacer()
                        Text(categoryName)
                            .foregroundColor(categoryColor)
                    }
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
                                category: categoryName,
                                plannedDate: nil,
                                calendarEventId: nil
                            )
                            await onSave(item)
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty)
                    .foregroundColor(title.isEmpty ? .gray : categoryColor)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Plan Wish Item View
struct PlanWishItemView: View {
    @Environment(\.dismiss) var dismiss
    let item: WishListItem
    let categoryColor: Color
    let onSave: (WishListItem, CalendarEvent?) async -> Void

    @State private var plannedDate = Date()
    @State private var addToCalendar = true
    @State private var location = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text("Wish")
                        Spacer()
                        Text(item.title)
                            .foregroundColor(categoryColor)
                    }
                }

                Section {
                    DatePicker("Date & Time", selection: $plannedDate)
                        .tint(categoryColor)

                    TextField("Location (optional)", text: $location)
                } header: {
                    Text("When?")
                }

                Section {
                    Toggle("Add to Calendar", isOn: $addToCalendar)
                        .tint(categoryColor)
                } footer: {
                    Text("This will create an event in the Calendar tab so you can see all your planned activities in one place.")
                }
            }
            .navigationTitle("Plan Wish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Plan") {
                        Task {
                            var updatedItem = item
                            updatedItem.plannedDate = plannedDate

                            var calendarEvent: CalendarEvent? = nil
                            if addToCalendar {
                                calendarEvent = CalendarEvent(
                                    title: item.title,
                                    description: item.description.isEmpty ? "Planned from Wish List" : item.description,
                                    date: plannedDate,
                                    endDate: nil,
                                    location: location,
                                    createdBy: UserIdentityManager.shared.currentUserName,
                                    isSpecial: false,
                                    photoURLs: []
                                )
                            }

                            await onSave(updatedItem, calendarEvent)
                            dismiss()
                        }
                    }
                    .foregroundColor(categoryColor)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Edit Planned Date View
struct EditPlannedDateView: View {
    @Environment(\.dismiss) var dismiss
    let item: WishListItem
    let categoryColor: Color
    let onSave: (WishListItem) async -> Void

    @State private var plannedDate: Date
    @State private var showingRemoveConfirmation = false

    init(item: WishListItem, categoryColor: Color, onSave: @escaping (WishListItem) async -> Void) {
        self.item = item
        self.categoryColor = categoryColor
        self.onSave = onSave
        self._plannedDate = State(initialValue: item.plannedDate ?? Date())
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text("Wish")
                        Spacer()
                        Text(item.title)
                            .foregroundColor(categoryColor)
                    }
                }

                Section {
                    DatePicker("Date & Time", selection: $plannedDate)
                        .tint(categoryColor)
                } header: {
                    Text("Change Date")
                }

                Section {
                    Button(role: .destructive, action: {
                        showingRemoveConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "calendar.badge.minus")
                            Text("Remove from Calendar")
                        }
                    }
                } footer: {
                    Text("This will remove the planned date and any associated calendar event.")
                }
            }
            .navigationTitle("Edit Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            var updatedItem = item
                            updatedItem.plannedDate = plannedDate
                            await onSave(updatedItem)
                            dismiss()
                        }
                    }
                    .foregroundColor(categoryColor)
                    .fontWeight(.semibold)
                }
            }
            .alert("Remove Planned Date?", isPresented: $showingRemoveConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    Task {
                        var updatedItem = item
                        updatedItem.plannedDate = nil
                        // Don't clear calendarEventId here - let updateItemDate handle it
                        // so it knows to delete the calendar event
                        await onSave(updatedItem)
                        dismiss()
                    }
                }
            } message: {
                Text("This will remove the planned date from '\(item.title)'")
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

    let iconOptions = ["sparkles", "star.fill", "heart.fill", "heart.circle.fill", "map.fill", "location.fill", "fork.knife", "film.fill", "airplane", "gift.fill", "cart.fill", "book.fill", "music.note", "gamecontroller.fill", "camera.fill", "paintbrush.fill", "figure.run", "car.fill", "house.fill", "building.2.fill"]

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
                    Text("Swipe left on a category to delete it. Wishes in deleted categories will be removed.")
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
    @Published var hasInitializedDefaults = false

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

    func initializeDefaultCategoriesIfNeeded() {
        guard !hasInitializedDefaults else { return }
        hasInitializedDefaults = true

        // Check if categories are empty after a short delay to let Firebase load
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.categories.isEmpty {
                Task {
                    await self.createDefaultCategories()
                }
            }
        }
    }

    private func createDefaultCategories() async {
        for defaultCategory in DefaultWishCategories.categories {
            let category = WishCategory(
                name: defaultCategory.name,
                icon: defaultCategory.icon,
                colorHex: defaultCategory.colorHex,
                createdAt: Date()
            )
            do {
                try await firebaseManager.addWishCategory(category)
            } catch {
                print("Error adding default category: \(error)")
            }
        }
    }

    func addItem(_ item: WishListItem) async {
        do {
            try await firebaseManager.addWishListItem(item)
            // Send notification
            NotificationManager.shared.notifyWishAdded(item: item, category: item.category)
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
            // Send notification only when marking as completed
            if updatedItem.isCompleted {
                NotificationManager.shared.notifyWishCompleted(item: updatedItem)
            }
        } catch {
            print("Error updating wish list item: \(error)")
        }
    }

    func deleteItem(_ item: WishListItem) async {
        do {
            // If item has a calendar event, delete it too
            if let eventId = item.calendarEventId {
                // Fetch and delete the calendar event
                let events = try await firebaseManager.fetchAllEvents()
                if let event = events.first(where: { $0.id == eventId }) {
                    try await firebaseManager.deleteCalendarEvent(event)
                }
            }
            try await firebaseManager.deleteWishListItem(item)
        } catch {
            print("Error deleting wish list item: \(error)")
        }
    }

    func planItem(_ item: WishListItem, createEvent calendarEvent: CalendarEvent?) async {
        var updatedItem = item

        do {
            if let event = calendarEvent {
                // Create the calendar event and get its ID
                let eventId = try await firebaseManager.addCalendarEventWithId(event)
                updatedItem.calendarEventId = eventId
            }

            try await firebaseManager.updateWishListItem(updatedItem)

            // Send notification when item is planned
            if let plannedDate = updatedItem.plannedDate {
                NotificationManager.shared.notifyWishPlanned(item: updatedItem, plannedDate: plannedDate)
            }
        } catch {
            print("Error planning wish list item: \(error)")
        }
    }

    func updateItemDate(_ item: WishListItem) async {
        var updatedItem = item

        do {
            if let eventId = item.calendarEventId {
                let events = try await firebaseManager.fetchAllEvents()
                if let existingEvent = events.first(where: { $0.id == eventId }) {
                    if let newDate = item.plannedDate {
                        // Date was changed - update the calendar event
                        var updatedEvent = existingEvent
                        updatedEvent.date = newDate
                        try await firebaseManager.updateCalendarEvent(updatedEvent)
                    } else {
                        // Date was removed - delete the calendar event
                        try await firebaseManager.deleteCalendarEvent(existingEvent)
                        updatedItem.calendarEventId = nil
                    }
                }
            }

            try await firebaseManager.updateWishListItem(updatedItem)
        } catch {
            print("Error updating wish list item date: \(error)")
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
            // Delete all items in this category
            let itemsToDelete = items.filter { $0.category == category.name }
            for item in itemsToDelete {
                try await firebaseManager.deleteWishListItem(item)
            }
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
