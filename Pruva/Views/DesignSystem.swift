import SwiftUI

enum Palette {
    static let background = Color(red: 0.96, green: 0.97, blue: 0.96)
    static let surface = Color.white
    static let ink = Color(red: 0.06, green: 0.09, blue: 0.08)
    static let secondary = Color(red: 0.36, green: 0.40, blue: 0.38)
    static let teal = Color(red: 0.02, green: 0.40, blue: 0.29)
    static let seafoam = Color(red: 0.89, green: 0.95, blue: 0.92)
    static let line = Color(red: 0.85, green: 0.89, blue: 0.87)
    static let gold = Color(red: 0.62, green: 0.36, blue: 0.06)
}

struct Surface<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(padding)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line.opacity(0.6), lineWidth: 0.75))
            .shadow(color: Palette.ink.opacity(0.035), radius: 16, x: 0, y: 6)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold))
            .tracking(1).foregroundStyle(Palette.secondary)
    }
}

struct Metric: View {
    let label: String
    let value: String
    let unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(text: label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
                Text(unit).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
            }.foregroundStyle(Palette.ink)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    var filled = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity).frame(minHeight: 54)
                .background(filled ? Palette.ink : Palette.seafoam, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(filled ? Color.white : Palette.teal)
        }.buttonStyle(.plain)
    }
}

func degrees(_ value: Double) -> String { String(format: "%03.0f°", (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) }
func decimal(_ value: Double) -> String { String(format: "%.1f", value) }
func journalDate(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "tr_TR")))
}
func duration(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
    if seconds < 60 { return "\(Int(seconds)) sn" }
    return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))"
}
