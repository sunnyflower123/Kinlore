#!/bin/bash
# The README's pictures, and Devpost's, from one run.
#
# Every image under docs/media/ is a screenshot of a seeded state on a
# simulator, in English, because the app is presented and judged in English.
# The first set was taken by hand on 16 Aug 2026 and stayed Finnish for six
# weeks, because retaking seven images by hand is an afternoon nobody has on
# the last day. This is that afternoon as one command, so that the pictures
# can follow the app instead of trailing it.
#
#   KINLORE_TEST_SIM=<udid> scripts/readme-shots.sh <Kinlore.app> [<devpost-dir> [<prints-dir>]]
#
# <Kinlore.app> is a DEBUG build for the simulator (the seeds and `-screen`
# arguments exist in no other build; docs/SETUP.md lists them):
#
#   xcodebuild -project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphonesimulator \
#     -destination "id=$KINLORE_TEST_SIM" -derivedDataPath /tmp/dd build
#   → /tmp/dd/Build/Products/Debug-iphonesimulator/Kinlore.app
#
# The simulator must be yours and booted (CLAUDE.md: a run installs, launches
# and terminates the app on it). An iPhone 16 draws 1179 × 2556, which is the
# size Devpost asks for; an iPhone 17 Pro draws 1206 × 2622, which it does not
# — measured 26 Sep 2026, and the run measures it again rather than trusting
# the name. The README does not care about the size; the second argument does.
#
# The film seeds draw a photograph only when the app's container holds one:
# `Documents/film-photo.jpg`, then `film-photo-2.jpg` onwards (docs/VIDEO.md).
# The third argument names a folder holding the video project's prints as
# `p1.jpg` … `p6.jpg`, and the run copies them in before the Devpost shots;
# without it those states show a placeholder. The prints are not in this
# repository, and the README's pictures never use them.
#
# Nothing here talks to a server: `-api ""` on every launch, so no OpenRouter
# credit is spent and no family is created anywhere. The status bar reads 9:41
# throughout — clear it before running the accessibility sweep on the same
# device, or the audit invents contrast findings (docs/VIDEO.md).
#
# A still is kept only once two screenshots three seconds apart are the same
# bytes, because on a busy machine a fixed wait photographs a half-drawn screen
# that looks finished. Forty seconds is the ceiling, and the run says when a
# screen never settled. The two GIFs are timed captures instead, since what
# they show is the app moving.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
PATH="$DEVELOPER_DIR/usr/bin:$PATH"

SIM="${KINLORE_TEST_SIM:?set KINLORE_TEST_SIM to a booted simulator of your own}"
APP="${1:?the first argument is a Debug Kinlore.app built for the simulator}"
DEVPOST="${2:-}"
PRINTS="${3:-}"
BUNDLE=com.kinlore.app
MEDIA="$ROOT/docs/media"
ICON="$ROOT/ios/Kinlore/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

[ -x "$APP/Kinlore" ] || { echo "not an app bundle: $APP" >&2; exit 2; }

TMP=$(mktemp -d)
cleanup() {
	xcrun simctl status_bar "$SIM" clear >/dev/null 2>&1 || true
	xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
	rm -rf "$TMP"
}
trap cleanup EXIT

echo "— the device —"
xcrun simctl io "$SIM" screenshot --type=png --mask=black "$TMP/probe.png" >/dev/null 2>&1
SIZE=$(sips -g pixelWidth -g pixelHeight "$TMP/probe.png" | awk '/pixel/ { printf "%s%s", sep, $2; sep = "x" }')
echo "  $SIM draws $SIZE"
if [ -n "$DEVPOST" ] && [ "$SIZE" != "1179x2556" ]; then
	echo "  Devpost wants 1179x2556 — an iPhone 16 simulator draws that; this one does not" >&2
	exit 2
fi

# The status bar clock follows the DEVICE's language and region, not the
# app's launch arguments, and a simulator created here inherits the host's
# en_FI — so "9:41" was drawn as "9.41" until the device itself was English.
# The device is yours by contract, so the run sets both and reboots it once;
# measured 26 Sep 2026, a SpringBoard restart was not enough and a reboot was.
if [ "$(xcrun simctl spawn "$SIM" defaults read .GlobalPreferences AppleLocale 2>/dev/null)" != "en_US" ]; then
	xcrun simctl spawn "$SIM" defaults write .GlobalPreferences AppleLanguages -array en-US
	xcrun simctl spawn "$SIM" defaults write .GlobalPreferences AppleLocale -string en_US
	xcrun simctl shutdown "$SIM"
	xcrun simctl boot "$SIM"
	xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1
	echo "  region set to en_US, rebooted"
fi

echo "— the app —"
xcrun swiftc -O -o "$TMP/gif" "$ROOT/scripts/frames-to-gif.swift"
xcrun simctl install "$SIM" "$APP"
# A fresh simulator has not answered the microphone question, and the alert
# then sits over every later launch (the note under `-mic unasked`, SETUP.md).
xcrun simctl privacy "$SIM" grant microphone "$BUNDLE"
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 \
	--wifiBars 3 --cellularBars 4 --operatorName ""
echo "  installed, microphone granted, status bar 9:41"

# `--mask=black` on every screenshot. Left to its default, the simulator draws
# the Dynamic Island as a black pill in some frames and not in others — at
# launch, while the app is listening, and whenever it pleases: measured 26 Sep
# 2026 at 3 of 24 shots over three launches of one card, 10 of 30 GIF frames,
# and one still whose two "identical" shots had both caught it. `--mask=ignored`
# does not stop it (4 of 25 frames of the interview still had the island, and
# 23 of them black corners), so the mask is drawn on every frame instead: the
# same face in every picture, corners and island, which is the face an
# iPhone 16 has. The pictures this replaces had the island in every frame too.
launch() {
	xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
	sleep 2   # terminate and an immediate launch race, and the launch loses silently (docs/VIDEO.md)
	xcrun simctl launch "$SIM" "$BUNDLE" -AppleLanguages "(en)" -AppleLocale en_US -api "" "$@" >/dev/null
}

# still <file> <launch arguments…>
still() {
	local file=$1; shift
	launch "$@"
	local a="$TMP/a.png" b="$TMP/b.png" waited=0
	rm -f "$a"
	while :; do
		sleep 3
		waited=$((waited + 3))
		xcrun simctl io "$SIM" screenshot --type=png --mask=black "$b" >/dev/null 2>&1
		if [ -f "$a" ] && cmp -s "$a" "$b"; then break; fi
		if [ "$waited" -ge 40 ]; then
			echo "    never settled; keeping the frame at 40 s" >&2
			break
		fi
		mv "$b" "$a"
	done
	mv "$b" "$file"
	echo "  $(basename "$file")  (${waited} s)"
}

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
sleep_until() { perl -MTime::HiRes=time,sleep -e '$d = $ARGV[0] - time; sleep $d if $d > 0' "$1"; }

# frames <out.gif> <count> <seconds between captures> <seconds each frame shows> <launch arguments…>
frames() {
	local gif=$1 count=$2 every=$3 shows=$4; shift 4
	local dir="$TMP/$(basename "$gif" .gif)" i=0 t0
	rm -rf "$dir"; mkdir -p "$dir"
	launch "$@"
	t0=$(now)
	while [ "$i" -lt "$count" ]; do
		sleep_until "$(perl -e 'printf "%.3f", $ARGV[0] + $ARGV[1] * $ARGV[2]' "$t0" "$every" "$i")"
		xcrun simctl io "$SIM" screenshot --type=png --mask=black "$(printf '%s/%03d.png' "$dir" "$i")" >/dev/null 2>&1
		i=$((i + 1))
	done
	"$TMP/gif" "$dir" "$gif" 380 "$shows"
	echo "  $(basename "$gif")  ($count frames, one every ${every} s, $(du -k "$gif" | cut -f1) KB)"
}

echo "— docs/media —"
# `-tab` is named on every still that has one, and `-person` on the card:
# without them a launch keeps the tab the previous launch left and opens
# whichever person card sorts first, and picture 1 came out as the Album and
# picture 4 as Kalle on 26 Sep 2026, in a run that had looked identical.
still "$MEDIA/01-tell.png"        -seed archive -tab tell
still "$MEDIA/02-result.png"      -seed empty -screen result
# The blind card under rule 4. `-seed blind` is the plain archive with the
# fixture's drawn photograph on `demo-photo`, which is what lets the card be
# built at all; the film's prints are for Devpost and never reach docs/media.
still "$MEDIA/03-who-is-this.png" -seed blind -tab tell
# `-you` names the phone owner's own card. Since 26 Sep 2026 a person card
# offers "This is me" on every confirmed card while the phone is linked to
# no card, and the demo owner is linked to none; naming another card keeps
# the row off the one being photographed, which is the card as a relative
# sees it.
still "$MEDIA/04-person.png"      -seed archive -tab people -screen person -person demo-sanni -you demo-eeva
still "$MEDIA/05-family.png"      -seed family -tab people -screen family
still "$MEDIA/06-result-xxxl.png" -seed empty -screen result \
	-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
# The stub pipeline reaches the result about three seconds after launch, and
# the interview's first spoken round ends by itself (docs/VIDEO.md, SETUP.md).
frames "$MEDIA/demo.gif"           12 1.0 0.50 -seed empty -screen result
frames "$MEDIA/demo-interview.gif" 18 1.3 0.55 -seed empty -screen interview

if [ -n "$DEVPOST" ]; then
	echo "— $DEVPOST —"
	mkdir -p "$DEVPOST/spares"
	if [ -n "$PRINTS" ]; then
		DOCS="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)/Documents"
		mkdir -p "$DOCS"
		cp "$PRINTS/p1.jpg" "$DOCS/film-photo.jpg"
		for i in 2 3 4 5 6; do cp "$PRINTS/p$i.jpg" "$DOCS/film-photo-$i.jpg"; done
		echo "  six prints copied into the app's container"
	fi
	# Five for the gallery, chosen on 26 Sep 2026 from twenty-five states: the
	# one button, the blind card over a photograph (rule 4's stronger
	# instrument), the album by decade, a person card whose telling and
	# proposal are in English, and the family's quota. The tree is not among
	# them: it opens on your own card and only a tap fits the whole family.
	cp "$MEDIA/01-tell.png"   "$DEVPOST/1-tell.png"
	still "$DEVPOST/2-who-is-this.png" -seed film-week -tab tell
	still "$DEVPOST/3-album.png"       -seed film-week -tab memories
	still "$DEVPOST/4-toivo.png"       -seed film -tab people -screen person -person demo-film-toivo -you demo-film-aino
	cp "$MEDIA/05-family.png" "$DEVPOST/5-family.png"
	# And four spares for whoever makes the final choice.
	cp "$MEDIA/02-result.png" "$DEVPOST/spares/result.png"
	still "$DEVPOST/spares/people.png"     -seed film -tab people -people list
	still "$DEVPOST/spares/elina.png"      -seed clan -tab people -screen person -person clan-elina -you clan-mikko
	still "$DEVPOST/spares/photograph.png" -seed film-family -tab people -screen person -person demo-photo
	cp "$ICON" "$DEVPOST/icon-1024.png"
	echo "  icon-1024.png  ($(sips -g pixelWidth -g pixelHeight "$ICON" | awk '/pixel/ { printf "%s%s", sep, $2; sep = "x" }'))"
fi

echo
echo "done — open every image before committing it"
