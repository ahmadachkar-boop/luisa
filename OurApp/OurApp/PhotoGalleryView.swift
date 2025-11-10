import SwiftUI
import PhotosUI

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
                                ZStack(alignment: .topTrailing) {
                                    Button(action: {
                                        if selectionMode {
                                            if selectedPhotoIndices.contains(index) {
                                                selectedPhotoIndices.remove(index)
                                            } else {
                                                selectedPhotoIndices.insert(index)
                                            }
                                        } else {
                                            selectedPhotoIndex = PhotoIndex(value: index)
                                        }
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
                                        .overlay(
                                            selectionMode ?
                                                RoundedRectangle(cornerRadius: 0)
                                                    .stroke(selectedPhotoIndices.contains(index) ? Color.blue : Color.clear, lineWidth: 3)
                                            : nil
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .onLongPressGesture(minimumDuration: 0.5) {
                                        if !selectionMode {
                                            selectionMode = true
                                            selectedPhotoIndices.insert(index)
                                        }
                                    }

                                    // Checkmark overlay
                                    if selectionMode {
                                        Image(systemName: selectedPhotoIndices.contains(index) ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .foregroundColor(selectedPhotoIndices.contains(index) ? .blue : .white)
                                            .shadow(radius: 2)
                                            .padding(8)
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .navigationTitle("Our Photos 💜")
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
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isUploading {
                            ProgressView()
                                .tint(Color(red: 0.8, green: 0.7, blue: 1.0))
                        } else {
                            PhotosPicker(selection: $selectedItems, maxSelectionCount: 10, matching: .images) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                            }
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
                                // Resize and compress the image before upload
                                let resized = uiImage.resized(toMaxDimension: 1920)
                                if let compressedData = resized.compressed(toMaxBytes: 1_000_000) {
                                    try await viewModel.uploadPhoto(imageData: compressedData)
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
                Text("\(selectedPhotoIndices.count) photo\(selectedPhotoIndices.count == 1 ? "" : "s") saved to your library")
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
                    }
                )
            }
        }
    }

    private func saveSelectedPhotos() {
        guard !selectedPhotoIndices.isEmpty else { return }

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
                        if savedCount == selectedPhotoIndices.count {
                            showingSaveSuccess = true
                            selectionMode = false
                            selectedPhotoIndices.removeAll()
                        }
                    }
                    imageSaver.errorHandler = { error in
                        if !errorOccurred {
                            errorOccurred = true
                            saveErrorMessage = "Failed to save some photos: \(error.localizedDescription)"
                            showingSaveError = true
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
                        if savedCount == selectedPhotoIndices.count {
                            showingSaveSuccess = true
                            selectionMode = false
                            selectedPhotoIndices.removeAll()
                        }
                    }
                    imageSaver.errorHandler = { error in
                        if !errorOccurred {
                            errorOccurred = true
                            saveErrorMessage = "Failed to save some photos: \(error.localizedDescription)"
                            showingSaveError = true
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
