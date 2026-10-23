#!/usr/bin/env bash
# Mirror the DeskStage 16:9 stage without the phone's 20:9 pillarboxes.
#
# DeskStage draws a centered 16:9 stage, which leaves black bars on the sides
# of a 20:9 phone. scrcpy preserves the phone's aspect ratio, so those bars
# survive into the mirror window and the stage looks small. This crops the
# mirror stream to the stage before scrcpy scales it.
#
# Usage:
#   scripts/deskstage-mirror.sh [serial]
#
# The app must already be running in DeskStage (landscape) mode.

set -euo pipefail

SERIAL="${1:-${ADB_SERIAL:-}}"
if [[ -z "$SERIAL" ]]; then
    SERIAL="$(adb devices | awk 'NR>1 && $2 == "device" {print $1; exit}')"
fi
if [[ -z "$SERIAL" ]]; then
    echo "No adb device found. Connect the phone or pass the serial as the first argument." >&2
    exit 1
fi

ADB=(adb -s "$SERIAL")

# Prefer the override size when one is set, otherwise use the physical size.
WM_OUTPUT="$("${ADB[@]}" shell wm size | tr -d '\r')"
SIZE="$(printf '%s\n' "$WM_OUTPUT" | awk -F': ' '/Override size/ {print $2; exit}')"
if [[ -z "$SIZE" ]]; then
    SIZE="$(printf '%s\n' "$WM_OUTPUT" | awk -F': ' '/Physical size/ {print $2; exit}')"
fi
if [[ ! "$SIZE" =~ ^([0-9]+)x([0-9]+)$ ]]; then
    echo "Could not parse wm size output: $WM_OUTPUT" >&2
    exit 1
fi

W="${BASH_REMATCH[1]}"
H="${BASH_REMATCH[2]}"

# scrcpy --crop is expressed in the device's natural orientation (portrait
# for a phone), while DeskStage runs in landscape. Compute the 16:9 stage in
# landscape, then translate it back to natural orientation for scrcpy.
if (( W < H )); then
    LAND_W="$H"
    LAND_H="$W"

    if (( LAND_W * 9 > LAND_H * 16 )); then
        STAGE_LAND_H="$LAND_H"
        STAGE_LAND_W=$(( LAND_H * 16 / 9 ))
    else
        STAGE_LAND_W="$LAND_W"
        STAGE_LAND_H=$(( LAND_W * 9 / 16 ))
    fi

    STAGE_W="$STAGE_LAND_H"
    STAGE_H="$STAGE_LAND_W"
    STAGE_X=$(( (W - STAGE_W) / 2 ))
    STAGE_Y=$(( (H - STAGE_H) / 2 ))
else
    if (( W * 9 > H * 16 )); then
        STAGE_H="$H"
        STAGE_W=$(( H * 16 / 9 ))
        STAGE_X=$(( (W - STAGE_W) / 2 ))
        STAGE_Y=0
    else
        STAGE_W="$W"
        STAGE_H=$(( W * 9 / 16 ))
        STAGE_X=0
        STAGE_Y=$(( (H - STAGE_H) / 2 ))
    fi
fi

echo "Mirroring ${SERIAL}: display ${W}x${H}, 16:9 stage ${STAGE_W}x${STAGE_H} at ${STAGE_X},${STAGE_Y}"

exec scrcpy \
    -s "$SERIAL" \
    --crop "${STAGE_W}:${STAGE_H}:${STAGE_X}:${STAGE_Y}" \
    --max-size 1280 \
    --max-fps 30 \
    --video-bit-rate 4M \
    --window-title "Signora DeskStage" \
    --fullscreen
