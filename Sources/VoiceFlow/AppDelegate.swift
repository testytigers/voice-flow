import AppKit
import os

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.voiceflow", category: "appdelegate")
    private var _voiceModel: VoiceModel?
    
    var voiceModel: VoiceModel {
        if _voiceModel == nil {
            _voiceModel = VoiceModel()
        }
        return _voiceModel!
    }
    
    func applicationDidFinishLaunching(_ notification: NSNotification) {
        Task {
            await voiceModel.connectServers()
        }
        setupHotkey()
        logger.info("AppDelegate: Application launched, hotkey setup complete")
    }
    
    private func setupHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // Cmd+Option+V to toggle recording
            if event.modifierFlags.contains(.command) && event.modifierFlags.contains(.option) && event.keyCode == 9 {
                Task {
                    await self.voiceModel.toggleRecording()
                }
            }
        }
        logger.info("AppDelegate: Global hotkey Cmd+Opt+V registered")
    }
}
