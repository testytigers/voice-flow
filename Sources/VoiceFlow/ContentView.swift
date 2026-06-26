import SwiftUI
import os

struct ContentView: View {
    @EnvironmentObject var voiceModel: VoiceModel
    
    let logger = Logger(subsystem: "com.voiceflow", category: "contentview")
    
    var body: some View {
        ZStack {
            // Background
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            
            // Main content
            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                
                Divider()
                
                // Messages list - fills all available space
                messageListView
                
                // Error message (if any)
                if let error = voiceModel.errorMessage {
                    errorView(error: error)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }
                
                // Controls
                controlsView
                    .padding(16)
            }
        }
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
            
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var statusText: String {
        if voiceModel.isRecording { return "Recording..." }
        if voiceModel.isTranscribing { return "Transcribing..." }
        if voiceModel.isGenerating { return "Thinking..." }
        return voiceModel.isConnected ? "Connected" : "No connection"
    }
    
    private var messageListView: some View {
        ScrollView {
            ScrollViewReader { proxy in
                LazyVStack(spacing: 12) {
                    if voiceModel.messages.isEmpty && !voiceModel.isRecording && !voiceModel.isTranscribing {
                        // Empty state
                        VStack(spacing: 16) {
                            Image(systemName: "mic.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.blue.opacity(0.5))
                            
                            Text("Tap the microphone to start")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            
                            Text("Record your voice and VoiceFlow will transcribe and respond")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                    
                    ForEach(voiceModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    
                    if voiceModel.isTranscribing {
                        TranscribingIndicator()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    if voiceModel.isGenerating {
                        GeneratingIndicator()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding()
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: voiceModel.messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: voiceModel.isTranscribing) {
                    if voiceModel.isTranscribing {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
        }
        .background(Color.clear)
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        // Scroll to the last message
        if let lastMessage = voiceModel.messages.last {
            DispatchQueue.main.async {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
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
