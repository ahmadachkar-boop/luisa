import UIKit
import Social
import UniformTypeIdentifiers
import MobileCoreServices

/// Share Extension view controller for handling shared photos and videos from other apps
/// Uploads are queued and processed by the main app - no app switch required
class ShareViewController: UIViewController {

    // MARK: - Properties
    private var sharedItems: [(url: URL, isVideo: Bool)] = []
    private var processingCount = 0
    private var totalItems = 0
    private var successCount = 0

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
        label.text = "Preparing media..."
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
        processSharedItems()
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
            containerView.heightAnchor.constraint(equalToConstant: 200),

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
        // Check for video first
        if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ||
           attachment.hasItemConformingToTypeIdentifier(UTType.video.identifier) ||
           attachment.hasItemConformingToTypeIdentifier(UTType.quickTimeMovie.identifier) ||
           attachment.hasItemConformingToTypeIdentifier(UTType.mpeg4Movie.identifier) {
            loadVideo(from: attachment)
        }
        // Then check for image
        else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            loadImage(from: attachment)
        }
        else {
            // Unknown type
            itemProcessed(success: false)
        }
    }

    private func loadImage(from attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
            guard error == nil else {
                self?.itemProcessed(success: false)
                return
            }

            if let url = item as? URL {
                self?.saveItemToSharedContainer(url: url, isVideo: false)
            } else if let image = item as? UIImage {
                self?.saveImageToSharedContainer(image: image)
            } else if let data = item as? Data, let image = UIImage(data: data) {
                self?.saveImageToSharedContainer(image: image)
            } else {
                self?.itemProcessed(success: false)
            }
        }
    }

    private func loadVideo(from attachment: NSItemProvider) {
        let videoType = attachment.hasItemConformingToTypeIdentifier(UTType.quickTimeMovie.identifier) ?
            UTType.quickTimeMovie.identifier : UTType.movie.identifier

        attachment.loadItem(forTypeIdentifier: videoType, options: nil) { [weak self] item, error in
            guard error == nil else {
                self?.itemProcessed(success: false)
                return
            }

            if let url = item as? URL {
                self?.saveItemToSharedContainer(url: url, isVideo: true)
            } else {
                self?.itemProcessed(success: false)
            }
        }
    }

    private func saveImageToSharedContainer(image: UIImage) {
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ourapp") else {
            itemProcessed(success: false)
            return
        }

        let pendingDir = sharedContainerURL.appendingPathComponent("PendingUploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).jpg"
        let fileURL = pendingDir.appendingPathComponent(filename)

        // Compress to reasonable quality
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            itemProcessed(success: false)
            return
        }

        do {
            try data.write(to: fileURL)
            sharedItems.append((url: fileURL, isVideo: false))
            itemProcessed(success: true)
        } catch {
            itemProcessed(success: false)
        }
    }

    private func saveItemToSharedContainer(url: URL, isVideo: Bool) {
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ourapp") else {
            itemProcessed(success: false)
            return
        }

        let pendingDir = sharedContainerURL.appendingPathComponent("PendingUploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)

        let ext = isVideo ? "mov" : url.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destURL = pendingDir.appendingPathComponent(filename)

        do {
            // Security scoped resource access
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try FileManager.default.copyItem(at: url, to: destURL)
            sharedItems.append((url: destURL, isVideo: isVideo))
            itemProcessed(success: true)
        } catch {
            print("Failed to copy item: \(error)")
            itemProcessed(success: false)
        }
    }

    private func itemProcessed(success: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.processingCount += 1
            if success {
                self.successCount += 1
            }

            let progress = Float(self.processingCount) / Float(self.totalItems)
            self.progressView.setProgress(progress, animated: true)

            if self.processingCount >= self.totalItems {
                self.finishProcessing()
            }
        }
    }

    private func finishProcessing() {
        if sharedItems.isEmpty {
            showError("Failed to process media")
            return
        }

        // Write manifest file for main app to read
        writePendingUploadManifest()

        // Show success UI without opening the app
        showSuccess()
    }

    private func showSuccess() {
        activityIndicator.stopAnimating()
        progressView.isHidden = true
        cancelButton.isHidden = true

        let itemText = successCount == 1 ? "item" : "items"
        statusLabel.text = "\(successCount) \(itemText) added to queue"
        titleLabel.text = "Added!"
        titleLabel.textColor = UIColor(red: 0.3, green: 0.7, blue: 0.4, alpha: 1.0)

        // Animate success checkmark
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
            self.successImageView.alpha = 1
            self.successImageView.transform = .identity
        }

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Auto-dismiss after showing success
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.dismissExtension()
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

    private func writePendingUploadManifest() {
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ourapp") else {
            return
        }

        // Read existing manifest if any
        let manifestURL = sharedContainerURL.appendingPathComponent("pending_uploads.json")
        var existingItems: [[String: Any]] = []

        if let existingData = try? Data(contentsOf: manifestURL),
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [[String: Any]] {
            existingItems = existing
        }

        // Add new items
        let newItems: [[String: Any]] = sharedItems.map { item in
            return [
                "path": item.url.path,
                "isVideo": item.isVideo,
                "timestamp": Date().timeIntervalSince1970
            ]
        }

        let allItems = existingItems + newItems

        do {
            let data = try JSONSerialization.data(withJSONObject: allItems, options: .prettyPrinted)
            try data.write(to: manifestURL)
        } catch {
            print("Failed to write manifest: \(error)")
        }
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.activityIndicator.stopAnimating()
            self?.statusLabel.text = message
            self?.statusLabel.textColor = UIColor(red: 0.9, green: 0.4, blue: 0.4, alpha: 1.0)

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: -1))
            }
        }
    }

    @objc private func cancelTapped() {
        // Clean up any saved files
        for item in sharedItems {
            try? FileManager.default.removeItem(at: item.url)
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.containerView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            self.containerView.alpha = 0
        }) { _ in
            self.extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled"]))
        }
    }
}
