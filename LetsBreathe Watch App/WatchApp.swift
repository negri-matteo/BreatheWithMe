import SwiftUI
import Combine
import WatchKit
import HealthKit
import WatchConnectivity

// App per Apple Watch: va aggiunta SOLO al target watchOS (non a quello iPhone).
//
// L'iPhone la apre quando parte una sessione di apnea. L'orologio avvia una sessione
// di allenamento, che tiene acceso il sensore del battito, e invia ogni lettura al telefono.
// A fine sessione l'allenamento viene scartato: non compare in Fitness né in Salute.

/// Chiavi dei messaggi scambiati con l'iPhone: devono coincidere con quelle in VitalsMonitor.swift.
// `nonisolated`: i messaggi dall'iPhone arrivano su un thread di sistema, non sul main actor.
private enum WatchLink {
    nonisolated static let command = "cmd"
    nonisolated static let stop = "stop"
    nonisolated static let heartRate = "hr"
    nonisolated static let timestamp = "t"
    nonisolated static let language = "lang"
}

/// Lingua dei testi sull'orologio: quella scelta nell'app iPhone, oppure quella dell'orologio.
private enum WatchLanguage {
    nonisolated static let key = "appLanguage"

    nonisolated static func store(_ value: Any?) {
        guard let code = value as? String, code == "it" || code == "en" else { return }
        UserDefaults.standard.set(code, forKey: key)
    }

    nonisolated static func isItalian(_ stored: String) -> Bool {
        if stored == "it" { return true }
        if stored == "en" { return false }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("it")
    }
}

@main
struct BreathWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var workout = WatchWorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(workout)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in WatchWorkoutManager.shared.activateConnectivity() }
    }

    /// Chiamata quando l'iPhone avvia una sessione di apnea.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in WatchWorkoutManager.shared.start() }
    }
}

// MARK: - Rilevazione del battito

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()

    override init() {
        super.init()
        #if DEBUG
        // Solo per gli screenshot: con l'argomento -demoVitals mostra una rilevazione in corso.
        if ProcessInfo.processInfo.arguments.contains("-demoVitals") {
            isRunning = true
            heartRate = 74
        }
        #endif
    }

    @Published private(set) var isRunning = false
    @Published private(set) var heartRate = 0.0
    enum Problem { case healthUnavailable, cannotStart, interrupted }

    @Published private(set) var problem: Problem?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var isStarting = false
    private var stopRequested = false
    private var startedAt = Date.distantPast

    func activateConnectivity() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func start() {
        guard session == nil, !isStarting else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            problem = .healthUnavailable
            return
        }
        isStarting = true
        stopRequested = false
        // Da qui in poi conta come sessione nuova: uno "stop" più vecchio viene ignorato.
        startedAt = Date()
        problem = nil
        Task {
            do {
                let share: Set<HKSampleType> = [HKObjectType.workoutType()]
                let read: Set<HKObjectType> = [HKQuantityType(.heartRate)]
                try await healthStore.requestAuthorization(toShare: share, read: read)
                // L'iPhone ha chiuso la sessione mentre si attendeva il permesso: non si avvia nulla.
                if !stopRequested { try begin() }
            } catch {
                problem = .cannotStart
            }
            isStarting = false
            stopRequested = false
        }
    }

    private func begin() throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder

        let now = Date()
        session.startActivity(with: now)
        builder.beginCollection(withStart: now) { _, _ in }
        isRunning = true
    }

    func stop() {
        if isStarting { stopRequested = true }
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        isRunning = false
        heartRate = 0

        session.end()
        builder.endCollection(withEnd: Date()) { _, _ in
            builder.discardWorkout()
        }
    }

    private func publish(bpm: Double) {
        guard isRunning else { return }
        heartRate = bpm
        let link = WCSession.default
        guard link.activationState == .activated, link.isReachable else { return }
        link.sendMessage([WatchLink.heartRate: bpm, WatchLink.timestamp: Date().timeIntervalSince1970],
                         replyHandler: nil, errorHandler: nil)
    }

    private func handle(command: String?, time: Double?) {
        guard command == WatchLink.stop else { return }
        // Ignora un eventuale "stop" rimasto in coda da una sessione precedente.
        if let time, time < startedAt.timeIntervalSince1970 - 1 { return }
        stop()
    }

    private func sessionEnded() {
        guard session != nil else { return }
        session = nil
        builder = nil
        isRunning = false
        heartRate = 0
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type),
              let quantity = workoutBuilder.statistics(for: type)?.mostRecentQuantity() else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in self.publish(bpm: bpm) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in self.sessionEnded() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.sessionEnded()
            self.problem = .interrupted
        }
    }
}

extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        WatchLanguage.store(session.receivedApplicationContext[WatchLink.language])
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        WatchLanguage.store(message[WatchLink.language])
        let command = message[WatchLink.command] as? String
        let time = message[WatchLink.timestamp] as? Double
        Task { @MainActor in self.handle(command: command, time: time) }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        WatchLanguage.store(applicationContext[WatchLink.language])
        let command = applicationContext[WatchLink.command] as? String
        let time = applicationContext[WatchLink.timestamp] as? Double
        Task { @MainActor in self.handle(command: command, time: time) }
    }
}

// MARK: - Interfaccia

struct WatchRootView: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    @AppStorage(WatchLanguage.key) private var language = ""

    private let mint = Color(red: 0.204, green: 0.941, blue: 0.631)

    private func t(_ italian: String, _ english: String) -> String {
        WatchLanguage.isItalian(language) ? italian : english
    }

    private var statusText: String {
        switch workout.problem {
        case .healthUnavailable:
            return t("Dati di Salute non disponibili", "Health data unavailable")
        case .cannotStart:
            return t("Non riesco ad avviare la rilevazione", "Couldn't start tracking")
        case .interrupted:
            return t("Rilevazione interrotta", "Tracking stopped")
        case nil:
            return workout.isRunning ? t("Battito inviato all'iPhone", "Heart rate sent to iPhone")
                                     : t("Avvia l'apnea dall'iPhone", "Start a breath-hold on iPhone")
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(mint)
                Text(workout.heartRate > 0 ? "\(Int(workout.heartRate.rounded()))" : "--")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("bpm")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(workout.isRunning ? t("Ferma", "Stop") : t("Avvia", "Start")) {
                if workout.isRunning {
                    workout.stop()
                } else {
                    workout.start()
                }
            }
            .tint(mint)
        }
        .padding(.horizontal, 4)
    }
}
