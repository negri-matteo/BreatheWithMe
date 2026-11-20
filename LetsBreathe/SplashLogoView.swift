import SwiftUI

// Logo animato per lo splash screen, ricavato dalla foto BrandMark in due livelli:
// - SplashWater: l'acqua con la luce dalla superficie, senza il sub. Resta ferma.
// - SplashDiver: solo il sub ritagliato. Sale in un secondo verso la luce
//   fino a tornare nella posizione della foto.

struct SplashLogoView: View {
    /// Lato del simbolo in punti.
    var size: CGFloat = 280
    /// Durata della salita in secondi.
    var duration: Double = 1.0
    /// Distanza di partenza sotto la posizione finale, in unità della griglia 240.
    var startOffset: CGFloat = 40
    /// Chiamata quando il sub ha raggiunto la sua posizione.
    var onFinished: () -> Void = {}

    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            layer("SplashWater")
            layer("SplashDiver")
                .offset(y: risen ? 0 : startOffset * size / 240)
                .opacity(risen ? 1 : 0)
        }
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Let's Breathe")
            .onAppear {
                guard !risen else { return }
                if reduceMotion {
                    risen = true
                    onFinished()
                } else {
                    withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: duration)) {
                        risen = true
                    } completion: {
                        onFinished()
                    }
                }
            }
    }

    private func layer(_ name: String) -> some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

// MARK: - Colori del marchio

enum Brand {
    /// Fondo dello splash: riprende l'acqua ai bordi della foto, più scura verso il basso.
    static let deepTop = Color(hex: 0x02303F)
    static let deepBottom = Color(hex: 0x020D16)
    static let wordmark = Color(hex: 0x39C2C0)         // "breathe", turchese
    static let white = Color(hex: 0xF2F7F6)            // "let's"

    static let deepWater = LinearGradient(colors: [deepTop, deepBottom],
                                          startPoint: .top, endPoint: .bottom)
}

/// Scritta del marchio: "let's" chiaro e sottile, "breathe" turchese.
/// Disegnata come testo, così resta nitida a ogni dimensione.
struct BrandWordmark: View {
    var size: CGFloat = 32

    var body: some View {
        (Text("let's ")
            .fontWeight(.light)
            .foregroundStyle(Brand.white)
            + Text("breathe")
            .fontWeight(.medium)
            .foregroundStyle(Brand.wordmark))
            .font(.system(size: size, design: .rounded))
            .accessibilityLabel("Let's Breathe")
    }
}

#Preview {
    SplashView()
}
