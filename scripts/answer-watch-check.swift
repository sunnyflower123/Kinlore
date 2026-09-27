// Checks when an answer in the conversation is over without anybody saying so.
//
// `AnswerWatch` is two limits over a stream of meter readings, and both ways
// of being wrong are silent. Too eager and it ends the conversation in the
// middle of a sentence, or while an 80-year-old is still remembering what
// came next; too slow and the microphone the loop opened by itself goes on
// recording an empty room, on a screen that never sleeps. Neither fails a
// build, and a screenshot of either shows "Kuuntelen".
//
// The readings are built from what was measured on the test phone (see the
// comment on AnswerWatch): the room between words at −51 to −64 dBFS, a
// breath or the phone in the hand at −42 to −49, and a pause inside speech
// never longer than 2.25 s, even with the recordings made 20 dB quieter.
// Every reading arrives at a time on the recording's clock, 50 ms apart
// unless a case says otherwise. Costs nothing. Run it after touching
// AnswerWatch.swift.
//
//   swiftc -parse-as-library -o /tmp/answer-watch-check \
//     scripts/answer-watch-check.swift ios/Kinlore/Recording/AnswerWatch.swift

import Foundation

@main
enum AnswerWatchCheck {
    static func main() {
        var failures = 0

        /// On time is the reading at the limit or the one after it: a time on
        /// the recording's clock is a Double, and 30.05 + 25 need not reach
        /// 55.05. Never a reading sooner.
        func check(_ label: String, _ actual: TimeInterval?, _ expected: TimeInterval?) {
            let same: Bool
            switch (actual, expected) {
            case (nil, nil): same = true
            case let (a?, e?): same = a > e - 0.001 && a < e + 0.051
            default: same = false
            }
            if same {
                print("  ok   \(label)")
            } else {
                failures += 1
                let got = actual.map { String(format: "%.2f s", $0) } ?? "never"
                let want = expected.map { String(format: "%.2f s", $0) } ?? "never"
                print("  FAIL \(label): ended \(got), expected \(want)")
            }
        }

        /// A seeded generator, so a failure names the same readings every run.
        struct Seeded {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
            mutating func between(_ low: Double, _ high: Double) -> Double {
                low + (high - low) * Double(next() >> 11) / Double(1 << 53)
            }
        }

        /// Feeds a fresh watch one reading per time until it says the answer
        /// is over, and returns when; nil if it never did.
        func ended(_ readings: [(at: TimeInterval, level: Float)]) -> TimeInterval? {
            var watch = AnswerWatch()
            for reading in readings where watch.hasEnded(hearing: reading.level, at: reading.at) {
                return reading.at
            }
            return nil
        }

        /// Readings 50 ms apart from `start` up to but not including `end`.
        /// The times are counted in whole ticks, so 25 s is exactly 25.
        func span(
            _ start: TimeInterval, _ end: TimeInterval, _ level: (TimeInterval) -> Float
        ) -> [(at: TimeInterval, level: Float)] {
            let first = Int((start * 20).rounded()), last = Int((end * 20).rounded())
            return (first ..< last).map { tick in
                let at = Double(tick) / 20
                return (at, level(at))
            }
        }

        var random = Seeded(state: 27_09_2026)
        func room(_: TimeInterval) -> Float { Float(random.between(-64, -51)) }

        /// Speech as the recordings have it: sounds from −38 up to −15 dBFS,
        /// 0.1 to 0.5 s long, with the room between them for up to 2.25 s.
        func speech(_ start: TimeInterval, _ end: TimeInterval) -> [(at: TimeInterval, level: Float)] {
            var readings: [(at: TimeInterval, level: Float)] = []
            var at = start
            while at < end {
                let pause = random.between(0, 2.25)
                readings += span(at, min(end, at + pause), room)
                at = min(end, at + pause)
                let sound = random.between(0.1, 0.5)
                readings += span(at, min(end, at + sound)) { _ in Float(random.between(-38, -15)) }
                at = min(end, at + sound)
            }
            return readings
        }

        print("— silence ends an answer —")
        check("digital silence, at 25 s and not a reading sooner", ended(span(0, 60) { _ in -160 }), 25)
        check("the room between words, the same", ended(span(0, 60, room)), 25)
        check(
            "a breath or the phone moving every two seconds is still silence",
            ended(span(0, 60) { at in
                at.truncatingRemainder(dividingBy: 2) < 0.2 ? Float(random.between(-49, -42)) : room(at)
            }),
            25
        )
        check(
            "counted from the last sound, not from the start",
            ended(speech(0, 30) + [(30, -20)] + span(30.05, 90, room)),
            55.05
        )

        print("— speech is never silence —")
        check("ten minutes of quiet speech run to the length limit", ended(speech(0, 700)), 600)
        check(
            "a pause just short of 25 s, to remember, is not the end",
            ended(speech(0, 20) + [(20, -20)] + span(20.05, 44.95, room) + [(44.95, -20)] + speech(45, 70)),
            nil
        )
        check(
            "one reading at the line is a sound",
            ended(span(0, 20, room) + [(20, AnswerWatch.quiet)] + span(20.05, 90, room)),
            45.05
        )

        print("— the length limit —")
        check("continuous speech, at 600 s and not a reading sooner", ended(span(0, 700) { _ in -20 }), 600)
        check(
            "a silence that began at 590 s ends at the limit, not at 615",
            ended(span(0, 590) { _ in -20 } + span(590, 700, room)),
            600
        )

        print("— the recording's clock, not a count of readings —")
        check(
            "readings half a second apart, as a busy main thread delivers them",
            ended(stride(from: 0.0, to: 60, by: 0.5).map { ($0, -160) }),
            25
        )
        check(
            "three seconds with no readings at all still count",
            ended(span(0, 10, room) + span(13, 60, room)),
            25
        )

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
