#!/bin/sh
# Regenerate the golden reference data in test/golden/ from the ISO 532-1:2017
# Annex A.4 reference implementation.
#
#   make golden                     # uses the default paths below
#   SOUNDS=... ISO_DIR=... make golden
#
# SOUNDS  : folder holding the ISO test signals (the Zenodo validation set,
#           sound_files/validation_SQAT_v1_0/Loudness_ISO532_1 by default)
# ISO_DIR : root of the "ISO 532-1 - Program etc" folder shipped with the
#           standard, used for the Annex B.2 level vector and the Annex C
#           1 kHz 40 dB anchor.
#
# The resulting CSVs are committed, so the MATLAB test suite does not need
# either this script or the ISO sources.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT="$REPO/test/golden"

SOUNDS=${SOUNDS:-"$REPO/sound_files/validation_SQAT_v1_0/Loudness_ISO532_1"}
ISO_DIR=${ISO_DIR:-"$HOME/Documents/git/ISO 532-1 - Program etc"}
CAL="$SOUNDS/calibration signal sine 1kHz 60dB.wav"
ORACLE="$HERE/iso532_oracle"

[ -x "$ORACLE" ] || { echo "build the oracle first: make"; exit 1; }
[ -f "$CAL" ]    || { echo "calibration signal not found: $CAL"; exit 1; }

mkdir -p "$OUT"

# --- signal 1: stationary, from 28 third-octave levels (Annex B.2) ----------
LEVELS="$ISO_DIR/Annex B.2/Test signal 1.txt"
if [ -f "$LEVELS" ]; then
    "$ORACLE" lv "$LEVELS" "$OUT/sig01_stationary_levels.csv"
else
    echo "skip: $LEVELS not found"
fi

# --- signals 2-5: stationary, from audio (Annex B.3), time_skip = 0 --------
for n in 2 3 4 5; do
    f=$(ls "$SOUNDS"/"Test signal $n ("*.wav 2>/dev/null | head -1) || true
    [ -n "$f" ] || { echo "skip: signal $n not found"; continue; }
    "$ORACLE" st "$f" "$CAL" 60 0 "$OUT/$(printf 'sig%02d' $n)_stationary.csv"
done

# --- signals 6-25: time varying (Annex B.4 synthetic, B.5 technical) -------
for n in 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
    f=$(ls "$SOUNDS"/"Test signal $n ("*.wav 2>/dev/null | head -1) || true
    [ -n "$f" ] || { echo "skip: signal $n not found"; continue; }
    tag=$(printf 'sig%02d' $n)
    "$ORACLE" tv "$f" "$CAL" 60 "$OUT/${tag}_timevarying.csv"
done

# --- specific loudness -----------------------------------------------------
# Annex B.3 tabulates the full 240-band pattern for stationary signals;
# Annex B.4 tabulates N'(t) at ONE Bark band per time-varying signal. Match
# that convention rather than dumping the whole 240-by-time matrix.
for n in 2 3 4 5; do
    f=$(ls "$SOUNDS"/"Test signal $n ("*.wav 2>/dev/null | head -1) || true
    [ -n "$f" ] || continue
    "$ORACLE" stp "$f" "$CAL" 60 0 "$OUT/$(printf 'sig%02d' $n)_stationary_pattern.csv"
done
[ -f "$LEVELS" ] && "$ORACLE" lvp "$LEVELS" "$OUT/sig01_stationary_levels_pattern.csv"

# Bark band used by the standard for each time-varying synthetic signal
spec_bark() {
    case "$1" in
        6)              echo 2.5  ;;
        8|9)            echo 17.5 ;;
        7|10|11|12|13)  echo 8.5  ;;
        *)              echo ""   ;;
    esac
}
for n in 6 7 8 9 10 11 12 13; do
    f=$(ls "$SOUNDS"/"Test signal $n ("*.wav 2>/dev/null | head -1) || true
    [ -n "$f" ] || continue
    b=$(spec_bark $n)
    "$ORACLE" tvb "$f" "$CAL" 60 "$b" "$OUT/$(printf 'sig%02d' $n)_specific_${b}Bark.csv"
done

# --- diffuse field ---------------------------------------------------------
# The DDF table (20 entries) is only exercised with field = 1, so cover a few
# signals across the frequency range rather than leaving it untested.
for n in 3 6 8 10 14; do
    f=$(ls "$SOUNDS"/"Test signal $n ("*.wav 2>/dev/null | head -1) || true
    [ -n "$f" ] || continue
    tag=$(printf 'sig%02d' $n)
    if [ "$n" -le 5 ]; then
        "$ORACLE" st "$f" "$CAL" 60 0 "$OUT/${tag}_stationary_diffuse.csv" D
    else
        "$ORACLE" tv "$f" "$CAL" 60 "$OUT/${tag}_timevarying_diffuse.csv" D
    fi
done
[ -f "$LEVELS" ] && "$ORACLE" lv "$LEVELS" "$OUT/sig01_stationary_levels_diffuse.csv" D

# --- non-zero time_skip (stationary) ---------------------------------------
# time_skip changes which part of the signal feeds the level calculation.
# Untested until now, and the code path differs from time_skip = 0.
for n in 2 3 5; do
    f=$(ls "$SOUNDS"/"Test signal $n ("*.wav 2>/dev/null | head -1) || true
    [ -n "$f" ] || continue
    "$ORACLE" st "$f" "$CAL" 60 0.2 "$OUT/$(printf 'sig%02d' $n)_stationary_skip0p2.csv"
done

# --- anchor: 1 kHz at 40 dB SPL, must yield 1 sone (Annex C) ---------------
ANCHOR="$ISO_DIR/Annex C/sine 1kHz 40dB 16bit.wav"
if [ -f "$ANCHOR" ]; then
    "$ORACLE" tv  "$ANCHOR" "$CAL" 60 "$OUT/anchor_1kHz_40dB_timevarying.csv"
    "$ORACLE" st  "$ANCHOR" "$CAL" 60 0 "$OUT/anchor_1kHz_40dB_stationary.csv"
    "$ORACLE" stp "$ANCHOR" "$CAL" 60 0 "$OUT/anchor_1kHz_40dB_pattern.csv"
else
    echo "skip: $ANCHOR not found"
fi

echo "golden data written to $OUT"
