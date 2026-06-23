import Foundation
import os
import MCP

@MainActor
class MCPClient {
    private let logger = Logger(subsystem: "com.voiceflow", category: "mcpclient")
    
    // Whisper.cpp STT server
    private let whisperClient: Client
    private let whisperTransport: HTTPClientTransport
    
    // Llama-server (LLM)
    private let llmClient: Client
    private let llmTransport: HTTPClientTransport
    
    // Configuration
    let whisperURL: URL
    let llmURL: URL
    
    init() {
        whisperURL = URL(string: "http://localhost:8081")!
        llmURL = URL(string: "http://localhost:8080")!
        
        whisperTransport = HTTPClientTransport(endpoint: whisperURL, streaming: true)
        whisperClient = Client(name: "VoiceFlow-Whisper", version: "1.0.0")
        
        llmTransport = HTTPClientTransport(endpoint: llmURL, streaming: true)
        llmClient = Client(name: "VoiceFlow-LLM", version: "1.0.0")
    }
    
    deinit {
        logger.info("MCPClient deinitialized")
    }
    
    /// Connect to both MCP servers
    func connect() async throws {
        logger.info("Connecting to whisper.cpp and llama-server...")
        
        // Connect whisper server
        try await whisperClient.connect(transport: whisperTransport)
        logger.info("✓ Whisper.cpp connected")
        
        // Connect LLM server
        try await llmClient.connect(transport: llmTransport)
        logger.info("✓ Llama-server connected")
        
        // Verify capabilities
        try await verifyCapabilities()
    }
    
    /// Transcribe audio file using whisper.cpp
    func transcribeAudio(fileURL: URL) async throws -> String {
        logger.info("Transcribing audio file: \(fileURL.absoluteString)")
        
        let result = try await whisperClient.callTool(
            name: "transcribe",
            arguments: [
                "audio_file": .string(fileURL.absoluteString),
                "model": .string("base"),
                "language": .string("en")
            ]
        )
        
        let text = extractText(from: result.content)
        logger.info("Transcription result: \(text)")
        
        return text
    }
    
    /// Generate AI response using llama-server
    func generateResponse(prompt: String, context: [VoiceModel.Message]) async throws -> String {
        logger.info("Generating response for prompt: \(prompt)")
        
        // Build conversation context
        let contextText = context.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        
        let result = try await llmClient.callTool(
            name: "generate",
            arguments: [
                "prompt": .string(prompt),
                "context": .string(contextText),
                "temperature": .string("0.7"),
                "max_tokens": .string("1024")
            ]
        )
        
        let response = extractText(from: result.content)
        logger.info("Generated response: \(response)")
        
        return response
    }
    
    /// List available tools on servers
    func listAvailableTools() async {
        do {
            let toolsResult = try await whisperClient.listTools()
            let toolNames = toolsResult.tools.compactMap { $0.name }
            logger.info("Available whisper tools: \(toolNames.joined(separator: ", "))")
        } catch {
            logger.error("Failed to list whisper tools: \(error.localizedDescription)")
        }
        
        do {
            let toolsResult = try await llmClient.listTools()
            let toolNames = toolsResult.tools.compactMap { $0.name }
            logger.info("Available LLM tools: \(toolNames.joined(separator: ", "))")
        } catch {
            logger.error("Failed to list LLM tools: \(error.localizedDescription)")
        }
    }
    
    /// Verify server capabilities
    private func verifyCapabilities() async throws {
        // Connect whisper server
        try await whisperClient.connect(transport: whisperTransport)
        logger.info("✓ Whisper connected")
        
        // Connect LLM server
        try await llmClient.connect(transport: llmTransport)
        logger.info("✓ LLM connected")
    }
    
    /// Extract text content from MCP tool result
    private func extractText(from content: [Tool.Content]) -> String {
        content.compactMap { content in
            switch content {
            case .text(let text, _, _):
                return text
            case .image(_, let mimeType, _, _):
                return "[Image: \(mimeType)]"
            case .audio(_, let mimeType, _, _):
                return "[Audio: \(mimeType)]"
            case .resource(_, _, _):
                return "[Resource]"
            case .resourceLink(let uri, let name, _, _, _, _):
                return "[Resource Link: \(name ?? uri)]"
            }
        }.joined(separator: "\n")
    }
    
    /// Disconnect from servers
    func disconnect() async {
        logger.info("Disconnecting from MCP servers...")
        await whisperClient.disconnect()
        await llmClient.disconnect()
    }
}
