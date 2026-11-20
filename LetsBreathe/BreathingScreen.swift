import SwiftUI
import Combine
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// Requisiti: iOS 17 / macOS 14 (stessi dell'originale, per `onChange` a due parametri).

// MARK: - Design system
//
// Palette: sfondo nero-blu che sfuma in verde abisso, accenti menta, ciano, azzurro e cobalto.
// Le quattro fasi del respiro percorrono la palette dal verde al blu:
//   Inspira (menta) -> Trattieni (ciano) -> Espira (azzurro) -> Trattieni (cobalto)

enum Theme {
    static let night      = Color(hex: 0x02060C)   // nero-blu
    static let deepBlue   = Color(hex: 0x061A2E)   // blu notte
    static let abyssGreen = Color(hex: 0x03241D)   // verde abisso

    static let mint    = Color(hex: 0x34F0A1)
    static let cyan    = Color(hex: 0x22D3EE)
    static let azure   = Color(hex: 0x3B9CFF)
    static let cobalt  = Color(hex: 0x4B7BFF)
    static let emerald = Color(hex: 0x10B981)
    static let ink     = Color(hex: 0x04121C)      // testo scuro sopra i colori chiari

    static let stroke = Color.white.opacity(0.10)
    static let card   = Color.white.opacity(0.06)

    static let accentGradient = LinearGradient(
        colors: [Theme.mint, Theme.cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Int {
    /// 75 -> "1:15"
    var clockString: String { String(format: "%d:%02d", self / 60, self % 60) }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Model

enum BreathingAction: String, CaseIterable, Codable {
    case inhale = "Inhale"
    case hold1 = "Hold 1"
    case exhale = "Exhale"
    case hold2 = "Hold 2"

    /// Titolo localizzato in italiano (il rawValue resta per compatibilità)
    var title: String {
        switch self {
        case .inhale: L("Inspira", "Inhale")
        case .hold1: L("Trattieni 1", "Hold 1")
        case .exhale: L("Espira", "Exhale")
        case .hold2: L("Trattieni 2", "Hold 2")
        }
    }

    var shortTitle: String {
        switch self {
        case .inhale: L("Inspira", "Inhale")
        case .hold1, .hold2: L("Trattieni", "Hold")
        case .exhale: L("Espira", "Exhale")
        }
    }

    /// Suggerimento mostrato sotto il titolo della fase: distingue anche le due trattenute.
    var hint: String {
        switch self {
        case .inhale: L("Dal naso, lentamente", "Slowly, through your nose")
        case .hold1: L("A polmoni pieni", "With full lungs")
        case .exhale: L("Svuota con calma", "Empty your lungs gently")
        case .hold2: L("A polmoni vuoti", "With empty lungs")
        }
    }

    var icon: String {
        switch self {
        case .inhale: "lungs.fill"
        case .hold1: "hand.raised.fill"
        case .exhale: "wind"
        case .hold2: "pause.fill"
        }
    }

    var color: Color {
        switch self {
        case .inhale: Theme.mint
        case .hold1: Theme.cyan
        case .exhale: Theme.azure
        case .hold2: Theme.cobalt
        }
    }
}

struct BreathingProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var inhale: Int
    var hold1: Int
    var exhale: Int
    var hold2: Int
    var cycles: Int
    var soundEnabled: Bool
    var beepSound: Int
    var tinSound: Int
    var hapticsEnabled: Bool
    var tickEnabled: Bool

    init(id: UUID = UUID(), name: String, inhale: Int, hold1: Int, exhale: Int, hold2: Int, cycles: Int,
         soundEnabled: Bool, beepSound: Int, tinSound: Int,
         hapticsEnabled: Bool = true, tickEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.inhale = inhale
        self.hold1 = hold1
        self.exhale = exhale
        self.hold2 = hold2
        self.cycles = cycles
        self.soundEnabled = soundEnabled
        self.beepSound = beepSound
        self.tinSound = tinSound
        self.hapticsEnabled = hapticsEnabled
        self.tickEnabled = tickEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id, name, inhale, hold1, exhale, hold2, cycles, soundEnabled, beepSound, tinSound
        case hapticsEnabled, tickEnabled
    }

    /// I profili salvati dalle versioni precedenti non hanno i campi nuovi: si usano i valori di default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        inhale = try c.decode(Int.self, forKey: .inhale)
        hold1 = try c.decode(Int.self, forKey: .hold1)
        exhale = try c.decode(Int.self, forKey: .exhale)
        hold2 = try c.decode(Int.self, forKey: .hold2)
        cycles = try c.decode(Int.self, forKey: .cycles)
        soundEnabled = try c.decode(Bool.self, forKey: .soundEnabled)
        beepSound = try c.decode(Int.self, forKey: .beepSound)
        tinSound = try c.decode(Int.self, forKey: .tinSound)
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        tickEnabled = try c.decodeIfPresent(Bool.self, forKey: .tickEnabled) ?? true
    }
}

extension BreathingProfile {
    var durations: [Int] { [inhale, hold1, exhale, hold2] }
    var cycleSeconds: Int { inhale + hold1 + exhale + hold2 }
    var totalSeconds: Int { cycleSeconds * cycles }

    /// Testo per VoiceOver, ad esempio "Inspira 4 secondi, Trattieni 1 4 secondi".
    var spokenPattern: String {
        BreathingAction.allCases.enumerated()
            .filter { durations[$0.offset] > 0 }
            .map { L("\($0.element.title) \(durations[$0.offset]) secondi", "\($0.element.title) \(durations[$0.offset]) seconds") }
            .joined(separator: ", ")
    }

    static var draft: BreathingProfile {
        BreathingProfile(name: L("Personalizzato", "Custom"), inhale: 4, hold1: 2, exhale: 4, hold2: 2,
                         cycles: 3, soundEnabled: true, beepSound: 420, tinSound: 840)
    }
}

struct BreathingPreset: Identifiable {
    let name: String
    let note: String
    let inhale: Int
    let hold1: Int
    let exhale: Int
    let hold2: Int

    var id: String { name }
    var pattern: String { "\(inhale)-\(hold1)-\(exhale)-\(hold2)" }

    // Calcolato a ogni accesso: i testi seguono la lingua scelta.
    static var all: [BreathingPreset] { [
        BreathingPreset(name: "Box", note: L("Calma e focus", "Calm and focus"), inhale: 4, hold1: 4, exhale: 4, hold2: 4),
        BreathingPreset(name: "4-7-8", note: L("Prima di dormire", "Before sleep"), inhale: 4, hold1: 7, exhale: 8, hold2: 0),
        BreathingPreset(name: L("Coerente", "Coherent"), note: L("Equilibrio", "Balance"), inhale: 5, hold1: 0, exhale: 5, hold2: 0),
        BreathingPreset(name: L("Diaframmatico", "Diaphragmatic"), note: L("Anti-stress", "Stress relief"), inhale: 4, hold1: 0, exhale: 6, hold2: 0),
        BreathingPreset(name: L("Triangolo", "Triangle"), note: L("Concentrazione", "Concentration"), inhale: 4, hold1: 4, exhale: 4, hold2: 0)
    ] }
}

// MARK: - Audio e aptica

/// Tutto il lavoro audio (attivazione della sessione, motore, generazione dei campioni) gira
/// su una coda seriale dedicata: `AVAudioSession.setActive` può bloccare per centinaia di
/// millisecondi e sul main thread farebbe scattare l'interfaccia.
/// `play` e `stop` si possono chiamare da qualsiasi thread e ritornano subito; la coda seriale
/// mantiene l'ordine delle chiamate.
nonisolated final class ToneGenerator: @unchecked Sendable {
    static let shared = ToneGenerator()

    private let queue = DispatchQueue(label: "ToneGenerator.audio", qos: .userInitiated)
    // Accessibili solo da `queue`.
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var configured = false

    private func configureIfNeeded() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !configured else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        configured = true
    }

    /// `bell: true` produce un suono più morbido con decadimento, usato per i cambi fase.
    func play(frequency: Int, duration: Double = 0.15, bell: Bool = false) {
        queue.async { self.render(frequency: frequency, duration: duration, bell: bell) }
    }

    func stop() {
        queue.async {
            // Il nodo viene collegato al motore solo al primo suono: prima di allora non c'è nulla da fermare.
            guard self.configured else { return }
            self.player.stop()
        }
    }

    private func render(frequency: Int, duration: Double, bell: Bool) {
        configureIfNeeded()
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }

        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frameCount

        let freq = Double(frequency)
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            // fade in/out per evitare "click"
            let fadeIn = min(1.0, t / (bell ? 0.004 : 0.01))
            let fadeOut = max(0.0, min(1.0, (duration - t) / 0.02))
            let fundamental = sin(2 * Double.pi * freq * t)
            let body: Double
            if bell {
                let overtone = sin(4 * Double.pi * freq * t)
                body = (fundamental + 0.35 * overtone) * exp(-t * 7) * 0.3
            } else {
                body = fundamental * 0.4
            }
            samples[i] = Float(body * fadeIn * fadeOut)
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}

enum Haptics {
    static func phaseChange() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

// MARK: - Motore della sessione
//
// Un unico ticker da 50 ms calcola il progresso dal tempo reale trascorso:
// niente deriva, pausa che congela davvero l'animazione, ring e cerchio sempre in sincrono.

@MainActor
final class SessionEngine: ObservableObject {
    enum State { case idle, countdown, running, paused }

    struct Completion: Equatable, Identifiable {
        let id = UUID()
        let name: String
        let cycles: Int
        let seconds: Int
    }

    static let countdownSeconds = 3

    @Published private(set) var state: State = .idle
    @Published private(set) var phaseIndex = 0
    @Published private(set) var cycle = 1
    @Published private(set) var phaseProgress = 0.0      // 0...1 nella fase corrente (o nel conto alla rovescia)
    @Published private(set) var secondsLeft = 0
    @Published private(set) var countdownLeft = SessionEngine.countdownSeconds
    @Published private(set) var sessionProgress = 0.0    // 0...1 sull'intera sessione
    @Published private(set) var completion: Completion?

    private var profile: BreathingProfile?
    private var phaseElapsed = 0.0
    private var finishedSeconds = 0.0
    private var countdownElapsed = 0.0
    private var lastTick = Date()
    private var ticker: Task<Void, Never>?
    private let sequence = BreathingAction.allCases

    var isActive: Bool { state != .idle }
    var keepsScreenAwake: Bool { state == .running || state == .countdown }
    var currentAction: BreathingAction { sequence[phaseIndex] }

    var upcomingPhase: (action: BreathingAction, seconds: Int)? {
        guard let profile = profile, let next = nextPhase(after: phaseIndex, cycle: cycle) else { return nil }
        return (sequence[next.index], profile.durations[next.index])
    }

    // MARK: Controlli

    func start(profile: BreathingProfile) {
        stopTicker()
        ToneGenerator.shared.stop()
        self.profile = profile
        completion = nil
        resetValues()
        secondsLeft = profile.inhale
        state = .countdown
        playCountdownBeep()
        startTicker()
    }

    func pause() {
        guard state == .running else { return }
        stopTicker()
        ToneGenerator.shared.stop()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        startTicker()
    }

    func stop() {
        stopTicker()
        ToneGenerator.shared.stop()
        resetValues()
        state = .idle
    }

    /// Permette di spegnere/accendere il suono anche a sessione in corso.
    func setSound(enabled: Bool) {
        profile?.soundEnabled = enabled
        if !enabled { ToneGenerator.shared.stop() }
    }

    // MARK: Ticker

    private func startTicker() {
        stopTicker()
        lastTick = Date()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 0.25)
        lastTick = now
        switch state {
        case .countdown: tickCountdown(dt)
        case .running: tickRunning(dt)
        case .idle, .paused: break
        }
    }

    private func tickCountdown(_ dt: Double) {
        countdownElapsed += dt
        if countdownElapsed >= Double(Self.countdownSeconds) {
            beginSession()
            return
        }
        phaseProgress = countdownElapsed / Double(Self.countdownSeconds)
        let left = Self.countdownSeconds - Int(countdownElapsed)
        if left != countdownLeft {
            countdownLeft = left
            playCountdownBeep()
        }
    }

    private func beginSession() {
        guard let first = nextPhase(after: -1, cycle: 1) else {
            stop()
            return
        }
        state = .running
        startPhase(index: first.index, cycle: first.cycle)
    }

    private func startPhase(index: Int, cycle: Int) {
        guard let profile = profile else { return }
        phaseIndex = index
        self.cycle = cycle
        phaseElapsed = 0
        phaseProgress = 0
        let length = profile.durations[index]
        secondsLeft = length

        if profile.hapticsEnabled { Haptics.phaseChange() }
        if profile.soundEnabled {
            ToneGenerator.shared.play(frequency: profile.tinSound, duration: 0.5, bell: true)
        }
        #if canImport(UIKit)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement,
                                 argument: L("\(sequence[index].title), \(length) secondi", "\(sequence[index].title), \(length) seconds"))
        }
        #endif
    }

    private func tickRunning(_ dt: Double) {
        guard let profile = profile else { stop(); return }
        phaseElapsed += dt
        let length = Double(profile.durations[phaseIndex])

        if phaseElapsed >= length {
            let carry = phaseElapsed - length          // il resto passa alla fase successiva: zero deriva
            finishedSeconds += length
            if let next = nextPhase(after: phaseIndex, cycle: cycle) {
                startPhase(index: next.index, cycle: next.cycle)
                phaseElapsed = carry
            } else {
                complete()
            }
            return
        }

        phaseProgress = phaseElapsed / length
        sessionProgress = min((finishedSeconds + phaseElapsed) / Double(max(profile.totalSeconds, 1)), 1)

        let left = Int((length - phaseElapsed).rounded(.up))
        if left != secondsLeft {
            secondsLeft = left
            if profile.soundEnabled && profile.tickEnabled {
                ToneGenerator.shared.play(frequency: profile.beepSound)
            }
        }
    }

    private func complete() {
        guard let profile = profile else { stop(); return }
        stopTicker()
        let summary = Completion(name: profile.name, cycles: profile.cycles, seconds: profile.totalSeconds)
        resetValues()
        state = .idle
        completion = summary
        if profile.hapticsEnabled { Haptics.success() }
        if profile.soundEnabled {
            ToneGenerator.shared.play(frequency: profile.tinSound, duration: 1.0, bell: true)
        }
    }

    // MARK: Utilità

    private func resetValues() {
        phaseIndex = 0
        cycle = 1
        phaseElapsed = 0
        finishedSeconds = 0
        countdownElapsed = 0
        phaseProgress = 0
        sessionProgress = 0
        countdownLeft = Self.countdownSeconds
        secondsLeft = profile?.inhale ?? 0
    }

    private func playCountdownBeep() {
        guard let profile = profile, profile.soundEnabled else { return }
        ToneGenerator.shared.play(frequency: profile.beepSound)
    }

    /// Trova la prossima fase con durata > 0 (saltando quelle a 0s) senza ricorsione.
    /// Restituisce nil quando la sessione è finita.
    private func nextPhase(after index: Int, cycle: Int) -> (index: Int, cycle: Int)? {
        guard let profile = profile else { return nil }
        var i = index
        var c = cycle
        for _ in 0..<sequence.count {
            i += 1
            if i >= sequence.count { i = 0; c += 1 }
            if c > profile.cycles { return nil }
            if profile.durations[i] > 0 { return (i, c) }
        }
        return nil
    }
}

// MARK: - Componenti grafici riutilizzabili

/// Nelle pagine che scorrono il contenuto sfuma e sparisce prima della barra delle schede:
/// sotto la barra non resta testo leggibile. Va messo prima di `.background`,
/// così lo sfondo resta visibile fino in fondo.
struct FadeAboveTabBar: ViewModifier {
    func body(content: Content) -> some View {
        content.mask {
            // Il riquadro della maschera si ferma dove inizia la barra (area sicura):
            // tutto quello che scorre più in basso viene nascosto.
            // In alto invece la maschera copre anche l'area sicura, dove sta il titolo grande.
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}

extension View {
    func fadeAboveTabBar() -> some View { modifier(FadeAboveTabBar()) }
}

struct AppBackground: View {
    var accent: Color = Theme.mint

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.night, Theme.deepBlue, Theme.abyssGreen],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(Theme.cobalt.opacity(0.22))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: -150, y: -300)
            Circle()
                .fill(Theme.emerald.opacity(0.20))
                .frame(width: 380, height: 380)
                .blur(radius: 100)
                .offset(x: 170, y: 330)
            // Alone dietro al cerchio: prende il colore della fase corrente.
            Circle()
                .fill(accent.opacity(0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(y: -20)
                .animation(.easeInOut(duration: 0.8), value: accent)
        }
        .ignoresSafeArea()
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GlassIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 44
    var tint: Color = .white
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

/// Le durate delle quattro fasi come piccole pillole colorate (le fasi a 0s non compaiono).
struct PatternChips: View {
    let profile: BreathingProfile

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(BreathingAction.allCases.enumerated()), id: \.offset) { index, action in
                let seconds = profile.durations[index]
                if seconds > 0 {
                    Text("\(seconds)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(action.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(action.color.opacity(0.16), in: Capsule())
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.spokenPattern)
    }
}

struct BreathingOrb: View {
    let color: Color
    let scale: CGFloat
    let ringProgress: Double
    let value: String
    let caption: String
    var dimmed: Bool = false
    var scaleAnimation: Animation = .linear(duration: 0.06)
    var valueFontScale: CGFloat = 0.2
    var animatesValue: Bool = true

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height, 340)
            let ringSize = side * 0.92
            let orbSize = side * 0.70

            ZStack {
                // alone morbido che respira insieme al cerchio
                Circle()
                    .fill(color.opacity(dimmed ? 0.10 : 0.24))
                    .frame(width: orbSize * 1.25, height: orbSize * 1.25)
                    .blur(radius: 36)
                    .scaleEffect(0.8 + 0.25 * scale)

                // anello: avanzamento della fase corrente
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                    .frame(width: ringSize, height: ringSize)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringSize, height: ringSize)
                    .shadow(color: color.opacity(0.7), radius: 8)

                // il cerchio che si espande e si contrae
                Circle()
                    .fill(color.opacity(dimmed ? 0.14 : 0.26))
                    .overlay(
                        Circle().fill(
                            RadialGradient(colors: [Color.white.opacity(0.26), Color.clear],
                                           center: UnitPoint(x: 0.32, y: 0.28),
                                           startRadius: 0, endRadius: orbSize * 0.55)
                        )
                    )
                    .overlay(Circle().stroke(color.opacity(dimmed ? 0.5 : 0.9), lineWidth: 2))
                    .frame(width: orbSize * scale, height: orbSize * scale)
                    .shadow(color: color.opacity(dimmed ? 0.2 : 0.5), radius: 26)

                VStack(spacing: 2) {
                    Text(value)
                        .font(.system(size: side * valueFontScale, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(animatesValue ? .easeInOut(duration: 0.25) : nil, value: value)
                    Text(caption)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(scaleAnimation, value: scale)
            .animation(.linear(duration: 0.06), value: ringProgress)
            .animation(.easeInOut(duration: 0.5), value: color)
            .animation(.easeInOut(duration: 0.3), value: dimmed)
        }
    }
}

struct ToastView: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Theme.mint)
            Text(text).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let text: String
}

struct EditorSession: Identifiable {
    let id = UUID()
    var profile: BreathingProfile
    var editingIndex: Int?      // nil = nuovo timer
}

// MARK: - Schermata Respira

struct BreathingScreen: View {
    @AppStorage("profiles") private var savedProfiles: Data = Data()
    @AppStorage("selectedProfileID") private var selectedProfileID: String = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var engine = SessionEngine()

    @State private var profiles: [BreathingProfile] = []
    @State private var didLoad = false
    @State private var selectedProfileIndex = 0
    @State private var showingProfileList = false
    @State private var editor: EditorSession?
    @State private var toast: Toast?
    @State private var completionBanner: SessionEngine.Completion?

    private var selectedProfile: BreathingProfile? {
        guard profiles.indices.contains(selectedProfileIndex) else { return nil }
        return profiles[selectedProfileIndex]
    }

    // MARK: Stato derivato

    private var accentColor: Color {
        switch engine.state {
        case .idle: return Theme.mint
        case .countdown: return Theme.azure
        case .running, .paused: return engine.currentAction.color
        }
    }

    private func smooth(_ x: Double) -> CGFloat {
        CGFloat(x * x * (3 - 2 * x))
    }

    /// Il cerchio segue il respiro: cresce in inspirazione, resta grande nella prima trattenuta,
    /// si restringe in espirazione, resta piccolo nella seconda trattenuta.
    private var orbScale: CGFloat {
        let low: CGFloat = reduceMotion ? 0.92 : 0.74
        let high: CGFloat = 1.0
        let idle = low + (high - low) * 0.35
        switch engine.state {
        case .idle:
            return idle
        case .countdown:
            return idle + (low - idle) * smooth(engine.phaseProgress)
        case .running, .paused:
            let p = smooth(engine.phaseProgress)
            switch engine.currentAction {
            case .inhale: return low + (high - low) * p
            case .hold1: return high
            case .exhale: return high - (high - low) * p
            case .hold2: return low
            }
        }
    }

    private var orbValue: String {
        switch engine.state {
        case .idle: return (selectedProfile?.totalSeconds ?? 0).clockString
        case .countdown: return "\(engine.countdownLeft)"
        case .running, .paused: return "\(engine.secondsLeft)"
        }
    }

    private var orbCaption: String {
        switch engine.state {
        case .idle: return L("durata", "duration")
        case .countdown: return L("inizio tra", "starts in")
        case .running: return L("secondi", "seconds")
        case .paused: return L("in pausa", "paused")
        }
    }

    private var status: (title: String, hint: String, next: String) {
        guard let profile = selectedProfile else { return ("", "", "") }
        switch engine.state {
        case .idle:
            return (L("Pronto?", "Ready?"), L("Siediti comodo e premi play", "Sit comfortably and press play"), L("Respira seguendo il cerchio", "Breathe along with the circle"))
        case .countdown:
            return (L("Preparati", "Get ready"), L("Rilassa le spalle e respira normalmente", "Relax your shoulders and breathe normally"), "")
        case .running:
            let action = engine.currentAction
            let next: String
            if let upcoming = engine.upcomingPhase {
                next = L("Poi: \(upcoming.action.title), \(upcoming.seconds)s", "Next: \(upcoming.action.title), \(upcoming.seconds)s")
            } else {
                next = L("Ultima fase", "Last phase")
            }
            return (action.shortTitle, action.hint, next)
        case .paused:
            return (L("In pausa", "Paused"), L("Premi play per riprendere", "Press play to resume"), L("Ciclo \(engine.cycle) di \(profile.cycles)", "Cycle \(engine.cycle) of \(profile.cycles)"))
        }
    }

    private var progressCaption: String {
        guard let profile = selectedProfile else { return "" }
        switch engine.state {
        case .idle:
            return L("\(profile.cycles) cicli, \(profile.totalSeconds.clockString)", "\(profile.cycles) cycles, \(profile.totalSeconds.clockString)")
        case .countdown:
            return L("Si parte tra \(engine.countdownLeft)", "Starting in \(engine.countdownLeft)")
        case .running, .paused:
            let remaining = Int((Double(profile.totalSeconds) * (1 - engine.sessionProgress)).rounded(.up))
            return L("Ciclo \(engine.cycle) di \(profile.cycles), restano \(remaining.clockString)", "Cycle \(engine.cycle) of \(profile.cycles), \(remaining.clockString) left")
        }
    }

    // MARK: Sottoviste

    private var headerView: some View {
        HStack(spacing: 12) {
            // Segnaposto: tiene il titolo centrato rispetto al pulsante di modifica a destra.
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.3)) { showingProfileList = true }
            } label: {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text(selectedProfile?.name ?? L("Nessun profilo", "No timer"))
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.mint)
                    }
                    .foregroundStyle(.white)
                    if let profile = selectedProfile {
                        PatternChips(profile: profile)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(engine.isActive)
            .accessibilityLabel(L("Timer \(selectedProfile?.name ?? ""). Apri l'elenco dei timer",
                                 "Timer \(selectedProfile?.name ?? ""). Open the timer list"))

            Spacer(minLength: 0)

            GlassIconButton(systemName: "slider.horizontal.3", label: L("Modifica timer", "Edit timer")) { editSelected() }
                .disabled(engine.isActive || selectedProfile == nil)
        }
    }

    /// Cambio rapido tra timer a un tocco, visibile solo quando la sessione non è attiva.
    /// Fino a 5 timer stanno tutti in una riga, a larghezza uguale, senza scorrere.
    /// Con più timer la riga torna a scorrere.
    private var profileChips: some View {
        Group {
            if profiles.count <= 5 {
                HStack(spacing: 6) {
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                        profileChip(profile, index: index, fill: true)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                            profileChip(profile, index: index, fill: false)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .frame(height: 38)
        .opacity(engine.isActive ? 0 : 1)
        .allowsHitTesting(!engine.isActive)
        .animation(.easeInOut(duration: 0.25), value: engine.isActive)
    }

    private func profileChip(_ profile: BreathingProfile, index: Int, fill: Bool) -> some View {
        let isSelected = index == selectedProfileIndex
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { selectProfile(index) }
        } label: {
            Text(profile.name)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? Theme.ink : Color.white.opacity(0.85))
                .padding(.horizontal, fill ? 6 : 14)
                .padding(.vertical, 8)
                .frame(maxWidth: fill ? .infinity : nil)
                .background(
                    Capsule().fill(isSelected ? AnyShapeStyle(Theme.accentGradient)
                                              : AnyShapeStyle(Color.white.opacity(0.08)))
                )
                .overlay(Capsule().stroke(Theme.stroke, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func isCurrentCycle(_ index: Int) -> Bool {
        engine.state != .idle && index == engine.cycle - 1
    }

    private func dotColor(for index: Int) -> Color {
        guard engine.state != .idle else { return Color.white.opacity(0.18) }
        if index < engine.cycle - 1 { return Theme.mint }
        if index == engine.cycle - 1 { return accentColor }
        return Color.white.opacity(0.18)
    }

    @ViewBuilder
    private var cycleIndicator: some View {
        if let profile = selectedProfile, profile.cycles <= 10 {
            HStack(spacing: 6) {
                ForEach(0..<profile.cycles, id: \.self) { index in
                    Capsule()
                        .fill(dotColor(for: index))
                        .frame(width: isCurrentCycle(index) ? 22 : 8, height: 8)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: engine.cycle)
            .accessibilityHidden(true)
        }
    }

    private var sessionProgressView: some View {
        VStack(spacing: 10) {
            HStack {
                cycleIndicator
                Spacer(minLength: 8)
                Text(progressCaption)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(Theme.accentGradient)
                        .frame(width: max(0, geo.size.width * engine.sessionProgress))
                }
            }
            .frame(height: 6)
            .animation(.linear(duration: 0.1), value: engine.sessionProgress)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Progresso della sessione", "Session progress"))
        .accessibilityValue(L("\(Int(engine.sessionProgress * 100)) per cento", "\(Int(engine.sessionProgress * 100)) percent"))
    }

    private var orbView: some View {
        BreathingOrb(
            color: accentColor,
            scale: orbScale,
            ringProgress: engine.state == .idle ? 0 : engine.phaseProgress,
            value: orbValue,
            caption: orbCaption,
            dimmed: engine.state == .paused
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.title). \(orbValue) \(orbCaption)")
    }

    private var statusView: some View {
        VStack(spacing: 6) {
            Text(status.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
            Text(status.hint)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
            Text(status.next)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(minHeight: 18)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 96)
        .animation(.easeInOut(duration: 0.3), value: status.title)
        .accessibilityElement(children: .combine)
    }

    private var primaryButtonLabel: String {
        switch engine.state {
        case .running: return L("Pausa", "Pause")
        case .paused: return L("Riprendi", "Resume")
        case .idle, .countdown: return L("Avvia", "Start")
        }
    }

    private var controlsView: some View {
        HStack(spacing: 36) {
            GlassIconButton(systemName: "stop.fill", label: L("Ferma la sessione", "Stop the session"), size: 56) { engine.stop() }
                .disabled(!engine.isActive)

            Button(action: primaryAction) {
                Image(systemName: engine.state == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(Theme.accentGradient))
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: Theme.mint.opacity(0.45), radius: 18, y: 4)
            }
            .buttonStyle(PressableStyle())
            .disabled(selectedProfile == nil || engine.state == .countdown)
            .opacity(engine.state == .countdown ? 0.5 : 1)
            .accessibilityLabel(primaryButtonLabel)

            GlassIconButton(
                systemName: selectedProfile?.soundEnabled == true ? "speaker.wave.2.fill" : "speaker.slash.fill",
                label: selectedProfile?.soundEnabled == true ? L("Disattiva il suono", "Turn sound off") : L("Attiva il suono", "Turn sound on"),
                size: 56,
                tint: selectedProfile?.soundEnabled == true ? Theme.mint : Color.white.opacity(0.6)
            ) { toggleSound() }
                .disabled(selectedProfile == nil)
        }
    }

    private var timerScreen: some View {
        VStack(spacing: 16) {
            headerView
            profileChips
            sessionProgressView
            orbView
            statusView
            controlsView
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lungs.fill")
                .font(.system(size: 54))
                .foregroundStyle(Theme.accentGradient)
            Text(L("Nessun timer", "No timers"))
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text(L("Crea la tua prima routine di respirazione oppure riparti dai timer di esempio.", "Create your first breathing routine, or start again from the sample timers."))
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button(action: makeDraftProfile) {
                Label(L("Nuovo timer", "New timer"), systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Theme.accentGradient, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            Button(L("Ripristina i timer di esempio", "Restore sample timers"), action: restoreDefaults)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.mint)
        }
        .foregroundStyle(.white)
        .padding(32)
    }

    private func completionBannerView(_ summary: SessionEngine.Completion) -> some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Sessione completata", "Session complete")).font(.headline)
                    Text(L("\(summary.name), \(summary.cycles) cicli, \(summary.seconds.clockString)", "\(summary.name), \(summary.cycles) cycles, \(summary.seconds.clockString)"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.mint.opacity(0.4), lineWidth: 1))
            .padding(.top, 8)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .allowsHitTesting(false)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            AppBackground(accent: accentColor)

            if showingProfileList {
                ProfilesListView(
                    profiles: profiles,
                    selectedProfileIndex: selectedProfileIndex,
                    onSelect: { index in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectProfile(index)
                            showingProfileList = false
                        }
                    },
                    onAdd: makeDraftProfile,
                    onEdit: { index in
                        selectProfile(index)
                        editSelected()
                    },
                    onDuplicate: duplicateProfile(at:),
                    onDelete: deleteProfile(at:),
                    onClose: { withAnimation(.easeInOut(duration: 0.3)) { showingProfileList = false } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if profiles.isEmpty {
                emptyStateView.transition(.opacity)
            } else {
                timerScreen.transition(.opacity)
            }

            if let toast = toast {
                VStack {
                    Spacer()
                    ToastView(icon: toast.icon, text: toast.text).padding(.bottom, 130)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }

            if let banner = completionBanner {
                completionBannerView(banner)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear(perform: loadProfiles)
        .onDisappear {
            switch engine.state {
            case .running: engine.pause()
            case .countdown: engine.stop()
            case .idle, .paused: break
            }
        }
        .onChange(of: profiles) { _, _ in saveProfiles() }
        .onChange(of: engine.keepsScreenAwake) { _, awake in setScreenAwake(awake) }
        .onChange(of: engine.completion) { _, summary in
            guard let summary else { return }
            withAnimation(.easeInOut(duration: 0.3)) { completionBanner = summary }
        }
        .onChange(of: scenePhase) { _, phase in
            // Il ticker non gira in background: pausa esplicita invece di una sessione "congelata".
            guard phase != .active else { return }
            switch engine.state {
            case .running: engine.pause()
            case .countdown: engine.stop()
            case .idle, .paused: break
            }
        }
        .task(id: toast?.id) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { toast = nil }
        }
        .task(id: completionBanner?.id) {
            guard completionBanner != nil else { return }
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { completionBanner = nil }
        }
        .sheet(item: $editor) { session in
            ProfileEditorView(
                profile: Binding(
                    get: { editor?.profile ?? session.profile },
                    set: { editor?.profile = $0 }
                ),
                isNew: session.editingIndex == nil,
                onSave: commitEditor,
                onCancel: { editor = nil }
            )
        }
    }

    // MARK: Azioni sulla sessione

    private func primaryAction() {
        guard let profile = selectedProfile else { return }
        switch engine.state {
        case .idle: engine.start(profile: profile)
        case .running: engine.pause()
        case .paused: engine.resume()
        case .countdown: break
        }
    }

    private func toggleSound() {
        guard profiles.indices.contains(selectedProfileIndex) else { return }
        profiles[selectedProfileIndex].soundEnabled.toggle()
        let enabled = profiles[selectedProfileIndex].soundEnabled
        engine.setSound(enabled: enabled)
        withAnimation(.easeInOut(duration: 0.25)) {
            toast = Toast(icon: enabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                          text: enabled ? L("Suono attivato", "Sound on") : L("Suono disattivato", "Sound off"))
        }
    }

    private func setScreenAwake(_ awake: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = awake
        #endif
    }

    // MARK: Profili

    private func selectProfile(_ index: Int) {
        guard profiles.indices.contains(index) else { return }
        engine.stop()
        selectedProfileIndex = index
        selectedProfileID = profiles[index].id.uuidString
    }

    private func makeDraftProfile() {
        editor = EditorSession(profile: .draft, editingIndex: nil)
    }

    private func editSelected() {
        guard let profile = selectedProfile else { return }
        editor = EditorSession(profile: profile, editingIndex: selectedProfileIndex)
    }

    private func commitEditor() {
        guard let session = editor else { return }
        var profile = session.profile
        profile.name = profile.name.trimmed
        guard !profile.name.isEmpty, profile.cycleSeconds > 0 else { return }

        engine.stop()
        if let index = session.editingIndex, profiles.indices.contains(index) {
            profiles[index] = profile
            selectedProfileIndex = index
        } else {
            profiles.append(profile)
            selectedProfileIndex = profiles.count - 1
        }
        selectedProfileID = profile.id.uuidString
        editor = nil
        showingProfileList = false
    }

    private func duplicateProfile(at index: Int) {
        guard profiles.indices.contains(index) else { return }
        var copy = profiles[index]
        copy.id = UUID()
        copy.name = L("\(copy.name) (copia)", "\(copy.name) (copy)")
        profiles.insert(copy, at: index + 1)
        if selectedProfileIndex > index { selectedProfileIndex += 1 }
        withAnimation(.easeInOut(duration: 0.25)) {
            toast = Toast(icon: "plus.square.on.square", text: L("Timer duplicato", "Timer duplicated"))
        }
    }

    private func deleteProfile(at index: Int) {
        guard profiles.indices.contains(index) else { return }
        engine.stop()
        let selectedID = selectedProfile?.id
        profiles.remove(at: index)
        if let selectedID, let newIndex = profiles.firstIndex(where: { $0.id == selectedID }) {
            selectedProfileIndex = newIndex
        } else {
            selectedProfileIndex = min(max(selectedProfileIndex, 0), max(profiles.count - 1, 0))
        }
        if let current = selectedProfile { selectedProfileID = current.id.uuidString }
    }

    private func restoreDefaults() {
        profiles = defaultProfiles()
        selectedProfileIndex = 0
        selectedProfileID = profiles[0].id.uuidString
    }

    private func defaultProfiles() -> [BreathingProfile] {
        [
            BreathingProfile(name: "Calm", inhale: 4, hold1: 4, exhale: 4, hold2: 4, cycles: 3, soundEnabled: true, beepSound: 440, tinSound: 880),
            BreathingProfile(name: "Focus", inhale: 5, hold1: 2, exhale: 5, hold2: 2, cycles: 4, soundEnabled: true, beepSound: 550, tinSound: 990),
            BreathingProfile(name: "Relax", inhale: 3, hold1: 3, exhale: 6, hold2: 3, cycles: 5, soundEnabled: true, beepSound: 660, tinSound: 1100),
            BreathingProfile(name: "Energy", inhale: 6, hold1: 2, exhale: 2, hold2: 2, cycles: 3, soundEnabled: true, beepSound: 770, tinSound: 1200),
            BreathingProfile(name: "Sleep", inhale: 4, hold1: 7, exhale: 8, hold2: 0, cycles: 4, soundEnabled: true, beepSound: 660, tinSound: 880)
        ]
    }

    private func loadProfiles() {
        guard !didLoad else { return }
        didLoad = true
        // Dati assenti -> profili di default. Lista vuota salvata volontariamente -> resta vuota.
        if savedProfiles.isEmpty {
            profiles = defaultProfiles()
        } else if let decoded = try? JSONDecoder().decode([BreathingProfile].self, from: savedProfiles) {
            profiles = decoded
        } else {
            profiles = defaultProfiles()
        }
        // Ripristina l'ultimo timer usato
        if let index = profiles.firstIndex(where: { $0.id.uuidString == selectedProfileID }) {
            selectedProfileIndex = index
        } else {
            selectedProfileIndex = 0
            if let first = profiles.first { selectedProfileID = first.id.uuidString }
        }
    }

    private func saveProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        savedProfiles = data
    }
}

// MARK: - Elenco timer

struct ProfilesListView: View {
    let profiles: [BreathingProfile]
    let selectedProfileIndex: Int
    let onSelect: (Int) -> Void
    let onAdd: () -> Void
    let onEdit: (Int) -> Void
    let onDuplicate: (Int) -> Void
    let onDelete: (Int) -> Void
    let onClose: () -> Void

    @State private var pendingDelete: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("I miei timer", "My timers"))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(profiles.count == 1 ? "1 routine" : L("\(profiles.count) routine", "\(profiles.count) routines"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                GlassIconButton(systemName: "plus", label: L("Nuovo timer", "New timer"), size: 48, tint: Theme.mint, action: onAdd)
                GlassIconButton(systemName: "xmark", label: L("Chiudi l'elenco", "Close list"), size: 48, action: onClose)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(spacing: 14) {
                    if profiles.isEmpty {
                        Text(L("Non hai ancora nessun timer. Tocca + per crearne uno.", "You don't have any timers yet. Tap + to create one."))
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, 40)
                    }
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                        ProfileCardView(
                            profile: profile,
                            isSelected: index == selectedProfileIndex,
                            onSelect: { onSelect(index) },
                            onEdit: { onEdit(index) },
                            onDuplicate: { onDuplicate(index) },
                            onDelete: { pendingDelete = index }
                        )
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .fadeAboveTabBar()
        }
        .foregroundStyle(.white)
        .confirmationDialog(
            L("Eliminare questo timer?", "Delete this timer?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { index in
            Button(L("Elimina", "Delete"), role: .destructive) { onDelete(index) }
            Button(L("Annulla", "Cancel"), role: .cancel) {}
        } message: { index in
            if profiles.indices.contains(index) {
                Text(L("«\(profiles[index].name)» verrà rimosso e l'azione non si può annullare.", "“\(profiles[index].name)” will be removed. This can't be undone."))
            }
        }
    }
}

struct ProfileCardView: View {
    let profile: BreathingProfile
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @ViewBuilder
    private var actions: some View {
        Button(action: onSelect) { Label(L("Usa questo timer", "Use this timer"), systemImage: "play.fill") }
        Button(action: onEdit) { Label(L("Modifica", "Edit"), systemImage: "slider.horizontal.3") }
        Button(action: onDuplicate) { Label(L("Duplica", "Duplicate"), systemImage: "plus.square.on.square") }
        Divider()
        Button(role: .destructive, action: onDelete) { Label(L("Elimina", "Delete"), systemImage: "trash") }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(String(profile.name.prefix(1)).uppercased())
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 48)
                .background(Theme.accentGradient, in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(.headline)
                        .lineLimit(1)
                    if isSelected {
                        Text(L("In uso", "In use"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.mint, in: Capsule())
                    }
                }
                Text(L("\(profile.cycles) cicli, \(profile.totalSeconds.clockString) in totale", "\(profile.cycles) cycles, \(profile.totalSeconds.clockString) total"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                PatternChips(profile: profile)
            }

            Spacer(minLength: 0)

            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? Theme.mint.opacity(0.10) : Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? Theme.mint.opacity(0.7) : Theme.stroke, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: onSelect)
        .contextMenu { actions }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(profile.name), \(profile.cycles) cicli, \(profile.spokenPattern)", "\(profile.name), \(profile.cycles) cycles, \(profile.spokenPattern)"))
        .accessibilityValue(isSelected ? L("In uso", "In use") : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityAction(named: L("Modifica", "Edit"), onEdit)
        .accessibilityAction(named: L("Duplica", "Duplicate"), onDuplicate)
        .accessibilityAction(named: L("Elimina", "Delete"), onDelete)
    }
}

// MARK: - Editor (nuovo timer e modifica)

struct ProfileEditorView: View {
    @Binding var profile: BreathingProfile
    let isNew: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var showAdvanced = false

    private var isValid: Bool {
        !profile.name.trimmed.isEmpty && profile.cycleSeconds > 0
    }

    private func binding(for action: BreathingAction) -> Binding<Int> {
        switch action {
        case .inhale: return $profile.inhale
        case .hold1: return $profile.hold1
        case .exhale: return $profile.exhale
        case .hold2: return $profile.hold2
        }
    }

    private func apply(_ preset: BreathingPreset) {
        profile.inhale = preset.inhale
        profile.hold1 = preset.hold1
        profile.exhale = preset.exhale
        profile.hold2 = preset.hold2
        let current = profile.name.trimmed
        if current.isEmpty || ["Personalizzato", "Custom"].contains(current) { profile.name = preset.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Nome", "Name")) {
                    TextField(L("Es. Respiro del mattino", "E.g. Morning breath"), text: $profile.name)
                        .wordsAutocapitalization()
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .accessibilityLabel(L("Nome del timer", "Timer name"))
                }
                .listRowBackground(Theme.card)

                Section(L("Modelli rapidi", "Quick presets")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(BreathingPreset.all) { preset in
                                Button { apply(preset) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.name).font(.subheadline.weight(.semibold))
                                        Text(preset.pattern)
                                            .font(.caption)
                                            .monospacedDigit()
                                            .foregroundStyle(Theme.mint)
                                        Text(preset.note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.08),
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    ForEach(Array(BreathingAction.allCases.enumerated()), id: \.offset) { _, action in
                        PhaseStepperRow(action: action, seconds: binding(for: action))
                    }
                    Stepper(value: $profile.cycles, in: 1...30) {
                        HStack {
                            Label(L("Cicli", "Cycles"), systemImage: "repeat")
                            Spacer()
                            Text("\(profile.cycles)")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text(L("Fasi del ciclo", "Cycle phases"))
                } footer: {
                    Text(L("Imposta 0 secondi per saltare una fase.", "Set 0 seconds to skip a phase."))
                }
                .listRowBackground(Theme.card)

                Section(L("Anteprima", "Preview")) {
                    cyclePreview
                    HStack {
                        Text(L("Un ciclo", "One cycle"))
                        Spacer()
                        Text(profile.cycleSeconds.clockString).monospacedDigit()
                    }
                    HStack {
                        Text(L("Sessione completa", "Full session"))
                        Spacer()
                        Text(profile.totalSeconds.clockString)
                            .monospacedDigit()
                            .foregroundStyle(Theme.mint)
                    }
                }
                .listRowBackground(Theme.card)

                Section(L("Suono e vibrazione", "Sound and vibration")) {
                    Toggle(L("Suono", "Sound"), isOn: $profile.soundEnabled)
                    Toggle(L("Beep a ogni secondo", "Beep every second"), isOn: $profile.tickEnabled)
                        .disabled(!profile.soundEnabled)
                    Toggle(L("Vibrazione al cambio fase", "Vibrate on phase change"), isOn: $profile.hapticsEnabled)
                    DisclosureGroup(L("Toni avanzati", "Advanced tones"), isExpanded: $showAdvanced) {
                        toneRow(title: "Beep", value: $profile.beepSound, bell: false)
                        toneRow(title: L("Cambio fase", "Phase change"), value: $profile.tinSound, bell: true)
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground(accent: Theme.mint))
            .navigationTitle(isNew ? L("Nuovo timer", "New timer") : L("Modifica timer", "Edit timer"))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annulla", "Cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Salva", "Save"), action: onSave)
                        .disabled(!isValid)
                }
            }
        }
        .tint(Theme.mint)
        .preferredColorScheme(.dark)
    }

    /// Barra proporzionale: si vede subito com'è fatto il ciclo.
    private var cyclePreview: some View {
        GeometryReader { geo in
            let total = CGFloat(max(profile.cycleSeconds, 1))
            let available = geo.size.width - 6
            HStack(spacing: 2) {
                ForEach(Array(BreathingAction.allCases.enumerated()), id: \.offset) { index, action in
                    let seconds = profile.durations[index]
                    if seconds > 0 {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(action.color)
                            .frame(width: max(0, available * CGFloat(seconds) / total))
                    }
                }
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    private func toneRow(title: String, value: Binding<Int>, bell: Bool) -> some View {
        Stepper(value: value, in: 200...2000, step: 10) {
            HStack {
                Text("\(title): \(value.wrappedValue) Hz")
                Spacer()
                Button(L("Prova", "Test")) {
                    ToneGenerator.shared.play(frequency: value.wrappedValue,
                                              duration: bell ? 0.6 : 0.15,
                                              bell: bell)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct PhaseStepperRow: View {
    let action: BreathingAction
    @Binding var seconds: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.icon)
                .foregroundStyle(action.color)
                .frame(width: 34, height: 34)
                .background(action.color.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                Text(action.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(seconds == 0 ? L("Salta", "Skip") : "\(seconds)s")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 48, alignment: .trailing)
            Stepper("", value: $seconds, in: 0...60)
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    BreathingScreen()
}

// MARK: - Compatibilità multipiattaforma (API solo iOS)

extension View {
    @ViewBuilder
    func wordsAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.words)
        #else
        self
        #endif
    }

    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
