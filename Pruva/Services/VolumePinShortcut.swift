import AVFoundation

@MainActor
final class VolumePinShortcut {
    var onEndpoint: ((StartEndpoint) -> Void)?
    private var observation: NSKeyValueObservation?
    private var lastVolume: Float = 0
    private var lastEndpoint: StartEndpoint?
    private var lastCaptureAt = Date.distantPast

    func start() {
        guard observation == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        lastVolume = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let volume = session.outputVolume
            Task { @MainActor [weak self] in self?.volumeChanged(to: volume) }
        }
    }

    func stop() { observation = nil }

    private func volumeChanged(to volume: Float) {
        let delta = volume - lastVolume
        lastVolume = volume
        guard abs(delta) > 0.005 else { return }
        let endpoint: StartEndpoint = delta > 0 ? .committee : .port
        let now = Date()
        guard endpoint != lastEndpoint || now.timeIntervalSince(lastCaptureAt) >= 0.6 else { return }
        lastEndpoint = endpoint
        lastCaptureAt = now
        onEndpoint?(endpoint)
    }
}
