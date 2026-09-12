#!/usr/bin/env bash
# Everything in this repo that can fail silently, in one command.
#
#   ./scripts/verify.sh
#
# Silent is the operative word. Each of these leaves a working app behind: an
# upsell on the wrong beat still shows a paywall, a coordinate wiped by the
# wrong device still opens a place, a transcript stripped by the second push
# still lists a memory. None of them reaches a screenshot.
#
# The guessing round used to head that list, and its check was the reason this
# file exists. The round was cut on 16 Aug 2026 (PLAN.md §5, row 8) and the
# check went with it.
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

upsell_rhythm() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/upsell-rhythm-check" scripts/upsell-rhythm-check.swift \
		ios/Kinlore/Services/UpsellRhythm.swift \
		&& "$OUT/upsell-rhythm-check"
}

# The family's bytes on every phone: what the full copy fetches after a sync,
# in what order, and what stops it. Every rule is silent when wrong — a copy
# that never starts looks exactly like one that is complete.
full_copy() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/full-copy-check" scripts/full-copy-check.swift \
		ios/Kinlore/Services/FullCopy.swift \
		&& "$OUT/full-copy-check"
}

# Which question the app decides to put in front of an 80-year-old. A
# staircase over three UserDefaults keys, and both ways of being wrong are
# silent: the wall that makes an elderly teller give up, and the run of naming
# questions somebody has long outgrown. Added 11 Sep 2026, and it found a
# defect on its first run — three weeks away PROMOTED a beginner, which is
# dormancy's own reason inverted on the person least likely to come back.
question_ladder() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/question-ladder-check" scripts/question-ladder-check.swift \
		ios/Kinlore/Services/QuestionLadder.swift ios/Kinlore/Model/Models.swift \
		&& "$OUT/question-ladder-check"
}

# Hermetic in a different way: it loads the shipping schema.sql into an
# in-memory SQLite and asks the database itself. No Worker, no D1, no
# RevenueCat — and the TypeScript guard it backs up cannot be run on this
# machine at all, which is why the rule underneath it is worth checking.
entitlement_binding() {
	node scripts/entitlement-binding-check.mjs
}

# The sealing itself, no Worker needed. This was a run-by-hand command in
# CLAUDE.md until 24 Aug 2026, when it turned out to have stopped COMPILING
# a week earlier — the guessing round's cut removed a field it referenced,
# and its own instruction said to run it only after touching FamilyCrypto,
# which nobody had. A check that does not build is the quietest green there
# is, so it runs here now, on every verify.
family_crypto() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/family-crypto-check" scripts/family-crypto-check.swift \
		ios/Kinlore/Services/FamilyCrypto.swift \
		ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Model/Models.swift \
		&& "$OUT/family-crypto-check"
}

# Rule 5 turned into a picture. A pin asserts a point, and a municipality is
# not one — so what may be drawn is arithmetic over `GeoPrecision`, and it is
# wrong in the one way a screenshot cannot show: a pin on the wrong doorstep
# looks exactly as confident as a pin on the right one.
place_map() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/place-map-check" scripts/place-map-check.swift \
		ios/Kinlore/Model/Models.swift \
		&& "$OUT/place-map-check"
}

# Whether a browser can open what the phone sealed — the claim every argument
# for reaching an Android relative rests on, and one that was used in both
# directions before anybody measured it. `webcrypto.subtle` is the same API a
# page gets, so what passes here passes in Safari. No Worker, no key, no
# network.
webcrypto_interop() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/webcrypto-interop-check" scripts/webcrypto-interop-check.swift \
		ios/Kinlore/Services/FamilyCrypto.swift \
		&& "$OUT/webcrypto-interop-check" emit \
		| node scripts/webcrypto-interop-check.mjs "$OUT/webcrypto-return.json" \
		&& "$OUT/webcrypto-interop-check" verify "$OUT/webcrypto-return.json"
}

echo
echo "Invariants"
# First, because it is the only failure here that cannot be undone by the next
# commit. The repository goes public on 28 Sep and publishes its history rather
# than its head, so a key committed today and deleted tomorrow is published
# anyway. Rule 7's instruction was "check .dev.vars before every push", which is
# a reminder rather than a check; this is the check. It scans the tree, every
# blob that has ever existed, and the two halves of the mechanism — and tests
# its own matcher against a specimen of each shape, so it cannot go quietly
# green. Takes about a third of a second.
run "no key is in the tree, and none ever was" node scripts/secret-check.mjs
run "the paid archive is offered on a rhythm" upsell_rhythm
run "nobody is asked more than they can answer" question_ladder
run "the family's bytes end up on every phone" full_copy
run "a wrong key opens nothing, a title seals stably" family_crypto
run "one purchase unlocks one family" entitlement_binding
# The webhook's revocation rules, driven through the real handleWebhook over
# the shipping schema in in-memory SQLite. The rule is RevenueCat's and it was
# assumed wrong once: auto-renew going off — the most common subscriber act —
# locked the family out of a month somebody had paid for.
run "a cancelled payer keeps the paid month" node scripts/webhook-revocation-check.mjs
# The other half of the purchase arc, and the one ARCHITECTURE §1 called unrun
# until 1 Sep 2026: /entitlement/sync does not accept a state from the client,
# it asks RevenueCat. The real syncEntitlement over the shipping schema with
# fetch replaced — no key, no network, nothing spent. Nine deliberate breakages
# were each caught before this line was added, including one that made the run
# print its own green closing sentence and then a stack trace.
run "the purchase is verified rather than believed" node scripts/entitlement-sync-check.mjs
# Rule 8, without making the request. `complete()` is imported straight out of
# openrouter.ts — Node runs TypeScript as it is — and fetch is replaced with
# something that keeps the body. Nothing leaves the machine and nothing is
# spent, which matters twice here: the one thing a check must never do is send
# a family's words upstream to prove they are being protected.
run "no request offers the memories for training" node scripts/data-collection-check.mjs
# The three below were run by hand and by nothing else, and each costs nothing
# — no simulator, no Worker, no key, no network. That is the whole argument for
# moving them here, and it is `family_crypto`'s argument above, made once
# already by a check that had quietly stopped compiling for a week: an
# instruction to run something "after touching X" is not a check, it is a
# reminder, and it is only as good as whoever last read it.
run "only a point may be drawn as a point" place_map
run "a long telling is given room to come back" node scripts/transcribe-budget-check.mjs
# The two pure functions between the model's JSON and the family's archive.
# Unreachable by any check until 12 Sep 2026 — not for want of value but for
# want of a loader, since Node cannot resolve extract.ts's extensionless
# import. A `.ts` on that one specifier fixed it. Both were wrong: an empty
# name became a person the family is asked to confirm, drawn as "Henkilö",
# and an untrimmed one became a second Aino.
run "a model cannot name a person nothing said" node scripts/extract-shaping-check.mjs
run "a browser can open what the phone sealed" webcrypto_interop

# --- What the documents say about the code ----------------------------------

# ARCHITECTURE.md §1 has twice carried a number that was simply wrong: 41 UI
# tests when there were 49, and "20 screens" that no file in this repository
# produces. Neither was caught by reading, and neither could be — a plausible
# number reads exactly like a true one, and that is the whole difficulty. Both
# survived until somebody counted, months after they stopped being true.
#
# This checks nothing about the prose. It counts the two claims that can be
# counted, and it fails if the sentence they live in was reworded away, because
# a check that has quietly stopped checking is the thing this file exists for.
# All three documents state the counts, in different words, and README.md was
# already a version behind ARCHITECTURE.md when this was written. So all three
# are checked: one file carrying the truth is exactly how another gets to keep
# lying.
#
# CLAUDE.md joined the list on 11 Sep 2026, and it is the argument against a
# flag that is global rather than per-file. It said "32 accessibility audits" —
# exactly right at 9aa6c07 on 28 Aug 2026, when `try sweep(` counted 32 — and
# was 24 behind by the time anybody counted, because this function read the
# other two files and never opened the one every session reads first. So each
# document must now state a count of its own: a sentence reworded away in one
# of them can no longer hide behind another still carrying it.
doc_counts() {
	local bad=0 seen_tests=0 seen_sweeps=0 seen_here
	local tests sweeps doc said

	tests=$(grep -rhE '^[[:space:]]+func test' ios/KinloreUITests/*.swift | wc -l | tr -d ' ')
	sweeps=$(grep -cE 'try sweep\(' ios/KinloreUITests/AccessibilitySweepTests.swift)

	for doc in docs/ARCHITECTURE.md README.md CLAUDE.md; do
		seen_here=0

		said=$(grep -oE '[0-9]+ UI tests' "$doc" | head -1 | grep -oE '^[0-9]+')
		if [ -n "$said" ]; then
			seen_tests=1
			seen_here=1
			[ "$said" = "$tests" ] || {
				echo "$doc says $said UI tests. Counted in ios/KinloreUITests: $tests"
				bad=1
			}
		fi

		said=$(grep -oE '[0-9]+ (of them an accessibility sweep|sweep tests|accessibility (sweeps|audits))' "$doc" \
			| head -1 | grep -oE '^[0-9]+')
		if [ -n "$said" ]; then
			seen_sweeps=1
			seen_here=1
			[ "$said" = "$sweeps" ] || {
				echo "$doc says $said sweep tests. Counted sweep() calls: $sweeps"
				bad=1
			}
		fi

		[ "$seen_here" = 1 ] || {
			echo "$doc states neither count any more"
			bad=1
		}
	done

	# Silence is the failure this is really guarding against. The per-document
	# guard above catches one file going quiet; these two catch every file
	# going quiet at once, which would otherwise pass while checking nothing.
	[ "$seen_tests" = 1 ] || { echo "no document states a UI test count any more"; bad=1; }
	[ "$seen_sweeps" = 1 ] || { echo "no document states a sweep count any more"; bad=1; }

	return $bad
}

echo
echo "Docs"
run "the test counts the documents state" doc_counts
# The site had no check at all until 30 Aug 2026, which made it the one surface
# here whose only guard was somebody looking. Two defects had already gone
# through: a page with no <h1> for a screen reader to find, and a line that
# said the same thing twice in one language and not the other. Costs nothing —
# no browser, no network.
run "the site says each thing once, in one language" node scripts/page-check.mjs
# The app gained English on 30 Aug 2026, in the cheapest shape there is: the
# Finnish literals in the source are the lookup keys, so nothing had to change
# except one table. Which means nothing warns you when a new Text() has no
# translation — the Finnish build is perfect and the English one shows one
# Finnish word in the middle of a screen nobody runs except on filming night.
# It found six missing dialog titles the hour it was written.
run "every string the app shows has an English one" node scripts/localisation-check.mjs

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
	# The same again for subjects, and this one found a defect rather than
	# confirming a rule: a date the family was careful about was erased by any
	# push from a phone that had not seen it.
	run "a date survives an older phone" node scripts/subject-rules-check.mjs
	# The pull cursor, which is the delivery guarantee itself: a number that
	# runs ahead skips other members' rows silently and forever. Three defects
	# lived in it (23 Aug 2026, §3) and every one looked like a working app.
	run "a telling reaches the phone that was pushing" node scripts/sync-cursor-check.mjs
	# PLAN §10 lever 3, end to end: the app's own sealing transforms pushed and
	# pulled as two identities through the running Worker, the key crossing only
	# in the invite text, the R2 bytes making the same trip. First production
	# run 24 Aug 2026; this keeps the local Worker honest about the same claims.
	lever3_roundtrip() {
		DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
			-o "$OUT/lever3-roundtrip-check" scripts/lever3-roundtrip-check.swift \
			ios/Kinlore/Services/FamilyCrypto.swift \
			ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Model/Models.swift \
			&& "$OUT/lever3-roundtrip-check" http://localhost:8787
	}
	run "a sealed memory crosses between two phones" lever3_roundtrip
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
		#
		# IN FINNISH, and this file was running them in the device's own
		# language until 12 Sep 2026. The tests query the accessibility tree by
		# the words on screen and those words are Finnish; the app's default is
		# English and follows the device. Counted on the day the flags were
		# added: of the 121 distinct strings the suite asks for by name, 93
		# translate to something else in en.lproj — "Tutut nimet" to "Familiar
		# names", "Hylkää" to "Reject" — so on an English device most of the
		# suite looks for text that is not there.
		#
		# The skip message below tells you to create a simulator, and a fresh
		# one is English. So this file was handing somebody a device and then
		# failing them on it, which is the same wasted hour CLAUDE.md describes
		# for a shared device and looks exactly as convincing.
		PATH="$XCODE/usr/bin:$PATH" DEVELOPER_DIR=$XCODE xcodebuild \
			-project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphonesimulator \
			-destination "platform=iOS Simulator,id=$KINLORE_TEST_SIM" \
			-derivedDataPath "$OUT/DerivedData-$KINLORE_TEST_SIM" \
			-testLanguage fi -testRegion FI test
	}
	# No count in the label: doc_counts above owns the numbers, and a label
	# that carried its own copy sat seven behind before anyone noticed.
	run "the UI suite, accessibility sweeps included" ui_tests
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
