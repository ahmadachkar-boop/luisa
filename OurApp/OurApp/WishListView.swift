import SwiftUI

struct WishListView: View {
    @StateObject private var viewModel = WishListViewModel()
    @State private var showingAddItem = false

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

                if viewModel.items.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(Color(red: 0.7, green: 0.6, blue: 0.9))

                        Text("No wishes yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                        Text("Add places and experiences you want to share together 💫")
                            .font(.subheadline)
                            .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.items) { item in
                                WishListItemCard(
                                    item: item,
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
            }
            .navigationTitle("Our Wish List ✨")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddItem = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                AddWishListItemView { item in
                    await viewModel.addItem(item)
                }
            }
        }
    }
}

struct WishListItemCard: View {
    let item: WishListItem
    let onToggleComplete: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteAlert = false

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            // Category icon
            VStack {
                Image(systemName: categoryIcon(item.category))
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle().fill(
                            LinearGradient(
                                colors: item.isCompleted ?
                                    [Color.green.opacity(0.7), Color.green.opacity(0.5)] :
                                    [Color(red: 0.6, green: 0.4, blue: 0.8), Color(red: 0.5, green: 0.3, blue: 0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                    .shadow(radius: 3)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))
                        .strikethrough(item.isCompleted)

                    if item.isCompleted {
                        Text("✓")
                            .foregroundColor(.green)
                            .fontWeight(.bold)
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
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.9, green: 0.85, blue: 0.95))
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

                Button(action: {
                    showingDeleteAlert = true
                }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red.opacity(0.7))
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.white, Color(red: 0.99, green: 0.97, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .alert("Delete Wish?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will remove '\(item.title)' from your wish list")
        }
    }

    func categoryIcon(_ category: String) -> String {
        switch category {
        case "Place to Visit": return "location.fill"
        case "Activity": return "figure.2.and.child.holdinghands"
        case "Restaurant": return "fork.knife"
        case "Experience": return "star.fill"
        default: return "sparkles"
        }
    }
}

struct AddWishListItemView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var category = "Place to Visit"

    let categories = ["Place to Visit", "Activity", "Restaurant", "Experience"]
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
                    Text("Wish Details ✨")
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .tint(Color(red: 0.6, green: 0.4, blue: 0.8))
                } header: {
                    Text("What kind of wish?")
                }
            }
            .navigationTitle("Add to Wish List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            let item = WishListItem(
                                title: title,
                                description: description,
                                addedBy: UserIdentityManager.shared.currentUserName,
                                createdAt: Date(),
                                isCompleted: false,
                                completedDate: nil,
                                category: category
                            )
                            await onSave(item)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Add")
                            Text("💫")
                                .font(.caption)
                        }
                        .foregroundColor(title.isEmpty ? .gray : Color(red: 0.6, green: 0.3, blue: 0.8))
                        .fontWeight(.semibold)
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

class WishListViewModel: ObservableObject {
    @Published var items: [WishListItem] = []

    private let firebaseManager = FirebaseManager.shared

    init() {
        loadItems()
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
}

#Preview {
    WishListView()
}
