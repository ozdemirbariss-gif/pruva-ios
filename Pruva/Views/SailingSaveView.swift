import SwiftUI
import Charts
import RaceCore

struct SailingSaveView: View {
    @Bindable var store: RaceStore
    @State private var note = ""

    var body: some View { saveCard }

    private var saveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ekibe bir not bırak…", text: $note, axis: .vertical)
                .font(.system(.footnote)).padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("decision-note")
            ActionButton(title: store.savedFeedback ? "Kaydedildi" : "Kararı kaydet", icon: store.savedFeedback ? "checkmark" : "bookmark") {
                store.saveDecision(note: note)
                if store.savedFeedback { note = "" }
            }.accessibilityLabel(store.savedFeedback ? "Seyir defterine kaydedildi" : "Kararı seyir defterine kaydet")
                .accessibilityIdentifier("save-decision").disabled(store.isLiveMode && store.liveReadinessMessage != nil)
        }
    }

}
