import Foundation
import os

@MainActor
class VoiceModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var isConnected = false
    
    private let logger = Logger(subsystem: "com.voiceflow", category: "voicemodel")
    private var audioRecorder: AudioRecorder?
    private let httpClient = HTTPClient()
    
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let role: String
        let content: String
        let timestamp: Date = .now
        
        static func == (lhs: Message, rhs: Message) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    init() {
        logger.info("VoiceModel initialized")
    }
    
    func connectServers() async {
        do {
            logger.info("Connecting to whisper.cpp and llama-server...")
            let whisperOk = await httpClient.testConnection(to: URL(string: "http://localhost:8081")!, endpoint: "/health")
            let llmOk = await httpClient.testConnection(to: URL(string: "http://localhost:8080")!, endpoint: "/api/v1/models")
            
            if whisperOk || llmOk {
                isConnected = true
                logger.info("✓ At least one server connected")
            } else {
                errorMessage = "Could not connect to servers. Ensure whisper.cpp (:8081) and llama-server (:8080) are running."
                isConnected = false
            }
        } catch {
            errorMessage = "Server connection failed: \(error.localizedDescription)"
            isConnected = false
        }
    }
    
    func toggleRecording() {
        if isRecording {
            Task { await stopRecording() }
        } else {
            Task { await startRecording() }
        }
    }
    
    @MainActor
    func startRecording() async {
        guard !isRecording else { return }
        
        isRecording = true
        errorMessage = nil
        
        do {
            let recorder = AudioRecorder()
            let recorderId = unsafeBitCast(recorder, to: UInt.self)
            logger.info("[VoiceModel startRecording: recorder=\(recorderId)]")
            audioRecorder = recorder
            try await recorder.start()
            logger.info("Recording started")
            
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isRecording = false
        }
    }
    
    @MainActor
    func stopRecording() async {
        guard isRecording, let recorder = audioRecorder else { return }
        
        let recorderId = unsafeBitCast(recorder, to: UInt.self)
        logger.info("[VoiceModel stopRecording: recorder=\(recorderId), isRecording=\(self.isRecording)]")
        isRecording = false
        await recorder.stop()
        logger.info("Audio recorder stopped")
        
        // Save URL BEFORE clearing recorder
        let audioURL = recorder.currentFileURL
        logger.info("[VoiceModel audioURL=\(audioURL?.absoluteString ?? "nil")]")
        
        audioRecorder = nil
        
        // Start transcription
        if let url = audioURL {
            logger.info("Starting transcription for: \(url.path)")
            await transcribeAudio(at: url)
        } else {
            logger.warning("No audio file recorded")
            isTranscribing = false
            errorMessage = "No audio was recorded."
        }
    }
    
    @MainActor
    private func transcribeAudio(at url: URL) async {
        isTranscribing = true
        errorMessage = nil
        logger.info("Starting transcription for: \(url.path)")
        
        do {
            let transcription = try await httpClient.transcribeAudio(from: url, serverURL: URL(string: "http://localhost:8081")!)
            logger.info("Transcription result: '\(transcription)'")
            logger.info("Transcription trimmed: '\(transcription.trimmingCharacters(in: .whitespacesAndNewlines))'")
            
            let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "[BLANK_AUDIO]" {
                logger.warning("Transcription is empty or blank audio")
                messages.append(Message(role: "user", content: "(silence detected)"))
                isTranscribing = false
                return
            }
            
            logger.info("Processing text for UI update")
            await processText(transcription)
            logger.info("Text processed successfully, messages count: \(self.messages.count)")
            
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription)")
            errorMessage = "Transcription failed: \(error.localizedDescription)"
            isTranscribing = false
        }
    }
    
    @MainActor
    private func processText(_ text: String) async {
        guard !text.isEmpty else { return }
        
        // Add user message
        messages.append(Message(role: "user", content: text))
        
        // Generate AI response
        await generateResponse(for: text)
    }
    
    @MainActor
    private func generateResponse(for prompt: String) async {
        isGenerating = true
        errorMessage = nil
        
        do {
            let response = try await httpClient.generateResponse(
                prompt: prompt,
                messages: messages,
                serverURL: URL(string: "http://localhost:8080")!
            )
            
            logger.info("Response: \(response)")
            messages.append(Message(role: "assistant", content: response))
            
        } catch {
            logger.error("Response failed: \(error.localizedDescription)")
            messages.append(Message(role: "assistant", content: "Server error: \(error.localizedDescription)"))
        }
        
        isGenerating = false
    }
}
