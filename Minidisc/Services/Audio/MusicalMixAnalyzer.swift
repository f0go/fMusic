import Accelerate
import AVFoundation
import OSLog
import Foundation

/// All timestamps are source seconds. The grid is inferred from onsets, not metadata BPM.
nonisolated struct MusicalGrid: Sendable {
    let beat: Double
    let firstBeat: Double
    let confidence: Double
    let end: Double
    var entryCue: Double? = nil
    var exitCue: Double? = nil
}

nonisolated struct MusicalMixPlan: Sendable {
    let exit: Double
    let entry: Double
    let overlap: Double
    let incomingRate: Float
    let outgoingRate: Float
    static let maximumOverlap: Double = 10

    static func deckGains(fraction: Double) -> (outgoing: Float, incoming: Float) {
        let x = min(1, max(0, fraction))
        let blend: Double
        if x < 0.2 { blend = x / 0.2 * 0.25 }
        else if x < 0.8 { blend = 0.25 + (x - 0.2) / 0.6 * 0.5 }
        else { blend = 0.75 + (x - 0.8) / 0.2 * 0.25 }
        return (Float(cos(blend * .pi / 2)), Float(sin(blend * .pi / 2)))
    }

    static func make(outgoing: MusicalGrid, incoming: MusicalGrid, position: Double) -> Self? {
        guard outgoing.confidence >= 0.35, incoming.confidence >= 0.35,
              outgoing.beat.isFinite, outgoing.beat > 0, incoming.beat.isFinite, incoming.beat > 0,
              outgoing.firstBeat.isFinite, incoming.firstBeat.isFinite,
              outgoing.end.isFinite, incoming.end.isFinite, position.isFinite else { return nil }
        // Octave ambiguity is common in hip-hop and electronic music. Compare half/double
        // tempo before deciding whether a sustained beat match is musically reasonable.
        let ratio = [0.5, 1.0, 2.0].map { incoming.beat * $0 / outgoing.beat }
            .min { abs(log($0)) < abs(log($1)) } ?? 1
        // Meet at a common tempo: split the adjustment between both decks. This also
        // bridges pairs such as 96 → 129 BPM without a two-beat cut or a 34% change
        // on one voice. Octave-equivalent grids still align every second beat.
        let incomingRate = sqrt(ratio)
        let outgoingRate = 1 / incomingRate
        guard (0.8...1.25).contains(incomingRate), (0.8...1.25).contains(outgoingRate) else { return nil }
        let bar = outgoing.beat * 4
        let targetEnd = outgoing.exitCue ?? (outgoing.end - bar)
        let end = outgoing.firstBeat + floor((targetEnd - outgoing.firstBeat) / bar) * bar
        // Keep complete four-beat groups at the shared tempo, with scheduling headroom
        // below the ten-second ceiling. Never cut a long blend halfway through a bar.
        let maximumBars = Int(floor((Self.maximumOverlap - 0.1) * outgoingRate / bar))
        guard maximumBars >= 1 else { return nil }
        let beatCounts = stride(from: maximumBars, through: 1, by: -1).map { Double($0 * 4) }
        let entry = incoming.entryCue ?? incoming.firstBeat
        guard entry >= 0, entry < 30 else { return nil }
        guard let overlap = beatCounts.map({ outgoing.beat * $0 }).first(where: {
            end - $0 > position + 6 && incoming.end > entry + $0 / outgoingRate * incomingRate + 5
        }) else { return nil }
        let exit = end - overlap
        guard exit > outgoing.end - 100 else { return nil }
        return Self(exit: exit, entry: entry, overlap: overlap / outgoingRate,
                    incomingRate: Float(incomingRate), outgoingRate: Float(outgoingRate))
    }
}

/// Bounded, cancellable analysis away from the playback queues. No audio leaves the device.
/// Remote sources are downloaded separately; failed/slow/oversized sources use ordinary crossfade.
nonisolated enum MusicalMixAnalyzer {
    static func analyzePair(url: URL, headers: [String: String]) async -> (MusicalGrid?, MusicalGrid?)? {
        var temporary: URL?
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }
        do {
            let source: URL
            if url.isFileURL { source = url }
            else {
                var request = URLRequest(url: url, timeoutInterval: 30)
                request.allHTTPHeaderFields = headers
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForResource = 45
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let delegate = MixDownloadLimit()
                let (file, response) = try await session.download(for: request, delegate: delegate)
                temporary = file
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
                // Own the file before the first suspension in AVFoundation; a URLSession
                // download location belongs to the completion callback, not the analyzer.
                let owned = try preserveDownloadedFile(file)
                temporary = owned
                source = owned
            }
            let intro = try await analyzeFile(url: source, outro: false)
            try Task.checkCancellation()
            let outro = try await analyzeFile(url: source, outro: true)
            return (intro, outro)
        } catch {
            Logger.player.info("[MIX] analysis unavailable code=\((error as NSError).code)")
            return nil
        }
    }

    /// AVFoundation uses the extension to select a demuxer. Stream URLs and URLSession's
    /// temporary names need not describe the actual container (for example stream.view).
    static func preserveDownloadedFile(_ downloaded: URL) throws -> URL {
        guard let container = AudioContainer.sniff(atPath: downloaded.path) else {
            throw URLError(.cannotDecodeContentData)
        }
        let owned = FileManager.default.temporaryDirectory
            .appendingPathComponent("mix-analysis-\(UUID()).\(container.rawValue)")
        try FileManager.default.moveItem(at: downloaded, to: owned)
        return owned
    }

    private static func analyzeFile(url source: URL, outro: Bool) async throws -> MusicalGrid? {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 20,
              let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let offset = outro ? max(0, duration - 60) : 0
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: offset, preferredTimescale: 11025),
            duration: CMTime(seconds: min(60, duration - offset), preferredTimescale: 11025))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 11025,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        guard reader.startReading() else { return nil }
        var pcm: [Float] = []
        pcm.reserveCapacity(60 * 11025)
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return nil }
            guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
            let size = CMBlockBufferGetDataLength(buffer)
            var data = Data(count: size)
            let status = data.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: size, destination: $0.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { return nil }
            data.withUnsafeBytes { bytes in
                pcm.append(contentsOf: bytes.bindMemory(to: Int16.self).map { Float($0) / 32768 })
            }
        }
        guard reader.status == .completed else { return nil }
        let envelope = spectralOnsets(pcm)
        return detectOnsets(envelope.onsets, levels: envelope.levels, interval: 110.0 / 11025,
                            offset: offset, end: duration)
    }

    /// Positive spectral flux separates new percussion attacks from sustained vocals/bass.
    /// Log compression and local whitening keep loud choruses from dominating the beat grid.
    private static func spectralOnsets(_ pcm: [Float]) -> (onsets: [Double], levels: [Double]) {
        let size = 512, half = 256, hop = 110
        guard pcm.count >= size,
              let setup = vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2)) else { return ([], []) }
        defer { vDSP_destroy_fftsetup(setup) }
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        var input = window, real = [Float](repeating: 0, count: half), imaginary = real
        var previous = [Double](repeating: 0, count: half)
        var averages = [Double](repeating: 0.01, count: half)
        var onsets: [Double] = [], levels: [Double] = []
        for start in stride(from: 0, through: pcm.count - size, by: hop) {
            if Task.isCancelled { return ([], []) }
            var rms = 0.0
            for i in 0..<size {
                let value = pcm[start + i]
                input[i] = value * window[i]
                rms += Double(value * value)
            }
            var flux = 0.0
            real.withUnsafeMutableBufferPointer { r in
                imaginary.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
                    input.withUnsafeBufferPointer { samples in
                        samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, 9, FFTDirection(FFT_FORWARD))
                    for k in 2..<half {
                        let magnitude = log1p(Double(hypot(r[k], im[k])))
                        averages[k] = averages[k] * 0.98 + magnitude * 0.02
                        let whitened = magnitude / max(0.03, averages[k])
                        flux += max(0, whitened - previous[k])
                        previous[k] = whitened
                    }
                }
            }
            // Center timestamps account for the FFT window's lookahead.
            onsets.append(flux)
            levels.append(sqrt(rms / Double(size)))
        }
        // Suppress start-up whitening, whose first window is not a musical onset.
        for i in 0..<min(3, onsets.count) { onsets[i] = 0 }
        return (onsets, levels)
    }

    static func detect(energy: [Double], interval: Double, offset: Double, end: Double) -> MusicalGrid? {
        guard energy.count > 1000, energy.allSatisfy({ $0.isFinite }) else { return nil }
        var onsets = [Double](repeating: 0, count: energy.count)
        for i in 1..<energy.count { onsets[i] = max(0, energy[i] - energy[i - 1]) }
        return detectOnsets(onsets, levels: energy, interval: interval, offset: offset, end: end)
    }

    private static func detectOnsets(_ raw: [Double], levels: [Double], interval: Double,
                                     offset: Double, end: Double) -> MusicalGrid? {
        guard raw.count > 1000, interval > 0, raw.allSatisfy({ $0.isFinite }),
              raw.max() ?? 0 > 0.00001 else { return nil }
        // A three-frame kernel tolerates human timing and attacks between analysis frames.
        var onset = raw
        for i in 1..<(raw.count - 1) { onset[i] = raw[i-1]*0.25 + raw[i]*0.5 + raw[i+1]*0.25 }
        let mean = onset.reduce(0, +) / Double(onset.count)
        guard mean > 1e-8 else { return nil }
        for i in onset.indices { onset[i] = min(onset[i], mean * 8) }
        func sample(_ index: Double) -> Double {
            let i = Int(index)
            guard i >= 0, i + 1 < onset.count else { return 0 }
            let f = index - Double(i)
            return onset[i] * (1-f) + onset[i+1] * f
        }
        func correlation(_ lag: Double) -> Double {
            var sum = 0.0, a = 0.0, b = 0.0
            for i in Int(ceil(lag))..<onset.count {
                let x = onset[i], y = sample(Double(i)-lag)
                sum += x*y; a += x*x; b += y*y
            }
            return sum / max(1e-12, sqrt(a*b))
        }
        var bestBeat = 0.5, bestScore = 0.0
        // Fractional lags avoid the accumulated drift of an integer 10-ms tempo grid.
        for bpmStep in 280...720 {
            let beat = 60 / (Double(bpmStep) / 4)
            let lag = beat / interval
            let score = correlation(lag)*0.5 + correlation(lag*2)*0.3 + correlation(lag*4)*0.2
            if score > bestScore { bestScore = score; bestBeat = beat }
        }
        let lag = bestBeat / interval
        var phase = 0.0, phaseScore = 0.0
        for step in 0..<Int(ceil(lag * 2)) {
            let candidate = Double(step) / 2
            var score = 0.0, count = 0
            var point = candidate
            while point < Double(onset.count - 1) {
                score += sample(point); count += 1; point += lag
            }
            score /= Double(max(1, count))
            if score > phaseScore { phase = candidate; phaseScore = score }
        }
        let concentration = phaseScore / max(1e-9, onset.reduce(0,+) / Double(onset.count))
        // Correlation alone over-scores sustained/noisy signals; require a distinct beat phase.
        guard bestScore >= 0.22, concentration >= 1.35 else { return nil }
        let confidence = min(1, bestScore * min(1.5, concentration / 2))
        guard confidence >= 0.35 else { return nil }
        let first = offset + phase * interval
        var grid = MusicalGrid(beat: bestBeat, firstBeat: first, confidence: confidence, end: end)
        func averageLevel(_ start: Double, _ length: Double) -> Double {
            let lower = max(0, Int(start / interval)), upper = min(levels.count, Int((start+length) / interval))
            guard upper > lower else { return 0 }
            return levels[lower..<upper].reduce(0,+) / Double(upper-lower)
        }
        let bar = bestBeat * 4
        let globalLevel = levels.reduce(0,+) / Double(max(1,levels.count))
        // Find the first established rhythmic passage, skipping quiet/unmetered lead-ins.
        if offset == 0 {
            for cue in stride(from: first, through: min(24, end - bar*4), by: bar) {
                let lower = max(0, Int(cue / interval))
                let upper = min(onset.count, Int((cue + bar*4) / interval))
                guard upper > lower else { continue }
                let localMean = onset[lower..<upper].reduce(0,+) / Double(upper-lower)
                var aligned = 0.0
                for beat in 0..<16 {
                    let point = (cue + Double(beat)*bestBeat) / interval
                    aligned += max(sample(point-1), sample(point), sample(point+1))
                }
                let rhythmicContrast = aligned / 16 / max(1e-9, localMean)
                if averageLevel(cue, bar*2) > globalLevel * 0.45, rhythmicContrast >= 1.6 {
                    grid.entryCue = cue; break
                }
            }
        }
        // Prefer a measured energy drop into the outro; otherwise leave four beats of tail.
        var exitEnd = end - bar
        var strongestDrop = 0.0
        for boundary in stride(from: first + bar*2, through: end - bar, by: bar) {
            guard boundary > end - 32 else { continue }
            let before = averageLevel(boundary - offset - bar*2, bar*2)
            let after = averageLevel(boundary - offset, bar)
            let drop = (before - after) / max(1e-8, before)
            if before > globalLevel * 0.4, drop > 0.4, drop > strongestDrop {
                strongestDrop = drop; exitEnd = boundary
            }
        }
        grid.exitCue = exitEnd
        return grid
    }
}

nonisolated private final class MixDownloadLimit: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > 64 * 1024 * 1024 || totalBytesExpectedToWrite > 64 * 1024 * 1024 { downloadTask.cancel() }
    }
}
