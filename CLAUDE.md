# Kinlore

A family's shared memory archive. An old person rambles; the AI gives it
structure. Side project for RevenueCat Shipaton 2026.

**Target category: Next Gen** (student category). **No App Store release** — it
was dropped because upper secondary school starts around 11 Aug and there is no
time for App Store Connect. Purchases run on the RevenueCat Test Store.

The official Devpost deadline is **30 Sep 2026, 23:45 PDT** (= 1 Oct, 09:45
Finnish time); **28 Sep is an internal buffer**, not the real limit. One
eligibility question is settled, confirmed by RevenueCat staff in Aug 2026 —
do not re-research it:

- **A non-qualifying school email domain is not a bar.** Student status is
  verified at submission; a student ID or letter of enrolment is accepted when
  the domain is not on the JetBrains/swot list.

**The repository is private, and stays private until submission. That is a
decision, not a task left undone** — decided 9 Sep 2026, and this paragraph
exists because the file used to read as an overdue chore and every session
dutifully raised it again. Do not raise it again.

Next Gen's rule, quoted from the rules page rather than paraphrased: *"The
repository must be public and open source by including an open source license
file. This license should be detectable and visible at the top of the repository
page."* It applies to Next Gen alone; no other category asks for a repository.

The dates that set the window, read from the same page on 9 Sep 2026:
submission closes **30 Sep 23:45 PDT**, judging runs **1–13 Oct**, and winners
are announced **21 Oct**. So the obligatory exposure is the fourteen days from
submission to the end of judging — which is what made the timing a free choice
rather than a risk to sit on.

**Flip it on 28 Sep, the internal buffer, not on the 30th.** Two things can only
be seen once the repo is public and neither should be met for the first time on
a deadline evening: whether GitHub actually *detects* the licence and shows it
at the top of the page, and whether Pages serves `docs/index.html` — whose four
links into the repository answer 404 until the moment it flips. A minute-long
dry run, public and straight back to private, settles both at no cost.

Nothing about safety is holding it: `.dev.vars` is in `.gitignore`, has never
been committed, and no key-shaped string appears anywhere in history. It is one
setting, not a cleanup. What it costs to wait is that GitHub Actions stays paid
until then — which is why `ci.yml` runs its expensive half only on pull requests
— and that Pages is off, so the page nobody can reach yet is also the DSA
contact surface. Both are priced and accepted.

Two consequences for anything written here in the meantime. Everything in this
file about the repo being a shop window is about the day it opens, not today.
And a public repository publishes its **history**, not merely its head — so what
goes into a commit now is as permanent as what goes into `main`, and unbuilt
plans belong outside the repository entirely.

**The schedule is built around school:** the heaviest work (backbone + magic
moment) happens 4–10 Aug during the holiday, not alongside school. When time
runs out, cut in the order given in PLAN.md §5 — it was decided in advance so
that nobody has to choose while exhausted.

Plan and scope: [docs/PLAN.md](docs/PLAN.md). **Read it before adding features** —
the scope is deliberately cut, and every addition requires a removal.

## Language — this repo is written in English

The category judges the **public source code**, so the repo is a shop window and
not just a tool. Two languages coexist here on purpose, and the boundary is not
negotiable:

| Audience | Language | Covers |
|----------|----------|--------|
| Whoever reads the repo | **English** | Docs, code comments, commit messages, identifiers, developer-facing log output, test names, debug launch arguments, config comments |
| Whoever uses the app | **Finnish, written; English, default** | Every string the user sees or hears — see the mechanism below |

**The app speaks both, and the mechanism is the part to understand before
touching anything.** Since 30 Aug 2026:

- **The Finnish strings in the Swift source are the KEYS.** SwiftUI reads a
  string literal in `Text`, `Button`, `Label`, `navigationTitle` and
  `accessibilityLabel` as a `LocalizedStringKey`, and the export uses
  `String(localized:)`. So writing a new user-facing string still means writing
  it in Finnish, in the source, exactly as before.
- **Both tables translate away from those keys.** `en.lproj` carries the
  English; `fi.lproj` maps every key to itself. The Finnish table is not
  redundant — English is the development language, the fallback for a missing
  key is the development language rather than the key, and an empty `fi.lproj`
  hands a Finnish phone English. That happened, and only a screenshot showed it.
- **`scripts/localisation-check.mjs` fails if either table is short.** Nothing
  else reports a missing translation: the Finnish build stays perfect, the
  build succeeds, and the English one shows one Finnish word in the middle of a
  screen nobody runs except on filming night.
- **English is the default because the app is presented, judged and filmed in
  it.** A Finnish phone still gets Finnish. Nothing in the app switches
  language; it follows the device.
- **A runtime `String` is looked up only if you look it up.** `Text`,
  `navigationTitle` and `accessibilityLabel` localise a *literal*; handed a
  `String` variable they show it verbatim. So a fallback name that lives in a
  computed property — `Subject.displayTitle`'s *"Valokuva"*, `SubjectKind.label`
  — must be built with `String(localized:)`. Both keys sat in both tables from
  30 Aug 2026 and an English phone still read "Valokuva" on every untitled
  photograph until 6 Sep, and the check above could not see it: it counts keys,
  not lookups.

Two things stay Finnish even though no user reads them, and each has a reason:

1. **Test transcripts and TTS sample texts** (`scripts/`). That is the input
   under test. Translating it would test a different thing.
2. **The Finnish half of the LLM prompts** (`backend/src/extract.ts`,
   `backend/src/transcribe.ts`). There are now two of each, and the English one
   is not a translation: rule 1 teaches a model about Finnish case endings and
   has no English counterpart, and the filler words and common nouns in rules 2,
   3 and 5 are the part that was tuned. **Which prompt runs follows who is
   SPEAKING**, not who is reading the screen — the app sends `lang`, absent
   means Finnish. The Finnish was tuned by measurement; do not edit it on the
   way past. `MAX_WORDS_PER_SECOND` is two numbers for the same reason.

Everything new follows this rule from the start. Do not write a Finnish comment
now and translate it later — the translation pass has already happened once.

## Layout

```
ios/       SwiftUI app, XcodeGen (project.yml → .xcodeproj)
backend/   Cloudflare Worker + D1 (metadata) + R2 (photos and audio)
scripts/   asr-bench.mjs — Finnish speech recognition comparison
docs/      PLAN.md, ARCHITECTURE.md, UX.md, SETUP.md, VIDEO.md, RECOVERY.md
```

## Data model

A single `subject` table covers photos, people, places and events. A `memory`
attaches to any subject. That is why "write a memory about this photo" and "tell
us what grandmother was like" are the same screen and the same code path — do
not split these into separate implementations, it is the core of the whole
architecture. Schema: [backend/schema.sql](backend/schema.sql).

## Rules that do not bend

1. **The primary user is 80 years old.** Dynamic Type up to XXL, VoiceOver,
   large tap targets. If a new screen does not work at the largest text size, it
   is not done. This is not a compliance checklist; it is the product.
   **Colours come from `Elder.swift` and the accent colour asset, never from
   `.secondary`, `.tertiary`, `.orange`, `.red` or the system blue** — every one
   of them measures below the contrast minimum, and contrast is the one rule
   eyes cannot check. Run the accessibility tests after touching any screen; see
   [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §15.
2. **Telling is never paywalled.** The paywall limits photos and AI minutes, not
   the act of writing or dictating a memory.
3. **The original audio and the raw transcript are always kept.** The speaker
   may no longer be around to ask. `memory.audio_r2_key` and
   `memory.raw_transcript` are not intermediate steps; they are the product.
4. **AI proposes, a human confirms.** A person or relationship inferred by the
   AI is created with `confirmed = 0`. Unconfirmed never appears in the family
   tree as fact. A wrong relationship is worse than a missing one.

   **The strongest kind is blind**: somebody who was never shown the name and
   arrived at it anyway has genuinely recognised the person. A card with the
   name already on it gets tapped "yes" without being read.

   That instrument was lost when the guessing round was cut on 16 Aug 2026
   (PLAN.md §5, row 8) and **came back on 30 Aug 2026 in a cheaper shape**: the
   Kerro tab's card shows the photograph the name was heard in and asks *"kuka
   tässä on?"* over four names with the proposal unmarked among them
   (`BlindConfirmation`, ARCHITECTURE §23). The join it needed —
   `memories(mentioning:)` — was already in the model, and a photograph has no
   name in it to leak, which is the whole cost the round's mask used to carry.

   Since 5 Sep 2026 the card follows whose phone it is: on a reader's phone it
   stays on the Kerro tab; on a grandparent's (the text-floor signal) it sits
   on Albumi (called Muistot until 13 Sep 2026) in the reading loop, and her Kerro tab is the button and nothing
   else (`BlindCardView`, one view in both places).

   The orange proposal row on the person list and in the Tell result is still
   there and is still the weaker instrument. It is what answers a proposal the
   blind card cannot reach: a name heard while talking about a person rather
   than a picture has no face to put in front of anybody.

   Two things the blind card must keep. **A wrong answer is never called
   wrong** — the app does not know who is in the photograph either, and saying
   otherwise is the guess asserted as fact. And **nothing on that screen may
   name the proposal**, including the photograph's accessibility label; that
   failure is silent, because a card that leaks its answer still looks exactly
   like a card that works. `BlindConfirmationTests` asserts it by walking every
   element on screen.
5. **Uncertainty is stored, not rounded.** "Sometime in the fifties" goes into
   `date_start`/`date_end` with precision `decade`. Do not force a date.
6. **No login screen.** Identity is a UUID in the Keychain
   (`kSecAttrSynchronizable`); you join a family through an invite link. Sign in
   with Apple *would* be possible and is still not used as a gate, at most as an
   optional account recovery for a paying member in v1.1.
   See [docs/SETUP.md](docs/SETUP.md).
7. **`OPENROUTER_API_KEY` lives only as a Worker secret.** The app uploads audio
   and text to the Worker; the Worker calls OpenRouter.

   This rule used to end "the repo is public — check `.dev.vars` before every
   push", which is a reminder and not a check, and it was the only one of these
   ten rules with nothing enforcing it. **`scripts/secret-check.mjs` enforces it
   now**, first in `verify.sh` and in well under a second on a quiet machine:
   the tree, every blob that has ever existed, `.dev.vars` being both ignored
   and untracked, and its own matcher against a specimen of each key shape so
   it cannot go quietly green.

   It is first in that file because it is the only failure here that the next
   commit cannot undo. **A public repository publishes its history, not its
   head** — so a key committed today and deleted tomorrow is published on 28 Sep
   regardless, and the only remedy left is rotating the key and rewriting every
   commit after it. The check counts what it scanned on every run, so these
   are records of runs rather than claims about now: 1370 blobs across 269
   commits on 10 Sep 2026, 1414 across 287 on 12 Sep. Clean both times.
8. **`provider: { data_collection: "deny" }` is unconditional**, never a
   per-call flag. The content is a family's memories of dead relatives. As a
   flag it would be forgotten on some call.
9. **The cause of an error never leaks to the client — and the log is not
   somewhere to leak it instead.** The app gets `{ error: "upstream_failed" }`.
   Upstream bodies and model output stay out of `console.error` as well:
   `observability` is on in `wrangler.jsonc`, so Workers Logs is a store beside
   D1 and R2 — and it is the one store a family cannot export, cannot clear with
   *"Tyhjennä tämä laite"*, and never agreed to. This rule used to send them
   there on purpose, and it cost 300 characters of the just-told memory on every
   extraction failure until 16 Aug 2026 (PLAN.md §10). Log shape, length,
   counts, status and the provider's own error codes. **An error message must
   not interpolate content** — not a title, not a transcript, not a name —
   because `message` is the one field of a thrown error that reaches the log.
10. **A file written by an older version must still load.** The local archive
    is one JSON file, and Swift's synthesized `Codable` does not use a
    property's default value for a missing key: a non-optional field added
    with a default throws on every old file. Until 4 Sep 2026 `load()`
    answered that by coming up empty and letting the next `save()` write
    empty over the family's only local copy. So a new persisted field is
    `Optional`, or `Snapshot`'s hand-written `init(from:)` reads it
    `IfPresent`; a file that still cannot be read is moved aside, never
    overwritten, and the app says so.

    **Two halves of that are narrower than they read, corrected 9 Sep 2026.**
    The `init(from:)` escape exists only for the ten keys `Snapshot` itself
    declares. A field added to `Subject`, `Memory`, `Relation` or
    `FollowUpQuestion` gets neither protection — `Models.swift` has no
    hand-written decoder anywhere, so those four use the synthesized `Codable`
    this rule is a warning about. **For them, `Optional` is not the preferred
    option; it is the only one.** And `schemaVersion` is written and decoded
    and read by nothing: it is a record of what wrote the file, available to a
    future migration, not a mechanism that does anything today.
    `-store outdated` and `-store unreadable` drive the two UI tests in
    `SilentFailureTests` that keep this true — run them after touching
    `Snapshot` or any persisted model.

## The assistant's rules — checked in, not personal setup

Most of the typing here is Claude Code's, and since **28 Aug 2026** it happens
under a guideline file that lives in the repository:
[`.claude/skills/karpathy-guidelines/SKILL.md`](.claude/skills/karpathy-guidelines/SKILL.md),
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
motion — and it earns it against [docs/index.html](docs/index.html), which
when this was written on 28 Aug 2026 was the one surface in this project with
no check of its own. `scripts/page-check.mjs` arrived two days later and runs
in `verify.sh`. The app is not the customer:
the skill's SwiftUI table is 50 rows of basics with zero VoiceOver rows and zero
contrast rows, against the 68 accessibility sweeps that already run here, each
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

### The closing recap is written as a matriculation essay

Requested 16 Sep 2026. The author sits the Finnish matriculation exam's
kirjoitustaito paper, and the one message every session ends with — the recap
that says what was done — is the one piece of prose read every single day. So
it doubles as a specimen: **the message that closes a task is written in
Finnish, in the form of a kirjoitustaidon koe answer at laudatur level (55–60 p
on the YTL 0–60 scale).** Progress notes during the work, answers to plain
questions and the one-line "about to do X" before starting are not affected —
only the recap that ends a task.

What the form asks for, in the order an assessor reads it:

- **An otsikko** that fits the text in both style and content, then an opening
  paragraph that frames the task as a claim or a question rather than a list.
- **One idea per paragraph**, paragraphs that hand over to each other, and a
  closing paragraph that answers the opening — not a "Yhteenveto" heading that
  restates it.
- **The work is the aineisto.** Files, commands, measurements and test results
  are referred to the way an essay refers to its pohjateksti — named and
  interpreted in the running text, not pasted as a table. A command the reader
  must run may follow the essay in a code block.
- **Yleiskieli to the exam's standard:** varied sentence structure, precise
  vocabulary, no filler, no rhetorical questions in place of content, no bullet
  points and no headings inside the essay itself.

"To some extent" is the brief: it is still a recap. Everything the reader needs
— what changed, what was verified and how, what failed or was skipped, what
remains — is in it and exact, and nothing is invented for the sake of the form.
Identifiers keep their exact spelling inside the prose. A recap of ten minutes'
work is three paragraphs; a recap of a day's work may approach the exam's
length, about 6 000 characters without spaces, and never exceeds it.

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
GIT_INDEX_FILE=$IDX git update-index --cacheinfo 100644 "$BLOB" <path>
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
# a brother with no line to his sister. None of them fails a build, and a
# screenshot shows a tree either way. Costs nothing. Run it after touching
# FamilyTreeLayout.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/family-tree-layout-check \
  scripts/family-tree-layout-check.swift ios/Kinlore/Services/FamilyTreeLayout.swift \
  && /tmp/family-tree-layout-check

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
# cannot wipe it, correcting the title clears it, and rubbish is refused. Costs
# nothing — no AI call — but needs `npx wrangler dev` running.
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
# unchanged — and the same one word would unlock `transcribe.ts`, `family.ts`
# and `worker.ts`, the only other modules Node still refuses.
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
