import Foundation
import Combine
#if os(iOS)
import HealthKit
import WatchConnectivity
#endif

// Lato iPhone del collegamento con l'Apple Watch.
//
// Battito: l'iPhone apre l'app sull'orologio, che avvia una sessione di allenamento
// e invia il battito in tempo reale (vedi WatchApp.swift).
// Ossigenazione: watchOS non permette alle app di avviare una misurazione. Le letture
// fatte dall'orologio (in automatico o dall'app Livelli O₂) finiscono in Salute e
// vengono lette da lì a fine sessione.

enum WatchStatus {
    case idle, connecting, live, unavailable
}

/// Chiavi dei messaggi scambiati con l'orologio: devono coincidere con quelle in WatchApp.swift.
enum WatchLink {
    nonisolated static let command = "cmd"
    nonisolated static let stop = "stop"
    nonisolated static let heartRate = "hr"
    nonisolated static let timestamp = "t"
    nonisolated static let language = "lang"
}

#if os(iOS)

@MainActor
final class VitalsMonitor: NSObject, ObservableObject {
    @Published private(set) var heartRate: Double?
    @Published private(set) var status: WatchStatus = .idle

    private let healthStore = HKHealthStore()
    private var samples: [VitalSample] = []
    private var isRecording = false

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Chiede i permessi di Salute. Va chiamata prima della sessione,
    /// così la richiesta non compare mentre si trattiene il fiato.
    func prepare() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.oxygenSaturation)]
        try? await healthStore.requestAuthorization(toShare: share, read: read)
    }

    func startSession() {
        samples = []
        heartRate = nil
        isRecording = true
        #if DEBUG
        // Solo per gli screenshot: con l'argomento -demoVitals il battito è simulato.
        if ProcessInfo.processInfo.arguments.contains("-demoVitals") {
            startDemoVitals()
            return
        }
        #endif
        guard HKHealthStore.isHealthDataAvailable(), WCSession.isSupported() else {
            status = .unavailable
            return
        }
        status = .connecting
        Task { await launchWatchApp() }
    }

    private func launchWatchApp() async {
        await prepare()
        let session = WCSession.default
        guard isRecording else { return }
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
            status = .unavailable
            return
        }
        // L'orologio mostra i testi nella stessa lingua scelta nell'app.
        try? session.updateApplicationContext([WatchLink.language: AppLanguage.current.rawValue])

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .indoor
        do {
            // Apre (o risveglia) l'app sull'orologio e le consegna la configurazione.
            try await healthStore.startWatchApp(toHandle: configuration)
            // La sessione è finita mentre l'orologio si avviava: lo "stop" mandato prima
            // risulterebbe più vecchio dell'avvio e verrebbe ignorato, quindi si ripete.
            if !isRecording { sendStopToWatch() }
        } catch {
            if isRecording, status != .live { status = .unavailable }
        }
    }

    /// Ferma la rilevazione sull'orologio e restituisce il battito registrato.
    @discardableResult
    func stopSession() -> [VitalSample] {
        isRecording = false
        status = .idle
        heartRate = nil

        sendStopToWatch()

        let result = samples
        samples = []
        return result
    }

    private func sendStopToWatch() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let message: [String: Any] = [
            WatchLink.command: WatchLink.stop,
            WatchLink.timestamp: Date().timeIntervalSince1970,
            WatchLink.language: AppLanguage.current.rawValue
        ]
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
        // Copia di sicurezza: arriva anche se in questo istante l'orologio non è raggiungibile.
        try? session.updateApplicationContext(message)
    }

    /// Letture di ossigenazione presenti in Salute nell'intervallo indicato (valori in %).
    func oxygenSamples(from start: Date, to end: Date) async -> [VitalSample] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let store = healthStore
        let type = HKQuantityType(.oxygenSaturation)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, _ in
                let quantities = (results as? [HKQuantitySample]) ?? []
                let samples = quantities.map {
                    VitalSample(date: $0.startDate, value: $0.quantity.doubleValue(for: .percent()) * 100)
                }
                continuation.resume(returning: samples)
            }
            store.execute(query)
        }
    }

    #if DEBUG
    private func startDemoVitals() {
        status = .connecting
        Task {
            var bpm = 72.0
            try? await Task.sleep(for: .seconds(1))
            while isRecording {
                bpm = min(84, max(62, bpm + Double.random(in: -2.5...2.0)))
                record(bpm: bpm.rounded())
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    #endif

    private func record(bpm: Double) {
        guard isRecording else { return }
        heartRate = bpm
        status = .live
        // Si usa l'orologio dell'iPhone, lo stesso che misura i tentativi.
        samples.append(VitalSample(date: Date(), value: bpm))
    }
}

extension VitalsMonitor: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Cambio di orologio: si riattiva la sessione per quello nuovo.
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let bpm = message[WatchLink.heartRate] as? Double else { return }
        Task { @MainActor in self.record(bpm: bpm) }
    }
}

#else

/// Su piattaforme senza Apple Watch si registrano solo i tempi.
@MainActor
final class VitalsMonitor: ObservableObject {
    @Published private(set) var heartRate: Double?
    @Published private(set) var status: WatchStatus = .idle

    func prepare() async {}

    func startSession() {
        status = .unavailable
    }

    @discardableResult
    func stopSession() -> [VitalSample] {
        status = .idle
        return []
    }

    func oxygenSamples(from start: Date, to end: Date) async -> [VitalSample] { [] }
}

#endif
