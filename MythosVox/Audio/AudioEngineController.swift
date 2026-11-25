import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioEngineController: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)

        var label: String {
            switch self {
            case .stopped:
                "Stopped"
            case .starting:
                "Starting…"
            case .running:
                "Live"
            case .failed(let message):
                message
            }
        }
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var ambianceName: String?
    @Published var voiceVolume: Float = 0.85 {
        didSet { voiceMixer.outputVolume = voiceVolume }
    }
    @Published var speechVolume: Float = 0.8
    @Published var ambianceVolume: Float = 0.45 {
        didSet { ambianceMixer.outputVolume = ambianceVolume }
    }
    @Published var masterVolume: Float = 0.9 {
        didSet { engine.mainMixerNode.outputVolume = masterVolume }
    }

    private let engine = AVAudioEngine()
    private let pitchEffect = AVAudioUnitTimePitch()
    private let distortionEffect = AVAudioUnitDistortion()
    private let reverbEffect = AVAudioUnitReverb()
    private let voiceMixer = AVAudioMixerNode()
    private let ambiancePlayer = AVAudioPlayerNode()
    private let ambianceMixer = AVAudioMixerNode()
    private let speechSynthesizer = AVSpeechSynthesizer()

    private var ambianceFile: AVAudioFile?
    private var isGraphConfigured = false
    private var shouldLoopAmbiance = false
    private var ambianceLoopGeneration = 0

    init() {
        engine.attach(pitchEffect)
        engine.attach(distortionEffect)
        engine.attach(reverbEffect)
        engine.attach(voiceMixer)
        engine.attach(ambiancePlayer)
        engine.attach(ambianceMixer)

        distortionEffect.loadFactoryPreset(.speechRadioTower)
        reverbEffect.loadFactoryPreset(.mediumHall)
        voiceMixer.outputVolume = voiceVolume
        ambianceMixer.outputVolume = ambianceVolume
        engine.mainMixerNode.outputVolume = masterVolume
    }

    func apply(_ preset: VoicePreset) {
        pitchEffect.pitch = preset.pitchCents
        distortionEffect.wetDryMix = preset.distortionMix
        reverbEffect.wetDryMix = preset.reverbMix
    }

    func start() async {
        guard state != .running, state != .starting else {
            return
        }

        state = .starting
        guard await requestMicrophoneAccess() else {
            state = .failed("Microphone access is required")
            return
        }

        do {
            try configureAudioSession()
            try configureGraphIfNeeded()
            engine.prepare()
            try engine.start()
            state = .running
            startAmbianceLoopIfAvailable()
        } catch {
            engine.stop()
            deactivateAudioSession()
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        shouldLoopAmbiance = false
        ambianceLoopGeneration += 1
        ambiancePlayer.stop()
        engine.stop()
        deactivateAudioSession()
        state = .stopped
    }

    func speak(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmedText)
        utterance.volume = speechVolume * masterVolume
        speechSynthesizer.speak(utterance)
    }

    func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    func importAmbiance(from sourceURL: URL) throws {
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL = try persistentAmbianceURL(for: sourceURL)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        shouldLoopAmbiance = false
        ambianceLoopGeneration += 1
        ambiancePlayer.stop()
        ambianceFile = try AVAudioFile(forReading: destinationURL)
        ambianceName = sourceURL.deletingPathExtension().lastPathComponent
        startAmbianceLoopIfAvailable()
    }

    func removeAmbiance() {
        shouldLoopAmbiance = false
        ambianceLoopGeneration += 1
        ambiancePlayer.stop()
        ambianceFile = nil
        ambianceName = nil
    }

    private func configureGraphIfNeeded() throws {
        guard !isGraphConfigured else {
            return
        }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw AudioEngineError.noInputChannels
        }

        engine.connect(input, to: pitchEffect, format: inputFormat)
        engine.connect(pitchEffect, to: distortionEffect, format: nil)
        engine.connect(distortionEffect, to: reverbEffect, format: nil)
        engine.connect(reverbEffect, to: voiceMixer, format: nil)
        engine.connect(voiceMixer, to: engine.mainMixerNode, format: nil)

        engine.connect(ambiancePlayer, to: ambianceMixer, format: nil)
        engine.connect(ambianceMixer, to: engine.mainMixerNode, format: nil)
        isGraphConfigured = true
    }

    private func startAmbianceLoopIfAvailable() {
        guard state == .running, let ambianceFile else {
            return
        }

        shouldLoopAmbiance = true
        ambianceLoopGeneration += 1
        let generation = ambianceLoopGeneration
        // Queue one repeat ahead so main-actor callback latency cannot create
        // an audible gap between loops.
        scheduleAmbianceLoop(ambianceFile, generation: generation)
        scheduleAmbianceLoop(ambianceFile, generation: generation)
        if !ambiancePlayer.isPlaying {
            ambiancePlayer.play()
        }
    }

    private func scheduleAmbianceLoop(_ file: AVAudioFile, generation: Int) {
        ambiancePlayer.scheduleFile(
            file,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.shouldLoopAmbiance,
                      generation == self.ambianceLoopGeneration,
                      let ambianceFile = self.ambianceFile
                else {
                    return
                }
                self.scheduleAmbianceLoop(
                    ambianceFile,
                    generation: generation
                )
            }
        }
    }

    private func persistentAmbianceURL(for sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = applicationSupport.appendingPathComponent(
            "MythosVox",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )
        return appDirectory
            .appendingPathComponent("ambiance")
            .appendingPathExtension(sourceURL.pathExtension)
    }

    private func requestMicrophoneAccess() async -> Bool {
#if os(iOS)
        await AVAudioApplication.requestRecordPermission()
#else
        await AVCaptureDevice.requestAccess(for: .audio)
#endif
    }

    private func configureAudioSession() throws {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
        )
        try session.setActive(true)
#endif
    }

    private func deactivateAudioSession() {
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
#endif
    }
}

private enum AudioEngineError: LocalizedError {
    case noInputChannels

    var errorDescription: String? {
        "No microphone input is available"
    }
}
