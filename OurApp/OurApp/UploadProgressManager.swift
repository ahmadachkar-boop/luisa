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

// MARK: - Mini Upload Indicator
/// Animated upload indicator similar to voice memo waveform
struct MiniUploadIndicator: View {
    let isUploading: Bool
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        if isUploading {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color(red: 0.8, green: 0.7, blue: 1.0))
                        .frame(width: 6, height: 6)
                        .offset(y: dotOffset(for: index))
                }
            }
            .onAppear {
                startAnimation()
            }
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.green)
        }
    }

    private func dotOffset(for index: Int) -> CGFloat {
        let phase = animationPhase + CGFloat(index) * 0.8
        return sin(phase) * 4
    }

    private func startAnimation() {
        withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
            animationPhase = .pi * 2
        }
    }
}

// MARK: - Upload Progress Banner View
/// A compact floating banner that shows upload progress, styled like mini player
struct UploadProgressBanner: View {
    @ObservedObject var uploadManager = UploadProgressManager.shared

    var body: some View {
        Group {
            // Only show if there are active uploads or recently completed
            if uploadManager.isUploading || !uploadManager.recentlyCompletedBatches.isEmpty {
                HStack(spacing: 12) {
                    // Animated upload indicator
                    MiniUploadIndicator(isUploading: uploadManager.isUploading)
                        .frame(width: 30)

                    // Status text
                    VStack(alignment: .leading, spacing: 2) {
                        if let firstBatch = uploadManager.activeBatches.first {
                            Text(firstBatch.statusText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))
                                .lineLimit(1)

                            if uploadManager.activeBatches.count > 1 {
                                Text("+\(uploadManager.activeBatches.count - 1) more upload\(uploadManager.activeBatches.count > 2 ? "s" : "")")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                            } else {
                                Text(firstBatch.eventId != nil ? "Event photos" : "Gallery photos")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                            }
                        } else if let completedBatch = uploadManager.recentlyCompletedBatches.first {
                            Text(completedBatch.statusText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))
                                .lineLimit(1)

                            Text("Upload complete")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                        }
                    }

                    Spacer()

                    // Progress percentage or completion indicator
                    if uploadManager.isUploading {
                        Text("\(Int(uploadManager.totalProgress * 100))%")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.85))
                    }

                    // Dismiss button for completed uploads
                    if !uploadManager.isUploading && !uploadManager.recentlyCompletedBatches.isEmpty {
                        Button(action: {
                            uploadManager.clearCompletedBatches()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.7))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: -2)
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: uploadManager.isUploading)
        .animation(.spring(response: 0.3), value: uploadManager.recentlyCompletedBatches.count)
    }
}

// MARK: - Preview
#Preview {
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.1)
            .ignoresSafeArea()

        VStack {
            Spacer()
            UploadProgressBanner()
                .padding(.bottom, 50)
        }
    }
    .onAppear {
        // Simulate an upload for preview
        let batchId = UploadProgressManager.shared.createBatch(count: 5, type: .photo, eventId: "test")
        UploadProgressManager.shared.updateTaskProgress(batchId: batchId, taskIndex: 0, progress: 0.5)
    }
}
