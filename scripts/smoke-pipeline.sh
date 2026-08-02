#!/usr/bin/env bash
# Smoke test for the whole AI pipeline: audio → /transcribe → /extract → structure.
#
# THIS DOES NOT MEASURE QUALITY. Synthesised speech is clear, steady and free of
# background noise — exactly what real elderly speech is not. If you used this to
# choose an ASR, you would get a falsely good result. For measuring quality there
# is `scripts/asr-bench.mjs` and real recordings.
#
# This only answers the question "does the pipeline work end to end".
#
# Requires a running Worker:
#   cd backend && npx wrangler dev
#
# Usage (from any directory):
#   ./scripts/smoke-pipeline.sh
#   ./scripts/smoke-pipeline.sh http://localhost:8787

set -euo pipefail

API="${1:-http://localhost:8787}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The same format AudioRecorder produces: AAC, 22 kHz, mono. The text is Finnish
# because that is what the pipeline processes.
VOICE="Grandma (Finnish (Finland))"
TEXT="No siinä kuvassa ollaan sitten sen mökin rannassa, se oli Puumalassa se mökki. Ainon kanssa me oltiin siinä ja Toivo otti sen kuvan. Se oli joskus 50-luvulla, en mä nyt muista tarkkaan."

echo "1/5  Synthesising speech with the voice \"$VOICE\""
say -v "$VOICE" -o "$WORK/speech.aiff" "$TEXT"
afconvert -f m4af -d aac -c 1 --soundcheck-generate "$WORK/speech.aiff" "$WORK/speech.m4a" >/dev/null 2>&1 \
  || afconvert -f m4af -d aac -c 1 "$WORK/speech.aiff" "$WORK/speech.m4a"
SIZE=$(( $(stat -f%z "$WORK/speech.m4a") / 1024 ))
echo "     ${SIZE} kB"

echo "2/5  Checking the Worker: $API"
HEALTH=$(curl -sf "$API/health") || { echo "     The Worker is not answering. Start it: cd backend && npx wrangler dev"; exit 1; }
echo "     $HEALTH"
case "$HEALTH" in
  *'"hasKey":false'*) echo "     OPENROUTER_API_KEY is missing — add it to backend/.dev.vars"; exit 1 ;;
esac

# /transcribe and /extract sit behind member authentication, so the smoke test
# registers a throwaway member first — the same POST /family the app makes on
# "Aloita perheen arkisto". Local D1 only; each run leaves one small row behind.
echo "3/5  Creating a throwaway member"
MEMBER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
SECRET=$(openssl rand -hex 32)
python3 - "$MEMBER_ID" "$SECRET" <<'PY' > "$WORK/family-req.json"
import json, sys
print(json.dumps({"memberID": sys.argv[1], "secret": sys.argv[2],
                  "displayName": "Smoke test", "familyName": "Smoke test"}))
PY
curl -sf -X POST "$API/family" -H 'content-type: application/json' \
  --data-binary "@$WORK/family-req.json" > "$WORK/family.json" \
  || { echo "     /family failed"; exit 1; }
AUTH="Authorization: Bearer $MEMBER_ID.$SECRET"
echo "     $(cat "$WORK/family.json")"

echo "4/5  POST /transcribe"
# Base64 into its own file: long audio would exceed the argument size limit.
{ printf '{"audio":"'; base64 -i "$WORK/speech.m4a" | tr -d '\n'; printf '","format":"m4a"}'; } > "$WORK/req.json"
curl -sf -X POST "$API/transcribe" -H 'content-type: application/json' -H "$AUTH" \
  --data-binary "@$WORK/req.json" > "$WORK/transcribe.json" \
  || { echo "     /transcribe failed"; exit 1; }

TRANSCRIPT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["text"])' "$WORK/transcribe.json")
echo "     \"$TRANSCRIPT\""

echo "5/5  POST /extract"
python3 -c 'import json,sys; print(json.dumps({"transcript": sys.argv[1]}))' "$TRANSCRIPT" > "$WORK/extract-req.json"
curl -sf -X POST "$API/extract" -H 'content-type: application/json' -H "$AUTH" \
  --data-binary "@$WORK/extract-req.json" | python3 -m json.tool

echo
echo "The pipeline works end to end. Quality is a different question — run scripts/asr-bench.mjs on real recordings."
