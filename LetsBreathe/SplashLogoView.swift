import SwiftUI

// Logo "Risalita verso la luce" animato per lo splash screen.
// Il sub parte poco più in basso e sale in un secondo fino alla posizione
// del logo; archi della superficie e scritta restano fermi.
// Le coordinate sono quelle del logo vettoriale su una griglia 240×240.

struct SplashLogoView: View {
    /// Lato del simbolo in punti.
    var size: CGFloat = 280
    /// Durata della salita in secondi.
    var duration: Double = 1.0
    /// Distanza di partenza sotto la posizione finale, in unità della griglia 240.
    var startOffset: CGFloat = 46
    /// Chiamata quando il sub ha raggiunto la posizione del logo.
    var onFinished: () -> Void = {}

    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SurfaceArcs()
            DiverFigure()
                .offset(y: risen ? 0 : startOffset * size / 240)
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
}

// MARK: - Colori del marchio

private enum Brand {
    static let navy = Color(red: 0x0B / 255, green: 0x2A / 255, blue: 0x3F / 255)
    static let arcOuter = Color(red: 0x12 / 255, green: 0x48 / 255, blue: 0x5A / 255)
    static let arcMiddle = Color(red: 0x1F / 255, green: 0x7F / 255, blue: 0x8C / 255)
    static let arcInner = Color(red: 0x8F / 255, green: 0xD6 / 255, blue: 0xD1 / 255)
    static let fins = Color(red: 0x2F / 255, green: 0xB7 / 255, blue: 0xB0 / 255)
    static let white = Color(red: 0xF2 / 255, green: 0xF7 / 255, blue: 0xF6 / 255)
}

// MARK: - Superficie (tre semicerchi fermi in alto)

private struct SurfaceArcs: View {
    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 240
            context.scaleBy(x: s, y: s)
            let arcs: [(CGFloat, Color)] = [
                (92, Brand.arcOuter), (62, Brand.arcMiddle), (34, Brand.arcInner),
            ]
            for (radius, color) in arcs {
                // Cerchio centrato sul bordo superiore: il Canvas ne mostra solo la metà inferiore.
                let rect = CGRect(x: 120 - radius, y: -radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }
}

// MARK: - Sub con pinne e bolle (la parte che si muove)

private struct DiverFigure: View {
    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 240
            context.scaleBy(x: s, y: s)

            // Pinne
            var finLeft = Path()
            finLeft.move(to: pt(112, 188))
            finLeft.addLine(to: pt(119, 188))
            finLeft.addCurve(to: pt(118, 232), control1: pt(119, 202), control2: pt(119, 216))
            finLeft.addLine(to: pt(100, 232))
            finLeft.addCurve(to: pt(112, 188), control1: pt(105, 216), control2: pt(110, 202))
            finLeft.closeSubpath()
            context.fill(finLeft, with: .color(Brand.fins))

            var finRight = Path()
            finRight.move(to: pt(128, 188))
            finRight.addLine(to: pt(121, 188))
            finRight.addCurve(to: pt(122, 232), control1: pt(121, 202), control2: pt(121, 216))
            finRight.addLine(to: pt(140, 232))
            finRight.addCurve(to: pt(128, 188), control1: pt(135, 216), control2: pt(130, 202))
            finRight.closeSubpath()
            context.fill(finRight, with: .color(Brand.fins))

            // Gambe
            var legs = Path()
            legs.move(to: pt(107, 146))
            legs.addLine(to: pt(133, 146))
            legs.addCurve(to: pt(128, 191), control1: pt(133, 162), control2: pt(130, 176))
            legs.addLine(to: pt(112, 191))
            legs.addCurve(to: pt(107, 146), control1: pt(110, 176), control2: pt(107, 162))
            legs.closeSubpath()
            context.fill(legs, with: .color(Brand.white))

            // Linea che separa le gambe
            var gap = Path()
            gap.move(to: pt(120, 158))
            gap.addLine(to: pt(120, 192))
            context.stroke(gap, with: .color(Brand.navy), lineWidth: 2)

            // Busto, spalle e collo
            var torso = Path()
            torso.move(to: pt(116, 90))
            torso.addLine(to: pt(124, 90))
            torso.addCurve(to: pt(139, 99), control1: pt(125, 95), control2: pt(132, 96))
            torso.addCurve(to: pt(141, 109), control1: pt(142, 101), control2: pt(142, 105))
            torso.addCurve(to: pt(133, 148), control1: pt(138, 122), control2: pt(134, 134))
            torso.addLine(to: pt(107, 148))
            torso.addCurve(to: pt(99, 109), control1: pt(106, 134), control2: pt(102, 122))
            torso.addCurve(to: pt(101, 99), control1: pt(98, 105), control2: pt(98, 101))
            torso.addCurve(to: pt(116, 90), control1: pt(108, 96), control2: pt(115, 95))
            torso.closeSubpath()
            context.fill(torso, with: .color(Brand.white))

            // Braccia
            let armStyle = StrokeStyle(lineWidth: 7, lineCap: .round)
            var armRight = Path()
            armRight.move(to: pt(139, 104))
            armRight.addCurve(to: pt(151, 150), control1: pt(146, 118), control2: pt(149, 134))
            context.stroke(armRight, with: .color(Brand.white), style: armStyle)

            var armLeft = Path()
            armLeft.move(to: pt(101, 104))
            armLeft.addCurve(to: pt(89, 150), control1: pt(94, 118), control2: pt(91, 134))
            context.stroke(armLeft, with: .color(Brand.white), style: armStyle)

            // Testa
            context.fill(
                Path(ellipseIn: CGRect(x: 110, y: 69, width: 20, height: 22)),
                with: .color(Brand.white))

            // Bolle
            let bubbles: [(CGFloat, CGFloat, CGFloat)] = [(172, 184, 5), (166, 158, 4), (174, 134, 3)]
            for (x, y, r) in bubbles {
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(Brand.arcInner), lineWidth: 2)
            }
            context.fill(
                Path(ellipseIn: CGRect(x: 165, y: 112, width: 4, height: 4)),
                with: .color(Brand.arcInner))
        }
    }

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
}

// MARK: - Esempio di schermata splash

struct SplashScreen: View {
    /// Chiamata a fine animazione, per passare al resto dell'app.
    var onFinished: () -> Void = {}

    var body: some View {
        ZStack {
            Brand.navy.ignoresSafeArea()
            VStack(spacing: 32) {
                SplashLogoView(onFinished: onFinished)
                BrandWordmark(size: 38)
            }
        }
    }
}

#Preview {
    SplashScreen()
}
