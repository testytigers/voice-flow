import Foundation
import os
import MCP

@MainActor
class VoiceModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var isConnected = false
    
    private let logger = Logger(subsystem: "com.voiceflow", category: "voicemodel")
    private var mcpClient: MCPClient?
    private var audioRecorder: AudioRecorder?
    
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
    
    func connectMCP() async {
        do {
            logger.info("Connecting to MCP servers...")
            
            mcpClient = MCPClient()
            try await mcpClient?.connect()
            
            isConnected = true
            logger.info("✓ MCP servers connected successfully")
            
            // List available tools for debugging
            await mcpClient?.listAvailableTools()
            
        } catch {
            logger.error("MCP connection failed: \(error.localizedDescription)")
            errorMessage = "Failed to connect to AI servers: \(error.localizedDescription)"
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
        
        isRecording = false
        await recorder.stop()
        
        // Start transcription
        await transcribeAudio()
    }
    
    @MainActor
    private func transcribeAudio() async {
        guard let audioURL = audioRecorder?.currentFileURL,
              let mcpClient = mcpClient else { return }
        
        isTranscribing = true
        errorMessage = nil
        
        do {
            let transcription = try await mcpClient.transcribeAudio(fileURL: audioURL)
            logger.info("Transcription complete: \(transcription)")
            await processText(transcription)
            
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription)")
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }
        
        isTranscribing = false
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
        guard !prompt.isEmpty,
              let mcpClient = mcpClient else { return }
        
        isGenerating = true
        errorMessage = nil
        
        do {
            let response = try await mcpClient.generateResponse(
                prompt: prompt,
                context: messages
            )
            
            logger.info("Response generated: \(response)")
            messages.append(Message(role: "assistant", content: response))
            
        } catch {
            logger.error("Response generation failed: \(error.localizedDescription)")
            errorMessage = "Failed to generate response: \(error.localizedDescription)"
        }
        
        isGenerating = false
    }
}
