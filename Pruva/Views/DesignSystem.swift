import SwiftUI

enum Palette {
    static let background = Color(red: 0.035, green: 0.075, blue: 0.135)
    static let surface = Color(red: 0.075, green: 0.145, blue: 0.235)
    static let ink = Color(red: 0.94, green: 0.97, blue: 1.0)
    static let secondary = Color(red: 0.61, green: 0.72, blue: 0.84)
    static let teal = Color(red: 0.39, green: 0.69, blue: 0.94)
    static let seafoam = Color(red: 0.11, green: 0.22, blue: 0.36)
    static let line = Color(red: 0.22, green: 0.34, blue: 0.48)
    static let gold = Color(red: 0.83, green: 0.72, blue: 0.48)
}

struct Surface<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(padding)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line.opacity(0.7), lineWidth: 1))
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced))
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
                Text(value).font(.system(size: 27, weight: .semibold, design: .monospaced)).monospacedDigit()
                    .contentTransition(.numericText())
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
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold, design: .default))
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(filled ? Palette.teal : Palette.seafoam, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(filled ? Palette.background : Palette.teal)
        }.buttonStyle(.plain)
    }
}

func degrees(_ value: Double) -> String { String(format: "%03.0f°", (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) }
func decimal(_ value: Double) -> String { String(format: "%.1f", value) }
func duration(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
    if seconds < 60 { return "\(Int(seconds)) sn" }
    return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))"
}
