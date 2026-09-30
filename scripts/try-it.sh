#!/bin/bash
# The real app, on a simulator of its own, in one command.
#
#   ./scripts/try-it.sh             Kinlore against the deployed Worker
#   ./scripts/try-it.sh --two       the same on two simulators, to share a family
#   ./scripts/try-it.sh --example   an invented family's archive, on stubs
#   ./scripts/try-it.sh --paywall   the paywall, with a RevenueCat Test Store key
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
# and made on the first run: "Kinlore Try", "Kinlore Try 2" with --two,
# "Kinlore Example" with --example and "Kinlore Paywall" with --paywall, on the
# newest iOS runtime installed that the app runs on. Its build goes to
# build/try-it, which git ignores. A second run reuses both, keeps what the app
# holds and rebuilds only what changed. It installs nothing on the Mac: Xcode
# and XcodeGen are asked for, never fetched.
#
# --paywall is the one run that needs a key: RevenueCat's Test Store key, which
# the paywall needs and the repository does not hold. The SDK stops a Release
# build that is given one (`checkForSimulatedStoreAPIKeyInRelease` in
# purchases-ios), so --paywall builds the Debug `Kinlore` scheme and points it
# at the deployed Worker through the app's settings, where the address and
# the key stay for a launch from the home screen as well. The key is asked for
# without being shown, or read from KINLORE_RC_KEY. It is never printed or
# logged, and it is written nowhere but the app's settings on "Kinlore Paywall".
# The Release runs take `rcKey` out of their own simulators' settings before
# they launch, because a Test Store key left there would stop them the same way.
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
	--paywall) MODE=paywall ;;
	-h | --help) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
esac
[ $# -le 1 ] || { usage >&2; exit 2; }

# The Test Store key, for --paywall. It leaves the environment at once, in
# every mode, so that nothing this script starts inherits it, and tracing is
# off because a trace would print it.
{ set +x; } 2>/dev/null
KEY=${KINLORE_RC_KEY:-}
unset KINLORE_RC_KEY

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

if [ "$MODE" = paywall ]; then
	# Asked for before the build, so that a wrong key costs no minutes.
	if [ -z "$KEY" ]; then
		if [ ! -t 0 ]; then
			cat >&2 <<-'EOF'
				--paywall needs RevenueCat's Test Store key, and there is no terminal to
				ask for it in. Run it in a terminal and paste the key when asked, or
				set KINLORE_RC_KEY.
			EOF
			exit 1
		fi
		read -rsp "RevenueCat Test Store key (it does not show as you paste): " KEY || true
		echo
	fi
	case $KEY in
		'')
			echo "No key was given, so nothing was built." >&2
			exit 1
			;;
		sk_*)
			cat >&2 <<-'EOF'
				That is RevenueCat's secret key, which belongs on a server and never in
				an app. The paywall needs the Test Store key, which starts with test_.
				Nothing was built or written.
			EOF
			exit 1
			;;
		test_*) ;;
		*)
			echo "That is not a Test Store key, which starts with test_. Nothing was built or written." >&2
			exit 1
			;;
	esac
	case $KEY in
		*[[:space:]]*)
			echo "The key has a space or a line break in it; copy it again. Nothing was built or written." >&2
			exit 1
			;;
	esac
	# The deployed Worker, read from the one line the Release build takes it
	# from, so that the two cannot point at different places.
	API=$(sed -nE 's|^[[:space:]]*static let productionURL = "(https://[^"]+)".*|\1|p' \
		ios/Kinlore/Services/AppServices.swift)
	if [ -z "$API" ]; then
		echo "ios/Kinlore/Services/AppServices.swift names no productionURL to point the app at." >&2
		exit 1
	fi
else
	unset KEY
fi

case $MODE in
	real) NAMES=("Kinlore Try") ;;
	two) NAMES=("Kinlore Try" "Kinlore Try 2") ;;
	example) NAMES=("Kinlore Example") ;;
	paywall) NAMES=("Kinlore Paywall") ;;
esac
case $MODE in
	example)
		# The Koivula family a year or two in (LargeArchiveFixture), which is
		# invented and DEBUG-only. It replaces the archive on every launch that
		# carries it, so each run puts the example back as it was.
		SCHEME=Kinlore CONFIG=Debug
		ARGS=(-seed large)
		;;
	paywall)
		# Debug, which the SDK lets a Test Store key into. The address and the
		# key go into the app's settings below rather than its arguments.
		SCHEME=Kinlore CONFIG=Debug
		ARGS=(-tryIt YES)
		;;
	*)
		SCHEME="Kinlore Production" CONFIG=Release
		ARGS=(-tryIt YES)
		;;
esac

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
# The window onto the simulator: Simulator.app up to Xcode 26, and DeviceHub
# from Xcode 27, which has no Simulator.app. Simulator draws a window for every
# simulator that is running, and the argument only chooses which one comes to
# the front when it was not open already. Without a window the app still
# installs and launches, and the guide below says where to look.
DEV=${DEVELOPER_DIR:-$(xcode-select -p)}
WINDOW=''
for viewer in "$DEV/Applications/Simulator.app" "${DEV%/Developer}/Applications/DeviceHub.app"; do
	[ -d "$viewer" ] || continue
	if open -a "$viewer" --args -CurrentDeviceUDID "${UDIDS[0]}" >>"$LOG" 2>&1; then
		WINDOW=${viewer##*/}
	fi
	break
done

# setting <udid> <name> <value> — writes one of the app's settings on that
# simulator and reads it back to compare. Its output goes nowhere and the
# value is never printed, because one of them is the key.
setting() {
	xcrun simctl spawn "$1" defaults write "$BUNDLE" "$2" -string "$3" >/dev/null 2>&1 \
		&& [ "$(xcrun simctl spawn "$1" defaults read "$BUNDLE" "$2" 2>/dev/null)" = "$3" ]
}

for udid in "${UDIDS[@]}"; do
	# An install over the last run's keeps the family and everything told.
	xcrun simctl install "$udid" "$APP" >>"$LOG" 2>&1 || fail "Kinlore did not install."
	# The app follows the phone's language, and the guide below is in English,
	# so the app's own language is set to English: the per-app setting iOS
	# keeps, which a launch from the home screen keeps too. The simulator's
	# language is left as it is.
	xcrun simctl spawn "$udid" defaults write "$BUNDLE" AppleLanguages -array en >>"$LOG" 2>&1 \
		|| fail "Kinlore's language could not be set to English."
	case $MODE in
		paywall)
			setting "$udid" api "$API" \
				|| fail "The Worker's address did not stay in Kinlore's settings."
			setting "$udid" rcKey "$KEY" \
				|| fail "The key did not stay in Kinlore's settings."
			;;
		real | two)
			# A Test Store key there would stop this Release build as it
			# launches. "Not found" is the usual answer, and it is ignored.
			xcrun simctl spawn "$udid" defaults delete "$BUNDLE" rcKey >/dev/null 2>&1 || true
			;;
	esac
	xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE" "${ARGS[@]}" \
		>>"$LOG" 2>&1 || fail "Kinlore did not launch."
done
unset KEY

# --- What to try ------------------------------------------------------------

case $MODE in
	real)
		cat <<-'EOF'

			Kinlore is open on the simulator "Kinlore Try", and it is the real app:
			what you say goes to the deployed Worker and comes back written down.

			  1. Start a family archive: type your name and press "Create the
			     archive", not "Keep the memories on this phone only" under it,
			     because nothing said in such an archive is written out as text.
			     The sheet that follows asks whose memories to keep; "Close"
			     skips it.
			  2. The Tell tab opens on an example to read aloud:

			       My grandmother Anna grew up in Helsinki. She married Walter sometime
			       in the fifties, and he always had the camera.

			     Press the microphone and read it, or tell something of your own.
			     iOS asks for the microphone first, and the Mac may then ask as
			     well. "Type it for me" puts it in the write field instead, and
			     "Save" sends it.
			  3. See what comes back: the people as proposals nobody has confirmed
			     yet, and "sometime in the fifties" kept as the 1950s rather than a
			     guessed year. A spoken telling is followed by questions asked out
			     loud; answer them, or press "That is enough for now".

			Two phones sharing one family:  ./scripts/try-it.sh --two
			An invented example family:     ./scripts/try-it.sh --example
			The paywall and a purchase:     ./scripts/try-it.sh --paywall
		EOF
		;;
	two)
		cat <<-'EOF'

			Kinlore is open on two simulators, "Kinlore Try" and "Kinlore Try 2", and
			both are the real app. To put them in one family:

			  1. On "Kinlore Try", start a family archive: type your name and press
			     "Create the archive", and "Close" the sheet that follows. Then
			     Settings, with the gear at the top right of Family tree.
			     There: "Family members and invitations", "Invite a family
			     member", give a name, then "Create an invitation", "Share the
			     invitation" and "Copy".
			  2. On "Kinlore Try 2", press "Join with an invitation link", paste the
			     whole invitation and press "Join a family". The two simulators
			     share the Mac's clipboard.
			  3. Tell something on one of them. The other fetches it when Kinlore
			     comes to the front there: go to its home screen (Shift-Command-H
			     in Simulator) and open Kinlore again.

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
	paywall)
		cat <<-'EOF'

			Kinlore is open on the simulator "Kinlore Paywall", with your Test Store
			key in its settings. It is the Debug build, because RevenueCat stops a
			Release build that has a Test Store key, and it talks to the deployed
			Worker all the same, opened from the home screen too.

			  1. Start a family archive: type your name and press "Create the
			     archive", not "Keep the memories on this phone only" under it,
			     because the paywall is for a family on the server. "Close" the
			     sheet that follows.
			  2. Open Settings with the gear at the top right of Family tree.
			     Then "Family members and invitations": "Open the whole archive",
			     under Usage, opens the paywall.
			  3. Choose a plan and buy it. RevenueCat's Test Store asks whether to
			     simulate a valid purchase or a failed one, and "Test valid
			     purchase" buys: no money moves. The Worker then asks RevenueCat
			     what was bought rather than taking the app's word for it.

			One member buys, and the whole family has it: every phone in the family,
			one that joined with an invitation too, stops meeting the free tier's
			limits of ten minutes of transcription a month, twenty photographs and
			five colourisations a month, and "Family members and invitations" says
			its Status is Paid. Telling was never limited. A Test Store
			subscription renews on a fast clock and ends by itself after a few
			renewals, and the family is then on the free tier again with
			everything it holds.
		EOF
		;;
esac

LISTED="\"${NAMES[0]}\""
[ ${#NAMES[@]} -eq 1 ] || LISTED="$LISTED and \"${NAMES[1]}\""
case $WINDOW in
	Simulator.app) ;;
	DeviceHub.app)
		echo
		echo "If no window shows Kinlore, DeviceHub has $LISTED under Simulators."
		;;
	*)
		cat <<-EOF

			No window onto the simulator opened. Kinlore is running all the same:
			open Simulator (Xcode 26) or DeviceHub (Xcode 27) and choose $LISTED.
		EOF
		;;
esac
