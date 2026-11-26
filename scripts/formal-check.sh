#!/usr/bin/env bash
# Model-checks formal/LocalModelLifecycle.tla with TLC.
# Usage: scripts/formal-check.sh [main|live|mutants|all]   (default: main)
#   main     the code as it is: every invariant must hold
#   live     every request ends (no symmetry, slower)
#   mutants  each formal/mutants/*.cfg turns one design decision back to its old value and must break
#            the invariant named on its "EXPECT" line. A mutant that still passes means the invariant is blind.
# Needs Java 11 or newer. Downloads the pinned TLC once into the cache directory. Not run on the maintainer's
# Mac (no Java there); CI runs it in .github/workflows/verify-formal.yml.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TLA_VERSION="v1.7.4"
TLA_SHA256="936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"
CACHE="${FORMAL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/anyrouter-formal}"
JAR="$CACHE/tla2tools-$TLA_VERSION.jar"
MODE="${1:-main}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

if [ ! -f "$JAR" ] || [ "$(sha256 "$JAR")" != "$TLA_SHA256" ]; then
  mkdir -p "$CACHE"
  curl -fsSL -o "$JAR" "https://github.com/tlaplus/tlaplus/releases/download/$TLA_VERSION/tla2tools.jar"
  [ "$(sha256 "$JAR")" = "$TLA_SHA256" ] || { echo "tla2tools.jar checksum mismatch" >&2; rm -f "$JAR"; exit 1; }
fi

# tlc CFG: output goes to $WORK/out.txt, the exit code to TLC_EXIT
tlc() {
  local cfg="$1"
  TLC_EXIT=0
  java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -workers auto -cleanup \
    -metadir "$WORK/states" -config "$cfg" "$ROOT/formal/LocalModelLifecycle.tla" >"$WORK/out.txt" 2>&1 || TLC_EXIT=$?
}

run_main() {
  tlc "$ROOT/formal/LocalModelLifecycle.cfg"
  tail -n 15 "$WORK/out.txt"
  [ "$TLC_EXIT" -eq 0 ] || { echo "FAIL main: TLC exit $TLC_EXIT" >&2; head -n 80 "$WORK/out.txt" >&2; exit 1; }
  echo "OK main: every invariant holds"
}

run_live() {
  tlc "$ROOT/formal/LocalModelLifecycleLive.cfg"
  tail -n 15 "$WORK/out.txt"
  [ "$TLC_EXIT" -eq 0 ] || { echo "FAIL live: TLC exit $TLC_EXIT" >&2; head -n 80 "$WORK/out.txt" >&2; exit 1; }
  echo "OK live: every request ends"
}

run_mutants() {
  local failed=0
  for cfg in "$ROOT"/formal/mutants/*.cfg; do
    local name expect
    name="$(basename "$cfg" .cfg)"
    expect="$(sed -n 's/^.. EXPECT \([A-Za-z]*\).*/\1/p' "$cfg" | head -n 1)"
    [ -n "$expect" ] || { echo "FAIL $name: no EXPECT line" >&2; failed=1; continue; }
    tlc "$cfg"
    if grep -q "Invariant $expect is violated" "$WORK/out.txt"; then
      echo "OK mutant $name breaks $expect"
      if [ -n "${FORMAL_TRACES:-}" ]; then echo "::group::counterexample of $name"; sed -n '/^Error:/,/^[0-9]* states generated/p' "$WORK/out.txt"; echo "::endgroup::"; fi
    else
      echo "FAIL mutant $name did not break $expect (TLC exit $TLC_EXIT)" >&2
      tail -n 15 "$WORK/out.txt" >&2
      failed=1
    fi
  done
  [ "$failed" -eq 0 ]
}

case "$MODE" in
  main) run_main ;;
  live) run_live ;;
  mutants) run_mutants ;;
  all) run_main; run_live; run_mutants ;;
  *) echo "usage: $0 [main|live|mutants|all]" >&2; exit 2 ;;
esac
