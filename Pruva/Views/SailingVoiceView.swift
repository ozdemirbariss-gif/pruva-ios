import SwiftUI
import Charts
import RaceCore

struct SailingVoiceView: View {
    @Bindable var store: RaceStore
    @Environment(VoiceCommandService.self) private var voice
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var commandTask: Task<Void, Never>?
    @State private var typedCommand = ""
    @FocusState private var commandFocused: Bool

    var body: some View {
        voiceCard
            .onAppear { voice.onCommand = { command in submit(command) } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { commandTask?.cancel(); voice.stop() } }
            .onDisappear { commandTask?.cancel(); voice.stop(); voice.onCommand = nil }
    }

    private var voiceCard: some View {
        Surface(padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                AdaptiveStack(spacing: 8) {
                    Image(systemName: "waveform").foregroundStyle(voice.isListening ? Palette.gold : Palette.teal)
                        .symbolEffect(.pulse, options: .repeating, isActive: voice.isListening && !reduceMotion)
                    TextField("Taktiğe sor · Rüzgâr açtı…", text: $typedCommand)
                        .font(.system(.subheadline)).textInputAutocapitalization(.sentences)
                        .focused($commandFocused)
                        .submitLabel(.send).onSubmit(sendTypedCommand)
                        .accessibilityIdentifier("voice-command-input")
                    Button(action: sendTypedCommand) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(.title)).frame(minWidth: 44, minHeight: 44)
                    }.disabled(typedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isInterpretingCommand)
                        .accessibilityLabel("Komutu değerlendir").accessibilityIdentifier("voice-submit")
                    Button {
                        commandFocused = false
                        if voice.isListening { voice.finish() }
                        else { Task { await voice.start() } }
                    } label: {
                        Image(systemName: voice.isListening ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(.largeTitle)).frame(minWidth: 44, minHeight: 44)
                    }.disabled(voice.isStarting)
                        .accessibilityLabel(voice.isStarting ? "Mikrofon hazırlanıyor" : voice.isListening ? "Dinlemeyi bitir" : "Sesli komut ver")
                        .accessibilityIdentifier("voice-listen")
                }.foregroundStyle(Palette.teal)
                Toggle("Cihaz içi dil yardımı", isOn: $store.languageModelEnabled)
                    .font(.footnote).onChange(of: store.languageModelEnabled) { _, _ in store.persist() }
                if store.isInterpretingCommand { ProgressView("Komut yorumlanıyor…") }
                if let message = store.languageModelMessage { Text(message).font(.footnote) }
                if voice.isStarting || voice.isListening {
                    Text(voice.isStarting ? "MİKROFON HAZIRLANIYOR" : voice.transcript.isEmpty ? "DİNLİYOR" : voice.transcript)
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(Palette.gold)
                }
                if let error = voice.errorMessage {
                    Text(error).font(.system(.caption)).foregroundStyle(Palette.gold)
                }
                if let advice = store.voiceAdvice {
                    AdaptiveStack(alignment: .top, spacing: 10) {
                        Image(systemName: advice.symbol).font(.system(.title2))

                            .frame(width: 35, height: 35)
                            .background(cueColor(advice.tone).opacity(0.17), in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(advice.title).font(.system(.caption, design: .monospaced, weight: .bold))
                                .tracking(0.7)
                            Text(advice.detail).font(.system(.caption)).foregroundStyle(Palette.ink)
                        }
                        Spacer(minLength: 0)
                        Button { voice.speak(advice.spoken) } label: { Image(systemName: "speaker.wave.2").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Yanıtı tekrar seslendir")
                    }.foregroundStyle(cueColor(advice.tone))
                        .padding(10).background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("voice-advice")
                }
            }
        }
    }

    private func sendTypedCommand() {
        let command = typedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        typedCommand = ""
        commandFocused = false
        submit(command)
    }

    private func submit(_ command: String) {
        guard !store.isInterpretingCommand else { return }
        commandTask = Task {
            if let advice = await store.interpretCommand(command), !Task.isCancelled { voice.speak(advice.spoken) }
        }
    }

    private func cueColor(_ tone: VoiceTone) -> Color {
        switch tone {
        case .information: Palette.teal
        case .caution, .action: Palette.gold
        }
    }

}
