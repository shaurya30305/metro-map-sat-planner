#!/usr/bin/env bash
# End-to-end test: encode -> MiniSat -> decode -> validate constraints.
set -u
cd "$(dirname "$0")"

if ! command -v minisat >/dev/null 2>&1; then
  echo "MiniSat not found. Install it first:"
  echo "  Debian/Ubuntu : sudo apt-get install minisat"
  echo "  macOS (brew)  : brew install minisat"
  exit 1
fi

BASE=tests/sample
echo "1) Encoding $BASE.city -> CNF"
bash encoder.sh "$BASE" >/dev/null || { echo "encode failed"; exit 1; }
echo "2) Solving with MiniSat"
minisat "$BASE.satinput" "$BASE.satoutput" >/dev/null 2>&1
echo "3) Decoding model -> metro map"
bash decoder.sh "$BASE" >/dev/null || { echo "decode failed"; exit 1; }
echo "4) Validating solution against constraints"
if python3 tests/validate.py "$BASE"; then
  echo; echo "TEST PASSED"; exit 0
else
  echo; echo "TEST FAILED"; exit 1
fi
