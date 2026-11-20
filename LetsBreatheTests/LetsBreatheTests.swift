//
//  LetsBreatheTests.swift
//  LetsBreatheTests
//
//  Created by Matteo Negri on 11/07/25.
//

import Foundation
import Testing
@testable import LetsBreathe

@MainActor
struct LetsBreatheTests {

    /// Il recupero tra due tentativi si registra; quello dopo l'ultimo tentativo no.
    @Test func restBetweenAttemptsIsRecorded() async throws {
        let engine = ApneaEngine()

        engine.tap()                                   // parte il tentativo 1
        try await Task.sleep(for: .milliseconds(450))
        engine.tap()                                   // fine tentativo 1, inizia il recupero
        try await Task.sleep(for: .milliseconds(800))
        engine.tap()                                   // fine recupero, parte il tentativo 2
        try await Task.sleep(for: .milliseconds(450))
        engine.tap()                                   // fine tentativo 2
        try await Task.sleep(for: .milliseconds(600))  // riposo finale: non va registrato

        let session = try #require(engine.endSession())
        #expect(session.attempts.count == 2)
        #expect(session.attempts[0].restBefore == nil)
        let rest = try #require(session.attempts[1].restBefore)
        #expect(rest > 0.7 && rest < 1.2)
        #expect(session.totalRest == rest)
    }

    /// Le sessioni salvate prima della modifica (senza recupero) si leggono ancora.
    @Test func oldSessionsStillDecode() throws {
        let json = """
        [{"id":"6F1C2C4E-1E0B-4E7A-9C8B-1A2B3C4D5E6F","start":0,"end":100,
          "attempts":[{"id":"7F1C2C4E-1E0B-4E7A-9C8B-1A2B3C4D5E6F","start":0,"duration":30,"beatPrevious":false}],
          "heartRate":[],"oxygen":[]}]
        """
        let sessions = try JSONDecoder().decode([ApneaSession].self, from: Data(json.utf8))
        #expect(sessions.first?.attempts.first?.restBefore == nil)
    }
}
