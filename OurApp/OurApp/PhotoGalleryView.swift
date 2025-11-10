import SwiftUI
import PhotosUI

struct PhotoGalleryView: View {
    @StateObject private var viewModel = PhotoGalleryViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingAddPhoto = false
    @State private var isUploading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showingPhotoViewer = false
    @State private var selectedPhotoIndex = 0

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
                            ForEach(Array(viewModel.photos.enumerated()), id: \.element.id) { index, photo in
                                Button(action: {
                                    selectedPhotoIndex = index
                                    showingPhotoViewer = true
                                }) {
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
                                    .frame(width: UIScreen.main.bounds.width / 3 - 2, height: UIScreen.main.bounds.width / 3 - 2)
                                    .clipped()
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .navigationTitle("Our Photos 💜")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isUploading {
                        ProgressView()
                            .tint(Color(red: 0.8, green: 0.7, blue: 1.0))
                    } else {
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                        }
                    }
                }
            }
            .onChange(of: selectedItem) { newItem in
                Task {
                    guard let item = newItem else { return }
                    isUploading = true

                    do {
                        if let data = try await item.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            // Resize and compress the image before upload
                            let resized = uiImage.resized(toMaxDimension: 1920)
                            if let compressedData = resized.compressed(toMaxBytes: 1_000_000) {
                                try await viewModel.uploadPhoto(imageData: compressedData)
                            } else {
                                throw NSError(domain: "PhotoUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
                            }
                        }
                    } catch {
                        errorMessage = "Failed to upload photo: \(error.localizedDescription)"
                        showError = true
                    }

                    isUploading = false
                    selectedItem = nil
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .fullScreenCover(isPresented: $showingPhotoViewer) {
                FullScreenPhotoViewer(
                    photoURLs: viewModel.photos.map { $0.imageURL },
                    initialIndex: selectedPhotoIndex,
                    onDismiss: { showingPhotoViewer = false }
                )
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

    func uploadPhoto(imageData: Data) async throws {
        try await firebaseManager.uploadPhoto(
            imageData: imageData,
            caption: "",
            uploadedBy: "You"
        )
    }

    func deletePhoto(_ photo: Photo) async throws {
        try await firebaseManager.deletePhoto(photo)
    }
}

#Preview {
    PhotoGalleryView()
}
