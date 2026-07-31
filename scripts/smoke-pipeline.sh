#!/usr/bin/env bash
# Savutesti koko AI-putkelle: ääni → /transcribe → /extract → rakenne.
#
# TÄMÄ EI MITTAA LAATUA. Syntetisoitu puhe on selkeää, tasaista ja
# taustameluton — juuri se mitä oikea vanhuksen puhe ei ole. Jos käyttäisit
# tätä ASR:n valintaan, saisit valheellisen hyvän tuloksen. Laadun mittaamiseen
# on `scripts/asr-bench.mjs` ja oikeat nauhoitukset.
#
# Tämä vastaa vain kysymykseen "toimiiko putki päästä päähän".
#
# Vaatii että Worker on käynnissä:
#   cd backend && npx wrangler dev
#
# Käyttö (mistä tahansa hakemistosta):
#   ./scripts/smoke-pipeline.sh
#   ./scripts/smoke-pipeline.sh http://localhost:8787

set -euo pipefail

API="${1:-http://localhost:8787}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Sama muoto kuin AudioRecorder tuottaa: AAC, 22 kHz, mono.
VOICE="Grandma (Finnish (Finland))"
TEXT="No siinä kuvassa ollaan sitten sen mökin rannassa, se oli Puumalassa se mökki. Ainon kanssa me oltiin siinä ja Toivo otti sen kuvan. Se oli joskus 50-luvulla, en mä nyt muista tarkkaan."

echo "1/4  Syntetisoidaan puhe äänellä \"$VOICE\""
say -v "$VOICE" -o "$WORK/speech.aiff" "$TEXT"
afconvert -f m4af -d aac -c 1 --soundcheck-generate "$WORK/speech.aiff" "$WORK/speech.m4a" >/dev/null 2>&1 \
  || afconvert -f m4af -d aac -c 1 "$WORK/speech.aiff" "$WORK/speech.m4a"
SIZE=$(( $(stat -f%z "$WORK/speech.m4a") / 1024 ))
echo "     ${SIZE} kt"

echo "2/4  Tarkistetaan Worker: $API"
HEALTH=$(curl -sf "$API/health") || { echo "     Worker ei vastaa. Käynnistä: cd backend && npx wrangler dev"; exit 1; }
echo "     $HEALTH"
case "$HEALTH" in
  *'"hasKey":false'*) echo "     OPENROUTER_API_KEY puuttuu — lisää backend/.dev.vars:iin"; exit 1 ;;
esac

echo "3/4  POST /transcribe"
# Base64 omaan tiedostoonsa: pitkä ääni ylittäisi argumenttien kokorajan.
{ printf '{"audio":"'; base64 -i "$WORK/speech.m4a" | tr -d '\n'; printf '","format":"m4a"}'; } > "$WORK/req.json"
curl -sf -X POST "$API/transcribe" -H 'content-type: application/json' \
  --data-binary "@$WORK/req.json" > "$WORK/transcribe.json" \
  || { echo "     /transcribe epäonnistui"; exit 1; }

TRANSCRIPT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["text"])' "$WORK/transcribe.json")
echo "     \"$TRANSCRIPT\""

echo "4/4  POST /extract"
python3 -c 'import json,sys; print(json.dumps({"transcript": sys.argv[1]}))' "$TRANSCRIPT" > "$WORK/extract-req.json"
curl -sf -X POST "$API/extract" -H 'content-type: application/json' \
  --data-binary "@$WORK/extract-req.json" | python3 -m json.tool

echo
echo "Putki toimii päästä päähän. Laatu on eri kysymys — aja scripts/asr-bench.mjs oikeilla nauhoituksilla."
