import AVFoundation
import AVFAudio
import Foundation
import os

class AudioRecorder {
    private let logger = Logger(subsystem: "com.voiceflow", category: "audiorecorder")
    private let audioWriteQueue = DispatchQueue(label: "com.voiceflow.audiowrite", qos: .userInitiated)
    
    private var engine: AVAudioEngine?
    private var audioFileURL: URL?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    
    var currentFileURL: URL? {
        let url = audioFileURL
        let id = unsafeBitCast(self, to: UInt.self)
        logger.info("[currentFileURL=\(url?.absoluteString ?? "nil") id=\(id)]")
        return url
    }
    
    enum AudioError: Error, LocalizedError {
        case permissionDenied
        case recordingFailed
        case invalidFormat
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone access denied. Please enable in System Preferences > Security & Privacy > Microphone."
            case .recordingFailed:
                return "Failed to start recording."
            case .invalidFormat:
                return "Invalid audio format."
            }
        }
    }
    
    func start() async throws {
        guard !isRecording else { return }
        
        // Request microphone permission
        let permission = await AVCaptureDevice.requestAccess(for: .audio)
        guard permission else { throw AudioError.permissionDenied }
        
        // Create audio engine
        engine = AVAudioEngine()
        guard let engine = engine else { throw AudioError.recordingFailed }
        
        // Get input node (microphone)
        let inputNode = engine.inputNode
        
        // Create output file with 16kHz mono (whisper.cpp format)
        let tempDir = FileManager.default.temporaryDirectory
        audioFileURL = tempDir.appendingPathComponent("recording-\(Int(Date.now.timeIntervalSince1970)).wav")
        
        let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        
        do {
            audioFile = try AVAudioFile(forWriting: audioFileURL!, settings: audioFormat.settings)
        } catch {
            logger.error("Failed to create audio file: \(error.localizedDescription)")
            throw AudioError.recordingFailed
        }
        
        // Install tap to capture audio
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, let audioFile = self.audioFile else { return }
            // Write directly on audio thread (no do/try to avoid concurrency assertions)
            try! audioFile.write(from: buffer)
        }
        
        // Start the engine
        try engine.start()
        isRecording = true
        
        logger.info("[Recording started at \(self.audioFileURL?.absoluteString ?? "unknown")]")
        let id = unsafeBitCast(self, to: UInt.self)
        logger.info("[instance id=\(id) startFileURL=\(self.audioFileURL?.absoluteString ?? "nil")]")
        logger.info("Audio format: \(audioFormat.settings.description ?? "unknown")")
    }
    
    func stop() async {
        guard isRecording else { return }
        
        isRecording = false
        
        guard let engine = engine else { return }
        
        // Remove tap first (stops callbacks)
        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        
        // Stop engine
        engine.stop()
        self.engine = nil
        
        // Close the audio file to flush and finalize
        audioFile = nil
        
        let id = unsafeBitCast(self, to: UInt.self)
        logger.info("[instance id=\(id) Recording stopped]")
    }
}
