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

# What is on disk is what gets measured, and in this worktree what is on disk is
# not always yours. A run against somebody else's half-finished edit reports
# their intermediate state under your name: it happened with a `VStack` in a
# footer that stopped its text scaling, was reported as two failing onboarding
# screens, and passed on the same commit an hour later because they had already
# fixed it. Said out loud rather than guarded against — a dirty tree is the
# normal way to work, and the only thing missing was knowing it.
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "${dirty:-0}" != "0" ]; then
	echo "Note: $dirty file(s) uncommitted — this measures the working tree, including"
	echo "      anything another session is in the middle of. git status to see whose."
	echo
fi

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

# Hermetic in a different way: it loads the shipping schema.sql into an
# in-memory SQLite and asks the database itself. No Worker, no D1, no
# RevenueCat — and the TypeScript guard it backs up cannot be run on this
# machine at all, which is why the rule underneath it is worth checking.
entitlement_binding() {
	node scripts/entitlement-binding-check.mjs
}

echo
echo "Invariants"
run "the hidden name stays hidden" guess_mask
run "the paid archive is offered on a rhythm" upsell_rhythm
run "one purchase unlocks one family" entitlement_binding

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
	run "two phones end up in one family" node scripts/family-sync-check.mjs
	run "a place's coordinates follow its title" node scripts/place-sync-check.mjs
	# The refusals rather than the happy path: §4 calls the invite link the
	# entire security boundary, and a revoked code that still works looks
	# exactly like a working app.
	run "a taken-back invite stays taken back" node scripts/invite-boundary-check.mjs
	# Rule 2 is the shortest rule this app has, and nothing checked it: the
	# quota limits photographs and minutes, never the act of saying something.
	run "the quota never stops a telling" node scripts/quota-check.mjs
	# The photographs and the voices, and who can reach them. Locally R2 is
	# simulated by wrangler, so this touches no real storage.
	run "media comes back, and only to its family" node scripts/media-check.mjs
	# There is no login, so `authenticate` is the whole of it — and the rule
	# nothing else covers is the departed member: the row is kept so the names
	# on their memories still resolve, which makes "in the database" and "in the
	# family" two different things.
	run "a session ends when the member leaves" node scripts/session-boundary-check.mjs
	# The second push of the same memory, which is where the damage lives: rule
	# 3's stickiness, §16's empty body, and the two about who is speaking.
	run "a second push cannot unwrite a telling" node scripts/memory-rules-check.mjs
	# The two unauthenticated doors. Measured by hand once (§4); this is the
	# part that runs again when somebody edits wrangler.jsonc.
	run "the two open doors are metered, per address" node scripts/rate-limit-check.mjs
else
	printf '  %-46s%s\n' "the family path, places and the invite boundary" \
		"skipped — no Worker (cd backend && npm run dev)"
fi

# Rule 9, in both halves — and this one needs no Worker running, because it
# brings its own: reading a log means owning the process that writes it. That
# Worker is started with no key, so the upstream call throws before it reaches
# the network and the check costs nothing.
run "a failure tells the app and the log nothing" node scripts/leak-check.mjs

# --- The screens ------------------------------------------------------------

echo
echo "Screens"
if [ ! -e ios/Kinlore.xcodeproj ]; then
	# XcodeGen writes it and it is not in the repository, so a fresh checkout
	# has none. Said plainly here: xcodebuild's own answer is "does not exist",
	# which reads like a broken project rather than an ungenerated one.
	printf '  %-46s%s\n' "accessibility and behaviour" \
		"skipped — cd ios && xcodegen generate"
elif [ -n "${KINLORE_TEST_SIM:-}" ]; then
	ui_tests() {
		# A build directory of its own, for the same reason the simulator is
		# already one: two sessions work in this worktree at once. Sharing the
		# default DerivedData with somebody else's build fails as
		#
		#   error: unable to attach DB: … build.db: database is locked
		#   Possibly there are two concurrent builds running in the same
		#   filesystem location.
		#
		# which reads like a broken build and is not one — the same shape as the
		# accessibility failures CLAUDE.md warns about on a shared device. Keyed
		# by the simulator, so two people running this at once get one each.
		PATH="$XCODE/usr/bin:$PATH" DEVELOPER_DIR=$XCODE xcodebuild \
			-project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphonesimulator \
			-destination "platform=iOS Simulator,id=$KINLORE_TEST_SIM" \
			-derivedDataPath "$OUT/DerivedData-$KINLORE_TEST_SIM" test
	}
	run "49 UI tests, 26 of them accessibility" ui_tests
	# After the tests, because it needs the app installed and they install it.
	# XCUITest cannot do this one: the zip lands in the app's container and the
	# test runner is not allowed to look inside it.
	run "the export opens on any computer" node scripts/export-check.mjs
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
