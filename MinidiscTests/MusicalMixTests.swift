import AVFoundation
import Foundation
import Testing
@testable import Minidisc

@Suite("Musical Mix")
struct MusicalMixTests {
    @Test func silenceAndInvalidAudioDoNotInventABeat() {
        #expect(MusicalMixAnalyzer.detect(energy: Array(repeating: 0, count: 4000), interval: 0.01, offset: 0, end: 40) == nil)
        #expect(MusicalMixAnalyzer.detect(energy: Array(repeating: .nan, count: 4000), interval: 0.01, offset: 0, end: 40) == nil)
    }

    @Test func detectsPulseAndSourceOffset() throws {
        var energy = Array(repeating: 0.0, count: 4000)
        for i in stride(from: 12, to: energy.count, by: 50) { energy[i] = 1 }
        let grid = try #require(MusicalMixAnalyzer.detect(energy: energy, interval: 0.01, offset: 120, end: 160))
        #expect(abs(grid.beat - 0.5) < 0.001)
        #expect(abs(grid.firstBeat - 120.12) < 0.015)
    }

    @Test func transitionIsBeatAlignedAndTempoBounded() throws {
        let out = MusicalGrid(beat: 0.5, firstBeat: 160.12, confidence: 0.9, end: 200)
        let incoming = MusicalGrid(beat: 0.48, firstBeat: 0.08, confidence: 0.9, end: 180)
        let plan = try #require(MusicalMixPlan.make(outgoing: out, incoming: incoming, position: 100))
        #expect(abs(plan.overlap * Double(plan.outgoingRate) / out.beat - 20) < 0.001)
        #expect(abs(Double(plan.incomingRate / plan.outgoingRate) - 0.96) < 0.0001)
        #expect(abs((plan.exit - out.firstBeat) / out.beat - 52) < 0.0001)
        #expect(plan.entry == incoming.firstBeat)
        #expect(MusicalMixPlan.make(outgoing: out, incoming: incoming, position: 196) == nil)
        let bridge = try #require(MusicalMixPlan.make(outgoing: out,
            incoming: .init(beat: 0.7, firstBeat: 0, confidence: 0.9, end: 180), position: 100))
        #expect(bridge.incomingRate > 1)
        #expect(bridge.outgoingRate < 1)
        #expect(bridge.overlap <= 10)
        #expect(MusicalMixPlan.make(outgoing: out,
            incoming: .init(beat: 0.5, firstBeat: 0, confidence: 0.2, end: 180), position: 170) == nil)
    }

    @Test func overlapFollowsTempoRatherThanSeconds() throws {
        func plan(_ beat: Double) throws -> MusicalMixPlan {
            try #require(MusicalMixPlan.make(
                outgoing: .init(beat: beat, firstBeat: 160, confidence: 1, end: 200),
                incoming: .init(beat: beat, firstBeat: 0, confidence: 1, end: 200), position: 100))
        }
        #expect(try abs(plan(0.4).overlap - 9.6) < 0.0001)
        #expect(try plan(0.75).overlap == 9)
    }

    @Test func musicalMixDoesNotSilentlyTurnOffForConsecutiveAlbumTracks() {
        #expect(PlayerService.effectiveCrossfadeOverlap(duration: 3, disableForGapless: true,
            isGaplessPair: true, musicalMixEnabled: true) == 3)
        #expect(PlayerService.effectiveCrossfadeOverlap(duration: 3, disableForGapless: true,
            isGaplessPair: true) == 0)
    }

    @Test func lateAnalysisShortensTheBlendInsteadOfRevertingToEOF() throws {
        let plan = try #require(MusicalMixPlan.make(
            outgoing: .init(beat: 60/92, firstBeat: 163.16, confidence: 1, end: 223.09, exitCue: 215.33),
            incoming: .init(beat: 0.625, firstBeat: 0.08, confidence: 1, end: 265), position: 200.8))
        #expect(plan.overlap < 60/92 * 16)
        #expect(plan.exit > 203.8)
        #expect(plan.exit + plan.overlap < 220)
    }

    @Test func halfTimeTempoIsMatched() throws {
        let plan = try #require(MusicalMixPlan.make(
            outgoing: .init(beat: 0.5, firstBeat: 160, confidence: 0.8, end: 200),
            incoming: .init(beat: 1, firstBeat: 0, confidence: 0.8, end: 180), position: 170))
        #expect(plan.incomingRate == 1)
        #expect(plan.overlap == 8)
    }

    @Test func distantTemposShareACommonTempoWithinTenSeconds() throws {
        let out = MusicalGrid(beat: 60/96, firstBeat: 205, confidence: 1, end: 265, exitCue: 262.5)
        let incoming = MusicalGrid(beat: 60/129, firstBeat: 0.05, confidence: 0.7, end: 218, entryCue: 7.5)
        let plan = try #require(MusicalMixPlan.make(outgoing: out, incoming: incoming, position: 170))
        #expect(plan.overlap > 5 && plan.overlap <= 10)
        #expect(abs(96 * Double(plan.outgoingRate) - 129 * Double(plan.incomingRate)) < 0.001)
        for fraction in [0.2, 0.4, 0.5, 0.6, 0.8] {
            let gains = MusicalMixPlan.deckGains(fraction: fraction)
            #expect(gains.outgoing > 0.38 && gains.incoming > 0.38)
            #expect(abs(gains.outgoing*gains.outgoing + gains.incoming*gains.incoming - 1) < 0.001)
        }
    }

    @Test func musicalMixFallbackAlsoRespectsTheLimit() {
        #expect(PlayerService.effectiveCrossfadeOverlap(duration: 12, disableForGapless: false,
            isGaplessPair: false, musicalMixEnabled: true) == 10)
    }

    @Test func overlapNeverExceedsTenSecondsAcrossTempos() throws {
        for outBPM in stride(from: 70.0, through: 180, by: 5) {
            for inBPM in stride(from: 70.0, through: 180, by: 5) {
                let out = MusicalGrid(beat: 60/outBPM, firstBeat: 140, confidence: 1, end: 200)
                let incoming = MusicalGrid(beat: 60/inBPM, firstBeat: 0, confidence: 1, end: 200)
                let plan = try #require(MusicalMixPlan.make(outgoing: out, incoming: incoming, position: 100))
                #expect(plan.overlap <= 9.9)
                let bars = plan.overlap * Double(plan.outgoingRate) / (out.beat * 4)
                #expect(abs(bars - bars.rounded()) < 0.0001)
            }
        }
    }

    @Test @MainActor func optInPersistsWithoutChangingCrossfade() throws {
        let name = "musical-mix-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = CrossfadeSettings(defaults: defaults)
        #expect(!settings.musicalMixEnabled)
        settings.musicalMixEnabled = true
        #expect(CrossfadeSettings(defaults: defaults).config.musicalMixEnabled)
        #expect(settings.duration == 0)
        #expect(settings.disableForGapless)
    }
}

/// Exercises decoding, analysis, muted cueing, time stretching and promotion together.
@Suite("Musical Mix — rendered audio", .serialized)
@MainActor
struct MusicalMixPlaybackTests {
    @Test func downloadedAudioWithAnOpaqueNameRemainsDecodable() async throws {
        let file = try makePulseFile(beat: 0.5)
        let opaque = FileManager.default.temporaryDirectory.appendingPathComponent("mix-\(UUID()).download")
        try FileManager.default.moveItem(at: file, to: opaque)
        defer { try? FileManager.default.removeItem(at: opaque) }
        let owned = try MusicalMixAnalyzer.preserveDownloadedFile(opaque)
        defer { try? FileManager.default.removeItem(at: owned) }
        #expect(owned.pathExtension == "wav")
        #expect(!FileManager.default.fileExists(atPath: opaque.path))
        let pair = try #require(await MusicalMixAnalyzer.analyzePair(url: owned, headers: [:]))
        #expect(pair.0 != nil && pair.1 != nil)
    }

    @Test func analyzedLocalTracksCanTransitionBeforeEOF() async throws {
        try AVAudioSession.sharedInstance().setCategory(.playback)
        try AVAudioSession.sharedInstance().setActive(true)
        let outgoing = try makePulseFile(beat: 0.5)
        let incoming = try makePulseFile(beat: 0.48)
        defer {
            try? FileManager.default.removeItem(at: outgoing)
            try? FileManager.default.removeItem(at: incoming)
        }
        let grids = try #require(await MusicalMixAnalyzer.analyzePair(url: outgoing, headers: [:]))
        #expect(grids.0 != nil)
        #expect(grids.1 != nil)
        let engine = AudioStreamingEngine()
        let observer = MixPlaybackObserver()
        engine.delegate = observer
        engine.volume = 0
        engine.setMusicalMixEnabled(true)
        engine.play(trackID: "out", url: outgoing, headers: [:])
        defer { engine.stop() }
        for _ in 0..<200 {
            if engine.isSeekable && engine.progress > 0.15 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await engine.seek(to: 12))
        engine.preloadNext(trackID: "in", url: incoming, headers: [:], crossfadeDuration: 3, replayGainDB: 0)
        for _ in 0..<1000 {
            if observer.transition != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let transition = try #require(observer.transition)
        #expect(transition.endedPosition < 30)
        #expect(transition.promotedPlayback?.trackID == "in")
        #expect((transition.promotedPlayback?.position ?? 0) > 3)
        #expect((transition.promotedPlayback?.audibleDuration ?? .infinity) <= 10)
        #expect(observer.failures == 0)
    }

    private func makePulseFile(beat: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mix-\(UUID()).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 11025, channels: 1)!
        let frames = AVAudioFrameCount(32 * 11025)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / 11025
            let phase = (t - 0.12).truncatingRemainder(dividingBy: beat)
            samples[i] = t >= 0.12 && phase >= 0 && phase < 0.025
                ? Float(sin(2 * .pi * 440 * t) * exp(-phase * 150) * 0.8) : 0
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}

nonisolated private final class MixPlaybackObserver: AudioEngineDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var storedTransition: AudioEngineTrackEnd?
    private var storedFailures = 0
    var transition: AudioEngineTrackEnd? { lock.withLock { storedTransition } }
    var failures: Int { lock.withLock { storedFailures } }
    func audioEngineDidChangeState(_ state: AudioEngineState, playbackToken: AudioEnginePlaybackToken) {}
    func audioEngineDidReachEndOfTrack(_ transition: AudioEngineTrackEnd) {
        lock.withLock { storedTransition = transition }
    }
    func audioEngineDidError(_ error: AudioEngineFailure, playbackToken: AudioEnginePlaybackToken) {
        lock.withLock { storedFailures += 1 }
    }
}
