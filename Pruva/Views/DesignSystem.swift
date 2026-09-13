import SwiftUI

enum Palette {
    static let background = Color(red: 0.966, green: 0.974, blue: 0.973)
    static let ink = Color(red: 0.09, green: 0.18, blue: 0.22)
    static let secondary = Color(red: 0.43, green: 0.50, blue: 0.53)
    static let teal = Color(red: 0.14, green: 0.47, blue: 0.46)
    static let seafoam = Color(red: 0.89, green: 0.95, blue: 0.93)
    static let line = Color(red: 0.89, green: 0.92, blue: 0.92)
    static let gold = Color(red: 0.69, green: 0.50, blue: 0.24)
}

struct Surface<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(padding)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line.opacity(0.7), lineWidth: 1))
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.7).foregroundStyle(Palette.secondary)
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
                Text(value).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
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
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(filled ? Palette.teal : Palette.seafoam, in: RoundedRectangle(cornerRadius: 15))
                .foregroundStyle(filled ? .white : Palette.teal)
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
