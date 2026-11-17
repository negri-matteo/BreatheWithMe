import SwiftUI

// Lingua dell'app, scelta dal selettore nella scheda Info.
//
// Ogni testo è scritto nelle due lingue nel punto in cui compare: L("Inspira", "Inhale").
// Così il cambio di lingua è immediato e non richiede cataloghi di stringhe in Xcode.

enum AppLanguage: String, CaseIterable, Identifiable {
    case italian = "it"
    case english = "en"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    /// Nome mostrato nel selettore, sempre nella propria lingua.
    var displayName: String {
        switch self {
        case .italian: return "Italiano"
        case .english: return "English"
        }
    }

    /// Usata per date e grafici.
    var locale: Locale {
        switch self {
        case .italian: return Locale(identifier: "it_IT")
        case .english: return Locale(identifier: "en_US")
        }
    }

    /// Finché l'utente non sceglie, l'app segue il telefono: italiano se è in italiano, altrimenti inglese.
    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("it") ? .italian : .english
    }

    static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let language = AppLanguage(rawValue: raw) {
            return language
        }
        return systemDefault
    }
}

/// Testo nella lingua scelta.
func L(_ italian: String, _ english: String) -> String {
    AppLanguage.current == .italian ? italian : english
}

/// Per le poche API che accettano solo LocalizedStringKey, come le etichette dei grafici.
func LK(_ italian: String, _ english: String) -> LocalizedStringKey {
    LocalizedStringKey(L(italian, english))
}

extension Date {
    /// Data e ora formattate nella lingua dell'app, non in quella del telefono.
    func appFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time, locale: AppLanguage.current.locale))
    }
}
