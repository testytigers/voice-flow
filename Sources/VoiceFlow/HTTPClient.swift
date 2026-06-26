import Foundation
import os

@MainActor
class HTTPClient {
    private let logger = Logger(subsystem: "com.voiceflow", category: "httpclient")
    private let session = URLSession(configuration: .default)
    
    /// Test if a server is reachable
    func testConnection(to url: URL, endpoint: String) async -> Bool {
        let target = url.appendingPathComponent(endpoint)
        do {
            let (data, _) = try await session.data(from: target)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["status"] as? String == "ok"
        } catch {
            return false
        }
    }
    
    /// Transcribe audio file using whisper.cpp server
    func transcribeAudio(from fileURL: URL, serverURL: URL) async throws -> String {
        var request = URLRequest(url: serverURL.appendingPathComponent("/inference"))
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add audio file
        let fileName = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add response_format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n".data(using: .utf8)!)
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HTTPError.transcriptionFailed
        }
        
        // Parse JSON response from whisper.cpp
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = json?["text"] as? String ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Generate AI response using llama-server
    func generateResponse(prompt: String, messages: [VoiceModel.Message], serverURL: URL) async throws -> String {
        var request = URLRequest(url: serverURL.appendingPathComponent("/v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build messages array for llama-server
        var chatMessages: [[String: Any]] = []
        chatMessages.append(["role": "system", "content": "You are a helpful AI assistant in VoiceFlow, a voice-to-text app."])
        
        for msg in messages {
            chatMessages.append(["role": msg.role == "user" ? "user" : "assistant", "content": msg.content])
        }
        
        // Get model name from the server
        let model = "gpt-oss-20b"
        
        let body: [String: Any] = [
            "model": model,
            "messages": chatMessages,
            "temperature": 0.7,
            "max_tokens": 1024,
            "stream": false
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw HTTPError.serializationFailed
        }
        request.httpBody = jsonData
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HTTPError.responseFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]] ?? []
        let firstChoice = choices.first
        let message = firstChoice?["message"] as? [String: Any]
        let responseText = message?["content"] as? String ?? "(no response)"
        
        return responseText
    }
}

enum HTTPError: Error, LocalizedError {
    case transcriptionFailed
    case responseFailed
    case serializationFailed
    
    var errorDescription: String? {
        switch self {
        case .transcriptionFailed: return "Audio transcription failed"
        case .responseFailed: return "AI response generation failed"
        case .serializationFailed: return "Failed to serialize request data"
        }
    }
}
