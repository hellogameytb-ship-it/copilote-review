import AVFoundation
import ScreenCaptureKit

/// The others: system audio through ScreenCaptureKit, without Copilote's own sound.
/// Needs the Screen Recording permission (same as captures).
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "org.example.copilote.system-audio")
    /// Called on a background queue with a buffer the receiver may keep.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onStop: ((Error) -> Void)?

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CaptureError.noDisplay }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1
        // Audio only: the smallest video stream the API allows, at one frame per second.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let buffer = sampleBuffer.copiedPCMBuffer() else { return }
        onBuffer?(buffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error)
    }
}

/// The user: the default microphone through AVAudioEngine.
final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var configurationObserver: NSObjectProtocol?
    /// Called on the audio thread; the buffer is only valid during the call.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// The microphone could not be restarted after a device change.
    var onFailure: ((String) -> Void)?

    static var permission: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    func start() throws {
        try startEngine()
        // Plugging in AirPods (or any input change) stops the engine: restart on the new device.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            engine.inputNode.removeTap(onBus: 0)
            do { try startEngine() } catch { onFailure?(error.localizedDescription) }
        }
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw CaptureError.failed("no microphone available") }
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate / 20), format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
        }
        engine.prepare()
        try engine.start()
    }
}

private extension CMSampleBuffer {
    /// Copies the audio out of the sample buffer (ScreenCaptureKit reuses its memory).
    func copiedPCMBuffer() -> AVAudioPCMBuffer? {
        guard let description = formatDescription,
              var streamDescription = description.audioStreamBasicDescription,
              let format = AVAudioFormat(streamDescription: &streamDescription),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(numSamples)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(self, at: 0, frameCount: Int32(numSamples), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}
