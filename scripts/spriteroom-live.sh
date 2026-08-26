#!/bin/sh
# Start the room for a day's work.
#
#     scripts/spriteroom-live.sh [extra spriteroom flags]
#
# `swift run spriteroom --live` works and is what the README documents, but it
# re-resolves the package and re-links on every invocation, and it runs the
# debug build. This runs the release binary and builds it only when something
# it is built from is newer, which is the difference between starting the room
# and waiting for a build to start the room.
#
# **It checks four things first, and every one of them has cost somebody a
# confusing failure.** Each check prints what is wrong and exits non-zero,
# rather than launching a panel that then does nothing:
#
#   1. `~/.claude/settings.json` parses. A stray object literal made this file
#      unparseable on the maintainer's own machine, which meant Claude Code
#      applied none of it, including a hook block that was sitting there
#      correctly installed. The panel came up and stayed empty forever, because
#      nothing was ever posted to it. Nothing about that failure is visible from
#      inside the app: the room's whole job is to be still when there is no
#      work, so "no events" and "no agents working" draw identically. [I1]
#   2. The hook block is actually in that file. `--hooks-status` is the app's
#      own answer, so this cannot disagree with the installer.
#   3. Port 8787 is free. A second instance fails to bind, and the hooks of
#      every session then post to whichever one got there first.
#   4. The art is on disk. `assets/` is two purchased packs and is not in the
#      repository, so a fresh clone reaches this script with a manifest and no
#      pixels.
#
# It does not install hooks, does not write settings, and does not consent to
# anything on your behalf: `--install-hooks --yes` is a separate, deliberate
# command. This script only ever reads.
#
# `--check` runs the four checks and the build and then stops, without opening
# anything. That exists so the preflight can be exercised on a machine somebody
# is working on: the whole point of this app is a panel that drops out of the
# notch, and a test that drops it over somebody's screen to prove a JSON file
# parses is a bad trade.

set -eu

check_only=no
if [ "${1:-}" = "--check" ]; then
    check_only=yes
    shift
fi

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

binary="$root/.build/release/spriteroom"
settings="$HOME/.claude/settings.json"
port=8787

fail() {
    echo "spriteroom-live: $1" >&2
    exit 1
}

# 4. The art, before the build, because a five-minute release build that ends
#    in "no pixels" is the wrong order to find that out in.
[ -f "$root/assets/manifest.json" ] || fail \
    "no assets/manifest.json. The art is two purchased packs and is not in the
repository: see 'Unpack the art' in README.md."

# 1. The settings file parses. Read-only, and it names the line so the fix is
#    obvious rather than a hunt.
if [ -f "$settings" ]; then
    python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$settings" 2>/dev/null || {
        echo "spriteroom-live: $settings is not valid JSON." >&2
        python3 -c 'import json,sys
try:
    json.load(open(sys.argv[1]))
except ValueError as e:
    print("  " + str(e), file=sys.stderr)' "$settings" >&2 || true
        fail "Claude Code applies none of a file it cannot parse, hooks included,
so the room would come up and stay empty. Fix the file, then run this again."
    }
else
    fail "$settings does not exist, so no hooks are installed. Run
'swift run spriteroom --install-hooks --yes' first, or use the menu bar item."
fi

# 3. The port, before the build for the same reason as the art.
if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "spriteroom-live: something is already listening on $port:" >&2
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2
    fail "quit it first, or pass --port N to run this one somewhere else."
fi

# Build only if a source file, the manifest of the package, or the art manifest
# is newer than the binary. `-newer` is a per-file comparison, so this asks the
# question once per candidate rather than stamping a marker file.
needs_build=no
if [ ! -x "$binary" ]; then
    needs_build=yes
elif [ -n "$(find "$root/Sources" "$root/Package.swift" -newer "$binary" -print -quit 2>/dev/null)" ]; then
    needs_build=yes
fi

if [ "$needs_build" = yes ]; then
    echo "spriteroom-live: building release (sources are newer than the binary)"
    swift build -c release
fi

# 2. The hook block, from the app's own mouth rather than from a grep of ours.
status=$("$binary" --hooks-status 2>&1) || fail "$status"
case "$status" in
    *installed*) echo "spriteroom-live: $status" ;;
    *) fail "$status
Install them from the menu bar item, or with
'$binary --install-hooks --yes'." ;;
esac

if [ "$check_only" = yes ]; then
    echo "spriteroom-live: all four checks passed, binary at $binary. Not launching (--check)."
    exit 0
fi

echo "spriteroom-live: point at the notch to drop the room down."
exec "$binary" --live "$@"
