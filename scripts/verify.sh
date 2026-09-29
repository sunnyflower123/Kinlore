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

# Colour from a model, brightness from the photograph. The one thing between
# an image model's reply and a family's photograph, and all three of its
# promises fail silently: a lock that kept the model's lightness still makes a
# fine colour photograph with every face repainted, a reply whose shapes moved
# still looks like one, and a ratio stretched instead of framed spends a
# family's round on a refusal.
colour_lock() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/colour-lock-check" scripts/colour-lock-check.swift \
		ios/Kinlore/Services/ColourLock.swift \
		&& "$OUT/colour-lock-check"
}

# The same colouring through sync, on the phone's side: a pull from a Worker
# that was not redeployed must not wipe the family's confirmed colours, a yes
# not yet uploaded must survive an older one arriving, and another phone's
# newer yes must not be shown with this phone's old picture under it.
colour_sync() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/colour-sync-check" scripts/colour-sync-check.swift \
		ios/Kinlore/Services/FamilyCrypto.swift ios/Kinlore/Data/MemoryStore+Sync.swift \
		ios/Kinlore/Model/Models.swift \
		&& "$OUT/colour-sync-check"
}

# Every field of the four synced models, through sync. A pull replaces the
# rows it brings, so a field `init?(dto:)` leaves out goes back to its default
# on every one of them — and a build that reads a new kind pulls the whole
# family again from zero. A relationship somebody confirmed turns back into a
# proposal, and the screen looks exactly as it would if nobody had.
sync_fields() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/sync-fields-check" scripts/sync-fields-check.swift \
		ios/Kinlore/Services/FamilyCrypto.swift ios/Kinlore/Data/MemoryStore+Sync.swift \
		ios/Kinlore/Model/Models.swift \
		&& "$OUT/sync-fields-check"
}

# The facts on a person's card, on the phone's side (ARCHITECTURE §26). A
# list inside one sealed column, and three ways of being wrong that no screen
# shows: a kind this build has no word for must come out of the decoder and go
# back in as it came, or the first phone to edit the card writes the family's
# list back without it; the wire carries ciphertext only, so the server can
# read no name and no trade; and two phones' lists are joined rather than
# chosen between, with a removal that stays a removal however many older
# copies arrive. Costs nothing — no simulator, no Worker.
person_facts() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/facts-check" scripts/facts-check.swift \
		ios/Kinlore/Services/FamilyCrypto.swift ios/Kinlore/Data/MemoryStore+Sync.swift \
		ios/Kinlore/Model/Models.swift \
		&& "$OUT/facts-check"
}

# A telling filed under a card somebody merged away, on every phone and not
# only the merging one. The server keeps the forwarding address and refuses
# to re-point another member's telling, so each phone moves it itself — and
# a telling that is on no card looks exactly like one nobody told.
merge_chain() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/merge-chain-check" scripts/merge-chain-check.swift \
		ios/Kinlore/Services/MergeChain.swift ios/Kinlore/Model/Models.swift \
		&& "$OUT/merge-chain-check"
}

# What the album's search finds when somebody types a year. "2000" found
# nothing on 28 Sep 2026 in an album with photographs from 2003 and 2015 in it,
# and every way of reading a year wrongly is as silent: a century where a
# decade was meant, a side of a year off by one, an undated photograph found by
# a date nobody knows. The grid is tidy either way. Also holds that a search
# with no year in it finds what it found before, and the time a keystroke takes
# over a thousand photographs.
archive_search() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/archive-search-check" scripts/archive-search-check.swift \
		ios/Kinlore/Services/ArchiveSearch.swift ios/Kinlore/Services/MergeChain.swift \
		ios/Kinlore/Model/Models.swift \
		&& "$OUT/archive-search-check"
}

# Which decade the album files a photograph under, on a phone in any zone.
# Every date in the archive is midnight in Helsinki, and until 28 Sep 2026 the
# headings read it on the phone's own calendar: in Los Angeles the date sheet's
# "1950s" is 31.12.1949, so on every phone west of Finland the fifties sat
# among the forties, and a heading reads as right whatever it says.
decade() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/decade-check" scripts/decade-check.swift ios/Kinlore/Model/Models.swift \
		&& "$OUT/decade-check"
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

# When an answer in the conversation is over without anybody saying so: 25
# seconds of silence, or ten minutes of anything. Both ways of being wrong are
# silent — an answer cut while somebody is remembering what came next, or a
# microphone the loop opened recording an empty room on a screen that never
# sleeps — and a screenshot of either shows "Kuuntelen". Added 27 Sep 2026.
answer_watch() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/answer-watch-check" scripts/answer-watch-check.swift \
		ios/Kinlore/Recording/AnswerWatch.swift \
		&& "$OUT/answer-watch-check"
}

# What the model is told about the family's archive before it writes a
# follow-up question. Until 19 Sep 2026 it was told nothing but the transcript,
# so it could only ask about a gap in ninety seconds of speech and asked the
# same three shapes on the fourth telling as on the first. Every way the
# context can be wrong is silent: a gap reported that is not one spends the
# single question an 80-year-old will answer, a gap missed stays a hole, and a
# fresh question discarded as a repeat is a hole nobody hears about again.
extraction_context() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/extraction-context-check" scripts/extraction-context-check.swift \
		ios/Kinlore/Services/ExtractionContext.swift ios/Kinlore/Model/Models.swift \
		&& "$OUT/extraction-context-check"
}

# What the app is willing to believe a model said about WHEN. The reply carries
# years and nothing finer while its precision may say "day" or "month", so a
# telling that mentioned a month used to be stored AS a month — built on the
# first of January and read back off the card as *tammikuu 1957*, a date nobody
# gave. Rule 5 inverted, and silent: a wrong date is as short and as confident
# a line as a right one. Added 19 Sep 2026, the day the shaping was fixed,
# because the fix was reasoned rather than measured.
# How often the app asks again for text it never got, and what it blames on
# the moment rather than on the recording. Both are silent in both directions:
# too forgiving and unusable audio costs paid minutes on every launch for ever,
# too strict and a week without signal abandons a good recording. Since 26 Sep
# 2026 the tally slows the asking down instead of ending it — a day after the
# third refusal, doubling, thirty days at most, and a tally the old rule left
# behind due at once — and every one of those numbers is held here. The tally is
# executed — `TranscriptionAttempts` sits in a file of its own so that it can
# be, since DeferredMemory.swift reaches three files that import UIKit — and
# the classifier beside it is read rather than run, which the check says of
# itself.
transcription_catchup() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/transcription-catchup-check" scripts/transcription-catchup-check.swift \
		ios/Kinlore/Services/TranscriptionAttempts.swift \
		&& "$OUT/transcription-catchup-check"
}

date_hint() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library -enable-bare-slash-regex \
		-o "$OUT/date-hint-check" scripts/date-hint-check.swift \
		ios/Kinlore/Services/AppServices.swift ios/Kinlore/Model/Models.swift \
		ios/Kinlore/Services/StoryComposer.swift \
		ios/Kinlore/Services/Extraction.swift ios/Kinlore/Services/ExtractionContext.swift \
		ios/Kinlore/Services/PurchaseService.swift ios/Kinlore/Services/Transcription.swift \
		ios/Kinlore/Services/Colourisation.swift ios/Kinlore/Services/RelationWords.swift \
		&& "$OUT/date-hint-check"
}

# A memory's text naming a relative the teller never mentioned: "Toivo, our
# dad, always had the camera." from an answer that said "Toivo did." Added
# 28 Sep 2026, when that sentence reached a card in a take for the demo film,
# the teller a synthetic voice. Rule 4's wrong relationship in her own voice,
# and silent: the sentence reads like hers.
relation_words() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/relation-words-check" scripts/relation-words-check.swift \
		ios/Kinlore/Services/RelationWords.swift \
		&& "$OUT/relation-words-check"
}

# Which names the blind card deals beside the proposal, and which seat the
# answer takes. Added 29 Sep 2026: every card got the archive's three newest
# confirmed people, so in `-seed large` the one name that changed from card to
# card was the answer. Silent, because each card alone is a fair question.
blind_card() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/blind-card-check" scripts/blind-card-check.swift \
		ios/Kinlore/Services/BlindConfirmation.swift ios/Kinlore/Model/Models.swift \
		&& "$OUT/blind-card-check"
}

# Where the family tree puts people and the lines between them. Pure arithmetic
# over confirmed people and relationships, and each way of being wrong is
# silent: a child drawn a row above her mother still draws. Added 13 Sep 2026
# with the drawn tree; engine and check both rewritten from zero 25 Sep 2026.
family_tree_layout() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/family-tree-layout-check" scripts/family-tree-layout-check.swift \
		ios/Kinlore/Services/FamilyTreeLayout.swift \
		&& "$OUT/family-tree-layout-check"
}

# The word under every card in the tree, from the phone owner's point of
# view. A wrong word is rule 4's wrong relationship drawn as fact, and it is
# silent: *Serkkusi* on a card looks exactly like *Pikkuserkkusi* to anybody
# who does not already know. Added 25 Sep 2026 with the words.
kinship() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/kinship-check" scripts/kinship-check.swift \
		ios/Kinlore/Services/Kinship.swift \
		&& "$OUT/kinship-check"
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

# And that the seal is applied. A phone that had lost the family key pushed
# and uploaded in the clear until 26 Sep 2026, and emptying another phone on
# the same Apple ID is one way to lose it. That looks exactly like a round
# that worked, and the words are then on the server for good.
keyless_sync() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/keyless-sync-check" scripts/keyless-sync-check.swift \
		ios/Kinlore/Data/Identity.swift ios/Kinlore/Services/FamilyCrypto.swift \
		ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Model/Models.swift \
		&& "$OUT/keyless-sync-check"
}

# The story on a card, on the phone's side (§27): when the model is asked at
# all, which is the cost; that a person's correction is never composed over,
# which is rule 4 in the story's clothes; what two phones settle on, which
# `sync.ts` cannot judge through a seal; and that a story written by one
# build reads on another, rule 10 both ways. None of it shows in a picture.
story_rules() {
	DEVELOPER_DIR=$XCODE xcrun swiftc -parse-as-library \
		-o "$OUT/story-check" scripts/story-check.swift \
		ios/Kinlore/Services/StoryComposer.swift ios/Kinlore/Model/Models.swift \
		ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Services/FamilyCrypto.swift \
		&& "$OUT/story-check"
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
# commit. The repo goes public at submission and publishes its history rather
# than its head, so a key committed today and deleted tomorrow is published
# anyway. Rule 7's instruction was "check .dev.vars before every push", which is
# a reminder rather than a check; this is the check. It scans the tree, every
# blob that has ever existed, and the two halves of the mechanism — and tests
# its own matcher against a specimen of each shape, so it cannot go quietly
# green. Takes about a third of a second.
run "no key is in the tree, and none ever was" node scripts/secret-check.mjs
run "the paid archive is offered on a rhythm" upsell_rhythm
run "nobody is asked more than they can answer" question_ladder
run "a silent answer ends, a pause does not" answer_watch
run "a question aims at what the archive lacks" extraction_context
run "no date is sharper than what was said" date_hint
run "no memory names a relative nobody said" relation_words
run "no two blind cards give the answer away" blind_card
run "the app asks again later, and not for the weather" transcription_catchup
run "a child is drawn below her parents" family_tree_layout
run "every word in the tree is exact" kinship
run "the family's bytes end up on every phone" full_copy
run "a photograph keeps its face under new colours" colour_lock
run "a confirmed colouring survives an older phone" colour_sync
run "a pull from zero changes nothing here" sync_fields
run "a fact of a kind this build has no word for survives it" person_facts
run "a merged card's tellings reach its survivor" merge_chain
run "a year finds the photographs of its time" archive_search
run "the fifties are the fifties on any phone" decade
run "a wrong key opens nothing, a title seals stably" family_crypto
run "a phone with no key sends the family nothing" keyless_sync
run "a person's story is never composed over" story_rules
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
# And the state neither of those two can produce: the word says paid and the
# date has passed, which only a missed webhook makes. Both halves are silent
# when wrong — a reconciliation that never fires looks like one with nothing to
# do, and one that downgrades on a timeout looks like a subscription that
# ended. Seven deliberate breakages, seven caught, before this line was added.
run "a stale tier is re-asked, not guessed" node scripts/entitlement-reconcile-check.mjs
# What a stranger can spend in a day. Every free-tier limit belongs to a family
# and a family costs nothing, so until 26 Sep 2026 only the credit limit on the
# OpenRouter account bounded a day's bill. The real Worker over the shipping
# schema with fetch replaced, each D1 statement a turn of the event loop so that
# calls made together interleave as they do in production — without the turn, a
# meter that checks and then writes passed here. Red on 24 of its 44 against the
# code before the ceiling, and thirteen deliberate breakages of the ceiling,
# thirteen caught, before this line was added.
run "a stranger's day is bounded, a telling is not" node scripts/free-tier-ceiling-check.mjs
# A question asked of one member by name, and the two notifications it can
# cause. The real push, pull and notify over the shipping schema with fetch
# replaced: an aim that does not resolve is stored as nothing instead of
# failing the whole batch, only the asker aims, a notice fires on a change and
# never on a re-send, and the log carries neither a token nor a name.
run "a question asked by name reaches the one it was asked of" node scripts/targeted-question-check.mjs
# A telling taken back and brought back by its teller, and by nobody else.
# The real push and pull over the shipping schema in an in-memory SQLite: a
# stale copy can neither revive a tombstone nor bury a restoration, only the
# author's hand does either, the later of the two moments is the state, and
# the pull answers that state so a phone built before the column sees it
# too. Red on nine of its twenty against the code before the column.
run "a taken-back telling comes back by its teller's hand alone" node scripts/memory-restore-check.mjs
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
# The twenty-five contrast ratios written into Elder.swift, measured against
# the assets the app ships. Rule 1 says contrast is the one thing eyes cannot
# check, and those numbers are the argument for every colour in the app —
# nothing verified any of them until 12 Sep 2026. `page-check.mjs` already
# does this for the six tokens in kinlore.css; the palette had no equivalent.
# The audit reads real pixels and is better, and it needs a quiet machine:
# three runs in a row proved it cannot be trusted under load. This answers at
# any load, so the two are not alternatives.
run "the palette still measures what it claims" node scripts/palette-contrast-check.mjs
# The accessibility audit's exemption list, which is the one place in this
# repository where rule 1 is switched off by name. Twenty-one clauses forgive
# a finding the audit would otherwise report, and twenty of them are a clause
# somebody has to write and review. One is not: it forgives by matching a
# sentence in a literal, so it widens by a line. This pins the sentences
# in that set and the two audit types the gate answers for, and fails if
# `.contrast` ever joins them — forgiven by label, contrast would be rule 1
# switched off by name and nothing would say so. Falsified three ways before it
# was believed: a fourth sentence, a reworded third with the count unchanged,
# and `.contrast` added to the gate.
run "the audit forgives only what was measured" node scripts/audit-exemption-check.mjs
# The sentence in the "Tyhjennä tämä laite" dialog, against the function that
# has to make it true. Six services keep a device-local record in UserDefaults
# — the ladder's comfort, the upsell rhythm, the deck's skips, the seen list,
# the blind card's answers, the transcription tally — and their eight keys are
# cleared because somebody remembered to add a line to `wipe()`. Each of them
# says "part of emptying the device" in a comment, which is a reminder and not
# a check, and the seventh will be written by somebody who has not read the
# other six. So the rule is read out of the source and a new service joins it
# by existing. A key that is only ever READ is a launch argument rather than a
# record — eight of those live in the same files, and the first matcher here
# reported all eight. Falsified four ways: a reset dropped from the wipe, a
# seventh service that stores and forgets, a key its own reset stopped
# clearing, and `wipe()` renamed.
run "the device wipe forgets every record of her" node scripts/device-wipe-check.mjs
run "only a point may be drawn as a point" place_map
run "a long telling is given room to come back" node scripts/transcribe-budget-check.mjs
# The two pure functions between the model's JSON and the family's archive.
# Unreachable by any check until 12 Sep 2026 — not for want of value but for
# want of a loader, since Node cannot resolve extract.ts's extensionless
# import. A `.ts` on that one specifier fixed it. Both were wrong: an empty
# name became a person the family is asked to confirm, drawn as "Henkilö",
# and an untrimmed one became a second Aino.
run "a model cannot name a person nothing said" node scripts/extract-shaping-check.mjs
# The story's card as the model sees it and the reply as the Worker believes
# it: an unconfirmed name is marked for the prompt, a name the family never
# confirmed cannot pass as fact, the tellings are numbered oldest first, and
# the budget is the story's length and not a guess. Costs nothing.
run "a story is composed from what was told, marked where unconfirmed" node scripts/story-shaping-check.mjs
# Colouring a photograph by what was told: what the model is told, what the
# Worker believes came back, and a meter of its own, so that a grandchild's
# colouring cannot use up a grandmother's telling minutes. None of the three
# shows in a picture, and all of them cost nothing to check.
run "a photograph is coloured by what was told" node scripts/colourise-check.mjs
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
#
# docs/DETAILS.md joined the list when the README was split, which makes four.
# It holds the long README word for word, count row included, and the short
# README that replaced it still states both numbers in a sentence of its own.
#
# CLAUDE.md left the list when it was cut down, because it no longer states a
# count. The sentence that did moved word for word to docs/DEVELOPMENT.md,
# which is checked in its place.
doc_counts() {
	local bad=0 seen_tests=0 seen_sweeps=0 seen_here
	local tests sweeps doc said hit

	tests=$(grep -rhE '^[[:space:]]+func test' ios/KinloreUITests/*.swift | wc -l | tr -d ' ')
	sweeps=$(grep -cE 'try sweep\(' ios/KinloreUITests/AccessibilitySweepTests.swift)

	# Every mention, not only the first. ARCHITECTURE.md §1 states both counts
	# twice since 28 Sep 2026, and a second copy nobody checks is the one that
	# drifts. Each hit is "line:count".
	for doc in docs/ARCHITECTURE.md README.md docs/DETAILS.md docs/DEVELOPMENT.md; do
		seen_here=0

		for hit in $(grep -noE '[0-9]+ UI tests' "$doc" | cut -d' ' -f1); do
			seen_tests=1
			seen_here=1
			said=${hit#*:}
			[ "$said" = "$tests" ] || {
				echo "$doc:${hit%%:*} says $said UI tests. Counted in ios/KinloreUITests: $tests"
				bad=1
			}
		done

		for hit in $(grep -noE '[0-9]+ (of them an accessibility sweep|sweep tests|accessibility (sweeps|audits))' "$doc" \
			| cut -d' ' -f1); do
			seen_sweeps=1
			seen_here=1
			said=${hit#*:}
			[ "$said" = "$sweeps" ] || {
				echo "$doc:${hit%%:*} says $said sweep tests. Counted sweep() calls: $sweeps"
				bad=1
			}
		done

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

# And the question before that one. The check above asks whether every key has
# an English translation; it cannot ask whether the string is LOOKED UP at all,
# because it counts keys, and a literal that reaches the screen as a `String` is
# not a key to it. So the table can be complete, this file green, the Finnish
# build perfect, and an English phone still show one Finnish sentence in the
# middle of a screen. Six of those have been found here, every one by accident:
# three by running the app in English and reading it, "Valokuva" by a
# screenshot, and two on 19 Sep 2026 by sweeping the class rather than waiting
# for the seventh.
#
# It reports only what is certain from the source — a sentence that is not a
# key in fi.lproj, which nothing downstream can look up, and a literal SwiftUI
# is handed as a String: a fallback behind a String's `??`, half of a `+`, a
# string inside an interpolation. A ternary of literals is not one of those; the
# compiler types it a key, and each branch is asked for in the table. The
# sentences carried as Strings WITH a key behind them are counted instead:
# `Text(LocalizedStringKey(x))` looks those up where they are drawn, and
# reading them as defects reports dozens of findings that are all fine.
run "every Finnish sentence on a screen has a key" node scripts/localisation-lookup-check.mjs

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
	# The facts on a person's card, the server's half (§26): one sealed list
	# under a moment, the newest kept whole, an older phone renaming the
	# person and wiping nothing, and what the Worker refuses.
	run "a person's facts survive an older phone" node scripts/facts-sync-check.mjs
	# The pull cursor, which is the delivery guarantee itself: a number that
	# runs ahead skips other members' rows silently and forever. Three defects
	# lived in it (23 Aug 2026, §3) and every one looked like a working app.
	run "a telling reaches the phone that was pushing" node scripts/sync-cursor-check.mjs
	# The story column's half of the sync rules the server can apply to a
	# seal it cannot read: the newest moment wins whole, a phone that has
	# never heard of the story cannot wipe it, junk has no opinion, and a
	# moment from a wrong clock is held to now.
	run "a story survives an older phone" node scripts/story-sync-check.mjs
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
# The colouring route's doors, in the order they must open, through a Worker of
# its own that has no key — so a request that gets past every door fails before
# the network and costs nothing. Nothing told is refused, the meter answers
# before the model, and a round that failed is not charged.
run "no telling, no colour; no image, no charge" node scripts/colourise-route-check.mjs
# The story route's doors through a keyless Worker of its own: nothing told is
# refused before the model, so is a card too long to be one call, and past
# every door the failure tells the app one word and the log no telling.
run "no telling, no story; a failure tells no telling" node scripts/story-route-check.mjs

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
