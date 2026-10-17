#!/usr/bin/env bash
# Build the firmware and run it in Renode for 3 s of virtual time.
#
#   ./run.sh                          on Renode's own STM32_Timer
#   ./run.sh --patched STM32_Timer.cs on a candidate fix: the file is compiled
#                                     into Renode under another name and used
#                                     for TIM15 instead
#
# Needs cargo with the thumbv7em-none-eabi target, and renode on PATH (or
# RENODE=/path/to/renode).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
renode=${RENODE:-renode}

cargo build --release --manifest-path "$here/Cargo.toml"

resc=$here/renode/repro.resc
if [ "${1:-}" = --patched ]; then
    [ -f "${2:-}" ] || { echo "usage: $0 --patched path/to/STM32_Timer.cs" >&2; exit 2; }
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    perl -pe 's/\bSTM32_Timer\b/STM32_TimerPatched/g' "$2" > "$tmp/STM32_TimerPatched.cs"
    sed 's/Timers\.STM32_Timer @/Timers.STM32_TimerPatched @/' "$here/renode/g474-tim15.repl" > "$tmp/g474-tim15.repl"
    cp "$here/renode/count.py" "$tmp/"
    sed -e "s#^path add \$ORIGIN#path add @$tmp#" \
        -e "s#^mach create#include @$tmp/STM32_TimerPatched.cs\nmach create#" \
        -e "s#\$ORIGIN/../target#@$here/target#" "$resc" > "$tmp/repro.resc"
    resc=$tmp/repro.resc
fi
"$renode" --console --disable-gui --plain "$resc" | grep toggles
