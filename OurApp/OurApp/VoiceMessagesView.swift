import SwiftUI
import AVFoundation

struct VoiceMessagesView: View {
    @StateObject private var viewModel = VoiceMessagesViewModel()
    @State private var showingRecorder = false

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

                VStack {
                    if viewModel.voiceMessages.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(Color(red: 0.7, green: 0.6, blue: 0.9))

                            Text("No voice messages yet")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.5))

                            Text("Tap + to record a sweet message 💜")
                                .font(.subheadline)
                                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(viewModel.voiceMessages) { message in
                                    VoiceMessageCard(
                                        message: message,
                                        isPlaying: viewModel.currentlyPlayingId == message.id,
                                        onPlay: {
                                            viewModel.playMessage(message)
                                        },
                                        onDelete: {
                                            Task {
                                                await viewModel.deleteMessage(message)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                }
                .navigationTitle("Voice Notes 💜")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showingRecorder = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
                        }
                    }
                }
                .sheet(isPresented: $showingRecorder) {
                    VoiceRecorderView { audioData, duration, title in
                        await viewModel.uploadVoiceMessage(
                            audioData: audioData,
                            title: title,
                            duration: duration
                        )
                    }
                }
            }
        }
    }
}

struct VoiceMessageCard: View {
    let message: VoiceMessage
    let isPlaying: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Color(red: 0.8, green: 0.7, blue: 1.0))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(red: 0.2, green: 0.1, blue: 0.4))

                HStack {
                    Text(formatDuration(message.duration))
                        .font(.caption)
                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                    Text("•")
                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))

                    Text(message.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.6))
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct VoiceRecorderView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var recorder = AudioRecorder()
    @State private var title = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    let onSave: (Data, TimeInterval, String) async -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                TextField("Message title (e.g., 'Good morning!')", text: $title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                // Waveform animation
                HStack(spacing: 4) {
                    ForEach(0..<20, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.8, green: 0.7, blue: 1.0))
                            .frame(width: 3, height: recorder.isRecording ? CGFloat.random(in: 10...60) : 10)
                            .animation(.easeInOut(duration: 0.3).repeatForever(), value: recorder.isRecording)
                    }
                }
                .frame(height: 60)

                if recorder.isRecording {
                    Text(formatTime(recorder.recordingTime))
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .monospacedDigit()
                }

                // Record button
                Button(action: {
                    if recorder.isRecording {
                        recorder.stopRecording()
                    } else {
                        recorder.startRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(recorder.isRecording ? Color.red : Color(red: 0.8, green: 0.7, blue: 1.0))
                            .frame(width: 80, height: 80)

                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 35))
                            .foregroundColor(.white)
                    }
                }

                if recorder.hasRecording {
                    Button("Save Recording") {
                        Task {
                            if let data = recorder.audioData {
                                await onSave(data, recorder.recordingDuration, title.isEmpty ? "Voice Note" : title)
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.8, green: 0.7, blue: 1.0))

                    Button("Discard", role: .destructive) {
                        recorder.deleteRecording()
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Record Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

class VoiceMessagesViewModel: ObservableObject {
    @Published var voiceMessages: [VoiceMessage] = []
    @Published var currentlyPlayingId: String?

    private var audioPlayer: AVAudioPlayer?
    private let firebaseManager = FirebaseManager.shared

    init() {
        loadVoiceMessages()
    }

    func loadVoiceMessages() {
        Task {
            for try await messages in firebaseManager.getVoiceMessages() {
                await MainActor.run {
                    self.voiceMessages = messages
                }
            }
        }
    }

    func uploadVoiceMessage(audioData: Data, title: String, duration: TimeInterval) async {
        do {
            _ = try await firebaseManager.uploadVoiceMessage(
                audioData: audioData,
                title: title,
                duration: duration,
                fromUser: "You"
            )
        } catch {
            print("Error uploading voice message: \(error)")
        }
    }

    func playMessage(_ message: VoiceMessage) {
        guard let url = URL(string: message.audioURL) else { return }

        if currentlyPlayingId == message.id {
            audioPlayer?.pause()
            currentlyPlayingId = nil
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                await MainActor.run {
                    do {
                        audioPlayer = try AVAudioPlayer(data: data)
                        audioPlayer?.play()
                        currentlyPlayingId = message.id
                    } catch {
                        print("Error playing audio: \(error)")
                    }
                }
            } catch {
                print("Error downloading audio: \(error)")
            }
        }
    }

    func deleteMessage(_ message: VoiceMessage) async {
        do {
            try await firebaseManager.deleteVoiceMessage(message)
        } catch {
            print("Error deleting message: \(error)")
        }
    }
}

class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var hasRecording = false
    @Published var recordingDuration: TimeInterval = 0

    var audioRecorder: AVAudioRecorder?
    var audioData: Data?
    private var timer: Timer?

    override init() {
        super.init()
        setupAudioSession()
    }

    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)
    }

    func startRecording() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording.m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()

            isRecording = true
            recordingTime = 0

            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.recordingTime += 0.1
            }
        } catch {
            print("Error starting recording: \(error)")
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()

        isRecording = false
        hasRecording = true
        recordingDuration = recordingTime

        if let url = audioRecorder?.url {
            audioData = try? Data(contentsOf: url)
        }
    }

    func deleteRecording() {
        hasRecording = false
        recordingTime = 0
        recordingDuration = 0
        audioData = nil
    }
}

#Preview {
    VoiceMessagesView()
}
