import UIKit
import Social
import UniformTypeIdentifiers
import MobileCoreServices
import AVFoundation

/// Share Extension that uploads directly to Firebase with progress
/// Uses background URLSession to continue uploads even after extension closes
class ShareViewController: UIViewController, URLSessionTaskDelegate, URLSessionDataDelegate {

    // MARK: - Properties
    private var sharedItems: [(url: URL, isVideo: Bool, data: Data?, thumbnailData: Data?, duration: TimeInterval?)] = []
    private var processingCount = 0
    private var totalItems = 0
    private var successCount = 0
    private var uploadedCount = 0
    private var currentUploadIndex = 0
    private var isUploading = false
    private var uploadSession: URLSession?
    private var currentUploadTask: URLSessionUploadTask?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // For tracking upload progress
    private var uploadTasks: [URLSessionTask: UploadTaskInfo] = [:]
    private var pendingDocumentCreations: Int = 0

    // Firebase configuration - loaded from shared container
    private var firebaseConfig: FirebaseConfig?

    private struct FirebaseConfig: Codable {
        let storageBucket: String
        let projectId: String
        let apiKey: String
        let idToken: String? // Auth token if user is signed in
    }

    private struct UploadTaskInfo {
        let itemIndex: Int
        let isVideo: Bool
        let isThumbnail: Bool
        let data: Data
        var thumbnailURL: String?
        var videoURL: String?
        var duration: TimeInterval?
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
    private func beginBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "ShareUpload") { [weak self] in
            // Called when time is about to expire
            print("[SHARE] Background time expiring, falling back to queue")
            self?.queueRemainingItemsForMainApp()
            self?.endBackgroundTask()
        }
        print("[SHARE] Started background task: \(backgroundTaskID.rawValue)")
    }

    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
            print("[SHARE] Ended background task")
        }
    }

    // MARK: - URL Session Setup
    private func setupUploadSession() {
        // Use a session with delegate for progress tracking
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        uploadSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
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
            return
        }

        let configURL = sharedURL.appendingPathComponent("firebase_share_config.json")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(FirebaseConfig.self, from: data) else {
            print("[SHARE] No Firebase config found - will queue for main app")
            return
        }

        firebaseConfig = config
        print("[SHARE] Firebase config loaded - direct upload enabled")
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
            itemProcessed(success: false, url: nil, isVideo: false, data: nil, thumbnailData: nil, duration: nil)
        }
    }

    private func loadImage(from attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
            guard error == nil else {
                self?.itemProcessed(success: false, url: nil, isVideo: false, data: nil, thumbnailData: nil, duration: nil)
                return
            }

            var imageData: Data?
            var fileURL: URL?

            if let url = item as? URL {
                fileURL = url
                imageData = try? Data(contentsOf: url)
            } else if let image = item as? UIImage {
                imageData = self?.compressImage(image)
            } else if let data = item as? Data, let image = UIImage(data: data) {
                imageData = self?.compressImage(image)
            }

            if let data = imageData {
                self?.itemProcessed(success: true, url: fileURL, isVideo: false, data: data, thumbnailData: nil, duration: nil)
            } else {
                self?.itemProcessed(success: false, url: nil, isVideo: false, data: nil, thumbnailData: nil, duration: nil)
            }
        }
    }

    private func loadVideo(from attachment: NSItemProvider) {
        let videoType = attachment.hasItemConformingToTypeIdentifier(UTType.quickTimeMovie.identifier) ?
            UTType.quickTimeMovie.identifier : UTType.movie.identifier

        attachment.loadItem(forTypeIdentifier: videoType, options: nil) { [weak self] item, error in
            guard error == nil, let url = item as? URL else {
                self?.itemProcessed(success: false, url: nil, isVideo: true, data: nil, thumbnailData: nil, duration: nil)
                return
            }

            // Generate thumbnail and get duration
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true

            var thumbnailData: Data?
            var duration: TimeInterval = 0

            do {
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                thumbnailData = self?.compressImage(thumbnail, maxBytes: 200_000)
                duration = CMTimeGetSeconds(asset.duration)
            } catch {
                print("[SHARE] Failed to generate thumbnail: \(error)")
            }

            // Read video data
            let videoData = try? Data(contentsOf: url)

            self?.itemProcessed(success: videoData != nil, url: url, isVideo: true, data: videoData, thumbnailData: thumbnailData, duration: duration)
        }
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

    private func itemProcessed(success: Bool, url: URL?, isVideo: Bool, data: Data?, thumbnailData: Data?, duration: TimeInterval?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.processingCount += 1
            if success, let data = data {
                self.successCount += 1
                self.sharedItems.append((url: url ?? URL(fileURLWithPath: ""), isVideo: isVideo, data: data, thumbnailData: thumbnailData, duration: duration))
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

        // If we have Firebase config, try direct upload
        if firebaseConfig != nil {
            isUploading = true
            titleLabel.text = "Uploading..."
            statusLabel.text = "Uploading 1 of \(sharedItems.count)..."
            uploadNextItem()
        } else {
            // Fall back to queue for main app
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

    private func uploadImage(_ item: (url: URL, isVideo: Bool, data: Data?, thumbnailData: Data?, duration: TimeInterval?)) {
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
            self?.createPhotoDocument(imageURL: downloadURL, isVideo: false, videoURL: nil, duration: nil) { success in
                if success {
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

    private func uploadVideo(_ item: (url: URL, isVideo: Bool, data: Data?, thumbnailData: Data?, duration: TimeInterval?)) {
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
                self?.createPhotoDocument(imageURL: thumbURL, isVideo: true, videoURL: videoURL, duration: item.duration) { success in
                    if success {
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

    private var uploadCompletions: [URLSessionTask: (String?) -> Void] = [:]

    private func uploadToStorage(data: Data, path: String, contentType: String, completion: @escaping (String?) -> Void) {
        guard let config = firebaseConfig, let session = uploadSession else {
            completion(nil)
            return
        }

        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let urlString = "https://firebasestorage.googleapis.com/v0/b/\(config.storageBucket)/o/\(encodedPath)?uploadType=media"

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        if let token = config.idToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Write data to temp file for upload task
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try data.write(to: tempURL)
        } catch {
            print("[SHARE] Failed to write temp file: \(error)")
            completion(nil)
            return
        }

        let task = session.uploadTask(with: request, fromFile: tempURL)
        uploadCompletions[task] = completion
        currentUploadTask = task
        task.resume()

        print("[SHARE] Started upload task for: \(path)")
    }

    // MARK: - URLSessionTaskDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        // Update progress for current item
        let itemProgress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        let baseProgress: Float = 0.3 // Processing is 30%
        let perItemProgress: Float = 0.7 / Float(max(sharedItems.count, 1))
        let overallProgress = baseProgress + (Float(uploadedCount) * perItemProgress) + (itemProgress * perItemProgress)

        DispatchQueue.main.async { [weak self] in
            self?.progressView.setProgress(min(overallProgress, 1.0), animated: true)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let completion = uploadCompletions.removeValue(forKey: task) else { return }

        if let error = error {
            print("[SHARE] Upload task failed: \(error.localizedDescription)")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // Success - process response data
        guard let config = firebaseConfig,
              let data = responseData.removeValue(forKey: task),
              let httpResponse = task.response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            print("[SHARE] Upload response invalid or failed")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // Construct download URL
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let downloadURL = "https://firebasestorage.googleapis.com/v0/b/\(config.storageBucket)/o/\(encodedName)?alt=media"

        print("[SHARE] Upload completed: \(name)")
        DispatchQueue.main.async { completion(downloadURL) }
    }

    // MARK: - URLSessionDataDelegate

    private var responseData: [URLSessionTask: Data] = [:]

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if responseData[dataTask] == nil {
            responseData[dataTask] = Data()
        }
        responseData[dataTask]?.append(data)
    }

    private func createPhotoDocument(imageURL: String, isVideo: Bool, videoURL: String?, duration: TimeInterval?, completion: @escaping (Bool) -> Void) {
        guard let config = firebaseConfig else {
            completion(false)
            return
        }

        let urlString = "https://firestore.googleapis.com/v1/projects/\(config.projectId)/databases/(default)/documents/photos?key=\(config.apiKey)"

        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }

        var fields: [String: Any] = [
            "imageURL": ["stringValue": imageURL],
            "caption": ["stringValue": ""],
            "uploadedBy": ["stringValue": "You"],
            "createdAt": ["timestampValue": ISO8601DateFormatter().string(from: Date())]
        ]

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
            let success = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(success) }
        }.resume()
    }

    private func updateUploadProgress() {
        let baseProgress: Float = 0.3 // Processing was 30%
        let uploadProgress = Float(uploadedCount) / Float(sharedItems.count) * 0.7 // Uploading is 70%
        progressView.setProgress(baseProgress + uploadProgress, animated: true)
    }

    private func uploadFailed() {
        print("[SHARE] Upload failed, falling back to queue")
        // Fall back to queue
        queueForMainApp()
    }

    private func finishUploading() {
        isUploading = false
        endBackgroundTask()
        showSuccess(message: "\(uploadedCount) item\(uploadedCount == 1 ? "" : "s") uploaded!")
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

    private func queueItems(_ items: [(url: URL, isVideo: Bool, data: Data?, thumbnailData: Data?, duration: TimeInterval?)]) {
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
                manifest.append([
                    "path": fileURL.path,
                    "isVideo": item.isVideo,
                    "timestamp": Date().timeIntervalSince1970
                ])
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
