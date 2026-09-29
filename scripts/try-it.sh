#!/bin/bash
# The real app, on a simulator of its own, in one command.
#
#   ./scripts/try-it.sh             Kinlore against the deployed Worker
#   ./scripts/try-it.sh --two       the same on two simulators, to share a family
#   ./scripts/try-it.sh --example   an invented family's archive, on stubs
#
# Xcode opens this project on the `Kinlore` scheme, a Debug build that runs on
# stubs, and the stubs cannot listen: a recording comes back as one of three
# sample tellings whatever was said (`StubTranscriptionService`). That is right
# for the tests and wrong for anybody finding out whether the app hears them.
# So this builds `Kinlore Production`, the Release build with the deployed
# Worker's address compiled in (`AppServices.productionURL`), and what is said
# is what gets written down. It launches the app with `-tryIt YES`, as that
# scheme's Run does in Xcode.
#
# It touches nothing it did not make. Its simulators are its own, found by name
# and made on the first run: "Kinlore Try", "Kinlore Try 2" with --two and
# "Kinlore Example" with --example, on the newest iOS runtime installed that
# the app runs on. Its build goes to build/try-it, which git ignores. A second
# run reuses both, keeps what the app holds and rebuilds only what changed. It
# installs nothing on the Mac: Xcode and XcodeGen are asked for, never fetched.
#
# The terminal gets a line per step. What xcodegen and xcodebuild say goes to
# build/try-it/build.log, and a failure prints the end of it.

set -euo pipefail

usage() {
	sed -n 's/^#   \(\.\/scripts\/try-it\.sh\)/\1/p' "$0"
}

MODE=real
case "${1:-}" in
	'') ;;
	--two) MODE=two ;;
	--example) MODE=example ;;
	-h | --help) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
esac
[ $# -le 1 ] || { usage >&2; exit 2; }

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
OUT=build/try-it
LOG=$OUT/build.log
BUNDLE=com.kinlore.app
mkdir -p "$OUT"
: >"$LOG"

# fail <what went wrong> — and the end of the log, which says why.
fail() {
	{
		echo
		echo "$1"
		echo
		# The compiler's own lines first: the end of an xcodebuild log lists
		# which steps failed rather than why. Matched as xcodebuild writes
		# them, because a bare "error" also matches the RevenueCat package's
		# ErrorUtils.swift on every line that names it.
		grep -E '(^|: )error: ' "$LOG" | sort -u | sed -n '1,8s/^/    /p' || true
		echo "The end of $LOG:"
		tail -n 20 "$LOG" | sed 's/^/    /'
	} >&2
	exit 1
}

# --- What it needs ----------------------------------------------------------

# Xcode, found the way xcrun finds it. When xcode-select still points at the
# Command Line Tools, which cannot build for iOS, xcodebuild refuses, and the
# usual place is tried for this run only; nothing on the Mac is changed. A
# DEVELOPER_DIR you set yourself is used as it is.
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcodebuild -version >/dev/null 2>&1 \
	&& [ -d /Applications/Xcode.app/Contents/Developer ]; then
	export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! XCODE=$(xcodebuild -version 2>/dev/null); then
	cat >&2 <<-'EOF'
		xcodebuild cannot run: Xcode is not installed, or xcode-select points at
		the Command Line Tools and Xcode is not in /Applications. Install Xcode 26
		or later and open it once, or name the Xcode you have:

		    DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer ./scripts/try-it.sh
	EOF
	exit 1
fi
XCODE=${XCODE%%$'\n'*}          # "Xcode 27.0"
major=${XCODE#Xcode }
major=${major%%.*}
if ! [ "$major" -ge 26 ] 2>/dev/null; then
	echo "Kinlore needs Xcode 26 or later, and this is $XCODE." >&2
	exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
	cat >&2 <<-'EOF'
		XcodeGen makes the Xcode project from ios/project.yml, and it is not
		installed. With Homebrew:

		    brew install xcodegen
	EOF
	exit 1
fi

case $MODE in
	real) NAMES=("Kinlore Try") ;;
	two) NAMES=("Kinlore Try" "Kinlore Try 2") ;;
	example) NAMES=("Kinlore Example") ;;
esac
if [ "$MODE" = example ]; then
	# The Koivula family a year or two in (LargeArchiveFixture), which is
	# invented and DEBUG-only. It replaces the archive on every launch that
	# carries it, so each run puts the example back as it was.
	SCHEME=Kinlore CONFIG=Debug
	ARGS=(-seed large)
else
	SCHEME="Kinlore Production" CONFIG=Release
	ARGS=(-tryIt YES)
fi

echo "Kinlore: the $SCHEME scheme ($CONFIG), built with $XCODE"
echo "- generating the Xcode project"
(cd ios && xcodegen generate) >>"$LOG" 2>&1 || fail "xcodegen could not generate the project."

# --- The simulators ---------------------------------------------------------

# The oldest iOS the app runs on, from the project itself.
TARGET=$(awk -F'"' '/^[[:space:]]+iOS:/ { print $2; exit }' ios/project.yml)

RUNTIMES=$OUT/runtimes.json
# field <key path> — one value from the runtime list simctl wrote as JSON.
field() { plutil -extract "$1" raw -o - "$RUNTIMES" 2>/dev/null || true; }
# at_least <version> <minimum> — whether the first is the second or later.
at_least() { printf '%s\n%s\n' "$2" "$1" | sort -V -C; }

# Sets RUNTIME and DEVICE_TYPE: the newest iOS runtime installed that is at
# least the app's target, and the newest iPhone it offers. Asked only when a
# simulator has to be made.
RUNTIME=''
pick_device() {
	local count i best='' version
	[ -z "$RUNTIME" ] || return 0
	xcrun simctl list runtimes available -j >"$RUNTIMES"
	count=$(field runtimes)
	for ((i = 0; i < ${count:-0}; i++)); do
		[ "$(field "runtimes.$i.platform")" = iOS ] || continue
		version=$(field "runtimes.$i.version")
		at_least "$version" "$TARGET" || continue
		if [ -z "$best" ] || at_least "$version" "$(field "runtimes.$best.version")"; then
			best=$i
		fi
	done
	if [ -z "$best" ]; then
		cat >&2 <<-EOF
			No iOS simulator runtime of $TARGET or later is installed. Xcode offers
			one in its Settings, under Components, or from the command line:

			    xcodebuild -downloadPlatform iOS
		EOF
		exit 1
	fi
	RUNTIME=$(field "runtimes.$best.identifier")
	RUNTIME_NAME=$(field "runtimes.$best.name")
	# simctl lists a runtime's devices newest first, so the first iPhone is
	# the newest one.
	count=$(field "runtimes.$best.supportedDeviceTypes")
	for ((i = 0; i < ${count:-0}; i++)); do
		if [ "$(field "runtimes.$best.supportedDeviceTypes.$i.productFamily")" = iPhone ]; then
			DEVICE_TYPE=$(field "runtimes.$best.supportedDeviceTypes.$i.identifier")
			DEVICE_NAME=$(field "runtimes.$best.supportedDeviceTypes.$i.name")
			return 0
		fi
	done
	echo "$RUNTIME_NAME offers no iPhone to simulate." >&2
	exit 1
}

# udid_of <name> — the available simulator with exactly that name, if any.
udid_of() {
	xcrun simctl list devices available \
		| sed -nE "s/^[[:space:]]+$1 \(([0-9A-F-]{36})\) \(.*/\1/p" \
		| sed -n 1p
}

# simulator <name> — sets SIM to this script's simulator of that name, and
# makes it on the first run. Nothing else is ever looked up by name here, so a
# simulator somebody else made is never booted, changed or deleted.
simulator() {
	SIM=$(udid_of "$1")
	[ -z "$SIM" ] || return 0
	pick_device
	SIM=$(xcrun simctl create "$1" "$DEVICE_TYPE" "$RUNTIME")
	echo "- made the simulator \"$1\": $DEVICE_NAME, $RUNTIME_NAME"
}

UDIDS=()
for name in "${NAMES[@]}"; do
	simulator "$name"
	UDIDS+=("$SIM")
done

# --- The app ----------------------------------------------------------------

echo "- building; the first build takes several minutes, and $LOG has the detail"
# ONLY_ACTIVE_ARCH because a Release build otherwise compiles for every
# architecture the simulator supports, and this one only has to run on this Mac.
xcodebuild -project ios/Kinlore.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
	-destination "platform=iOS Simulator,id=${UDIDS[0]}" \
	-derivedDataPath "$OUT/DerivedData" ONLY_ACTIVE_ARCH=YES build >>"$LOG" 2>&1 \
	|| fail "The build failed. If Xcode has never been opened on this Mac, open it once so that it can finish installing, and run this again."
APP=$OUT/DerivedData/Build/Products/$CONFIG-iphonesimulator/Kinlore.app
[ -d "$APP" ] || fail "The build reported success and left no $APP."

echo "- starting the simulator and opening Kinlore"
for udid in "${UDIDS[@]}"; do
	xcrun simctl bootstatus "$udid" -b >>"$LOG" 2>&1 || fail "The simulator did not start."
done
# Simulator draws a window for every simulator that is running. The argument
# only chooses which one comes to the front when it was not open already.
DEV=${DEVELOPER_DIR:-$(xcode-select -p)}
open -a "$DEV/Applications/Simulator.app" --args -CurrentDeviceUDID "${UDIDS[0]}" 2>/dev/null \
	|| open -a Simulator
for udid in "${UDIDS[@]}"; do
	# An install over the last run's keeps the family and everything told.
	xcrun simctl install "$udid" "$APP" >>"$LOG" 2>&1 || fail "Kinlore did not install."
	xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" "${ARGS[@]}" \
		>>"$LOG" 2>&1 || fail "Kinlore did not launch."
done

# --- What to try ------------------------------------------------------------

case $MODE in
	real)
		cat <<-'EOF'

			Kinlore is open on the simulator "Kinlore Try", and it is the real app:
			what you say goes to the deployed Worker and comes back written down.

			  1. Start a family archive: type your name and press "Create the
			     archive". Do not choose to keep the memories on this phone only,
			     because nothing said in such an archive is written out as text.
			     The sheet that follows asks whose memories to keep; "Close"
			     skips it.
			  2. The Tell tab opens on an example to read aloud:

			       My grandmother Anna grew up in Helsinki. She married Walter sometime
			       in the fifties, and he always had the camera.

			     Press the microphone and read it, or tell something of your own.
			     iOS asks for the microphone first, and the Mac may then ask on
			     Simulator's behalf. "Type it for me" puts it in the write field
			     instead, and "Save" sends it.
			  3. See what comes back: the people as proposals nobody has confirmed
			     yet, and "sometime in the fifties" kept as the 1950s rather than a
			     guessed year. A spoken telling is followed by questions asked out
			     loud; answer them, or press "That is enough for now".

			Two phones sharing one family:  ./scripts/try-it.sh --two
			An invented example family:     ./scripts/try-it.sh --example
		EOF
		;;
	two)
		cat <<-'EOF'

			Kinlore is open on two simulators, "Kinlore Try" and "Kinlore Try 2", and
			both are the real app. To put them in one family:

			  1. On "Kinlore Try", start a family archive: type your name and press
			     "Create the archive", and "Close" the sheet that follows. Then
			     Settings, which is the gear on People, or the menu on Family tree
			     once somebody is in it. There: "Family members and invitations",
			     "Invite a family member", give a name, then "Create an invitation",
			     "Share the invitation" and "Copy".
			  2. On "Kinlore Try 2", press "Join with an invitation link", paste the
			     whole invitation and press "Join a family". The two simulators
			     share the Mac's clipboard.
			  3. Tell something on one of them. The other fetches it when Kinlore
			     comes to the front there: Shift-Command-H, then Kinlore.

			An invitation is valid for a week and lets one person in.
		EOF
		;;
	example)
		cat <<-'EOF'

			This is the example you asked for, on this simulator only ("Kinlore
			Example"): a family's archive a year or two in. Everything in it is
			invented: the Koivula family and its people, the pictures, which the app
			drew here, and the tellings.

			It is a Debug build on stubs, with no server behind it. A telling here
			comes back as one of three sample tellings, whatever you say, so nothing
			you say is heard, and the next run of --example puts the example back
			as it was.

			To be heard, run ./scripts/try-it.sh without --example.
		EOF
		;;
esac
