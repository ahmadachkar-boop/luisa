import Foundation
import SwiftUI
import Combine

// MARK: - Upload Task Model
/// Represents a single upload task with progress tracking
struct UploadTask: Identifiable, Equatable {
    let id: String
    let type: UploadType
    let fileName: String
    var progress: Double      // 0.0 to 1.0
    var status: UploadStatus
    let createdAt: Date
    var eventId: String?      // Optional event ID if uploading to an event

    enum UploadType: String {
        case photo = "Photo"
        case voiceMemo = "Voice Memo"
    }

    enum UploadStatus: Equatable {
        case pending
        case uploading
        case completed
        case failed(String)

        var isActive: Bool {
            switch self {
            case .pending, .uploading:
                return true
            case .completed, .failed:
                return false
            }
        }
    }

    static func == (lhs: UploadTask, rhs: UploadTask) -> Bool {
        lhs.id == rhs.id &&
        lhs.progress == rhs.progress &&
        lhs.status == rhs.status
    }
}

// MARK: - Upload Batch Model
/// Represents a batch of uploads (e.g., multiple photos selected at once)
struct UploadBatch: Identifiable {
    let id: String
    let totalCount: Int
    var completedCount: Int
    var failedCount: Int
    var tasks: [UploadTask]
    let createdAt: Date
    var eventId: String?

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var isComplete: Bool {
        completedCount + failedCount >= totalCount
    }

    var statusText: String {
        if isComplete {
            if failedCount > 0 {
                return "Completed with \(failedCount) error\(failedCount == 1 ? "" : "s")"
            }
            return "Completed"
        }
        return "Uploading \(completedCount + 1) of \(totalCount)"
    }
}

// MARK: - Upload Progress Manager
/// Global manager to track upload progress across the app, persisting state during navigation
class UploadProgressManager: ObservableObject {
    static let shared = UploadProgressManager()

    @Published private(set) var activeBatches: [UploadBatch] = []
    @Published private(set) var isUploading: Bool = false
    @Published private(set) var totalProgress: Double = 0.0

    // Recently completed batches (kept for a short time to show completion)
    @Published private(set) var recentlyCompletedBatches: [UploadBatch] = []

    private var cleanupTimer: Timer?
    private let completedBatchRetentionTime: TimeInterval = 5.0 // Show completed for 5 seconds

    private init() {
        startCleanupTimer()
    }

    // MARK: - Public API

    /// Create a new upload batch
    func createBatch(count: Int, type: UploadTask.UploadType, eventId: String? = nil) -> String {
        let batchId = UUID().uuidString
        let tasks = (0..<count).map { index in
            UploadTask(
                id: "\(batchId)_\(index)",
                type: type,
                fileName: "\(type.rawValue) \(index + 1)",
                progress: 0,
                status: .pending,
                createdAt: Date(),
                eventId: eventId
            )
        }

        let batch = UploadBatch(
            id: batchId,
            totalCount: count,
            completedCount: 0,
            failedCount: 0,
            tasks: tasks,
            createdAt: Date(),
            eventId: eventId
        )

        DispatchQueue.main.async {
            self.activeBatches.append(batch)
            self.updateGlobalState()
        }

        return batchId
    }

    /// Update progress for a specific task in a batch
    func updateTaskProgress(batchId: String, taskIndex: Int, progress: Double) {
        DispatchQueue.main.async {
            guard let batchIndex = self.activeBatches.firstIndex(where: { $0.id == batchId }),
                  taskIndex < self.activeBatches[batchIndex].tasks.count else {
                return
            }

            self.activeBatches[batchIndex].tasks[taskIndex].progress = progress
            self.activeBatches[batchIndex].tasks[taskIndex].status = .uploading
            self.updateGlobalState()
        }
    }

    /// Mark a task as completed
    func completeTask(batchId: String, taskIndex: Int) {
        DispatchQueue.main.async {
            guard let batchIndex = self.activeBatches.firstIndex(where: { $0.id == batchId }),
                  taskIndex < self.activeBatches[batchIndex].tasks.count else {
                return
            }

            self.activeBatches[batchIndex].tasks[taskIndex].progress = 1.0
            self.activeBatches[batchIndex].tasks[taskIndex].status = .completed
            self.activeBatches[batchIndex].completedCount += 1

            self.checkBatchCompletion(at: batchIndex)
            self.updateGlobalState()
        }
    }

    /// Mark a task as failed
    func failTask(batchId: String, taskIndex: Int, error: String) {
        DispatchQueue.main.async {
            guard let batchIndex = self.activeBatches.firstIndex(where: { $0.id == batchId }),
                  taskIndex < self.activeBatches[batchIndex].tasks.count else {
                return
            }

            self.activeBatches[batchIndex].tasks[taskIndex].status = .failed(error)
            self.activeBatches[batchIndex].failedCount += 1

            self.checkBatchCompletion(at: batchIndex)
            self.updateGlobalState()
        }
    }

    /// Get current batch for an event (useful for showing progress on event detail page)
    func currentBatch(forEventId eventId: String) -> UploadBatch? {
        return activeBatches.first { $0.eventId == eventId && !$0.isComplete }
    }

    /// Get all active batches for an event
    func activeBatches(forEventId eventId: String) -> [UploadBatch] {
        return activeBatches.filter { $0.eventId == eventId && !$0.isComplete }
    }

    /// Check if there are any active uploads for an event
    func hasActiveUploads(forEventId eventId: String) -> Bool {
        return activeBatches.contains { $0.eventId == eventId && !$0.isComplete }
    }

    /// Clear completed batches immediately
    func clearCompletedBatches() {
        DispatchQueue.main.async {
            self.recentlyCompletedBatches.removeAll()
        }
    }

    // MARK: - Private Methods

    private func checkBatchCompletion(at index: Int) {
        guard index < activeBatches.count else { return }

        let batch = activeBatches[index]
        if batch.isComplete {
            // Move to recently completed
            recentlyCompletedBatches.append(batch)
            activeBatches.remove(at: index)
        }
    }

    private func updateGlobalState() {
        isUploading = !activeBatches.isEmpty

        if activeBatches.isEmpty {
            totalProgress = 0
        } else {
            let totalTasks = activeBatches.reduce(0) { $0 + $1.totalCount }
            let completedTasks = activeBatches.reduce(0) { $0 + $1.completedCount }
            totalProgress = totalTasks > 0 ? Double(completedTasks) / Double(totalTasks) : 0
        }
    }

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.cleanupOldCompletedBatches()
        }
    }

    private func cleanupOldCompletedBatches() {
        let cutoff = Date().addingTimeInterval(-completedBatchRetentionTime)
        DispatchQueue.main.async {
            self.recentlyCompletedBatches.removeAll { batch in
                // Only remove if all tasks are complete (not failed)
                batch.failedCount == 0 && batch.createdAt < cutoff
            }
        }
    }

    deinit {
        cleanupTimer?.invalidate()
    }
}

// MARK: - Upload Progress Banner View
/// A floating banner that shows upload progress, visible across all screens
struct UploadProgressBanner: View {
    @ObservedObject var uploadManager = UploadProgressManager.shared
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Only show if there are active uploads or recently completed
            if uploadManager.isUploading || !uploadManager.recentlyCompletedBatches.isEmpty {
                VStack(spacing: 8) {
                    // Main progress bar
                    HStack(spacing: 12) {
                        // Icon
                        if uploadManager.isUploading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }

                        // Status text
                        VStack(alignment: .leading, spacing: 2) {
                            if let firstBatch = uploadManager.activeBatches.first {
                                Text(firstBatch.statusText)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(AppTheme.Colors.textPrimary)
                            } else if let completedBatch = uploadManager.recentlyCompletedBatches.first {
                                Text(completedBatch.statusText)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(AppTheme.Colors.textPrimary)
                            }

                            if uploadManager.activeBatches.count > 1 {
                                Text("+\(uploadManager.activeBatches.count - 1) more")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.Colors.textTertiary)
                            }
                        }

                        Spacer()

                        // Progress percentage
                        if uploadManager.isUploading {
                            Text("\(Int(uploadManager.totalProgress * 100))%")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppTheme.Colors.accent)
                        }

                        // Expand/collapse button
                        if uploadManager.activeBatches.count > 1 || isExpanded {
                            Button(action: {
                                withAnimation(.spring(response: 0.3)) {
                                    isExpanded.toggle()
                                }
                            }) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.Colors.textTertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    // Progress bar
                    if uploadManager.isUploading {
                        ProgressView(value: uploadManager.totalProgress)
                            .tint(AppTheme.Colors.accent)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    // Expanded details
                    if isExpanded {
                        VStack(spacing: 8) {
                            ForEach(uploadManager.activeBatches) { batch in
                                HStack {
                                    Text(batch.eventId != nil ? "Event Upload" : "Gallery Upload")
                                        .font(.caption)
                                        .foregroundColor(AppTheme.Colors.textSecondary)
                                    Spacer()
                                    Text(batch.statusText)
                                        .font(.caption)
                                        .foregroundColor(AppTheme.Colors.textTertiary)
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                )
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: uploadManager.isUploading)
        .animation(.spring(response: 0.3), value: uploadManager.recentlyCompletedBatches.count)
    }
}

// MARK: - Preview
#Preview {
    VStack {
        UploadProgressBanner()
        Spacer()
    }
    .onAppear {
        // Simulate an upload for preview
        let batchId = UploadProgressManager.shared.createBatch(count: 5, type: .photo, eventId: "test")
        UploadProgressManager.shared.updateTaskProgress(batchId: batchId, taskIndex: 0, progress: 0.5)
    }
}
