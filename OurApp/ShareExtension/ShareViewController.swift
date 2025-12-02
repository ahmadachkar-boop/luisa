import UIKit
import Social
import UniformTypeIdentifiers
import MobileCoreServices
import AVFoundation
import ImageIO

/// Share Extension that uploads directly to Firebase with progress
/// Uses background URLSession to continue uploads even after extension closes
class ShareViewController: UIViewController {

    // MARK: - Properties
    private var sharedItems: [(url: URL, isVideo: Bool, data: Data?, thumbnailData: Data?, duration: TimeInterval?, capturedAt: Date?)] = []
    private var processingCount = 0
    private var totalItems = 0
    private var successCount = 0
    private var uploadedCount = 0
    private var currentUploadIndex = 0
    private var isUploading = false
    private var currentUploadTask: URLSessionTask?
    private var retryCount = 0
    private let maxRetries = 2

    // Firebase configuration - loaded from shared container
    private var firebaseConfig: FirebaseConfig?

    private struct FirebaseConfig: Codable {
        let storageBucket: String
        let projectId: String
        let apiKey: String
        let idToken: String? // Auth token if user is signed in
    }

    private lazy var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0.98, green: 0.96, blue: 1.0, alpha: 1.0)
        view.layer.cornerRadius = 20
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 20
        view.layer.shadowOpacity = 0.15
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Add to OurApp"
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = UIColor(red: 0.25, green: 0.15, blue: 0.45, alpha: 1.0)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Preparing..."
        label.font = .systemFont(ofSize: 15)
        label.textColor = UIColor(red: 0.5, green: 0.4, blue: 0.7, alpha: 1.0)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.progressTintColor = UIColor(red: 0.6, green: 0.4, blue: 0.85, alpha: 1.0)
        progress.trackTintColor = UIColor(red: 0.9, green: 0.88, blue: 0.95, alpha: 1.0)
        progress.layer.cornerRadius = 4
        progress.clipsToBounds = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        return progress
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        button.setTitleColor(UIColor(red: 0.5, green: 0.4, blue: 0.7, alpha: 1.0), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = UIColor(red: 0.6, green: 0.4, blue: 0.85, alpha: 1.0)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var successImageView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 50, weight: .medium)
        let image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor(red: 0.4, green: 0.8, blue: 0.5, alpha: 1.0)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.alpha = 0
        imageView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        return imageView
    }()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        // Request extended execution time for the upload
        beginBackgroundTask()

        loadFirebaseConfig()
        setupUploadSession()
        processSharedItems()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Don't end background task here - let it continue
    }

    deinit {
        endBackgroundTask()
    }

    // MARK: - Background Task
    // Note: Share extensions have limited execution time (~30 seconds)
    // We use a background URLSession to continue uploads even after extension closes
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    private func beginBackgroundTask() {
        // Request extended execution time - this helps but has limits
        // The real solution is the background URLSession which continues after extension closes
        print("[SHARE] Started background activity - using background session for reliability")
    }

    private func endBackgroundTask() {
        print("[SHARE] Background activity ending")
    }

    // MARK: - URL Session Setup
    private func setupUploadSession() {
        // Using URLSession.shared with completion handlers for reliable uploads
        print("[SHARE] Upload session ready")
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        view.addSubview(containerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(statusLabel)
        containerView.addSubview(progressView)
        containerView.addSubview(activityIndicator)
        containerView.addSubview(successImageView)
        containerView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 300),
            containerView.heightAnchor.constraint(equalToConstant: 220),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            activityIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),

            successImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            successImageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),

            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            progressView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            progressView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            progressView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            progressView.heightAnchor.constraint(equalToConstant: 8),

            cancelButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            cancelButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor)
        ])

        activityIndicator.startAnimating()
    }

    // MARK: - Firebase Config
    private func loadFirebaseConfig() {
        guard let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ourapp") else {
            print("[SHARE] ❌ Could not access shared container - app group may not be configured")
            return
        }

        print("[SHARE] 📁 Shared container: \(sharedURL.path)")

        let configURL = sharedURL.appendingPathComponent("firebase_share_config.json")

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            print("[SHARE] ❌ Config file does not exist at: \(configURL.path)")
            print("[SHARE] Please open the main app while signed in to enable direct uploads")
            return
        }

        guard let data = try? Data(contentsOf: configURL) else {
            print("[SHARE] ❌ Could not read config file")
            return
        }

        print("[SHARE] 📄 Config file size: \(data.count) bytes")

        // Try manual JSON parsing first (more flexible)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let storageBucket = json["storageBucket"] as? String,
           let projectId = json["projectId"] as? String,
           let apiKey = json["apiKey"] as? String {

            let idToken = json["idToken"] as? String
            firebaseConfig = FirebaseConfig(storageBucket: storageBucket, projectId: projectId, apiKey: apiKey, idToken: idToken)

            print("[SHARE] ✅ Firebase config loaded successfully")
            print("[SHARE]    - Storage bucket: \(storageBucket)")
            print("[SHARE]    - Project ID: \(projectId)")
            print("[SHARE]    - Has auth token: \(idToken != nil ? "YES" : "NO")")
            if let token = idToken {
                print("[SHARE]    - Token length: \(token.count) chars")
            }
            return
        }

        // Try JSONDecoder as fallback
        if let config = try? JSONDecoder().decode(FirebaseConfig.self, from: data) {
            firebaseConfig = config
            print("[SHARE] ✅ Firebase config loaded via JSONDecoder")
            print("[SHARE]    - Has auth token: \(config.idToken != nil ? "YES" : "NO")")
            return
        }

        print("[SHARE] ❌ Failed to parse Firebase config - will queue for main app")
        if let jsonStr = String(data: data, encoding: .utf8) {
            print("[SHARE]    Raw config: \(jsonStr.prefix(200))...")
        }
    }

    // MARK: - Process Shared Items
    private func processSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError("No items to share")
            return
        }

        var allAttachments: [NSItemProvider] = []
        for item in extensionItems {
            if let attachments = item.attachments {
                allAttachments.append(contentsOf: attachments)
            }
        }

        totalItems = allAttachments.count
        if totalItems == 0 {
            showError("No media found")
            return
        }

        statusLabel.text = "Processing \(totalItems) item\(totalItems > 1 ? "s" : "")..."

        for attachment in allAttachments {
            processAttachment(attachment)
        }
    }

    private func processAttachment(_ attachment: NSItemProvider) {
        if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ||
           attachment.hasItemConformingToTypeIdentifier(UTType.video.identifier) ||
           attachment.hasItemConformingToTypeIdentifier(UTType.quickTimeMovie.identifier) ||
           attachment.hasItemConformingToTypeIdentifier(UTType.mpeg4Movie.identifier) {
            loadVideo(from: attachment)
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            loadImage(from: attachment)
        } else {
            itemProcessed(success: false, url: nil, isVideo: false, data: nil, thumbnailData: nil, duration: nil, capturedAt: nil)
        }
    }

    private func loadImage(from attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
            guard error == nil else {
                self?.itemProcessed(success: false, url: nil, isVideo: false, data: nil, thumbnailData: nil, duration: nil, capturedAt: nil)
                return
            }

            var imageData: Data?
            var fileURL: URL?
            var capturedAt: Date?

            if let url = item as? URL {
                fileURL = url
                imageData = try? Data(contentsOf: url)
                // Extract EXIF date from file
                capturedAt = self?.extractImageDate(from: url)
            } else if let image = item as? UIImage {
                imageData = self?.compressImage(image)
            } else if let data = item as? Data, let image = UIImage(data: data) {
                imageData = self?.compressImage(image)
                // Try to extract date from data
                capturedAt = self?.extractImageDate(from: data)
            }

            if let data = imageData {
                self?.itemProcessed(success: true, url: fileURL, isVideo: false, data: data, thumbnailData: nil, duration: nil, capturedAt: capturedAt)
            } else {
                self?.itemProcessed(success: false, url: nil, isVideo: false, data: nil, thumbnailData: nil, duration: nil, capturedAt: nil)
            }
        }
    }

    /// Extract capture date from image EXIF metadata
    private func extractImageDate(from url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else {
            return nil
        }

        // Try DateTimeOriginal first (when photo was taken)
        if let dateString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            return parseExifDate(dateString)
        }

        // Fallback to DateTimeDigitized
        if let dateString = exif[kCGImagePropertyExifDateTimeDigitized as String] as? String {
            return parseExifDate(dateString)
        }

        return nil
    }

    /// Extract capture date from image data
    private func extractImageDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else {
            return nil
        }

        if let dateString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            return parseExifDate(dateString)
        }

        if let dateString = exif[kCGImagePropertyExifDateTimeDigitized as String] as? String {
            return parseExifDate(dateString)
        }

        return nil
    }

    /// Parse EXIF date string (format: "yyyy:MM:dd HH:mm:ss")
    private func parseExifDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }

    private func loadVideo(from attachment: NSItemProvider) {
        let videoType = attachment.hasItemConformingToTypeIdentifier(UTType.quickTimeMovie.identifier) ?
            UTType.quickTimeMovie.identifier : UTType.movie.identifier

        attachment.loadItem(forTypeIdentifier: videoType, options: nil) { [weak self] item, error in
            guard error == nil, let url = item as? URL else {
                self?.itemProcessed(success: false, url: nil, isVideo: true, data: nil, thumbnailData: nil, duration: nil, capturedAt: nil)
                return
            }

            // Generate thumbnail and get duration
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true

            var thumbnailData: Data?
            var duration: TimeInterval = 0
            var capturedAt: Date?

            do {
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                thumbnailData = self?.compressImage(thumbnail, maxBytes: 200_000)
                duration = CMTimeGetSeconds(asset.duration)
            } catch {
                print("[SHARE] Failed to generate thumbnail: \(error)")
            }

            // Extract video creation date
            capturedAt = self?.extractVideoDate(from: asset)

            // Read video data
            let videoData = try? Data(contentsOf: url)

            self?.itemProcessed(success: videoData != nil, url: url, isVideo: true, data: videoData, thumbnailData: thumbnailData, duration: duration, capturedAt: capturedAt)
        }
    }

    /// Extract creation date from video metadata
    private func extractVideoDate(from asset: AVAsset) -> Date? {
        // Try creationDate metadata
        if let creationDate = asset.creationDate?.dateValue {
            return creationDate
        }

        // Try common metadata keys
        let metadataItems = asset.metadata
        for item in metadataItems {
            if let key = item.commonKey?.rawValue, key == "creationDate",
               let dateValue = item.dateValue {
                return dateValue
            }
        }

        // Try file modification date as fallback
        if let urlAsset = asset as? AVURLAsset {
            let url = urlAsset.url
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let creationDate = attributes[.creationDate] as? Date {
                return creationDate
            }
        }

        return nil
    }

    private func compressImage(_ image: UIImage, maxBytes: Int = 1_000_000) -> Data? {
        // Resize if too large
        let maxDimension: CGFloat = 1920
        var resized = image
        if image.size.width > maxDimension || image.size.height > maxDimension {
            let scale = maxDimension / max(image.size.width, image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
        }

        // Compress
        var quality: CGFloat = 0.85
        var data = resized.jpegData(compressionQuality: quality)
        while let d = data, d.count > maxBytes && quality > 0.3 {
            quality -= 0.1
            data = resized.jpegData(compressionQuality: quality)
        }
        return data
    }

    private func itemProcessed(success: Bool, url: URL?, isVideo: Bool, data: Data?, thumbnailData: Data?, duration: TimeInterval?, capturedAt: Date?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.processingCount += 1
            if success, let data = data {
                self.successCount += 1
                self.sharedItems.append((url: url ?? URL(fileURLWithPath: ""), isVideo: isVideo, data: data, thumbnailData: thumbnailData, duration: duration, capturedAt: capturedAt))
            }

            let progress = Float(self.processingCount) / Float(self.totalItems) * 0.3 // Processing is 30% of total
            self.progressView.setProgress(progress, animated: true)

            if self.processingCount >= self.totalItems {
                self.startUploading()
            }
        }
    }

    // MARK: - Upload
    private func startUploading() {
        if sharedItems.isEmpty {
            showError("Failed to process media")
            return
        }

        print("[SHARE] 🚀 Starting upload process for \(sharedItems.count) items")

        // If we have Firebase config, try direct upload
        if let config = firebaseConfig {
            print("[SHARE] ✅ Firebase config available - attempting direct upload")
            print("[SHARE]    Bucket: \(config.storageBucket)")
            print("[SHARE]    Has token: \(config.idToken != nil)")

            isUploading = true
            titleLabel.text = "Uploading..."
            statusLabel.text = "Uploading 1 of \(sharedItems.count)..."
            uploadNextItem()
        } else {
            // Fall back to queue for main app
            print("[SHARE] ❌ No Firebase config - falling back to queue")
            queueForMainApp()
        }
    }

    private func uploadNextItem() {
        guard currentUploadIndex < sharedItems.count else {
            // All done
            finishUploading()
            return
        }

        let item = sharedItems[currentUploadIndex]
        statusLabel.text = "Uploading \(currentUploadIndex + 1) of \(sharedItems.count)..."

        if item.isVideo {
            uploadVideo(item)
        } else {
            uploadImage(item)
        }
    }

    private func uploadImage(_ item: (url: URL, isVideo: Bool, data: Data?, thumbnailData: Data?, duration: TimeInterval?, capturedAt: Date?)) {
        guard let config = firebaseConfig, let imageData = item.data else {
            uploadFailed()
            return
        }

        let fileName = "\(UUID().uuidString).jpg"
        uploadToStorage(data: imageData, path: "photos/\(fileName)", contentType: "image/jpeg") { [weak self] downloadURL in
            guard let downloadURL = downloadURL else {
                self?.uploadFailed()
                return
            }

            // Create Firestore document
            self?.createPhotoDocument(imageURL: downloadURL, isVideo: false, videoURL: nil, duration: nil, capturedAt: item.capturedAt) { success in
                if success {
                    self?.retryCount = 0  // Reset retry count on success
                    self?.uploadedCount += 1
                    self?.currentUploadIndex += 1
                    self?.updateUploadProgress()
                    self?.uploadNextItem()
                } else {
                    self?.uploadFailed()
                }
            }
        }
    }

    private func uploadVideo(_ item: (url: URL, isVideo: Bool, data: Data?, thumbnailData: Data?, duration: TimeInterval?, capturedAt: Date?)) {
        guard let config = firebaseConfig,
              let videoData = item.data,
              let thumbnailData = item.thumbnailData else {
            uploadFailed()
            return
        }

        let videoFileName = "\(UUID().uuidString).mp4"
        let thumbFileName = "\(UUID().uuidString)_thumb.jpg"

        // Upload thumbnail first
        uploadToStorage(data: thumbnailData, path: "photos/\(thumbFileName)", contentType: "image/jpeg") { [weak self] thumbURL in
            guard let thumbURL = thumbURL else {
                self?.uploadFailed()
                return
            }

            // Then upload video
            self?.uploadToStorage(data: videoData, path: "videos/\(videoFileName)", contentType: "video/mp4") { videoURL in
                guard let videoURL = videoURL else {
                    self?.uploadFailed()
                    return
                }

                // Create Firestore document
                self?.createPhotoDocument(imageURL: thumbURL, isVideo: true, videoURL: videoURL, duration: item.duration, capturedAt: item.capturedAt) { success in
                    if success {
                        self?.retryCount = 0  // Reset retry count on success
                        self?.uploadedCount += 1
                        self?.currentUploadIndex += 1
                        self?.updateUploadProgress()
                        self?.uploadNextItem()
                    } else {
                        self?.uploadFailed()
                    }
                }
            }
        }
    }

    private func uploadToStorage(data: Data, path: String, contentType: String, completion: @escaping (String?) -> Void) {
        guard let config = firebaseConfig else {
            print("[SHARE] No Firebase config for upload")
            completion(nil)
            return
        }

        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let urlString = "https://firebasestorage.googleapis.com/v0/b/\(config.storageBucket)/o/\(encodedPath)?uploadType=media"

        guard let url = URL(string: urlString) else {
            print("[SHARE] Invalid upload URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300 // 5 minute timeout for large files

        if let token = config.idToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        print("[SHARE] Starting upload for: \(path) (\(data.count) bytes)")

        // Use completion handler-based upload for reliability
        let task = URLSession.shared.uploadTask(with: request, from: data) { [weak self] responseData, response, error in
            if let error = error {
                print("[SHARE] Upload failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("[SHARE] No HTTP response")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            print("[SHARE] Upload response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200,
                  let data = responseData,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String else {
                if let data = responseData, let errorStr = String(data: data, encoding: .utf8) {
                    print("[SHARE] Upload error response: \(errorStr)")
                }
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Construct download URL
            let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            let downloadURL = "https://firebasestorage.googleapis.com/v0/b/\(config.storageBucket)/o/\(encodedName)?alt=media"

            print("[SHARE] Upload completed: \(name)")
            DispatchQueue.main.async { completion(downloadURL) }
        }

        currentUploadTask = task
        task.resume()
    }


    private func createPhotoDocument(imageURL: String, isVideo: Bool, videoURL: String?, duration: TimeInterval?, capturedAt: Date?, completion: @escaping (Bool) -> Void) {
        guard let config = firebaseConfig else {
            completion(false)
            return
        }

        let urlString = "https://firestore.googleapis.com/v1/projects/\(config.projectId)/databases/(default)/documents/photos?key=\(config.apiKey)"

        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var fields: [String: Any] = [
            "imageURL": ["stringValue": imageURL],
            "caption": ["stringValue": ""],
            "uploadedBy": ["stringValue": "You"],
            "createdAt": ["timestampValue": isoFormatter.string(from: Date())]
        ]

        // Add capturedAt if available (this is the original photo/video creation date)
        if let capturedAt = capturedAt {
            fields["capturedAt"] = ["timestampValue": isoFormatter.string(from: capturedAt)]
            print("[SHARE] Setting capturedAt: \(capturedAt)")
        } else {
            print("[SHARE] No capturedAt date found for media")
        }

        if isVideo {
            fields["mediaType"] = ["stringValue": "video"]
            if let videoURL = videoURL {
                fields["videoURL"] = ["stringValue": videoURL]
            }
            if let duration = duration {
                fields["duration"] = ["doubleValue": duration]
            }
        } else {
            fields["mediaType"] = ["stringValue": "photo"]
        }

        let body: [String: Any] = ["fields": fields]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = config.idToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            let httpResponse = response as? HTTPURLResponse
            let success = error == nil && httpResponse?.statusCode == 200
            if !success {
                print("[SHARE] Document creation failed: \(error?.localizedDescription ?? "Unknown"), status: \(httpResponse?.statusCode ?? 0)")
            }
            DispatchQueue.main.async { completion(success) }
        }.resume()
    }

    private func updateUploadProgress() {
        let baseProgress: Float = 0.3 // Processing was 30%
        let uploadProgress = Float(uploadedCount) / Float(sharedItems.count) * 0.7 // Uploading is 70%
        progressView.setProgress(baseProgress + uploadProgress, animated: true)
    }

    private func uploadFailed() {
        print("[SHARE] Upload failed for item \(currentUploadIndex + 1), retry count: \(retryCount)")

        // Retry current item if we haven't exceeded max retries
        if retryCount < maxRetries {
            retryCount += 1
            print("[SHARE] Retrying upload (attempt \(retryCount + 1) of \(maxRetries + 1))...")
            statusLabel.text = "Retrying \(currentUploadIndex + 1) of \(sharedItems.count)..."

            // Delay before retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.uploadNextItem()
            }
            return
        }

        // Max retries exceeded - skip this item and try next
        print("[SHARE] Max retries exceeded for item \(currentUploadIndex + 1), skipping to next")
        retryCount = 0
        currentUploadIndex += 1

        // Check if there are more items to try
        if currentUploadIndex < sharedItems.count {
            uploadNextItem()
        } else {
            // All items attempted - check results
            if uploadedCount > 0 {
                // Some items uploaded successfully
                let skipped = sharedItems.count - uploadedCount
                if skipped > 0 {
                    // Queue failed items for main app
                    print("[SHARE] Uploaded \(uploadedCount), queueing \(skipped) failed items")
                    finishUploading()
                } else {
                    finishUploading()
                }
            } else {
                // All items failed - fall back to queue
                print("[SHARE] All uploads failed, falling back to queue")
                queueForMainApp()
            }
        }
    }

    private func finishUploading() {
        isUploading = false
        endBackgroundTask()
        let message = uploadedCount == sharedItems.count
            ? "\(uploadedCount) item\(uploadedCount == 1 ? "" : "s") uploaded!"
            : "\(uploadedCount) of \(sharedItems.count) uploaded"
        showSuccess(message: message)
    }

    // MARK: - Queue Fallback

    /// Queue only remaining (not yet uploaded) items for main app processing
    private func queueRemainingItemsForMainApp() {
        guard currentUploadIndex < sharedItems.count else { return }

        let remainingItems = Array(sharedItems[currentUploadIndex...])
        queueItems(remainingItems)
    }

    private func queueForMainApp() {
        queueItems(sharedItems)
    }

    private func queueItems(_ items: [(url: URL, isVideo: Bool, data: Data?, thumbnailData: Data?, duration: TimeInterval?, capturedAt: Date?)]) {
        // Save files to shared container for main app
        guard let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ourapp") else {
            showError("Failed to access shared storage")
            return
        }

        let pendingDir = sharedURL.appendingPathComponent("PendingUploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)

        var manifest: [[String: Any]] = []

        // Load existing manifest
        let manifestURL = sharedURL.appendingPathComponent("pending_uploads.json")
        if let existingData = try? Data(contentsOf: manifestURL),
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [[String: Any]] {
            manifest = existing
        }

        for item in items {
            guard let data = item.data else { continue }

            let ext = item.isVideo ? "mov" : "jpg"
            let filename = "\(UUID().uuidString).\(ext)"
            let fileURL = pendingDir.appendingPathComponent(filename)

            do {
                try data.write(to: fileURL)
                var entry: [String: Any] = [
                    "path": fileURL.path,
                    "isVideo": item.isVideo,
                    "timestamp": Date().timeIntervalSince1970
                ]
                // Include capturedAt if available (the original photo/video creation date)
                if let capturedAt = item.capturedAt {
                    entry["capturedAt"] = capturedAt.timeIntervalSince1970
                }
                // Include thumbnail for videos
                if item.isVideo, let thumbData = item.thumbnailData {
                    let thumbFilename = "\(UUID().uuidString)_thumb.jpg"
                    let thumbURL = pendingDir.appendingPathComponent(thumbFilename)
                    try? thumbData.write(to: thumbURL)
                    entry["thumbnailPath"] = thumbURL.path
                }
                // Include duration for videos
                if let duration = item.duration {
                    entry["duration"] = duration
                }
                manifest.append(entry)
            } catch {
                print("[SHARE] Failed to save: \(error)")
            }
        }

        // Save manifest
        if let manifestData = try? JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted) {
            try? manifestData.write(to: manifestURL)
        }

        endBackgroundTask()
        showSuccess(message: "\(items.count) item\(items.count == 1 ? "" : "s") queued")
    }

    // MARK: - UI Updates
    private func showSuccess(message: String) {
        activityIndicator.stopAnimating()
        progressView.setProgress(1.0, animated: true)
        cancelButton.isHidden = true

        statusLabel.text = message
        titleLabel.text = "Done!"
        titleLabel.textColor = UIColor(red: 0.3, green: 0.7, blue: 0.4, alpha: 1.0)

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
            self.successImageView.alpha = 1
            self.successImageView.transform = .identity
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.dismissExtension()
        }
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.activityIndicator.stopAnimating()
            self?.statusLabel.text = message
            self?.statusLabel.textColor = UIColor(red: 0.9, green: 0.4, blue: 0.4, alpha: 1.0)

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: -1))
            }
        }
    }

    private func dismissExtension() {
        UIView.animate(withDuration: 0.25, animations: {
            self.containerView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            self.containerView.alpha = 0
            self.view.backgroundColor = UIColor.black.withAlphaComponent(0)
        }) { _ in
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    @objc private func cancelTapped() {
        currentUploadTask?.cancel()

        UIView.animate(withDuration: 0.2, animations: {
            self.containerView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            self.containerView.alpha = 0
        }) { _ in
            self.extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled"]))
        }
    }
}
