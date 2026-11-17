import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Modello dello storico apnee

/// Una singola rilevazione (battito in bpm oppure ossigenazione in %).
struct VitalSample: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var value: Double
}

/// Un tentativo di apnea all'interno di una sessione.
struct ApneaAttempt: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var duration: Double          // secondi
    var beatPrevious: Bool        // ha superato il tentativo precedente della stessa sessione
}

struct ApneaSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var end: Date
    var attempts: [ApneaAttempt]
    var heartRate: [VitalSample] = []
    var oxygen: [VitalSample] = []
}

extension ApneaSession {
    var bestHold: Double { attempts.map(\.duration).max() ?? 0 }
    var totalHold: Double { attempts.reduce(0) { $0 + $1.duration } }

    var averageHeartRate: Double? {
        guard !heartRate.isEmpty else { return nil }
        return heartRate.reduce(0) { $0 + $1.value } / Double(heartRate.count)
    }

    /// Battito minimo, medio e massimo durante un tentativo.
    func heartStats(for attempt: ApneaAttempt) -> (min: Double, avg: Double, max: Double)? {
        let end = attempt.start.addingTimeInterval(attempt.duration)
        let values = heartRate.filter { $0.date >= attempt.start && $0.date <= end }.map(\.value)
        guard let low = values.min(), let high = values.max() else { return nil }
        return (low, values.reduce(0, +) / Double(values.count), high)
    }

    /// Ossigenazione minima durante il tentativo e nei due minuti successivi
    /// (la desaturazione si legge al polso con un po' di ritardo).
    func oxygenMin(for attempt: ApneaAttempt) -> Double? {
        let end = attempt.start.addingTimeInterval(attempt.duration + 120)
        return oxygen.filter { $0.date >= attempt.start && $0.date <= end }.map(\.value).min()
    }
}

extension Double {
    /// 83.47 -> "1:23.4"
    var stopwatchString: String {
        let tenths = Int((Swift.max(self, 0) * 10).rounded(.down))
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
}

// MARK: - Archivio sul dispositivo

/// Lo storico vive in un file JSON nella cartella Application Support dell'app: resta solo sul telefono.
@MainActor
final class ApneaStore: ObservableObject {
    @Published private(set) var sessions: [ApneaSession] = []     // dalla più recente

    private let fileURL: URL

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("apnea-sessions.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ApneaSession].self, from: data) {
            sessions = decoded.sorted { $0.start > $1.start }
        }
    }

    var record: Double? { sessions.map(\.bestHold).max() }

    func session(id: UUID) -> ApneaSession? {
        sessions.first { $0.id == id }
    }

    func add(_ session: ApneaSession) {
        sessions.insert(session, at: 0)
        save()
    }

    func setOxygen(_ samples: [VitalSample], for id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].oxygen = samples
        save()
    }

    func delete(id: UUID) {
        delete(ids: [id])
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        sessions.removeAll { ids.contains($0.id) }
        save()
    }

    func deleteAll() {
        guard !sessions.isEmpty else { return }
        sessions.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Esportazione CSV

enum CSVExporter {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    static func fileName(for sessions: [ApneaSession]) -> String {
        let stamp = formatter("yyyy-MM-dd_HHmm")
        if sessions.count == 1, let session = sessions.first {
            return "apnea_" + stamp.string(from: session.start)
        }
        return L("apnea_storico_", "apnea_history_") + stamp.string(from: Date())
    }

    /// Una riga per ogni tentativo e per ogni rilevazione di battito e ossigeno.
    /// Il separatore segue le impostazioni del telefono: con la virgola decimale (Italia)
    /// i campi sono separati da punto e virgola, così Excel e Numbers aprono il file correttamente.
    static func csv(for sessions: [ApneaSession]) -> String {
        let decimal = Locale.current.decimalSeparator ?? "."
        let separator = decimal == "," ? ";" : ","
        let stamp = formatter("yyyy-MM-dd HH:mm:ss")

        func number(_ value: Double?, _ digits: Int) -> String {
            guard let value else { return "" }
            return String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: decimal)
        }

        var lines = [
            [L("sessione", "session"), L("tipo", "type"), L("numero", "number"), L("data_ora", "date_time"), L("valore", "value"), L("unita", "unit"),
             L("superato_precedente", "beat_previous"), L("fc_min", "hr_min"), L("fc_media", "hr_avg"), L("fc_max", "hr_max"), "spo2_min"].joined(separator: separator)
        ]

        for session in sessions.sorted(by: { $0.start < $1.start }) {
            let label = stamp.string(from: session.start)

            for (index, attempt) in session.attempts.enumerated() {
                let heart = session.heartStats(for: attempt)
                lines.append([
                    label, L("apnea", "breath_hold"), "\(index + 1)", stamp.string(from: attempt.start),
                    number(attempt.duration, 1), "s", attempt.beatPrevious ? L("si", "yes") : "no",
                    number(heart?.min, 0), number(heart?.avg, 0), number(heart?.max, 0),
                    number(session.oxygenMin(for: attempt), 0)
                ].joined(separator: separator))
            }
            for (index, sample) in session.heartRate.enumerated() {
                lines.append([
                    label, L("battito", "heart_rate"), "\(index + 1)", stamp.string(from: sample.date),
                    number(sample.value, 0), "bpm", "", "", "", "", ""
                ].joined(separator: separator))
            }
            for (index, sample) in session.oxygen.enumerated() {
                lines.append([
                    label, L("ossigeno", "oxygen"), "\(index + 1)", stamp.string(from: sample.date),
                    number(sample.value, 0), "%", "", "", "", "", ""
                ].joined(separator: separator))
            }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}

/// Documento usato da "Salva in File".
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
