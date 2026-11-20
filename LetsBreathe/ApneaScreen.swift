import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Motore del cronometro
//
// Un tap avvia, un tap ferma, il tap successivo riparte da zero nella stessa sessione.
// Quando il tempo supera quello del tentativo precedente parte il segnale (suono e/o vibrazione).
// Il tempo è calcolato dall'orologio di sistema, quindi resta esatto anche se l'app va in secondo piano.

enum ApneaSettings {
    static let soundKey = "apneaSound"
    static let hapticsKey = "apneaHaptics"
}

@MainActor
final class ApneaEngine: ObservableObject {
    enum State { case idle, holding, resting }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed = 0.0           // tentativo in corso, oppure l'ultimo fermato
    @Published private(set) var restSeconds = 0         // recupero dopo l'ultimo tentativo
    @Published private(set) var attempts: [ApneaAttempt] = []
    @Published private(set) var beatTarget = false

    private var sessionStart = Date()
    private var phaseStart = Date()
    private var lastTap = Date.distantPast
    /// Recupero appena concluso: finisce nel tentativo che parte ora.
    private var pendingRest: Double?
    private var ticker: Task<Void, Never>?

    /// Il tempo da superare: quello del tentativo precedente.
    var target: Double? { attempts.last?.duration }
    var best: Double? { attempts.map(\.duration).max() }

    func tap() {
        let now = Date()
        // Evita che un doppio tocco involontario fermi subito il cronometro.
        guard now.timeIntervalSince(lastTap) > 0.35 else { return }
        lastTap = now

        switch state {
        case .idle:
            attempts = []
            pendingRest = nil
            sessionStart = now
            beginHold(at: now)
            startTicker()
        case .holding:
            finishHold(at: now)
        case .resting:
            // Il recupero tra due tentativi si registra solo quando ne parte uno nuovo:
            // quello dopo l'ultimo tentativo, fino alla chiusura, resta fuori.
            pendingRest = now.timeIntervalSince(phaseStart)
            beginHold(at: now)
        }
    }

    /// Chiude la sessione. Restituisce nil se non c'è nessun tentativo da salvare.
    func endSession() -> ApneaSession? {
        let now = Date()
        if state == .holding { finishHold(at: now) }
        ticker?.cancel()
        ticker = nil

        let result = attempts.isEmpty ? nil : ApneaSession(start: sessionStart, end: now, attempts: attempts)
        state = .idle
        attempts = []
        elapsed = 0
        restSeconds = 0
        beatTarget = false
        pendingRest = nil
        return result
    }

    private func beginHold(at date: Date) {
        phaseStart = date
        elapsed = 0
        beatTarget = false
        state = .holding
        if hapticsEnabled { Haptics.phaseChange() }
    }

    private func finishHold(at date: Date) {
        let duration = date.timeIntervalSince(phaseStart)
        let beat = target.map { duration > $0 } ?? false
        attempts.append(ApneaAttempt(start: phaseStart, duration: duration, beatPrevious: beat,
                                     restBefore: pendingRest))
        pendingRest = nil
        elapsed = duration
        phaseStart = date
        restSeconds = 0
        state = .resting
        if hapticsEnabled { Haptics.phaseChange() }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        let now = Date()
        switch state {
        case .holding:
            elapsed = now.timeIntervalSince(phaseStart)
            if let target, !beatTarget, elapsed > target {
                beatTarget = true
                signalBeat()
            }
        case .resting:
            let seconds = Int(now.timeIntervalSince(phaseStart))
            if seconds != restSeconds { restSeconds = seconds }
        case .idle:
            break
        }
    }

    private var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: ApneaSettings.soundKey) as? Bool ?? true
    }

    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: ApneaSettings.hapticsKey) as? Bool ?? true
    }

    private func signalBeat() {
        if soundEnabled {
            // Due note ascendenti: si riconoscono anche a occhi chiusi.
            ToneGenerator.shared.play(frequency: 880, duration: 0.3, bell: true)
            ToneGenerator.shared.play(frequency: 1320, duration: 0.6, bell: true)
        }
        if hapticsEnabled { Haptics.success() }
    }
}

// MARK: - Componenti

struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = .white

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Schermata Apnea

struct ApneaScreen: View {
    @EnvironmentObject private var engine: ApneaEngine
    @EnvironmentObject private var vitals: VitalsMonitor
    @EnvironmentObject private var store: ApneaStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(ApneaSettings.soundKey) private var soundEnabled = true
    @AppStorage(ApneaSettings.hapticsKey) private var hapticsEnabled = true
    @State private var toast: Toast?

    // MARK: Stato derivato

    private var accent: Color {
        switch engine.state {
        case .idle: return Theme.mint
        case .holding: return engine.beatTarget ? Theme.mint : Theme.cyan
        case .resting: return Theme.cobalt
        }
    }

    private var orbScale: CGFloat {
        let small: CGFloat = reduceMotion ? 0.94 : 0.8
        switch engine.state {
        case .idle: return small + 0.04
        case .holding: return 1.0        // polmoni pieni
        case .resting: return small
        }
    }

    private var ringProgress: Double {
        guard engine.state == .holding, let target = engine.target, target > 0 else { return 0 }
        return min(engine.elapsed / target, 1)
    }

    private var orbCaption: String {
        switch engine.state {
        case .idle: return L("tocca per partire", "tap to start")
        case .holding: return L("tocca per fermare", "tap to stop")
        case .resting: return L("recupero \(engine.restSeconds.clockString)", "recovery \(engine.restSeconds.clockString)")
        }
    }

    private var status: (title: String, hint: String, next: String) {
        switch engine.state {
        case .idle:
            return (L("Pronto?", "Ready?"),
                    L("Tocca il cerchio per far partire il cronometro", "Tap the circle to start the stopwatch"),
                    L("Allenati seduto o sdraiato, mai in acqua e mai da solo", "Train seated or lying down, never in water and never alone"))
        case .holding:
            let hint: String
            if let target = engine.target {
                hint = engine.beatTarget ? L("Hai superato il tentativo precedente", "You beat your previous attempt")
                                         : L("Da superare: \(target.stopwatchString)", "To beat: \(target.stopwatchString)")
            } else {
                hint = L("Primo tentativo della sessione", "First attempt of the session")
            }
            return (L("Trattieni", "Hold"), hint, L("Tocca il cerchio per fermare", "Tap the circle to stop"))
        case .resting:
            let last = engine.attempts.last
            let hint = last?.beatPrevious == true ? L("Tentativo migliore del precedente", "Better than your previous attempt")
                                                  : L("Respira con calma prima di ripartire", "Breathe calmly before going again")
            return (L("Recupera", "Recover"), hint, L("Tocca il cerchio per ripartire da zero", "Tap the circle to start again from zero"))
        }
    }

    private var watchText: String {
        switch vitals.status {
        case .idle: return L("Il battito arriva dall'Apple Watch all'avvio", "Heart rate comes from Apple Watch once you start")
        case .connecting: return L("Collegamento all'Apple Watch", "Connecting to Apple Watch")
        case .unavailable: return L("Apple Watch non disponibile: registro solo i tempi", "Apple Watch unavailable: recording times only")
        case .live:
            if let bpm = vitals.heartRate { return "\(Int(bpm.rounded())) bpm" }
            return L("Apple Watch collegato", "Apple Watch connected")
        }
    }

    // MARK: Sottoviste

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apnea")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(L("Cronometro del respiro trattenuto", "Breath-hold stopwatch"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
            GlassIconButton(
                systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                label: soundEnabled ? L("Disattiva il segnale acustico", "Turn the beep off") : L("Attiva il segnale acustico", "Turn the beep on"),
                tint: soundEnabled ? Theme.mint : Color.white.opacity(0.6)
            ) {
                soundEnabled.toggle()
                show(soundEnabled ? L("Segnale acustico attivato", "Beep on") : L("Segnale acustico disattivato", "Beep off"),
                     icon: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            GlassIconButton(
                systemName: hapticsEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash",
                label: hapticsEnabled ? L("Disattiva la vibrazione", "Turn vibration off") : L("Attiva la vibrazione", "Turn vibration on"),
                tint: hapticsEnabled ? Theme.mint : Color.white.opacity(0.6)
            ) {
                hapticsEnabled.toggle()
                show(hapticsEnabled ? L("Vibrazione attivata", "Vibration on") : L("Vibrazione disattivata", "Vibration off"),
                     icon: hapticsEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash")
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatTile(title: L("Precedente", "Previous"), value: engine.target?.stopwatchString ?? "-")
            StatTile(title: L("Migliore oggi", "Best today"), value: engine.best?.stopwatchString ?? "-", tint: Theme.cyan)
            StatTile(title: "Record", value: store.record?.stopwatchString ?? "-", tint: Theme.mint)
        }
    }

    /// I tentativi della sessione in corso, dal più recente.
    private var attemptsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if engine.attempts.isEmpty {
                    Text(L("I tentativi della sessione compaiono qui", "This session's attempts appear here"))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                }
                ForEach(Array(engine.attempts.enumerated().reversed()), id: \.element.id) { index, attempt in
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .foregroundStyle(.white.opacity(0.6))
                        Text(attempt.duration.stopwatchString)
                            .monospacedDigit()
                        if attempt.beatPrevious {
                            Image(systemName: "arrow.up")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.mint)
                        }
                    }
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("Tentativo \(index + 1): \(attempt.duration.stopwatchString)", "Attempt \(index + 1): \(attempt.duration.stopwatchString)")
                                        + (attempt.beatPrevious ? L(", superato il precedente", ", beat the previous one") : ""))

                    // Recupero che ha preceduto il tentativo (l'elenco va dal più recente).
                    if let rest = attempt.restBefore {
                        Label(Int(rest).clockString, systemImage: "pause.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.cobalt)
                            .accessibilityLabel(L("Recupero \(Int(rest).clockString)", "Recovery \(Int(rest).clockString)"))
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 32)
    }

    private var orb: some View {
        Button(action: handleTap) {
            BreathingOrb(
                color: accent,
                scale: orbScale,
                ringProgress: ringProgress,
                value: engine.elapsed.stopwatchString,
                caption: orbCaption,
                dimmed: false,
                scaleAnimation: .easeInOut(duration: 0.6),
                valueFontScale: 0.15,
                animatesValue: false
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("\(status.title). \(engine.elapsed.stopwatchString). \(status.next)")
    }

    private var vitalsStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: vitals.status == .live ? "heart.fill" : "applewatch")
                .foregroundStyle(vitals.status == .live ? Theme.mint : Color.white.opacity(0.6))
            Text(watchText)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var statusView: some View {
        VStack(spacing: 6) {
            Text(status.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
            Text(status.hint)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
            Text(status.next)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 88)
        .animation(.easeInOut(duration: 0.3), value: status.title)
        .accessibilityElement(children: .combine)
    }

    private var endButton: some View {
        Button(action: endSession) {
            Label(L("Termina e salva la sessione", "End and save the session"), systemImage: "stop.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .opacity(engine.state == .idle ? 0 : 1)
        .disabled(engine.state == .idle)
        .animation(.easeInOut(duration: 0.25), value: engine.state == .idle)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            AppBackground(accent: accent)

            VStack(spacing: 14) {
                header
                statsRow
                attemptsStrip
                orb
                vitalsStrip
                statusView
                endButton
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if let toast = toast {
                VStack {
                    Spacer()
                    ToastView(icon: toast.icon, text: toast.text).padding(.bottom, 90)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task { await vitals.prepare() }
        .onChange(of: engine.state != .idle) { _, active in setScreenAwake(active) }
        .task(id: toast?.id) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { toast = nil }
        }
    }

    // MARK: Azioni

    private func handleTap() {
        let wasIdle = engine.state == .idle
        engine.tap()
        if wasIdle, engine.state != .idle { vitals.startSession() }
    }

    private func endSession() {
        let heartRate = vitals.stopSession()
        guard var session = engine.endSession() else { return }
        session.heartRate = heartRate
        store.add(session)
        show(L("Sessione salvata nello storico", "Session saved to history"), icon: "checkmark.seal.fill")

        // Le letture di ossigeno si recuperano da Salute: possono arrivare con qualche minuto di ritardo,
        // per questo nello storico c'è anche il pulsante per aggiornarle.
        let id = session.id
        let from = session.start.addingTimeInterval(-300)
        let to = session.end.addingTimeInterval(300)
        Task {
            let oxygen = await vitals.oxygenSamples(from: from, to: to)
            if !oxygen.isEmpty { store.setOxygen(oxygen, for: id) }
        }
    }

    private func show(_ text: String, icon: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            toast = Toast(icon: icon, text: text)
        }
    }

    private func setScreenAwake(_ awake: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = awake
        #endif
    }
}

#Preview {
    ApneaScreen()
        .environmentObject(ApneaEngine())
        .environmentObject(VitalsMonitor())
        .environmentObject(ApneaStore())
}
