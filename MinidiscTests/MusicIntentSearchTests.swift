import Testing
@testable import Minidisc

@Suite("Siri search destinations")
@MainActor
struct MusicIntentSearchTests {
    @Test func retriesTheReportedSongWithoutTheAppDestination() async throws {
        var queries: [String] = []
        let songs = try await MusicIntentSearch.results(for: "Trap Queen in Mus1c") { query in
            queries.append(query)
            return query == "Trap Queen" ? ["trap-queen-id"] : []
        }
        #expect(queries == ["Trap Queen in Mus1c", "Trap Queen"])
        #expect(songs == ["trap-queen-id"])
    }

    @Test func preservesLiteralMatches() async throws {
        var queries: [String] = []
        let songs = try await MusicIntentSearch.results(for: "Lost in Music") { query in
            queries.append(query)
            return ["literal-song-id"]
        }
        #expect(queries == ["Lost in Music"])
        #expect(songs == ["literal-song-id"])
    }

    @Test(arguments: ["Trap Queen en Mus1c", "Trap Queen in MUS1C.",
                      "Trap Queen on Music", "Trap Queen in Minidisc"])
    func recognizesAppDestinations(_ text: String) {
        #expect(MusicIntentSearch.fallbackTerm(for: text) == "Trap Queen")
    }

    @Test(arguments: ["Trap Queen", "In Mus1c", "Trap Queen on Spotify", "Mus1c in the Night"])
    func preservesOtherQueries(_ text: String) {
        #expect(MusicIntentSearch.fallbackTerm(for: text) == nil)
    }

    @Test func doesNotHideSearchFailures() async {
        enum Failure: Error { case unavailable }
        var calls = 0
        do {
            let _: [String] = try await MusicIntentSearch.results(for: "Trap Queen in Mus1c") { _ in
                calls += 1
                throw Failure.unavailable
            }
            Issue.record("Expected search failure")
        } catch { #expect(error is Failure) }
        #expect(calls == 1)
    }
}
