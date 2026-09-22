import Foundation
import RaceCore

enum VoiceIntent: Equatable {
    case windLift, windHeader, layline, status, committeePin, portPin, startDistance, unknown
}

enum VoiceTone { case information, caution, action }

struct VoiceAdvice {
    let command: String
    let title: String
    let detail: String
    let spoken: String
    let symbol: String
    let tone: VoiceTone
}

enum VoiceAdvisor {
    static func intent(for text: String) -> VoiceIntent {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                      locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .lowercased()
        let words = normalized.split { !$0.isLetter }.map(String.init)
        let tokens = Set(words)
        func has(_ values: String...) -> Bool { !tokens.isDisjoint(with: values) }
        // Never infer a write command from fuzzy text, negation, or two endpoints.
        if has("hayir", "degil", "alma", "almayin", "iptal", "yapma", "acmadi", "acilmadi", "kafalamadi", "daralmadi") {
            return .unknown
        }
        if has("start", "baslangic") && has("mesafe", "mesafesi", "uzak", "kadar") { return .startDistance }
        let committee = has("komite", "starboard", "sancak")
        let port = has("port", "end", "samandira", "iskele")
        if has("pin", "pini") {
            let captureWords: Set<String> = ["komite", "starboard", "sancak", "port", "end", "samandira", "iskele", "pin", "pini", "al", "alin", "kaydet", "lutfen"]
            guard committee != port, tokens.isSubset(of: captureWords) else { return .unknown }
            return committee ? .committeePin : .portPin
        }
        var candidates: [VoiceIntent] = []
        if has("layline", "laylayn", "layline'dayiz") || words.contains(where: { $0.hasPrefix("layline") })
            || normalized.contains("lay layn") { candidates.append(.layline) }
        // Conservative recognition aliases for clipped on-device transcripts.
        if has("ruzgar", "ruzga", "ruzgarin") {
            if has("acti", "ac", "acildi", "lift") { candidates.append(.windLift) }
            if has("kafaladi", "kafalama", "kafala", "daraldi", "daral") { candidates.append(.windHeader) }
        }
        if has("durum", "karar") || normalized.contains("ne yap") { candidates.append(.status) }
        if candidates.count == 1 { return candidates[0] }
        return .unknown
    }

    static func advice(for command: String, analysis: RaceAnalysis,
                       readiness: String?, measuredShift: Double?, interpretedIntent: VoiceIntent? = nil) -> VoiceAdvice {
        let intent = interpretedIntent ?? intent(for: command)
        if let readiness {
            return VoiceAdvice(command: command, title: "ÖLÇÜM EKSİK", detail: readiness,
                               spoken: "Karar için ölçüm eksik. \(readiness)",
                               symbol: "exclamationmark.triangle", tone: .caution)
        }
        switch intent {
        case .windLift, .windHeader:
            let event = intent == .windLift ? "Rüzgâr açması" : "Rüzgâr kafalaması"
            let shift = measuredShift.map { String(format: " Ölçülen sapma: %+.0f°.", $0) } ?? ""
            let action = actionText(analysis)
            let detail = "\(event) bildirildi.\(shift) \(analysis.message)"
            return VoiceAdvice(command: command, title: action.title, detail: detail,
                               spoken: "\(event) bildirildi. \(action.spoken)",
                               symbol: action.symbol, tone: action.tone)
        case .layline:
            if analysis.isOverstood {
                return VoiceAdvice(command: command, title: "LAYLINE AŞILDI",
                                   detail: "Model layline dışında gösteriyor. Hedefe doğrudan yaklaşma açısını ve çevreyi kontrol edin.",
                                   spoken: "Layline aşıldı. Doğrudan yaklaşma açısını kontrol edin.",
                                   symbol: "arrow.turn.down.right", tone: .action)
            }
            if let seconds = analysis.laylineSeconds {
                let near = seconds <= 30
                let text = "Model layline'a yaklaşık \(Int(max(0, seconds))) saniye gösteriyor. \(analysis.message)"
                return VoiceAdvice(command: command, title: near ? "LAYLINE YAKIN" : "LAYLINE KONTROLÜ",
                                   detail: text, spoken: near ? "Layline yakın. Manevraya hazırlanın ve hattı doğrulayın."
                                        : "Layline'a yaklaşık \(Int(max(0, seconds))) saniye. Hattı doğrulayın.",
                                   symbol: "scope",
                                   tone: near ? .action : .information)
            }
            return VoiceAdvice(command: command, title: "LAYLINE HESAPLANAMADI",
                               detail: "Mevcut parkur ve hızla layline süresi üretilemiyor. Hedef ve ölçümleri kontrol edin.",
                               spoken: "Layline süresi hesaplanamadı. Hedef ve ölçümleri kontrol edin.",
                               symbol: "scope", tone: .caution)
        case .status:
            let action = actionText(analysis)
            return VoiceAdvice(command: command, title: action.title, detail: analysis.message,
                               spoken: action.spoken, symbol: action.symbol, tone: action.tone)
        case .unknown, .committeePin, .portPin, .startDistance:
            return VoiceAdvice(command: command, title: "KOMUTU ANLAMADIM",
                               detail: "“Rüzgâr açtı”, “Layline'dayız”, “Durum”, “Komite pin” veya “Port pin” deyin.",
                               spoken: "Komutu anlamadım. Rüzgâr açtı, layline'dayız veya durum deyin.",
                               symbol: "questionmark.circle", tone: .information)
        }
    }

    private static func actionText(_ analysis: RaceAnalysis) ->
        (title: String, spoken: String, symbol: String, tone: VoiceTone) {
        switch analysis.recommendation {
        case .maneuver:
            return ("MANEVRAYI DEĞERLENDİR", "Model manevra öneriyor. \(analysis.title).", "arrow.triangle.2.circlepath", .action)
        case .prepare:
            return ("HAZIRLAN", "Model hazırlık öneriyor. \(analysis.title).", "exclamationmark.circle", .caution)
        case .hold:
            return ("KONTRAYI KORU", "Model mevcut kontrayı korumayı öneriyor. \(analysis.title).", "checkmark.circle", .information)
        }
    }
}
