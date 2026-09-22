import AVFoundation
import Observation
import Speech

@Observable
@MainActor
final class VoiceCommandService {
    var isListening = false
    var isStarting = false
    var transcript = ""
    var errorMessage: String?
    var onCommand: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var startGeneration = 0

    func start() async {
        guard !isListening && !isStarting else { return }
        isStarting = true
        startGeneration += 1
        let generation = startGeneration
        defer { if generation == startGeneration { isStarting = false } }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        errorMessage = nil
        transcript = ""
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard generation == startGeneration else { return }
        guard authorization == .authorized else {
            errorMessage = "Konuşma tanıma izni gerekli. Komutu yazıyla verebilirsiniz."
            return
        }
        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        guard generation == startGeneration else { return }
        guard microphoneAllowed else {
            errorMessage = "Mikrofon izni gerekli. Komutu yazıyla verebilirsiniz."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Türkçe konuşma tanıma şu anda kullanılamıyor. Komutu yazıyla verebilirsiniz."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            errorMessage = "Cihaz içi Türkçe konuşma tanıma kullanılamıyor. Komutu yazıyla verebilirsiniz."
            return
        }
        stopAudio()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.request = request
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            isListening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                Task { @MainActor [weak self] in
                    guard let self, self.isListening else { return }
                    if let text { self.transcript = text }
                    if final {
                        self.finish()
                    } else if let error {
                        self.errorMessage = "Ses tanınamadı: \(error.localizedDescription)"
                        self.stopAudio()
                    }
                }
            }
        } catch {
            errorMessage = "Mikrofon başlatılamadı: \(error.localizedDescription)"
            stopAudio()
        }
    }

    func finish() {
        let command = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopAudio()
        if !command.isEmpty { onCommand?(command) }
    }

    func stop() {
        startGeneration += 1
        isStarting = false
        stopAudio()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    @discardableResult func announce(_ message: String) -> Bool {
        guard !isListening, !isStarting, !synthesizer.isSpeaking else { return false }
        speak(message)
        return true
    }

    func speak(_ message: String) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }

    private func stopAudio() {
        isListening = false
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }
}
