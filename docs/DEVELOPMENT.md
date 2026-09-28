# Development

The long form of the working notes in [CLAUDE.md](../CLAUDE.md), moved here word for word. A rule cited by number is one of the ten rules there.

## The assistant's rules — checked in, not personal setup

Most of the typing here is Claude Code's, and since **28 Aug 2026** it happens
under a guideline file that lives in the repository:
[`.claude/skills/karpathy-guidelines/SKILL.md`](../.claude/skills/karpathy-guidelines/SKILL.md),
vendored unmodified from
[multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)
(MIT; provenance in `SOURCE.md` beside it). Four rules against the four things a
model does wrong when left to itself: inventing scope, abstracting for a single
caller, tidying code it was not asked to touch, and calling a thing done without
a check that could have failed.

It is checked in rather than left in `~/.claude` for the same reason everything
else here is written down — so that it travels with the clone and can be read
instead of taken on trust.

**It is not retroactive.** Two of the four rules this repository had already
paid for the hard way: *surgical changes* is the staging rule immediately below,
learned from one commit that swept up two other sessions' work; *goal-driven
execution* is why the Commands section is a list of scripts rather than a list
of intentions, learned from four features that were marked done and were not.
That overlap is why the file was adopted, not a claim that the months before it
were worked this way.

A second skill sits beside it in `~/.claude/skills/` and is deliberately **not**
checked in: [ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)
(MIT), 3.3 MB of design reference across 47 files. One file of it earns its keep
here — `data/ux-guidelines.csv`, 119 rules, 30 of them about accessibility and
motion — and it earns it against [docs/index.html](index.html), which
when this was written on 28 Aug 2026 was the one surface in this project with
no check of its own. `scripts/page-check.mjs` arrived two days later and runs
in `verify.sh`. The app is not the customer:
the skill's SwiftUI table is 50 rows of basics with zero VoiceOver rows and zero
contrast rows, against the 115 accessibility sweeps that already run here, each
auditing its screen at the default text size and again at the largest.

Run over the page on 28 Aug 2026 it produced **one real defect and one false
alarm**: ten headings and no `<h1>` at all, so a screen reader navigating by
level found no page heading — fixed; and a fixed-chrome `scroll-padding-top`
rule that measurement then killed, because the page has exactly one fragment
link and `<main>` already reserves the chrome's height. One in two is the
honest yield, and the second one is why a guideline is read against the page
rather than applied to it.

**The palettes, font pairings and style presets are not to be used at all.**
They are measured on white. `#C2410C` is 5.2:1 on white and 4.43:1 on the
parchment this project actually uses; it failed here and had to be replaced.
Colours come from `Elder.swift` in the app and the six tokens in `kinlore.css`
on the page — and neumorphism and glassmorphism are low-contrast by
construction, which is rule 1 inverted.

## Git — commit by path, because the index is shared

Several sessions often work in this worktree at once, on `main`, and a commit is
pushed to the public repo within minutes. A commit here is published by default,
not local.

**Commit the paths you changed yourself, in one command:**

```bash
git commit -F <message-file> -- ios/Kinlore/Design/SubjectAvatar.swift
```

Never `git add -A`, `git add .` or `git commit -a`: they sweep up another
session's half-finished work, and it has happened — one piece of work ended up
split across three commits whose messages were about something else entirely.
If `git status` shows changes you did not make, leave them alone and say so.

**`git add <path>` and then `git commit` is not enough, and that is the part
this rule used to get wrong.** There is one index and every session shares it,
so the gap between staging and committing is a hole: on 12 Sep 2026 a commit
staged exactly one file, verified it with `git diff --cached --name-only`, and
still went in carrying four of somebody else's — `docs/ARCHITECTURE.md`,
`GalleryScreen.swift` and both `.strings` tables — because that session ran
`git add` in between. The check passed and the commit was wrong anyway.

`git commit -- <paths>` takes the working-tree content of those paths and
ignores the index, so a concurrent `git add` cannot leak into it. Anything
already staged stays staged and stays theirs.

**That protects you from another session's index, not from their working tree,
and the difference is the whole safety of this rule.** The paragraph above
reads as "commit by path and nobody else's work can get in"; what it says is
that nobody else's *staging* can get in. When two sessions edit the **same
file**, `git commit -- <path>` takes that file's entire working-tree content,
so the other session's unstaged hunks ride in exactly as `git add -A` would
have carried them — same outcome, from the command written to prevent it.

Measured 19 Sep 2026, and caught before the commit rather than after. A change
rewording the consent texts in the microphone permission, the onboarding
notice and the Help screen was about to commit both `.strings` tables by path,
while a second session's nine date-sheet keys sat appended at the end of both
files, and a third session's `git merge --ff-only` waited behind the same two
paths. Those nine are deliberately not named here: two of them were renamed
within twenty minutes of being read, because a sweep went red at five rows in
that section and green at four, and an anecdote that pins somebody else's
half-finished identifiers goes stale faster than the lesson it carries.
Nothing overlapped textually: one change replaced two entries in place, one
appended a block, one inserted a line after `Minä`. The file was all they
shared, and the file is the unit git commits.

So read the diff before committing a path — `git diff -- <path>`, every hunk,
every time. Do not reach for `git add -p` to cut around a hunk you did not
write: that puts your own hunks in the shared index, which is the hole
`git commit -- <paths>` exists to close, and trades a visible collision for an
invisible one.

**Waiting for the other session is the weaker answer, and the same evening
found the better one.** Build the commit from HEAD's own copy of the file plus
your hunks alone, through an index of your own, and their text stays on disk
where they left it:

```bash
IDX=$(mktemp)                                    # never .git/index, which is shared
# write HEAD's version of the file plus ONLY your hunks to $BLENDED
GIT_INDEX_FILE=$IDX git read-tree HEAD
BLOB=$(git hash-object -w "$BLENDED")
MODE=$(git ls-tree HEAD -- <path> | cut -d' ' -f1)   # HEAD's mode, never a guess
GIT_INDEX_FILE=$IDX git update-index --cacheinfo "$MODE" "$BLOB" <path>
TREE=$(GIT_INDEX_FILE=$IDX git write-tree)
NEW=$(git commit-tree "$TREE" -p HEAD -F <message-file>)
git update-ref refs/heads/main "$NEW" "$(git rev-parse HEAD)"   # compare-and-swap
git reset -q -- <path>                           # ← the leg that is easy to miss
```

**That last line is not optional, and leaving it out loses the commit
silently.** `update-ref` moves the branch, but the shared index still holds the
pre-commit blob, so `git status` reads `MM` and the index is staged to *delete*
what was just committed. Measured 19 Sep 2026 in a throwaway repo: a plain
`git commit -m <something unrelated>` by the next session succeeded and left
HEAD without the line — no conflict, no warning, and a message about something
else. `git reset -q -- <path>` resets that one entry to HEAD and touches
neither the working tree nor any other path; with it, the staged diff is empty
and a plain commit refuses.

**The mode is read from HEAD, because this recipe used to write `100644` for
every file.** On 21 Sep 2026 that took the executable bit off
`scripts/subject-rules-check.mjs` in db685c6 — the only time a tracked file has
changed mode anywhere in this repository's history. It broke nothing, since
`verify.sh` runs that file through `node`. What it left was an `M` in every
session's `git status` for four days, and on 25 Sep it was the one line in a
census of uncommitted work that no session could claim. The same recipe run on
`scripts/verify.sh` would publish a script that CI, which calls
`./scripts/verify.sh`, can no longer execute.

**The recipe has a premise it never states: your own change has to be on
disk.** `$BLENDED` is HEAD's copy of the file with your hunks written back into
it, so everything this publishes is content the shared working tree already
holds. When your change is not in that tree at all — it lives on a branch, or
in a worktree of its own — the private index is not the better tool here, it is
the wrong one. Write the change into the shared tree first, and the ordinary
by-path rules apply again.

**Moving the ref while the tree lacks the content is the same silent loss as
the missing reset leg, arriving from the other side.** HEAD carries the line
and disk does not, so the next session's by-path commit of that file takes the
working-tree copy and removes it — no conflict, no warning, and a message about
something else, which is exactly the shape measured above. `git reset` answers
the index; nothing answers this but putting the content on disk before the ref
moves.

Three sessions hit this collision within one hour on 19 Sep 2026 — `CLAUDE.md`,
`docs/ARCHITECTURE.md` and both `.strings` tables — and a fourth arrived on a
microphone string while they were still arguing about the order. Every ordering
argued that evening dissolved the moment somebody rebuilt a file instead. The
order was never a property of the files; it was a property of committing the
working-tree copy of them, which was the only instrument anybody had while they
were measuring.

**A file git has never seen is the other gap.** The pathspec is matched
against tracked paths, so a brand-new file fails the whole commit with
`pathspec … did not match any file(s) known to git` — and on 12 Sep 2026 that
left the work uncommitted while the `git push` on the next line shipped
somebody else's commit instead. Register it first and then commit by path as
usual: `git add -N <newfile>` records the path without staging content, which
is exactly enough for the pathspec to find it and still take the working-tree
version.

**Two more things that bite in the same place.** `git commit --amend` with no
pathspec picks the index up again — use `--only -- <paths>`. And
`.git/COMMIT_EDITMSG` belongs to whoever committed last, which may not be you:
repairing the commit above by restoring that file put somebody else's message
on it. Keep your message in a file of your own.

**And do not edit a shared file to run an experiment.** Staging by path keeps
another session's work out of your commit; it does nothing for their work on
disk. On 12 Sep 2026 an accessibility finding was chased by editing
`RootView.swift` in place — hide a section, run the audit, restore from a copy
taken beforehand — and between the copy and the restore another session began
migrating that same file. The restore wrote a pre-experiment version over their
work. It survived only because they happened to write again immediately after,
which is luck and not a method.

An experiment that changes code belongs in a worktree of its own, which costs
one command and leaves the shared tree untouched:

    git worktree add --detach /tmp/try HEAD && (cd /tmp/try/ios && xcodegen generate)
    # …edit, build and measure in /tmp/try…
    git worktree remove --force /tmp/try

The same rule answers a subtler version: a measurement taken in the shared tree
is a measurement of somebody else's half-finished work, not of HEAD. Every
number in this session that meant anything was taken in a worktree pinned to a
commit.

**A third version bites without anybody changing your files: a long script
reads itself from disk as it runs.** On 12 Sep 2026 a full `verify.sh` died
after two and a half minutes with

    ./scripts/verify.sh: line 350: syntax error near unexpected token `}'

on a file that parses perfectly, then and now. Its mtime was inside the run —
another session edited it while bash was part-way through, and bash resumed
reading at a byte offset that no longer meant what it had. **The error names a
line that is fine**, which is what makes it expensive: the first instinct is to
go and read line 350. A full run belongs in a worktree for that reason alone,
before any argument about whose half-finished work is in the tree.

**And one trap in answering a red audit from a picture.** The PNG that
`TEST_RUNNER_KINLORE_AUDIT_SHOT` writes is taken *after* the audit has
finished — `AccessibilityAudit.swift` says so at "Now that the audit is
finished, one screenshot answers all of them", and it is the settled screen.
So it proves what the colour **is**; it cannot show what the audit **saw**.
Measuring one at 18.21:1 and concluding the audit was simply wrong is a step
the picture does not support, and it was taken on 12 Sep 2026 before the
cheaper check was run: the same test passed on its own minutes later. **A red
audit that does not reproduce alone has already answered the question** — the
arithmetic is for the one that does.

### Worktrees — whoever makes one removes it, in the turn its work lands

On 25 Sep 2026 this repository still carried three worktrees and seven
branches that no session was using. `.claude/worktrees/colourise` and
`.claude/worktrees/family-tree-2` were still checked out twelve days after both
branches had merged. A subagent's `worktree-agent-*` branch held work that had
long since landed, and a cloud session had left a branch on origin whose one
commit `main` still lacks. The expensive one was
`.claude/worktrees/keen-napier-ce00c4`: its branch held nine commits from
10–12 Sep that never reached `main`, and five of them were still worth having
when they were found — a stricter localisation scanner, a fix for a test that
races, and a missing setup step. None of these was wrong when it was made. Each
outlived its task because removing it was nobody's step, and once nobody can
account for a list of worktrees, finished work and unfinished work look the
same.

There are four kinds here, and each has exactly one owner:

- **A session's worktree** (`.claude/worktrees/<name>`, made by the desktop
  app). The session lands its commits on `main`, pushes, and removes the
  worktree and its branch before it reports done.
- **A subagent's worktree.** Every subagent that edits files is started with
  `isolation: "worktree"`, never in the shared tree. Its worktree disappears by
  itself only if the agent changed nothing. If it committed, the worktree stays,
  and the parent lands the work and removes it.
- **A measurement or experiment** (`git worktree add --detach /tmp/<name> HEAD`,
  as above). Whoever made it removes it as soon as the number has been read.
- **A cloud session's branch** (`claude/<name>` on origin). Deleted with
  `git push origin --delete <branch>` once its commit is on `main`, or once it
  has been judged obsolete.

Removal, in this order:

    rm <path>/backend/node_modules     # if you symlinked it (it must be a symlink)
    git cherry origin/main <branch>    # no "+" lines: nothing is left unlanded
    git worktree remove <path>         # no --force: a refusal means work is still there
    git branch -d <branch>             # -d refuses an unmerged branch, and that refusal is the check

Both of the stale worktrees above had `backend/node_modules` symlinked into
*this* tree, which is how a worktree gets the backend's dependencies without a
second install. `rm` on the link removes the link. With a trailing slash it does
not: measured on this machine on 25 Sep 2026, `rm -rf <link>/` deleted the
directory the link pointed to and left the link behind. Here that directory is
the shared tree's dependencies, so every session would lose them at once.

`--force` belongs only to the throwaway experiment above, whose changes you made
and mean to throw away. A `+` line from `git cherry` is not proof of lost work,
because a commit rebased through a conflict gets a new patch-id. It is,
however, the owner's to explain and nobody else's to delete.

## Commands

**Most of the checks below are also one command.** `./scripts/verify.sh` runs
every invariant in this repository that costs nothing — and it is what CI's
Invariants job runs, so it is the same green a stranger sees. It skips only
what it says it skips: anything that spends OpenRouter credit, the UI suite
unless `KINLORE_TEST_SIM` names a simulator of your own, and `geo-check.swift`,
which measures somebody else's gazetteer over the network. With a
`npx wrangler dev` running it picks up the eleven backend checks too.

It is listed here because it was not, and the cost of that is the reason
`family_crypto` sits inside it: that check had stopped **compiling** a week
before anybody noticed, because its instruction said to run it after touching
a file nobody had touched. An instruction to run something by hand is a
reminder rather than a check, and it is only as good as whoever last read it.
The individual commands below are still worth having — they are what you run
while working on one thing — but the run before a commit is this one:

```bash
./scripts/verify.sh
```

```bash
# Generate the iOS project. Run this after changing project.yml — and also
# after ADDING OR REMOVING A SOURCE FILE. XcodeGen globs the sources when it
# generates, so a new .swift file is invisible to xcodebuild until this runs,
# and the build fails with "cannot find X in scope" for a type that is plainly
# there on disk. This has cost time twice.
cd ios && xcodegen generate

# A simulator for BUILDING, by UDID. `name=iPhone 17 Pro` does not resolve on
# this machine at all: four simulators carry that name, two of them on the same
# runtime, and an ambiguous name fails as "Unable to find a device matching the
# provided destination specifier" — which reads like a missing simulator and is
# not one. A build touches no device, so sharing this one is fine; the UI tests
# are the case that is not, and they use $KINLORE_TEST_SIM below.
SIM=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list \
  devices available | grep -m1 'iPhone 17 Pro (' \
  | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}')

# iOS build. DEVELOPER_DIR is mandatory: this machine's xcode-select points at
# CommandLineTools, and changing it would need sudo. This overrides it.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphonesimulator \
  -destination "id=$SIM" build

# The same app for a REAL device, which is how the phase E visit installs it
# (PLAN.md §8) and which nothing had ever run until 12 Sep 2026 — every build
# in this project's history targeted the simulator. The code compiles for
# arm64, which is what the first line checks; the second is the real thing.
#
# This entry said until 19 Sep 2026 that "Xcode resolves signing on its own
# even though project.yml names no DEVELOPMENT_TEAM". It does not, and the
# likeliest reading of 12 Sep's run is that the team was still sitting in the
# pbxproj from Xcode's own Signing & Capabilities tab — where it does not
# survive the next `xcodegen generate`, because the project file is generated
# and ignored by git. Re-measured in a worktree pinned to a commit, so that
# nothing else in a busy tree could explain either result: with no team the
# device build fails outright at "Signing for \"Kinlore\" requires a
# development team".
#
# The team now comes from `ios/Signing.xcconfig`, which is tracked, carries no
# team of its own and optionally includes `ios/Signing.local.xcconfig`, which
# is in .gitignore because the Apple account identifier stays out of HEAD
# (10 Sep 2026). Write the local file once — docs/SETUP.md has the one command
# that reads it out of the keychain. Without it a clone still generates and
# still builds for the simulator, with no team and no error.
#
# With it, the command below gets past signing and stops at provisioning:
# xcodebuild will not create a profile unless it is passed
# `-allowProvisioningUpdates`, a step Xcode's own build performs by itself.
# That flag talks to the Apple account and can create a profile and an App ID
# there, so it is a decision rather than a default — which is why it is not
# written into the line below.
#
# Do not grep this output for "error" — the RevenueCat package has files
# called ErrorUtils.swift and BackendError.swift, and the paths alone produce
# pages of false matches. Grep for '^\*\* BUILD' instead.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphoneos \
  -destination 'generic/platform=iOS' build

# Accessibility tests. VoiceOver reads the accessibility tree and XCUITest
# queries the same tree, so this is how rule 1 is checked rather than asserted.
# performAccessibilityAudit() also catches contrast, clipping and tap targets —
# it has already found real defects that screenshots did not.
#
# GIVE THE RUN A SIMULATOR OF ITS OWN, by id and not by name. Several sessions
# work in this worktree at once, every one of them targets "iPhone 17 Pro", and
# a UI test does not survive another session launching the app on the same
# device: the audit's target process disappears mid-run.
#
# It does not fail honestly either. Most of it arrives as "Invalid target app
# <pid>", but some of it arrives as ACCESSIBILITY FAILURES THAT ARE NOT REAL —
# one shared run reported ten contrast and clipping issues on a screen that
# passes on its own. Measured: 15 failures on the shared device, 0/17 failures
# on a private one, same commit, minutes apart. Do not chase a red audit before
# checking which device it ran on.
#
# **And when the machine is never quiet, do not wait for it — measure the
# pixels.** A busy machine can make the audit report a colour that is not
# there; it cannot change the colour that was drawn. So a red contrast finding
# is answerable from a screenshot at any load, with the same WCAG arithmetic
# `ContrastMeter` runs inside the test: launch the screen with its own seed and
# `-UIPreferredContentSizeCategoryName`, screenshot it, and take the 95th
# percentile of the frame as the paper and the 1st as the ink.
#
# Measured 12 Sep 2026, after two hours of waiting for a window that never
# came — three sessions were rendering the video and running simulators
# throughout. A suite run that began at load 7 and ended at 472 reported three
# contrast failures. From the pixels: "Jäsenet" 18.21:1, "Paikat" at XXXL
# 20.18:1, and the new avatar initial "S" 9.54:1, against a 4.5:1 minimum. All
# three were the machine. The measurement took minutes, and the newest element
# on the list — the one most likely to be a real regression, and argued to be
# one — was the least close to failing.
#
# **The method has one blind spot, and the avatar is the example of it.** The
# 95th and 1st percentiles are taken *inside the element's frame*, so the
# arithmetic can only see text against what is behind the text. It cannot see
# WCAG 1.4.11 — a shape against the ground *outside* its frame — because
# that ground is not in the crop. Both numbers are worth having, and they
# are not the same check.
#
# That avatar reads 9.54:1 because it was measured after the fix for exactly
# that blind spot. Before it, the same disc was `Elder.card` on `Elder.paper`:
# **1.11:1** against the ground, while its letter measured 20.18:1 — text
# comfortably fine, shape invisible. The letter was never the defect and the
# audit's finding on it was never believed; what was argued was an A/B, not
# novelty (`testPeople` green at `9c5bac6`, red at `42b3c99`, same simulator
# minutes apart, and the fill the one variable that flipped it: card red 4/4,
# clear green 3/3, ink green 2/2). Novelty is indeed not a measurement — and
# neither is a passing text ratio, when the thing that failed was an edge.
#
#   xcrun simctl create kinlore-tests \
#     com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
#     com.apple.CoreSimulator.SimRuntime.iOS-26-5
#
# iOS-26-5 is the ONLY runtime installed — measured 15 Aug 2026 with
# `xcrun simctl list runtimes`, which prints exactly one line. This file
# previously said 26-2 and claimed 18.6, 26.1 and 26.2 were installed; none of
# the three exists here, and following it fails as "Invalid runtime", which
# reads like a broken Xcode and is not one. Run the list before copying a
# runtime id out of any document, including this one.
#
# RUN IT IN FINNISH. The tests query the accessibility tree by the words on
# screen, and those words are Finnish — `staticTexts["Uutta perheeltä"]`,
# `buttons["Kysy perheeltä"]`. The app's default is English, so a run without
# these two flags fails on tests that are not broken, which is the same wasted
# hour as a shared simulator and looks exactly as convincing.
#
# Measured 8 Sep 2026: `testResultWithKnownNames` looks for "Tutut nimet",
# en.lproj translates that key to "Familiar names", and the test failed on an
# English device and passed on a Finnish one, same commit, minutes apart. It
# was one test then because most Finnish on screen was not being looked up at
# all. Fixing the gallery's four unlooked-up strings the next day made it
# several, which is the fix working — the app now answers in the device's
# language, so the tests have to ask in the app's.
#
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$KINLORE_TEST_SIM" \
  -testLanguage fi -testRegion FI test

# Backend locally
cd backend && npx wrangler dev

# D1 schema into the local database. FIRST TIME ONLY — this creates the tables,
# it does not migrate them. On a database that already exists it stops on the
# first statement with "table family already exists" and changes nothing, which
# reads like it ran.
#
# That is how a local database ends up several changes behind while looking
# fine. Measured 15 Aug 2026: `subject` was missing `lat`, `lon` and
# `geo_precision` and still carried a `blurhash` the schema had dropped, so
# `place-sync-check.mjs` failed with a 502 whose real cause was
# "D1_ERROR: table subject has no column named lat" in the Worker log — three
# levels away from anything the script prints.
#
# To bring an existing local database forward, run the ALTER statements that
# schema.sql keeps beside the columns they add:
#
#   npx wrangler d1 execute memorize --local --command \
#     "ALTER TABLE subject ADD COLUMN lat REAL;"
#
# Compare first, so you alter what is actually missing:
#
#   npx wrangler d1 execute memorize --local \
#     --command "PRAGMA table_info(subject);"
#
cd backend && npx wrangler d1 execute memorize --local --file=schema.sql

# A copy of the PRODUCTION database as SQL, into backend/backups/ — ignored by
# git, because family and member names are plaintext in it. D1's Time Travel
# keeps the last days of history by itself and needs no command until the day
# it is needed; this is the copy that outlives the account. It carries no R2
# object — the photographs and the voices — and R2 has no versioning to lean
# on. Both facts, the restore commands, and what to do when the account itself
# is gone are in docs/RECOVERY.md: read it BEFORE typing anything on the day
# something has gone wrong, because two of the commands there make things
# worse when run against the wrong target.
cd backend && npm run db:export

# ASR comparison
node scripts/asr-bench.mjs samples/

# The export, opened. The one output that leaves the app for good, and its
# promise — "avautuu millä tahansa koneella ilman tätä sovellusta" — is not
# something XCUITest can check: the file lands in the app's container and the
# test runner may not look inside it. Records a memory first, because the demo
# archive has no media and an export of it looks complete while carrying none.
# Needs a booted simulator with the app installed; set KINLORE_TEST_SIM.
node scripts/export-check.mjs

# When the paid archive is offered. Four lines of arithmetic over one
# UserDefaults key, and every way they can go wrong is silent: an offer after
# every story, or none ever, or one landing beside the names rule 4 asks a human
# to check. Run it after touching UpsellRhythm.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/upsell-rhythm-check \
  scripts/upsell-rhythm-check.swift ios/Kinlore/Services/UpsellRhythm.swift \
  && /tmp/upsell-rhythm-check

# Which question the app puts in front of an 80-year-old. A transformed
# up/down staircase over three UserDefaults keys, and both ways of being wrong
# are silent: the reflective question offered too early, which is where an
# elderly teller decides this app is not for them, and the naming question
# still being asked to somebody who has told stories for a month. Neither
# fails a build, neither shows in a screenshot, and the accessibility suite
# reads what is on screen rather than why that question is the one on it.
#
# Written 11 Sep 2026 because 380 lines of this had no check while
# UpsellRhythm's four did — and it found a defect on its first run. Run it
# after touching QuestionLadder.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/question-ladder-check \
  scripts/question-ladder-check.swift ios/Kinlore/Services/QuestionLadder.swift \
  ios/Kinlore/Model/Models.swift \
  && /tmp/question-ladder-check

# Where the family tree puts people, and the lines it draws. Pure arithmetic
# over confirmed people and relationships, and every way of being wrong is
# silent: a child drawn a row above her mother, a couple split by a stranger,
# a brother with no line to his sister, two broods on one bar. None of them
# fails a build, and a screenshot shows a tree either way. Costs nothing.
# Engine and check were rewritten from zero on 25 Sep 2026 against the nine
# requirements in ARCHITECTURE §8 item 13. Run it after touching
# FamilyTreeLayout.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/family-tree-layout-check \
  scripts/family-tree-layout-check.swift ios/Kinlore/Services/FamilyTreeLayout.swift \
  && /tmp/family-tree-layout-check

# The word under every card in the tree — *Vanhempasi*, *Sisaruksesi lapsi*,
# *Puolisosi vanhempi* — said from the phone owner's point of view, and only
# where it is exact. A wrong word is rule 4's wrong relationship drawn as
# fact, and it is silent: *Serkkusi* on a card looks exactly like
# *Pikkuserkkusi* to anybody who does not already know, and a build and a
# screenshot are both fine either way. Derives every word of `-seed clan`
# from Elina's card and from seven other phones, then holds the engine over
# seeded random families against a brute-force walk of every shortest path
# — and against each word's mirror wherever a pair has one shortest reading,
# because two siblings married to two siblings are *Sisaruksesi puoliso*
# from both ends and no table order can make them differ. Costs nothing.
# Run it after touching Kinship.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/kinship-check \
  scripts/kinship-check.swift ios/Kinlore/Services/Kinship.swift \
  && /tmp/kinship-check

# A memory's text naming a relative the teller never mentioned. In a take for
# the demo film on 28 Sep 2026, the answer "Toivo did. He always had the
# camera.", spoken by a synthetic voice, was saved as "Toivo, our dad, always
# had the camera.", and the prompt forbidding it was the only guard.
# `RemoteExtractionService` now keeps her own words whenever the text names a
# relationship her telling did not, in either language and in any Finnish case.
# This holds the table behind that: the sentence itself, every relationship in
# both languages, the spoken forms the prompt tidies (*faija* into *isä*), and
# the words that only begin like one (*isäntä*, *enough*). Costs nothing. Run it
# after touching RelationWords.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/relation-words-check \
  scripts/relation-words-check.swift ios/Kinlore/Services/RelationWords.swift \
  && /tmp/relation-words-check

# The names the blind card deals beside the proposal (ARCHITECTURE §23). Until
# 29 Sep 2026 every card got the archive's three newest confirmed people, so in
# `-seed large` the one name that changed from card to card was the answer.
# Deals 400 cards from one family and counts the threes, who is dealt and which
# seat the answer takes: dealing by the hash that seats the names puts the
# answer last on 308 of them. Pins the README's and the film's cards. Costs
# nothing, with a stand-in `MemoryStore`. Run it after touching
# BlindConfirmation.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/blind-card-check scripts/blind-card-check.swift \
  ios/Kinlore/Services/BlindConfirmation.swift ios/Kinlore/Model/Models.swift \
  && /tmp/blind-card-check

# What the album's search finds when somebody types a year (ARCHITECTURE §8
# item 12). "2000" found nothing on 28 Sep 2026 in an album with photographs
# from 2003 and 2015 in it, and every way of reading a year wrongly is silent —
# a century where a decade was meant, a side of a year off by one, an undated
# photograph found by a date nobody knows. Holds every spelling, the order,
# that a query with no year finds what it found before, and a keystroke over
# a thousand photographs. Costs nothing. Run it after touching
# ArchiveSearch.swift or the search in MemoryStore.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/archive-search-check \
  scripts/archive-search-check.swift ios/Kinlore/Services/ArchiveSearch.swift \
  ios/Kinlore/Services/MergeChain.swift ios/Kinlore/Model/Models.swift \
  && /tmp/archive-search-check

# Which decade the album files a photograph under, on a phone in any zone.
# Every date in the archive is midnight in Helsinki; read on the phone's own
# calendar, as the headings were until 28 Sep 2026, the date sheet's "1950s"
# is 31.12.1949 in Los Angeles, and the fifties sat among the forties on every
# phone west of Finland. Takes the decade under six zones, and the span "around
# 1955" with it, which read "1954" until 29 Sep 2026, then reads ios/Kinlore for
# the phone's calendar anywhere else. Costs nothing. Run it from the root after
# touching `DateHint`, the album's decade headings or a seed's dates.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/decade-check \
  scripts/decade-check.swift ios/Kinlore/Model/Models.swift \
  && /tmp/decade-check

# The family's bytes on every phone. After a sync, the photographs and voices
# that exist only in R2 are fetched here in the background — voices first, on
# Wi-Fi only, never the last gigabyte, three failures ending a round, the
# store written every tenth file rather than every file — so the phone is a
# copy of the archive and not a window onto one (docs/RECOVERY.md).
# Every rule is silent when wrong: a copy that never starts looks exactly like
# one that is complete. Run it after touching FullCopy.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/full-copy-check \
  scripts/full-copy-check.swift ios/Kinlore/Services/FullCopy.swift \
  && /tmp/full-copy-check

# Encryption at rest. The one place in this app where being wrong is silent
# AND permanent: a memory sealed under the wrong key still syncs, still draws a
# row, and is simply unreadable — and by then the plaintext is gone. Also
# asserts the claim lever 3 actually makes, that none of the words cross to the
# Worker. Run it after touching FamilyCrypto.swift or the sealing in
# MemoryStore+Sync.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/family-crypto-check \
  scripts/family-crypto-check.swift ios/Kinlore/Services/FamilyCrypto.swift \
  ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Model/Models.swift \
  && /tmp/family-crypto-check

# And that the seal is applied. Until 26 Sep 2026 a phone that had lost the
# family key pushed and uploaded in the clear, and emptying another phone on
# the same Apple ID deletes the shared Keychain entry on both. Drives that road
# through `SyncSeal` and `FamilyKey.onRejoin`, then reads SyncEngine.swift and
# Session.swift for any other road. Costs nothing. Run it after touching
# SyncEngine.swift, `Session.rejoin`, FamilyKey or the sealing in
# MemoryStore+Sync.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/keyless-sync-check \
  scripts/keyless-sync-check.swift ios/Kinlore/Data/Identity.swift \
  ios/Kinlore/Services/FamilyCrypto.swift ios/Kinlore/Data/MemoryStore+Sync.swift \
  ios/Kinlore/Model/Models.swift \
  && /tmp/keyless-sync-check

# The same sealing, end to end: two identities through a real Worker, the key
# crossing only in the invite text, D1 rows and R2 bytes checked sealed and
# opened byte for byte on the second identity (PLAN §10 lever 3's "test to run
# the day it deploys" — first production run 24 Aug 2026). Same compile line
# with the round-trip source; needs `npx wrangler dev`, and against production
# pass https://memorize.arkiste.workers.dev instead. Leaves one throwaway
# family behind wherever it runs.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/lever3-roundtrip-check \
  scripts/lever3-roundtrip-check.swift ios/Kinlore/Services/FamilyCrypto.swift \
  ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Model/Models.swift \
  && /tmp/lever3-roundtrip-check http://localhost:8787

# Whether a browser can read this archive at all. Every argument for reaching
# anyone off an iPhone — an Android relative, the universal link ARCHITECTURE §4
# has wanted since August, any web surface at all — rests on one claim about
# lever 3: that WebCrypto opens what CryptoKit sealed. That claim was reasoning,
# and it was used in BOTH directions before it was measured — once to argue a web
# surface is impossible, which it is not. Measured 8 Sep 2026: 9 of 9, both
# directions. `webcrypto.subtle` is the same API a page gets, so what passes here
# passes in Safari; there is no library and no polyfill, because a helper would
# be a second implementation and the check would be measuring the helper.
#
# The one nobody expected: the browser can REPRODUCE the deterministic nonce
# (HMAC-SHA256 of the plaintext, truncated to 12 bytes), so a web client could
# write a title without `sync.ts` reading every push as a rename. Reading never
# needed that. It came free.
#
# Costs nothing — no Worker, no key, no network. Run it after touching
# FamilyCrypto.swift, and before believing anything about a web client.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/webcrypto-interop-check \
  scripts/webcrypto-interop-check.swift ios/Kinlore/Services/FamilyCrypto.swift \
  && /tmp/webcrypto-interop-check emit \
   | node scripts/webcrypto-interop-check.mjs /tmp/kinlore-webcrypto-return.json \
  && /tmp/webcrypto-interop-check verify /tmp/kinlore-webcrypto-return.json

# Place coordinates through sync. Checks the four rules that are silent when
# broken: a resolved point round-trips, a device that has not looked the name up
# cannot wipe it, correcting the title clears it, and rubbish is refused. And
# since 25 Sep 2026 the rules for a point somebody placed, which is their word
# rather than a lookup: it keeps who and when, survives lookups, older phones
# and a corrected title, moves only for a newer word, and another phone may
# repeat that word only where the server already holds it. Costs nothing — no
# AI call — but needs `npx wrangler dev` running, on a local database that has
# the `geo_confirmed_*` columns (the ALTERs are in schema.sql).
node scripts/place-sync-check.mjs

# The pull cursor, which is the delivery guarantee itself. Three defects lived
# in this one number (found 23 Aug 2026, ARCHITECTURE §3) and every one showed
# a working app while a telling silently never reached another phone: a cursor
# advanced from a push reply, a seq reservation that was not atomic, and a
# reply cursor that ran past a capped table. The rule they left behind — the
# cursor moves only through pull replies — is Swift's half to keep; this
# drives the server's half. Needs `npx wrangler dev`.
node scripts/sync-cursor-check.mjs

# The invite link, which §4 calls the entire security boundary. Six rules that
# are silent when broken: a code expires, a code can be revoked, a code belongs
# to one family, a code admits one person, the owner can close the door behind
# somebody who should not have come through it, and a wrong code answers
# exactly like an expired, revoked or used one — a different answer would tell
# a guesser they had found a real family. And since 13 Sep 2026 the card an
# invitation names: its joiner is linked only to a live person card of the
# invitation's own family, and a card not yet synced up never burns the code.
# Needs `npx wrangler dev`; leaves two throwaway families behind.
node scripts/invite-boundary-check.mjs

# One purchase, one family. Loads the real schema.sql into an in-memory SQLite
# and asks it: the same customer id cannot unlock two families, a refund finds
# exactly one payer, and a restore inside the family still works. Costs nothing
# — no Worker, no D1, no RevenueCat — and the guard it backs up cannot be run
# on this machine at all. After touching the member table or entitlement.ts.
node scripts/entitlement-binding-check.mjs

# When the webhook may take the paid tier away. Drives the real handleWebhook
# over the shipping schema in in-memory SQLite — no Worker, no RevenueCat
# secret. The rule is RevenueCat's and was assumed wrong once: there is no
# REFUND event (a refund is CANCELLATION with cancel_reason CUSTOMER_SUPPORT),
# and a plain auto-renew-off must keep the tier until EXPIRATION — the old set
# locked a family out of a month somebody had paid for. After touching
# entitlement.ts.
node scripts/webhook-revocation-check.mjs

# The other half of the same arc: /entitlement/sync does not accept a state
# from the client, it asks RevenueCat. That claim went unchecked until 1 Sep
# 2026 because it looked as though it needed a key, and it does not — the real
# syncEntitlement runs over the shipping schema with `fetch` replaced by
# something that answers like RevenueCat and keeps the request. Nothing leaves
# the machine, which matters twice here: the request that proves the payer's
# account is protected must not be the request that sends it anywhere. Pins the
# claim the endpoint exists for, the 409 before any upstream call, the restore,
# the two-payer rule, and rules 7 and 9 on the one path whose upstream body is
# somebody's account. After touching entitlement.ts.
node scripts/entitlement-sync-check.mjs

# And the state neither of those can produce. `quota.isPaid` gated the paid
# archive on one word, and only an event could change it — the device stops
# reporting once `hasActivePurchase` goes false, which is exactly when the news
# matters — so a webhook that never arrived left a family paid for ever over a
# date months in the past. The tier is now re-asked when the stored one cannot
# be true, and the failure mode is the point: missing keys, no bound customer
# or an unreachable RevenueCat all answer "keep what you had", which is paid.
# Ending a month somebody paid for is the mistake this file already made once.
# After touching entitlement.ts or quota.ts.
node scripts/entitlement-reconcile-check.mjs

# What a stranger can spend in a day. Every free-tier limit above belongs to a
# family, and a family costs nothing — POST /family asks for no invitation —
# so until 26 Sep 2026 nothing bounded a day's upstream bill but the credit
# limit on the OpenRouter account: 7 200 families a day from one address, a
# first transcription of any length, any number of them at once, and
# `/extract` with no meter at all. One pool per route per UTC day now covers
# the whole free tier, reserved in the statement that decides. Drives the real
# Worker over schema.sql in an in-memory SQLite with `fetch` replaced — no
# wrangler, no key, no network — and pins that ten calls at once get what one
# gets, that the refusal is 429 and never a 402, that a paid family is never
# counted, that a spent day still saves every memory (rule 2), and that the
# shipped values admit the largest recording and the longest telling on a day
# nobody has touched. After touching quota.ts, budget.ts, the three AI routes
# in worker.ts, or the FREE_TIER_* values in wrangler.jsonc.
node scripts/free-tier-ceiling-check.mjs

# A question asked of one member by name, and the two notifications it can
# send. Runs the real push, pull and notify over schema.sql in an in-memory
# SQLite with `fetch` replaced — no Worker, no key, no network — and pins who
# may aim a question, that nobody else can move the aim, that one reference
# that does not resolve cannot fail a batch, who is told and who never is,
# and that a notification carries no words. The wire to APNs is the one part
# it cannot reach: `wrangler dev` on macOS has no HTTP/2 for it, so that is
# checked once, deployed (ARCHITECTURE §11). After touching sync.ts, apns.ts
# or the question fields in MemoryStore+Sync.swift.
node scripts/targeted-question-check.mjs

# A telling taken back and brought back, by its teller and by nobody else
# (ARCHITECTURE §19). The state is two moments on one row, `deleted_at` and
# `restored_at`, and the later one wins; both ways of being wrong are silent —
# a stale copy from the author's other phone reviving a tombstone, or burying
# the telling she just brought back — and a card looks the same either way.
# Runs the real push and pull over schema.sql in an in-memory SQLite: no
# Worker, no key, no network. Nine of its twenty were red against the COALESCE
# that preceded the column. After touching the memory upsert or the pull in
# sync.ts, or `restore(memoryID:)` and the restorable seed in MemoryStore.swift.
node scripts/memory-restore-check.mjs

# The transcription's output budget. `complete()` sends no cap unless told
# one, and the route's default is low: a long telling came back cut off, was
# rejected whole, and after three attempts the catch-up gave up on it. The
# budget is the hallucination bound turned into tokens, and both ways of being
# wrong are silent. Runs on Node's own type stripping — no build, no Worker,
# no key. After touching budget.ts or transcribe.ts.
node scripts/transcribe-budget-check.mjs

# What the app is willing to believe a model said. Two pure functions between
# the model's JSON and the family's archive, and both were wrong in ways
# nothing reported: a mention with an empty name became a PERSON the family is
# asked to confirm — drawn as "Henkilö", because `displayTitle` falls back to
# the kind — and an untrimmed name became a second Aino, which is the
# duplicate card the base-form requirement exists to prevent arriving by
# another road. Neither shows in a screenshot.
#
# They were unreachable by any check until 12 Sep 2026, and not for want of
# value: Node cannot resolve extract.ts's extensionless `./openrouter` import,
# which is the whole reason `budget.ts` was carved out as a file with no
# runtime imports. Writing `./openrouter.ts` and setting
# `allowImportingTsExtensions` is the cheaper answer — esbuild bundles it
# unchanged — and on 26 Sep 2026 the same one word unlocked `transcribe.ts`,
# `family.ts` and `worker.ts`, the last modules Node refused.
#
# Costs nothing: no Worker, no key, no network, no model. After touching
# extract.ts.
node scripts/extract-shaping-check.mjs

# Colours by the telling (ARCHITECTURE §24), in four checks that cost nothing —
# no key, no network. First the lock between an image model's reply and a
# family's photograph: lightness from the photograph and only the hue from the
# model, a reply whose shapes moved refused, a ratio framed and not stretched.
# A lock that got this wrong still hands back a fine colour photograph, with
# every face the model's. Then the phone's half of the colour sync rules, what
# the model is told and what is believed back, and the route's doors through a
# keyless Worker of its own. The server's half of the sync rules is in
# `subject-rules-check.mjs`, which needs `npx wrangler dev`. After touching
# ColourLock.swift, colourise.ts, or the colour fields in MemoryStore+Sync.swift
# or sync.ts.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/colour-lock-check \
  scripts/colour-lock-check.swift ios/Kinlore/Services/ColourLock.swift \
  && /tmp/colour-lock-check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/colour-sync-check \
  scripts/colour-sync-check.swift ios/Kinlore/Services/FamilyCrypto.swift \
  ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Model/Models.swift \
  && /tmp/colour-sync-check
node scripts/colourise-check.mjs
node scripts/colourise-route-check.mjs

# The palette against its own argument. Elder.swift carries twenty-five
# contrast ratios in its comments — "15.17:1 under primary text", "5.59:1 on
# wax", "1.39:1, never text" — and they are the justification for every colour
# in the app under rule 1. Nothing verified them until 12 Sep 2026: edit one
# hex in Assets.xcassets and every sentence around it becomes a lie, silently,
# in the file whose whole job is to be believed. `page-check.mjs` already does
# this for the six tokens in kinlore.css.
#
# It checks both directions — the computed ratio against the written number,
# and the written number still being in the file — so an edited asset and an
# edited sentence each fail, and the two can only move together on purpose.
#
# It does NOT replace the accessibility audit, which reads the pixels iOS
# actually drew and so catches pairs nobody wrote down. It complements it: the
# audit needs a quiet machine and three runs in a row on 12 Sep proved it
# cannot be trusted under load, while this costs nothing and answers at any
# load. Anything built on `Color.primary` is deliberately out of scope — that
# is the system's colour, not this repo's, and asserting a guess about it
# would be a check that goes green for the wrong reason.
#
# After touching Elder.swift or any .colorset.
node scripts/palette-contrast-check.mjs

# Place lookup. Re-measures the claims in ARCHITECTURE.md §18 against the real
# MapKit answers — they are claims about somebody else's gazetteer, and they can
# stop being true without this repo changing. Needs a network; run it after
# touching PlaceLookup.swift, and before believing §18.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/geo-check scripts/geo-check.swift \
  ios/Kinlore/Services/PlaceLookup.swift && /tmp/geo-check
```

## Environment notes

- **`sudo` is not available.** Do not suggest `xcode-select -s` — use the
  `DEVELOPER_DIR` variable as in the command above. **Xcode 26.6, iOS 26.5
  simulator SDK, one runtime (`iOS-26-5`)** — measured 15 Aug 2026 with
  `xcodebuild -version`, `-showsdks` and `simctl list runtimes`.

  This entry said "Xcode 26.2, iOS 26.2" and asserted that *"this file said
  26.6 / 26.5 for a while; neither has ever been on this machine"* — which was
  exactly backwards, since 26.6 and 26.5 are what is installed and 26.2 is not.
  A correction was made in the wrong direction and then stated with confidence,
  which is worse than leaving a version out. **Measure before editing this
  line**, and paste the command output rather than a remembered number.
- **The simulator is shared; the UI tests must not be.** Building on the shared
  device is fine — a build touches no device. Running the app and running the
  tests are not: they install, launch and terminate one bundle id, and two
  sessions doing that at once take turns killing each other's process. Use a
  device of your own and **never shut down or reboot a booted one you did not
  create** — somebody else is very likely mid-run on it.
- **A device of your own is the rule; a device left booted is the cost.** Eight
  were booted here at once on 16 Aug — three sessions of this project, another
  project's two, and a stray — and a run of the UI suite died with

      IDELaunchReport: Finished with error: The operation couldn't be
      completed. (Mach error -308 - (ipc/mig) server died)

  before a single test executed. **A starved machine does not only kill runs, it
  invents findings.** The next attempt crawled through in two hours instead of
  fourteen minutes and reported two failures: one audit that timed out after
  33 minutes, and one Dynamic Type finding on a sheet's *"Peruuta"*. That sheet
  then passed three times in a row on a quiet machine, same commit, 36–47
  seconds each. Nothing was wrong with it.

  So: `xcrun simctl list devices | grep -c "(Booted)"` before believing either a
  dead run or a surprising finding, and delete your own device when you are
  finished rather than leaving it booted for the next session to inherit. Two
  sessions keeping one each is fine; six is the error above.
- **A timeout that reproduces alone is not the machine, and it does not end
  when the audit does.** Measured 25 Sep 2026: `testFamilyTreeAtSize` timed
  out at the largest text size on every run at any load, because the audit's
  contrast check reads a text element's pixels into a set of colours, and
  text on glass or under it — a `.bordered` capsule, the tab bar — is more
  colours than its fifteen seconds hold. And every audit that gave up left a
  thread of testmanagerd running, until twenty of them had the daemon at
  800 % of a core and every session's tests failing to start with "Timed out
  waiting for AX loaded notification". `sample <pid>` names the work in a
  minute; `kill -9` is what ends it; the header of
  `AccessibilitySweepTests.swift` has the measurement.
- `xcrun simctl` is not on the path xcodebuild hands to its own child processes,
  so a test run ends with `unable to find utility "simctl"` while collecting
  diagnostics. It is noise from a run that had already failed, not the failure.
  Prepending `/Applications/Xcode.app/Contents/Developer/usr/bin` to `PATH`
  silences it.
- The name is **Kinlore** and the bundle ID is `com.kinlore.app` (renamed
  15 Aug 2026, PLAN.md §10). The backend's Cloudflare resources are deliberately
  still called `memorize`: renaming an R2 bucket means making an empty new one,
  and rule 3 lives in that bucket.
- Purchases go through the **RevenueCat Test Store**, not App Store Connect
  products. No paid Apple Developer account is needed — and **the Test Store has
  no bundle-id field**, so the rename needed nothing there. It is keyed by its
  API key. A bundle id becomes a RevenueCat setting only when an App Store app
  config is added, which is a §2.1 decision and not a current one.
