#!/usr/bin/env python3
"""Generoi synteettisiä suomenkielisiä näytteitä ASR-vertailuun.

MIKSI: oikeiden nauhoitusten hankkiminen kestää, mutta moottorin valinnan voi
tehdä jo ennen sitä. Synteettisellä äänellä on yksi todellinen etu — referenssi
on virheetön, koska tiedämme täsmälleen mitä sanottiin. Käsin litteroinnissa on
omat virheensä.

MITÄ TÄMÄ EI KERRO: absoluuttista laatua. TTS ei tuota murretta, änkytystä,
itsensä korjaamista, päällekkäistä puhetta eikä sitä että lause jää kesken.
Oikea vanhus tekee kaikkea tätä. Näiden luvut ovat siis optimistisia.

MITÄ TÄMÄ KERTOO: moottoreiden keskinäisen paremmuusjärjestyksen ja sen kuinka
nopeasti kukin hajoaa kun ääni huononee. Se riittää MODEL_TRANSCRIBE-valintaan.

Rappeutus tehdään puhtaalla Pythonilla, koska koneessa ei ole ffmpegiä eikä
soxia. Kolme porrasta jäljittelevät sitä mikä oikeassa nauhoituksessa menee
pieleen: hiljainen puhuja, huoneen taustaääni ja vaimea sointi.

Käyttö:
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

# Sisältö on valittu sen mukaan mikä arkistolle merkitsee: erisnimiä, paikkoja
# ja epätarkka vuosikymmen. Nämä ohjaavat sukupuun rakentumista, joten niiden
# osuvuus painaa enemmän kuin täytesanojen.
TEXTS = {
    "mokki": (
        "Siinä kuvassa ollaan sen mökin rannassa, se oli Puumalassa se mökki. "
        "Aino oli siinä vieressäni ja Toivo otti sen kuvan. "
        "Se oli joskus viideskymmenluvulla, en muista tarkkaan."
    ),
    "sisarukset": (
        "Impi ja Tyyne olivat siskoksia. Eevertti oli heidän veljensä "
        "ja se muutti Amerikkaan eikä palannut koskaan. "
        "Hilma jäi Sotkamoon hoitamaan taloa."
    ),
    "haat": (
        "Me mentiin naimisiin vuonna kuusikymmentäkaksi Tampereella. "
        "Kaarina oli kaaso ja Väinö oli bestman. "
        "Sinä päivänä satoi kaatamalla."
    ),
}

# Portaat: nimi -> (voimakkuus, kohinan taso, vaimennuksen leveys)
# Viimeinen porras on lähinnä sitä mitä puhelin nauhoittaa olohuoneessa
# hiljaa puhuvasta ihmisestä.
STAGES = {
    "puhdas": (1.0, 0.0, 0),
    "hiljainen": (0.18, 0.0, 0),
    "kohina": (0.5, 0.010, 0),
    "vaikea": (0.15, 0.014, 4),
}

VOICE = "Grandma (Finnish (Finland))"
RATE = 150  # sanaa minuutissa; hitaampi kuin oletus, kuten iäkkäällä puhujalla


def synth(text: str, aiff: Path) -> None:
    subprocess.run(
        ["say", "-v", VOICE, "-r", str(RATE), "-o", str(aiff), text],
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
    # Sama muoto jota AudioRecorder tuottaa: AAC, mono.
    subprocess.run(
        ["afconvert", "-f", "m4af", "-d", "aac", "-c", "1", str(src), str(dst)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def degrade(src: Path, dst: Path, gain: float, noise: float, smooth: int) -> None:
    """Vaimennus, taustakohina ja liukuva keskiarvo (karkea alipäästö)."""
    with wave.open(str(src), "rb") as w:
        params = w.getparams()
        samples = array.array("h")
        samples.frombytes(w.readframes(params.nframes))

    rng = random.Random(12345)  # toistettava: sama kohina joka ajolla
    peak = 32767
    noise_amp = noise * peak

    out = array.array("h", bytes(len(samples) * 2))
    for i, s in enumerate(samples):
        v = s * gain
        if noise_amp:
            v += rng.gauss(0, noise_amp)
        out[i] = max(-peak, min(peak, int(v)))

    if smooth > 1:
        # Liukuva keskiarvo vaimentaa korkeat taajuudet: puhe kuulostaa
        # peitetymmältä, kuten kaukaa tai iäkkäältä puhujalta.
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
        print("Tämä skripti käyttää macOS:n say- ja afconvert-työkaluja.")
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / ".tmp"
    tmp.mkdir(exist_ok=True)

    made = 0
    for name, text in TEXTS.items():
        aiff = tmp / f"{name}.aiff"
        wav = tmp / f"{name}.wav"
        synth(text, aiff)
        to_wav(aiff, wav)

        for stage, (gain, noise, smooth) in STAGES.items():
            degraded = tmp / f"{name}-{stage}.wav"
            degrade(wav, degraded, gain, noise, smooth)

            base = OUT / f"{name}-{stage}"
            to_m4a(degraded, base.with_suffix(".m4a"))
            # Referenssi on virheetön: tämä on täsmälleen se mitä syntetisoitiin.
            base.with_suffix(".txt").write_text(text, encoding="utf-8")
            made += 1

    for f in tmp.iterdir():
        f.unlink()
    tmp.rmdir()

    print(f"Tehtiin {made} näytettä kansioon {OUT}")
    print(f"  {len(TEXTS)} tekstiä × {len(STAGES)} rappeutusporrasta")
    print("\nAja vertailu:  node scripts/asr-bench.mjs")
    print("\nHUOM: nämä luvut ovat optimistisia. TTS ei tuota murretta,")
    print("itsensä korjaamista eikä kesken jääviä lauseita. Käytä näitä")
    print("moottorin VALINTAAN, älä sen hyväksymiseen.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
