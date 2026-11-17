import SwiftUI
import Charts
import UniformTypeIdentifiers
#if canImport(MessageUI)
import MessageUI
#endif

// MARK: - Esportazione (Salva in File, email)

struct ExportState {
    var document: CSVDocument?
    var fileName = "apnea"
    var sessionCount = 0
    var showExporter = false
    var showMail = false
    var mailUnavailable = false
}

struct ExportMenu: View {
    let sessions: [ApneaSession]
    @Binding var state: ExportState

    var body: some View {
        Menu {
            Button {
                prepare()
                state.showExporter = true
            } label: {
                Label(L("Salva il CSV in File", "Save CSV to Files"), systemImage: "folder")
            }
            Button {
                prepare()
                if MailComposer.canSend {
                    state.showMail = true
                } else {
                    state.mailUnavailable = true
                }
            } label: {
                Label(L("Invia il CSV per email", "Email the CSV"), systemImage: "envelope")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel(L("Esporta in CSV", "Export as CSV"))
    }

    private func prepare() {
        state.document = CSVDocument(text: CSVExporter.csv(for: sessions))
        state.fileName = CSVExporter.fileName(for: sessions)
        state.sessionCount = sessions.count
    }
}

private struct CSVExportModifier: ViewModifier {
    @Binding var state: ExportState

    private var mailBody: String {
        state.sessionCount == 1
            ? L("In allegato i dati di una sessione di apnea in formato CSV.", "Attached is the data from one breath-hold session in CSV format.")
            : L("In allegato i dati di \(state.sessionCount) sessioni di apnea in formato CSV.", "Attached is the data from \(state.sessionCount) breath-hold sessions in CSV format.")
    }

    func body(content: Content) -> some View {
        content
            .fileExporter(isPresented: $state.showExporter,
                          document: state.document,
                          contentType: .commaSeparatedText,
                          defaultFilename: state.fileName) { _ in }
            .sheet(isPresented: $state.showMail) {
                #if canImport(MessageUI)
                MailComposer(subject: L("Sessioni di apnea", "Breath-hold sessions"),
                             body: mailBody,
                             attachment: Data((state.document?.text ?? "").utf8),
                             fileName: state.fileName + ".csv") {
                    state.showMail = false
                }
                .ignoresSafeArea()
                #else
                EmptyView()
                #endif
            }
            .alert(L("Email non configurata", "Email not set up"), isPresented: $state.mailUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(L("Aggiungi un account nell'app Mail oppure salva il CSV in File e allegalo da lì.", "Add an account in the Mail app, or save the CSV to Files and attach it from there."))
            }
    }
}

extension View {
    func csvExport(_ state: Binding<ExportState>) -> some View {
        modifier(CSVExportModifier(state: state))
    }
}

#if canImport(MessageUI)
struct MailComposer: UIViewControllerRepresentable {
    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    let subject: String
    let body: String
    let attachment: Data
    let fileName: String
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.addAttachmentData(attachment, mimeType: "text/csv", fileName: fileName)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            onFinish()
        }
    }
}
#else
enum MailComposer {
    static var canSend: Bool { false }
}
#endif

// MARK: - Storico

struct HistoryScreen: View {
    @EnvironmentObject private var store: ApneaStore

    @State private var export = ExportState()
    @State private var pendingDelete: ApneaSession?
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var confirmBatchDelete = false

    private var totalHold: Double {
        store.sessions.reduce(0) { $0 + $1.totalHold }
    }

    private var allSelected: Bool {
        !store.sessions.isEmpty && selection.count == store.sessions.count
    }

    private var selectionLabel: String {
        switch selection.count {
        case 0: return L("Nessuna selezionata", "None selected")
        case 1: return L("1 selezionata", "1 selected")
        default: return L("\(selection.count) selezionate", "\(selection.count) selected")
        }
    }

    /// In modalità selezione si esporta solo ciò che è selezionato.
    private var exportSessions: [ApneaSession] {
        guard isSelecting else { return store.sessions }
        return store.sessions.filter { selection.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppBackground())
            .navigationTitle(L("Storico", "History"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !store.sessions.isEmpty {
                        Button(isSelecting ? L("Fine", "Done") : L("Seleziona", "Select"), action: toggleSelectionMode)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    ExportMenu(sessions: exportSessions, state: $export)
                        .disabled(exportSessions.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { selectionBar }
            }
            .navigationDestination(for: UUID.self) { id in
                SessionDetailView(sessionID: id)
            }
            .csvExport($export)
            .confirmationDialog(
                L("Eliminare questa sessione?", "Delete this session?"),
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { session in
                Button(L("Elimina", "Delete"), role: .destructive) { store.delete(id: session.id) }
                Button(L("Annulla", "Cancel"), role: .cancel) {}
            } message: { _ in
                Text(L("I dati della sessione vengono rimossi dal telefono e l'azione non si può annullare.", "The session data will be removed from this phone. This can't be undone."))
            }
            .confirmationDialog(
                selection.count == 1 ? L("Eliminare la sessione selezionata?", "Delete the selected session?")
                                     : L("Eliminare \(selection.count) sessioni?", "Delete \(selection.count) sessions?"),
                isPresented: $confirmBatchDelete,
                titleVisibility: .visible
            ) {
                Button(L("Elimina", "Delete"), role: .destructive, action: deleteSelected)
                Button(L("Annulla", "Cancel"), role: .cancel) {}
            } message: {
                Text(L("I dati vengono rimossi dal telefono e l'azione non si può annullare.", "The data will be removed from this phone. This can't be undone."))
            }
        }
        .tint(Theme.mint)
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accentGradient)
            Text(L("Ancora nessuna sessione", "No sessions yet"))
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text(L("Fai una sessione nella scheda Apnea: tempi, battito e ossigenazione compaiono qui.", "Do a session in the Apnea tab: times, heart rate and blood oxygen will appear here."))
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(32)
    }

    private var sessionList: some View {
        List {
            // Durante la selezione restano solo le sessioni: riepilogo e grafico tornano dopo.
            if !isSelecting {
                summarySection
                chartSection
            }
            sessionsSection
        }
        .scrollContentBackground(.hidden)
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 10) {
                StatTile(title: L("Sessioni", "Sessions"), value: "\(store.sessions.count)")
                StatTile(title: "Record", value: (store.record ?? 0).stopwatchString, tint: Theme.mint)
                StatTile(title: L("Apnea totale", "Total apnea"), value: Int(totalHold).clockString, tint: Theme.cyan)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var chartSection: some View {
        Group {
            Section(L("Miglior tempo per sessione", "Best time per session")) {
                if store.sessions.count > 1 {
                    Chart(Array(store.sessions.reversed())) { session in
                        LineMark(x: .value(LK("Data", "Date"), session.start),
                                 y: .value(LK("Secondi", "Seconds"), session.bestHold))
                            .foregroundStyle(Theme.mint)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value(LK("Data", "Date"), session.start),
                                  y: .value(LK("Secondi", "Seconds"), session.bestHold))
                            .foregroundStyle(Theme.mint)
                    }
                    .chartYAxisLabel(LK("secondi", "seconds"))
                    .frame(height: 180)
                    .padding(.vertical, 6)
                } else {
                    Text(L("Il grafico dell'andamento compare dalla seconda sessione.", "The progress chart appears from your second session."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    private var sessionsSection: some View {
        Section {
            if !isSelecting { SessionRowHeader() }
            ForEach(store.sessions) { session in
                if isSelecting {
                    selectableRow(session)
                } else {
                    NavigationLink(value: session.id) {
                        SessionRow(session: session)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            pendingDelete = session
                        } label: {
                            Label(L("Elimina", "Delete"), systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        } header: {
            Text(L("Sessioni", "Sessions"))
        } footer: {
            Text(isSelecting
                 ? L("Tocca le sessioni da eliminare, poi usa il cestino in basso.", "Tap the sessions to delete, then use the trash button below.")
                 : L("I dati restano solo su questo iPhone. Tocca una sessione per grafici e tabella. Scorri una riga verso sinistra per eliminarla.", "Data stays on this iPhone only. Tap a session for charts and a table. Swipe a row left to delete it."))
        }
        .listRowBackground(Theme.card)
    }

    private func selectableRow(_ session: ApneaSession) -> some View {
        let isOn = selection.contains(session.id)
        return Button {
            toggle(session)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Theme.mint : Color.white.opacity(0.35))
                SessionRow(session: session)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// Barra che compare in fondo durante la selezione.
    private var selectionBar: some View {
        HStack(spacing: 14) {
            Button(allSelected ? L("Deseleziona tutto", "Deselect all") : L("Seleziona tutto", "Select all")) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if allSelected {
                        selection.removeAll()
                    } else {
                        selection = Set(store.sessions.map(\.id))
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.mint)

            Spacer(minLength: 8)

            Text(selectionLabel)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)

            Button {
                confirmBatchDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selection.isEmpty ? Color.white.opacity(0.3) : Color.red)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(selection.isEmpty)
            .accessibilityLabel(L("Elimina le sessioni selezionate", "Delete selected sessions"))
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .top)
        .transition(.move(edge: .bottom))
    }

    // MARK: Azioni di selezione

    private func toggleSelectionMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isSelecting.toggle()
            if !isSelecting { selection.removeAll() }
        }
    }

    private func toggle(_ session: ApneaSession) {
        if selection.contains(session.id) {
            selection.remove(session.id)
        } else {
            selection.insert(session.id)
        }
    }

    private func deleteSelected() {
        withAnimation(.easeInOut(duration: 0.25)) {
            store.delete(ids: selection)
            selection.removeAll()
            if store.sessions.isEmpty { isSelecting = false }
        }
    }
}

private struct SessionRowHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(L("Data", "Date")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L("Tent.", "Att.")).frame(width: 40, alignment: .trailing)
            Text(L("Migliore", "Best")).frame(width: 70, alignment: .trailing)
            Text(L("FC media", "Avg HR")).frame(width: 62, alignment: .trailing)
            // Spazio occupato dalla freccia delle righe sottostanti
            Color.clear.frame(width: 14, height: 1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

private struct SessionRow: View {
    let session: ApneaSession

    private var heartText: String {
        session.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "-"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(session.start.appFormatted(date: .abbreviated, time: .shortened))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(session.attempts.count)")
                .frame(width: 40, alignment: .trailing)
            Text(session.bestHold.stopwatchString)
                .foregroundStyle(Theme.mint)
                .frame(width: 70, alignment: .trailing)
            Text(heartText)
                .frame(width: 62, alignment: .trailing)
        }
        .font(.system(.subheadline, design: .rounded))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.start.appFormatted(date: .abbreviated, time: .shortened)), "
                            + L("\(session.attempts.count) tentativi, migliore \(session.bestHold.stopwatchString)", "\(session.attempts.count) attempts, best \(session.bestHold.stopwatchString)"))
    }
}

// MARK: - Dettaglio sessione

struct SessionDetailView: View {
    let sessionID: UUID

    @EnvironmentObject private var store: ApneaStore
    @EnvironmentObject private var vitals: VitalsMonitor

    @State private var export = ExportState()
    @State private var refreshing = false

    private var session: ApneaSession? { store.session(id: sessionID) }

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                Text(L("Sessione non trovata", "Session not found"))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
        .navigationTitle(session?.start.appFormatted(date: .abbreviated, time: .shortened) ?? L("Sessione", "Session"))
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ExportMenu(sessions: session.map { [$0] } ?? [], state: $export)
                    .disabled(session == nil)
            }
        }
        .csvExport($export)
    }

    private func offset(_ date: Date, in session: ApneaSession) -> Double {
        date.timeIntervalSince(session.start)
    }

    private func whole(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))" } ?? "-"
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.headline, design: .rounded))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }

    private func content(_ session: ApneaSession) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    StatTile(title: L("Tentativi", "Attempts"), value: "\(session.attempts.count)")
                    StatTile(title: L("Migliore", "Best"), value: session.bestHold.stopwatchString, tint: Theme.mint)
                    StatTile(title: L("FC media", "Avg HR"), value: whole(session.averageHeartRate), tint: Theme.azure)
                }

                card(L("Tempi di apnea", "Breath-hold times")) {
                    Chart(Array(session.attempts.enumerated()), id: \.element.id) { index, attempt in
                        BarMark(x: .value(LK("Tentativo", "Attempt"), "\(index + 1)"),
                                y: .value(LK("Secondi", "Seconds"), attempt.duration))
                            .foregroundStyle(attempt.beatPrevious ? Theme.mint : Theme.azure)
                            .cornerRadius(5)
                    }
                    .chartYAxisLabel(LK("secondi", "seconds"))
                    .frame(height: 180)
                    Text(L("In verde i tentativi che hanno superato il precedente.", "Attempts that beat the previous one are shown in green."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                card(L("Battito cardiaco", "Heart rate")) {
                    if session.heartRate.isEmpty {
                        Text(L("Nessun battito registrato: l'Apple Watch non era collegato durante la sessione.", "No heart rate recorded: Apple Watch wasn't connected during the session."))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Chart {
                            ForEach(session.attempts) { attempt in
                                RectangleMark(
                                    xStart: .value(LK("Inizio", "Start"), offset(attempt.start, in: session)),
                                    xEnd: .value(LK("Fine", "End"), offset(attempt.start, in: session) + attempt.duration)
                                )
                                .foregroundStyle(Theme.mint.opacity(0.16))
                            }
                            ForEach(session.heartRate) { sample in
                                LineMark(x: .value(LK("Tempo", "Time"), offset(sample.date, in: session)),
                                         y: .value(LK("Battito", "Heart rate"), sample.value))
                                    .foregroundStyle(Theme.azure)
                                    .interpolationMethod(.monotone)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxisLabel(LK("secondi dall'inizio", "seconds from start"))
                        .chartYAxisLabel("bpm")
                        .frame(height: 200)
                        Text(L("Le fasce verdi indicano i momenti di apnea.", "Green bands mark the breath-holds."))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                card(L("Ossigenazione", "Blood oxygen")) {
                    if session.oxygen.isEmpty {
                        Text(L("Nessuna lettura trovata in Salute per questa sessione. L'Apple Watch misura l'ossigeno in automatico solo ogni tanto: per avere il dato, durante il recupero avvia una misurazione dall'app Livelli O₂ dell'orologio, poi aggiorna.", "No readings found in Health for this session. Apple Watch measures blood oxygen automatically only now and then: to get a reading, start a measurement from the Blood Oxygen app on your watch during recovery, then refresh."))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        if session.oxygen.count > 1 {
                            Chart(session.oxygen) { sample in
                                PointMark(x: .value(LK("Tempo", "Time"), offset(sample.date, in: session)),
                                          y: .value("SpO₂", sample.value))
                                    .foregroundStyle(Theme.cyan)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartXAxisLabel(LK("secondi dall'inizio", "seconds from start"))
                            .chartYAxisLabel(LK("percentuale", "percent"))
                            .frame(height: 140)
                        }
                        ForEach(session.oxygen) { sample in
                            HStack {
                                Text(sample.date.appFormatted(date: .omitted, time: .standard))
                                Spacer()
                                Text(verbatim: "\(Int(sample.value.rounded()))%")
                                    .foregroundStyle(Theme.cyan)
                            }
                            .font(.system(.subheadline, design: .rounded))
                            .monospacedDigit()
                        }
                    }
                    Button {
                        refreshOxygen(for: session)
                    } label: {
                        Label(refreshing ? L("Aggiornamento in corso", "Refreshing") : L("Aggiorna da Salute", "Refresh from Health"),
                              systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(refreshing)
                }

                card(L("Tabella dei tentativi", "Attempts table")) {
                    Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 10) {
                        GridRow {
                            Text(L("N.", "No."))
                            Text(L("Durata", "Duration"))
                            Text(L("FC min", "Min HR"))
                            Text(L("FC med", "Avg HR"))
                            Text(L("FC max", "Max HR"))
                            Text("SpO₂")
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))

                        ForEach(Array(session.attempts.enumerated()), id: \.element.id) { index, attempt in
                            let heart = session.heartStats(for: attempt)
                            GridRow {
                                Text("\(index + 1)")
                                Text(attempt.duration.stopwatchString)
                                    .foregroundStyle(attempt.beatPrevious ? Theme.mint : Color.white)
                                Text(whole(heart?.min))
                                Text(whole(heart?.avg))
                                Text(whole(heart?.max))
                                Text(whole(session.oxygenMin(for: attempt)))
                            }
                            .font(.system(.subheadline, design: .rounded))
                            .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Text(L("FC in battiti al minuto. SpO₂: valore minimo in percentuale, letto fino a due minuti dopo il tentativo.", "HR in beats per minute. SpO₂: lowest value in percent, read up to two minutes after the attempt."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding()
        }
        .foregroundStyle(.white)
    }

    private func refreshOxygen(for session: ApneaSession) {
        let id = session.id
        let from = session.start.addingTimeInterval(-300)
        let to = session.end.addingTimeInterval(300)
        refreshing = true
        Task {
            let oxygen = await vitals.oxygenSamples(from: from, to: to)
            if !oxygen.isEmpty { store.setOxygen(oxygen, for: id) }
            refreshing = false
        }
    }
}
