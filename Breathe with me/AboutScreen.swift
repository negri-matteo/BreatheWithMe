import SwiftUI

// Dati dello sviluppatore, testi legali, consenso iniziale e schermata Informazioni.

enum AppInfo {
    static let developer = "Matteo Negri"
    static let supportEmail = "silentmat@proton.me"

    // Pagine pubblicate con GitHub Pages dalla cartella docs del repository negri-matteo/BreatheWithMe.
    // Devono restare pubbliche: App Store Connect chiede l'URL della privacy policy.
    static let privacyURLString = "https://negri-matteo.github.io/BreatheWithMe/privacy"
    static let termsURLString = "https://negri-matteo.github.io/BreatheWithMe/termini"

    /// Se cambi il testo dell'avviso di sicurezza, aumenta questo numero:
    /// il consenso verrà richiesto di nuovo a tutti.
    static let consentVersion = 1
    static let consentKey = "acceptedConsentVersion"

    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Let's Breathe"
    }

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return L("Versione \(short) (\(build))", "Version \(short) (\(build))")
    }

    static var copyright: String {
        "© \(Calendar.current.component(.year, from: Date())) \(developer)"
    }

    static var privacyURL: URL? { URL(string: privacyURLString) }
    static var termsURL: URL? { URL(string: termsURLString) }
    static var supportMailURL: URL? { URL(string: "mailto:\(supportEmail)") }
}

enum LegalText {
    /// Regole di sicurezza: compaiono sia nel consenso iniziale sia nelle Informazioni.
    /// Proprietà calcolate, così seguono la lingua scelta.
    static var safetyPoints: [String] {
        [
            L("Mai in acqua. Non trattenere il respiro in piscina, in vasca o al mare: si può perdere coscienza senza preavviso e annegare.",
              "Never in water. Don't hold your breath in a pool, bathtub or the sea: you can black out without warning and drown."),
            L("Mai da solo. Allenati con qualcuno nelle vicinanze che sappia cosa stai facendo.",
              "Never alone. Train with someone nearby who knows what you are doing."),
            L("Da seduto o sdraiato, su una superficie stabile. Mai in piedi, alla guida o mentre fai altro.",
              "Seated or lying down, on a stable surface. Never standing, driving or while doing anything else."),
            L("Non iperventilare prima di trattenere: aumenta il rischio di svenimento.",
              "Don't hyperventilate before a hold: it increases the risk of fainting."),
            L("Interrompi subito in caso di capogiro, formicolio, vista offuscata o contrazioni intense.",
              "Stop at once if you feel dizzy, tingling, blurred vision or strong contractions."),
            L("Non adatto a chi ha problemi cardiaci, respiratori o di pressione, a chi soffre di epilessia, in gravidanza e ai minori di 18 anni.",
              "Not suitable for people with heart, breathing or blood pressure problems, epilepsy, during pregnancy, or for anyone under 18."),
            L("In caso di dubbi, parlane prima con il tuo medico.",
              "If in doubt, talk to your doctor first.")
        ]
    }

    static var medical: String {
        L("Questa app non è un dispositivo medico e non fornisce diagnosi, terapie o consigli medici. I valori di battito cardiaco e ossigenazione provengono dai sensori di Apple Watch, hanno finalità di benessere personale e non hanno valore clinico. Non usarli per prendere decisioni sulla tua salute.",
          "This app is not a medical device and does not provide diagnosis, treatment or medical advice. Heart rate and blood oxygen values come from Apple Watch sensors, are intended for personal wellness only and have no clinical value. Don't use them to make decisions about your health.")
    }

    static var privacy: String {
        L("Tutti i dati restano su questo dispositivo: lo storico delle sessioni è un file nella memoria dell'app, le impostazioni sono salvate dal sistema. L'app non ha un server, non invia nulla in rete, non usa pubblicità né strumenti di analisi e non chiede la creazione di un account. I dati di Salute vengono solo letti, mai modificati. Escono dal dispositivo solo quando sei tu a esportarli in CSV o a inviarli per email.",
          "All data stays on this device: session history is a file in the app's storage, and settings are saved by the system. The app has no server, sends nothing over the network, uses no advertising or analytics and doesn't ask you to create an account. Health data is only read, never changed. It leaves the device only when you export it as CSV or send it by email.")
    }
}

// MARK: - Selettore della lingua

/// Usato sia nel consenso iniziale (versione compatta) sia nella scheda Info.
struct LanguagePicker: View {
    var compact = false

    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue

    var body: some View {
        if compact {
            Picker(L("Lingua", "Language"), selection: $languageRaw) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
        } else {
            Picker(selection: $languageRaw) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            } label: {
                Label(L("Lingua", "Language"), systemImage: "globe")
            }
            .pickerStyle(.menu)
        }
    }
}

// MARK: - Consenso alla prima apertura

struct SafetyConsentView: View {
    let onAccept: () -> Void

    @State private var accepted = false

    var body: some View {
        ZStack {
            AppBackground(accent: Theme.cyan)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(spacing: 18) {
                            BrandImage(asset: .mark)
                                .frame(height: 110)
                            // La lingua si sceglie subito, prima di leggere le avvertenze.
                            LanguagePicker(compact: true)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Theme.cyan)
                                Text(L("Prima di iniziare", "Before you start"))
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                            }
                            Text(L("Trattenere il respiro comporta rischi reali. Leggi queste regole: valgono ogni volta che usi l'app.",
                                   "Holding your breath carries real risks. Read these rules: they apply every time you use the app."))
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.75))
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(LegalText.safetyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(Theme.mint)
                                        .padding(.top, 7)
                                    Text(point)
                                        .font(.callout)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Non è un dispositivo medico", "Not a medical device"))
                                .font(.system(.headline, design: .rounded))
                            Text(LegalText.medical)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1))

                        HStack(spacing: 18) {
                            if let url = AppInfo.privacyURL {
                                Link(L("Informativa privacy", "Privacy policy"), destination: url)
                            }
                            if let url = AppInfo.termsURL {
                                Link(L("Termini di servizio", "Terms of service"), destination: url)
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.mint)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 14) {
                    Toggle(isOn: $accepted) {
                        Text(L("Ho letto le avvertenze e accetto i termini di servizio",
                               "I have read the warnings and accept the terms of service"))
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(Theme.mint)

                    Button(action: onAccept) {
                        Text(L("Accetto e continuo", "Accept and continue"))
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(accepted ? AnyShapeStyle(Theme.accentGradient)
                                                 : AnyShapeStyle(Color.white.opacity(0.12)),
                                        in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!accepted)
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
                .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .top)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Informazioni

struct AboutScreen: View {
    @EnvironmentObject private var store: ApneaStore
    @State private var confirmWipe = false

    private var sessionsLabel: String {
        switch store.sessions.count {
        case 0: return L("Nessuna sessione salvata", "No sessions saved")
        case 1: return L("1 sessione salvata su questo iPhone", "1 session saved on this iPhone")
        default:
            return L("\(store.sessions.count) sessioni salvate su questo iPhone",
                     "\(store.sessions.count) sessions saved on this iPhone")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(Theme.mint)
                .padding(.top, 7)
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            BrandImage(asset: .mark)
                                .frame(height: 56)
                            BrandWordmark(size: 28)
                        }
                        .padding(.bottom, 4)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(AppInfo.name)
                        Text(AppInfo.version)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.65))
                        Text(L("di \(AppInfo.developer)", "by \(AppInfo.developer)"))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
                }

                Section {
                    LanguagePicker()
                } footer: {
                    Text(L("Le richieste di accesso a Salute mostrate dal sistema seguono la lingua del telefono.",
                           "Health access requests shown by the system follow your phone's language."))
                }
                .listRowBackground(Theme.card)

                Section(L("Sicurezza", "Safety")) {
                    ForEach(LegalText.safetyPoints, id: \.self) { point in
                        bullet(point)
                    }
                }
                .listRowBackground(Theme.card)

                Section(L("Non è un dispositivo medico", "Not a medical device")) {
                    Text(LegalText.medical)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Theme.card)

                Section(L("Privacy e dati", "Privacy and data")) {
                    Text(LegalText.privacy)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = AppInfo.privacyURL {
                        Link(destination: url) {
                            Label(L("Informativa privacy completa", "Full privacy policy"), systemImage: "hand.raised")
                        }
                    }
                    if let url = AppInfo.termsURL {
                        Link(destination: url) {
                            Label(L("Termini di servizio", "Terms of service"), systemImage: "doc.text")
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section(L("Assistenza", "Support")) {
                    if let url = AppInfo.supportMailURL {
                        Link(destination: url) {
                            Label(AppInfo.supportEmail, systemImage: "envelope")
                        }
                    } else {
                        Label(AppInfo.supportEmail, systemImage: "envelope")
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    Button(role: .destructive) {
                        confirmWipe = true
                    } label: {
                        Label(L("Elimina tutto lo storico", "Delete all history"), systemImage: "trash")
                    }
                    .disabled(store.sessions.isEmpty)
                } header: {
                    Text(L("Dati sul dispositivo", "Data on this device"))
                } footer: {
                    Text(L("\(sessionsLabel). Disinstallando l'app i dati vengono rimossi insieme a essa.",
                           "\(sessionsLabel). Uninstalling the app removes its data too."))
                }
                .listRowBackground(Theme.card)

                Section {
                    Text(AppInfo.copyright)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(L("Informazioni", "About"))
            .confirmationDialog(L("Eliminare tutto lo storico?", "Delete all history?"),
                                isPresented: $confirmWipe,
                                titleVisibility: .visible) {
                Button(L("Elimina tutto", "Delete all"), role: .destructive) { store.deleteAll() }
                Button(L("Annulla", "Cancel"), role: .cancel) {}
            } message: {
                Text(L("Tutte le sessioni salvate vengono rimosse dal telefono e l'azione non si può annullare.",
                       "All saved sessions will be removed from this phone. This can't be undone."))
            }
        }
        .tint(Theme.mint)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SafetyConsentView {}
}
