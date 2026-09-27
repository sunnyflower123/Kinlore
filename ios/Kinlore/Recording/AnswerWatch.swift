import Foundation

/// When an answer in the conversation is over and nobody has said so.
///
/// After every question the loop opens the microphone by itself, and until
/// 27 Sep 2026 only a hand closed it again. A teller who had said her piece
/// and was waiting for the app to take its turn — it had taken the first one
/// — left "Kuuntelen" standing on a screen the recorder keeps awake, and the
/// file grew for as long as nobody touched the phone. Two limits end it now,
/// and both end it the way "Riittää tältä erää" does
/// (`TellViewModel.finishAfterThisAnswer`): what was said is kept and
/// transcribed (rule 3), no further question is asked, and every name the
/// rounds heard waits unconfirmed on the result card (rule 4).
///
/// **Silence**: `silence` seconds in which no reading reaches `quiet`.
/// **Length**: `length` seconds of one answer, whatever it holds. A radio
/// left on is not silence, and a loop that went on asking it questions would
/// send ten minutes of it to be transcribed every round — so this limit ends
/// the conversation too, rather than moving on to the next question.
///
/// Only answers in the conversation are watched. The first telling is not:
/// whoever pressed record can press stop, and a long pause to remember is
/// part of a story rather than the end of one.
///
/// The threshold is measured. Three recordings the app made on the test
/// phone, decoded and read in 50 ms windows, the meter's own interval: the
/// room between words at −51 to −64 dBFS, a breath or the phone moving in the
/// hand at −42 to −49, the recordings' median at −28 to −45 and their 95th
/// percentile at −15 or −16. Against −40 the longest pause in them is 1.5 s,
/// and 2.25 s with every sample made 20 dB quieter, as a soft voice with the
/// phone on the table might be; twenty-five seconds is ten times that. And
/// −40 clears the loudest room by 10 dB, so somebody waiting — who is still
/// breathing, and still holding the phone — reads as silence.
///
/// Time is the recording's own clock, not a count of readings. The ticker is
/// a timer on the main run loop, and whatever holds the main thread holds it.
struct AnswerWatch {
    /// How long an answer may stay quiet before it is over.
    static let silence: TimeInterval = 25
    /// How long one answer may run.
    static let length: TimeInterval = 600
    /// A reading below this is silence: dBFS, as `averagePower` reports it.
    static let quiet: Float = -40

    /// Where on the recording's clock the current quiet began; nil while
    /// something is being heard.
    private var quietSince: TimeInterval?

    /// Fed every meter reading while the recorder is recording. True once the
    /// answer is over.
    mutating func hasEnded(hearing level: Float, at elapsed: TimeInterval) -> Bool {
        if elapsed >= Self.length { return true }
        guard level < Self.quiet else {
            quietSince = nil
            return false
        }
        let since = quietSince ?? elapsed
        quietSince = since
        return elapsed - since >= Self.silence
    }
}
