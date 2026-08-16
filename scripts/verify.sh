#!/usr/bin/env bash
# Everything in this repo that can fail silently, in one command.
#
#   ./scripts/verify.sh
#
# Silent is the operative word. Each of these leaves a working app behind: a
# guessing round that has given the answer away still looks like a round, an
# upsell on the wrong beat still shows a paywall, a coordinate wiped by the
# wrong device still opens a place. None of them reaches a screenshot.
#
# WHAT THIS DOES NOT RUN, and why:
#
#   * Anything that calls a model. `extract-tests.mjs` and `smoke-pipeline.sh`
#     spend OpenRouter credit on every run, and a script you feel free to run
#     twenty times a day must not cost money. Run them by hand.
#   * The UI tests, unless $KINLORE_TEST_SIM is set. They install, launch and
#     terminate one bundle id, so two sessions on one simulator kill each
#     other's process — and report accessibility failures that are not real.
#     A device of your own is the whole precondition. See CLAUDE.md.
#   * `geo-check.swift`, which asks MapKit real questions over the network.
#     It measures somebody else's gazetteer rather than this repo, so it is
#     not part of a green-or-red run.
#
# Exits non-zero on the first failure, and says which check failed.

set -uo pipefail
cd "$(dirname "$0")/.."

# This machine's xcode-select points at CommandLineTools and changing it would
# need sudo, so the full Xcode is named directly. Elsewhere — a CI runner, a
# machine with a sane xcode-select — take whatever is already selected.
XCODE=/Applications/Xcode.app/Contents/Developer
[ -d "$XCODE" ] || XCODE=$(xcode-select -p)

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

pass=0
fail=0

run() {
	local name=$1
	shift
	printf '  %-46s' "$name"
	if "$@" >"$OUT/log" 2>&1; then
		printf 'ok\n'
		pass=$((pass + 1))
	else
		printf 'FAILED\n\n'
		sed 's/^/    /' "$OUT/log"
		printf '\n'
		fail=$((fail + 1))
	fi
}

# --- The invariants that need nothing but Xcode -----------------------------

guess_mask() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -o "$OUT/guess-mask-check" \
		scripts/guess-mask-check.swift ios/Kinlore/Model/GuessRound.swift \
		&& "$OUT/guess-mask-check"
}

upsell_rhythm() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/upsell-rhythm-check" scripts/upsell-rhythm-check.swift \
		ios/Kinlore/Services/UpsellRhythm.swift \
		&& "$OUT/upsell-rhythm-check"
}

echo
echo "Invariants"
run "the hidden name stays hidden" guess_mask
run "the paid archive is offered on a rhythm" upsell_rhythm

# --- The backend ------------------------------------------------------------

echo
echo "Backend"
if [ -d backend/node_modules ]; then
	run "types" npm --prefix backend run --silent typecheck
else
	printf '  %-46s%s\n' "types" "skipped — run npm install in backend/"
fi

# Free, but it needs a Worker: it drives /sync rather than reimplementing it.
if curl -fsS --max-time 2 http://localhost:8787/health >/dev/null 2>&1; then
	run "a place's coordinates follow its title" node scripts/place-sync-check.mjs
else
	printf '  %-46s%s\n' "place coordinates through sync" \
		"skipped — no Worker (cd backend && npm run dev)"
fi

# --- The screens ------------------------------------------------------------

echo
echo "Screens"
if [ -n "${KINLORE_TEST_SIM:-}" ]; then
	ui_tests() {
		PATH="$XCODE/usr/bin:$PATH" DEVELOPER_DIR=$XCODE xcodebuild \
			-project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphonesimulator \
			-destination "platform=iOS Simulator,id=$KINLORE_TEST_SIM" test
	}
	run "49 UI tests, 26 of them accessibility" ui_tests
else
	printf '  %-46s%s\n' "accessibility and behaviour" \
		"skipped — set KINLORE_TEST_SIM to a simulator of your own"
	printf '  %-46s%s\n' "" \
		"xcrun simctl create kinlore-tests \\"
	printf '  %-46s%s\n' "" \
		"  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \\"
	printf '  %-46s%s\n' "" \
		"  com.apple.CoreSimulator.SimRuntime.iOS-26-5"
fi

echo
if [ "$fail" -gt 0 ]; then
	echo "$fail failed, $pass passed."
	exit 1
fi
echo "$pass passed."
