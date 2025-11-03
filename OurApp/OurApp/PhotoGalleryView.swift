import SwiftUI
import PhotosUI

struct PhotoGalleryView: View {
    @StateObject private var viewModel = PhotoGalleryViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingAddPhoto = false

    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

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

                if viewModel.photos.isEmpty {
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
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(viewModel.photos) { photo in
                                NavigationLink(destination: PhotoDetailView(photo: photo, onDelete: {
                                    Task {
                                        await viewModel.deletePhoto(photo)
                                    }
                                })) {
                                    AsyncImage(url: URL(string: photo.imageURL)) { image in
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
                                    .frame(width: UIScreen.main.bounds.width / 3 - 2, height: UIScreen.main.bounds.width / 3 - 2)
                                    .clipped()
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .navigationTitle("Our Photos 💜")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                    }
                }
            }
            .onChange(of: selectedItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        await viewModel.uploadPhoto(imageData: data)
                    }
                }
            }
        }
    }
}

struct PhotoDetailView: View {
    let photo: Photo
    let onDelete: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var showingDeleteAlert = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                AsyncImage(url: URL(string: photo.imageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }

                if !photo.caption.isEmpty {
                    Text(photo.caption)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        .padding()
                }

                Text("Added by \(photo.uploadedBy)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

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
    }
}

class PhotoGalleryViewModel: ObservableObject {
    @Published var photos: [Photo] = []

    private let firebaseManager = FirebaseManager.shared

    init() {
        loadPhotos()
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

    func uploadPhoto(imageData: Data) async {
        do {
            try await firebaseManager.uploadPhoto(
                imageData: imageData,
                caption: "",
                uploadedBy: "You"
            )
        } catch {
            print("Error uploading photo: \(error)")
        }
    }

    func deletePhoto(_ photo: Photo) async {
        do {
            try await firebaseManager.deletePhoto(photo)
        } catch {
            print("Error deleting photo: \(error)")
        }
    }
}

#Preview {
    PhotoGalleryView()
}
