import SwiftUI
import os

struct ContentView: View {
    @EnvironmentObject var voiceModel: VoiceModel
    
    let logger = Logger(subsystem: "com.voiceflow", category: "contentview")
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal)
                .padding(.vertical, 12)
            
            Divider()
            
            // Messages list
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(spacing: 12) {
                        ForEach(voiceModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if voiceModel.isTranscribing {
                            TranscribingIndicator()
                        }
                        
                        if voiceModel.isGenerating {
                            GeneratingIndicator()
                        }
                    }
                    .padding()
                }
            }
            
            // Status bar
            if let error = voiceModel.errorMessage {
                errorView(error: error)
            }
            
            // Controls
            controlsView
                .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            logger.info("ContentView appeared")
        }
    }
    
    // MARK: - Views
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("VoiceFlow")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Voice-to-text AI chat")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Connection status indicator
            statusIndicator
        }
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(voiceModel.isRecording ? Color.red :
                      voiceModel.isTranscribing ? Color.yellow :
                      voiceModel.isGenerating ? Color.blue :
                      Color.green)
                .frame(width: 8, height: 8)
                .animation(.easeInOut, value: voiceModel.isConnected)
            
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var statusText: String {
        if voiceModel.isRecording { return "Recording..." }
        if voiceModel.isTranscribing { return "Transcribing..." }
        if voiceModel.isGenerating { return "Thinking..." }
        return "Ready"
    }
    
    private var controlsView: some View {
        HStack(spacing: 16) {
            // Record button (large, center)
            Button(action: {
                Task {
                    if voiceModel.isRecording {
                        await voiceModel.stopRecording()
                    } else {
                        await voiceModel.startRecording()
                    }
                }
            }) {
                Image(systemName: voiceModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title)
                    .frame(width: 64, height: 64)
                    .background(
                        Capsule()
                            .fill(voiceModel.isRecording ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                    )
                    .foregroundColor(voiceModel.isRecording ? .red : .blue)
            }
            .buttonStyle(.plain)
            .disabled(voiceModel.isTranscribing || voiceModel.isGenerating)
            
            Spacer()
            
            // Clear button
            Button(action: {
                voiceModel.messages.removeAll()
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(voiceModel.messages.isEmpty)
        }
    }
    
    private func errorView(error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .foregroundColor(.orange)
            
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: VoiceModel.Message
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            avatarView
                .frame(width: 32, height: 32)
            
            // Message content
            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == "user" ? "You" : "VoiceFlow")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text(message.content)
                    .font(.body)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .background(
                        Capsule()
                            .fill(message.role == "user" ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                    )
                
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var avatarView: some View {
        Circle()
            .fill(message.role == "user" ? Color.blue : Color.green)
            .overlay(
                Image(systemName: message.role == "user" ? "person.fill" : "sparkles")
                    .foregroundColor(.white)
                    .font(.caption)
            )
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Indicators
struct TranscribingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundColor(.yellow)
                .rotationEffect(.degrees(360))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: _pulse)
            
            Text("Transcribing your voice...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(8)
    }
    
    @State private var _pulse: Int = 0
}

struct GeneratingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .foregroundColor(.blue)
                .rotationEffect(.degrees(360))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: _pulse)
            
            Text("Generating response...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    @State private var _pulse: Int = 0
}

// MARK: - Menu Bar View
struct MenuBarView: View {
    @EnvironmentObject var voiceModel: VoiceModel
    
    var body: some View {
        VStack {
            HStack {
                Text("VoiceFlow")
                    .font(.headline)
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Status
            HStack {
                Circle()
                    .fill(voiceModel.isRecording ? Color.red : Color.green)
                    .frame(width: 12, height: 12)
                
                Text(voiceModel.isRecording ? "Recording..." : "Ready")
                    .font(.caption)
            }
            .padding()
            
            Divider()
            
            // Quick actions
            Button(action: {
                Task {
                    if voiceModel.isRecording {
                        await voiceModel.stopRecording()
                    } else {
                        await voiceModel.startRecording()
                    }
                }
            }) {
                Label(
                    voiceModel.isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: voiceModel.isRecording ? "stop.circle" : "mic.circle"
                )
            }
            .disabled(voiceModel.isTranscribing || voiceModel.isGenerating)
            
            Divider()
            
            Button(action: {
                NSApp.terminate(nil)
            }) {
                Label("Quit VoiceFlow", systemImage: "xmark.circle")
            }
        }
        .frame(width: 200)
    }
}
