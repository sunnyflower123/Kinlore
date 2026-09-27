import AVFoundation

/// The shape of a recording as a row of bars: how loud each stretch of it was.
///
/// Read from the file rather than kept while recording. The recorder's own
/// `levels` are a window of the last 48 ticks, gone when the telling ends,
/// and the file is the one thing every memory with a voice has — so a shape
/// drawn from it cannot disagree with what the play button then plays.
enum AudioEnvelope {
    /// `count` values from 0 to 1, the loudest stretch at 1, or nil when the
    /// file cannot be read.
    ///
    /// Decoded a chunk at a time, so a half-hour telling costs one buffer
    /// rather than the whole recording in memory. Call it off the main
    /// thread: a five-minute file is a few million samples.
    static func bars(of url: URL, count: Int) -> [Float]? {
        guard count > 0, let file = try? AVAudioFile(forReading: url) else { return nil }
        let total = file.length
        let chunk: AVAudioFrameCount = 16_384
        guard total > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk)
        else { return nil }

        var sums = [Double](repeating: 0, count: count)
        var frames = [Int](repeating: 0, count: count)
        var position: AVAudioFramePosition = 0
        while position < total {
            do {
                try file.read(into: buffer, frameCount: chunk)
            } catch {
                return nil
            }
            let read = Int(buffer.frameLength)
            guard read > 0, let samples = buffer.floatChannelData?[0] else { break }
            for index in 0 ..< read {
                let frame = position + AVAudioFramePosition(index)
                let bar = min(count - 1, Int(frame * AVAudioFramePosition(count) / total))
                let sample = Double(samples[index])
                sums[bar] += sample * sample
                frames[bar] += 1
            }
            position += AVAudioFramePosition(read)
        }

        let loudness = zip(sums, frames).map { sum, samples in
            samples > 0 ? (sum / Double(samples)).squareRoot() : 0
        }
        guard let peak = loudness.max(), peak > 0 else {
            return Array(repeating: 0, count: count)
        }
        // Decibels under the loudest stretch, forty of them onto the bar's
        // height. Speech has a wide range, and on a linear scale every quietly
        // spoken word is drawn as silence.
        return loudness.map { value in
            guard value > 0 else { return 0 }
            return Float(max(0, 1 + 20 * log10(value / peak) / 40))
        }
    }
}
