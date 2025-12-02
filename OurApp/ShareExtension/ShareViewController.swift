import UIKit
import Social
import UniformTypeIdentifiers
import MobileCoreServices

/// Share Extension view controller for handling shared photos and videos from other apps
class ShareViewController: UIViewController {

    // MARK: - Properties
    private var sharedItems: [(url: URL, isVideo: Bool)] = []
    private var processingCount = 0
    private var totalItems = 0

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

        statusLabel.text = "Opening OurApp..."
        activityIndicator.stopAnimating()

        // Open main app via URL scheme
        let urlString = "ourapp://import-media"
        if let url = URL(string: urlString) {
            // Use openURL to launch main app
            var responder: UIResponder? = self
            while responder != nil {
                if let application = responder as? UIApplication {
                    application.open(url, options: [:], completionHandler: nil)
                    break
                }
                responder = responder?.next
            }
        }

        // Complete extension after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func writePendingUploadManifest() {
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ourapp") else {
            return
        }

        let manifest: [[String: Any]] = sharedItems.map { item in
            return [
                "path": item.url.path,
                "isVideo": item.isVideo,
                "timestamp": Date().timeIntervalSince1970
            ]
        }

        let manifestURL = sharedContainerURL.appendingPathComponent("pending_uploads.json")

        do {
            let data = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
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
        extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled"]))
    }
}
