import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Radice dell'app: splash, consenso iniziale e quattro schede (Respira, Apnea, Storico, Info).

struct ContentView: View {
    enum Tab: Hashable { case breathe, apnea, history, info }

    @StateObject private var store = ApneaStore()
    @StateObject private var vitals = VitalsMonitor()
    @StateObject private var apnea = ApneaEngine()

    @AppStorage(AppInfo.consentKey) private var acceptedConsent = 0
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue
    @State private var tab: Tab = .breathe
    @State private var showSplash = true

    private var needsConsent: Bool { acceptedConsent < AppInfo.consentVersion }
    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .systemDefault }

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                BreathingScreen()
                    .tabItem { Label(L("Respira", "Breathe"), systemImage: "wind") }
                    .tag(Tab.breathe)
                ApneaScreen()
                    .tabItem { Label("Apnea", systemImage: "stopwatch") }
                    .tag(Tab.apnea)
                HistoryScreen()
                    .tabItem { Label(L("Storico", "History"), systemImage: "chart.xyaxis.line") }
                    .tag(Tab.history)
                AboutScreen()
                    .tabItem { Label("Info", systemImage: "info.circle") }
                    .tag(Tab.info)
            }
            // Quando cambia la lingua le schede vengono ricostruite con i nuovi testi.
            // Storico, Apple Watch e sessione di apnea vivono qui sopra e non si perdono,
            // e la scheda aperta resta la stessa.
            .id(languageRaw)
            .environment(\.locale, language.locale)
            .tint(Theme.mint)
            .environmentObject(store)
            .environmentObject(vitals)
            .environmentObject(apnea)

            // Avvertenze di sicurezza: si accettano una volta, prima di poter usare l'app.
            if needsConsent && !showSplash {
                SafetyConsentView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        acceptedConsent = AppInfo.consentVersion
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(2)
                    .onTapGesture(perform: dismissSplash)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // 1 secondo di risalita del sub, poi il logo resta fermo per poco meno di un secondo.
            try? await Task.sleep(for: .seconds(2.5))
            dismissSplash()
        }
    }

    private func dismissSplash() {
        guard showSplash else { return }
        withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
    }
}

// MARK: - Marchio

/// Immagini del marchio nel catalogo Assets dell'app.
enum BrandAsset: String {
    case logo = "BrandLogo"               // verticale: foto del sub e scritta sotto
    case mark = "BrandMark"               // foto del sub con i bordi sfumati
    case horizontal = "BrandHorizontal"   // foto a sinistra, scritta a destra
    case square = "BrandSquare"           // come l'icona: foto quadrata

    var isAvailable: Bool {
        #if canImport(UIKit)
        return UIImage(named: rawValue) != nil
        #else
        return true
        #endif
    }
}

/// Mostra un'immagine del marchio. Se manca dal catalogo compare un simbolo di riserva,
/// così una dimenticanza in Xcode non lascia uno spazio vuoto.
struct BrandImage: View {
    let asset: BrandAsset

    var body: some View {
        Group {
            if asset.isAvailable {
                Image(asset.rawValue)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "lungs.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.accentGradient)
                    .padding(16)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Splash

/// Il logo "risale verso la luce": la foto del sub compare in un secondo
/// con una leggera risalita (vedi `SplashLogoView.swift`).
/// Con "Riduci movimento" attivo il logo compare già nella posizione finale.
struct SplashView: View {
    @State private var visible = false

    var body: some View {
        ZStack {
            Brand.deepWater.ignoresSafeArea()

            VStack(spacing: 26) {
                VStack(spacing: 18) {
                    SplashLogoView(size: 230)

                    // Scritta del marchio, ferma sotto la foto.
                    BrandWordmark(size: 32)
                }
                .opacity(visible ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: visible)

                Text(L("Respira, trattieni, migliora", "Breathe, hold, improve"))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(visible ? 1 : 0)
                    .animation(.easeOut(duration: 0.7).delay(0.6), value: visible)
            }
        }
        .foregroundStyle(.white)
        .onAppear { visible = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppInfo.name)
    }
}

#Preview {
    ContentView()
}
