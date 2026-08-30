#!/usr/bin/env python3
"""Generate synthetic Finnish samples for the ASR comparison.

WHY: getting real recordings takes time, but the engine can be chosen before
that. Synthetic audio has one real advantage — the reference is flawless,
because we know exactly what was said. Transcribing by hand has errors of its
own.

WHAT THIS DOES NOT TELL YOU: absolute quality. TTS does not produce dialect,
stammering, self-correction, overlapping speech, or a sentence trailing off. A
real elderly speaker does all of that. These figures are therefore optimistic.

WHAT THIS DOES TELL YOU: the relative ranking of the engines and how fast each
falls apart as the audio degrades. That is enough to choose MODEL_TRANSCRIBE.

Degradation is done in pure Python, because this machine has neither ffmpeg nor
sox. The three steps imitate what goes wrong in a real recording: a quiet
speaker, room noise and a muffled tone.

The sample texts are Finnish because that is the input under test.

Usage:
    python3 scripts/make-synthetic-samples.py
"""

import array
import math
import os
import random
import subprocess
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "samples"

# The content is chosen for what matters to the archive: proper nouns, places
# and an imprecise decade. These drive how the family tree is built, so their
# accuracy weighs more than that of filler words.
# Two sets, and the English one is not the Finnish one translated. What each
# text is FOR is the same — proper nouns an engine can plausibly get wrong, a
# place, and a date that is vague in one and exact in another — but the traps
# have to be that language's own traps. "Sotkamo" heard as "Skotlanti" is a
# Finnish failure; the English equivalent is Alnwick, which is not pronounced
# the way it is spelled, and Elsie, which is a name no model has heard often.
TEXTS_EN = {
    "cottage": (
        "In that photograph we are down at the cottage by the water, "
        "that was in Ambleside. Elsie was sitting beside me and Arthur took "
        "the picture. It was sometime in the fifties, I do not remember exactly."
    ),
    "siblings": (
        "Margaret and Beatrice were sisters. Wilfred was their brother "
        "and he went out to Canada and never came back. "
        "Elsie stayed in Alnwick to look after the house."
    ),
    "wedding": (
        "We were married in nineteen sixty-two in Keswick. "
        "Beatrice was the bridesmaid and Wilfred was the best man. "
        "It poured with rain the whole day."
    ),
}

TEXTS_FI = {
    "cottage": (
        "Siinä kuvassa ollaan sen mökin rannassa, se oli Puumalassa se mökki. "
        "Aino oli siinä vieressäni ja Toivo otti sen kuvan. "
        "Se oli joskus viideskymmenluvulla, en muista tarkkaan."
    ),
    "siblings": (
        "Impi ja Tyyne olivat siskoksia. Eevertti oli heidän veljensä "
        "ja se muutti Amerikkaan eikä palannut koskaan. "
        "Hilma jäi Sotkamoon hoitamaan taloa."
    ),
    "wedding": (
        "Me mentiin naimisiin vuonna kuusikymmentäkaksi Tampereella. "
        "Kaarina oli kaaso ja Väinö oli bestman. "
        "Sinä päivänä satoi kaatamalla."
    ),
}

# Steps: name -> (gain, noise level, smoothing width)
# The last step is closest to what a phone records of someone speaking quietly
# in a living room.
STAGES = {
    "clean": (1.0, 0.0, 0),
    "quiet": (0.18, 0.0, 0),
    "noisy": (0.5, 0.010, 0),
    "hard": (0.15, 0.014, 4),
}

# The same voice in both languages, which is what makes the two sets comparable
# rather than merely both synthetic: same family, same rate, same degradation.
VOICES = {
    "fi": "Grandma (Finnish (Finland))",
    "en": "Grandma (English (UK))",
}
RATE = 150  # words per minute; slower than the default, as with an elderly speaker


def synth(text: str, aiff: Path, lang: str) -> None:
    subprocess.run(
        ["say", "-v", VOICES[lang], "-r", str(RATE), "-o", str(aiff), text],
        check=True,
    )


def to_wav(src: Path, dst: Path) -> None:
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", "LEI16@22050", "-c", "1", str(src), str(dst)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def to_m4a(src: Path, dst: Path) -> None:
    # The same format AudioRecorder produces: AAC, mono.
    subprocess.run(
        ["afconvert", "-f", "m4af", "-d", "aac", "-c", "1", str(src), str(dst)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def degrade(src: Path, dst: Path, gain: float, noise: float, smooth: int) -> None:
    """Attenuation, background noise and a moving average (a crude low-pass)."""
    with wave.open(str(src), "rb") as w:
        params = w.getparams()
        samples = array.array("h")
        samples.frombytes(w.readframes(params.nframes))

    rng = random.Random(12345)  # reproducible: the same noise on every run
    peak = 32767
    noise_amp = noise * peak

    out = array.array("h", bytes(len(samples) * 2))
    for i, s in enumerate(samples):
        v = s * gain
        if noise_amp:
            v += rng.gauss(0, noise_amp)
        out[i] = max(-peak, min(peak, int(v)))

    if smooth > 1:
        # A moving average attenuates the high frequencies: the speech sounds
        # more muffled, as if from a distance or from an elderly speaker.
        smoothed = array.array("h", bytes(len(out) * 2))
        acc = 0
        for i in range(len(out)):
            acc += out[i]
            if i >= smooth:
                acc -= out[i - smooth]
            smoothed[i] = int(acc / min(i + 1, smooth))
        out = smoothed

    with wave.open(str(dst), "wb") as w:
        w.setparams(params)
        w.writeframes(out.tobytes())


def main() -> int:
    if sys.platform != "darwin":
        print("This script uses the macOS say and afconvert tools.")
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / ".tmp"
    tmp.mkdir(exist_ok=True)

    # The language is in the FILE NAME rather than in a flag the bench also has
    # to be told: asr-bench.mjs reads it off the name and picks the matching
    # system prompt, so one directory can hold both sets and one run measures
    # both. A flag would have to agree with the files, and one day would not.
    lang = "en" if "--lang" in sys.argv and sys.argv[sys.argv.index("--lang") + 1] == "en" else "fi"
    texts = TEXTS_EN if lang == "en" else TEXTS_FI
    print(f"Language: {lang} ({VOICES[lang]})")

    made = 0
    for base, text in texts.items():
        name = f"{lang}-{base}"
        aiff = tmp / f"{name}.aiff"
        wav = tmp / f"{name}.wav"
        synth(text, aiff, lang)
        to_wav(aiff, wav)

        for stage, (gain, noise, smooth) in STAGES.items():
            degraded = tmp / f"{name}-{stage}.wav"
            degrade(wav, degraded, gain, noise, smooth)

            base = OUT / f"{name}-{stage}"
            to_m4a(degraded, base.with_suffix(".m4a"))
            # The reference is flawless: this is exactly what was synthesised.
            base.with_suffix(".txt").write_text(text, encoding="utf-8")
            made += 1

    for f in tmp.iterdir():
        f.unlink()
    tmp.rmdir()

    print(f"Made {made} samples in {OUT}")
    print(f"  {len(texts)} texts × {len(STAGES)} degradation steps")
    print("\nRun the comparison:  node scripts/asr-bench.mjs")
    print("\nNOTE: these figures are optimistic. TTS does not produce dialect,")
    print("self-correction or sentences trailing off. Use these to CHOOSE an")
    print("engine, not to accept one.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
