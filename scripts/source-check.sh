#!/usr/bin/env bash
# Fast checks that catch the compile breaks seen on main without Xcode:
# Swift files that share a name (Xcode: "Filename used twice") and test files that
# declare a type named like a Swift Testing type.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
# One target per group; names only have to be unique inside a target.
for group in "App Core Design Engines Features Shared Controls Share" "Tests" "UITests"; do
  # shellcheck disable=SC2086
  dups=$(git ls-files -- $(printf '%s/*.swift ' $group) | xargs -n1 basename 2>/dev/null | sort | uniq -d)
  for d in $dups; do
    # shellcheck disable=SC2086
    echo "::error::Swift file name used twice in one target: $(git ls-files -- $(printf '%s/*.swift ' $group) | grep "/$d$" | tr '\n' ' ')"
    fail=1
  done
done
if git grep -n -E '^(public |internal |private |fileprivate )?(struct|class|enum|actor) (Attachment|Test|Tag|Issue|Trait|Confirmation)\b' -- '*.swift' >/dev/null; then
  git grep -n -E '^(public |internal |private |fileprivate )?(struct|class|enum|actor) (Attachment|Test|Tag|Issue|Trait|Confirmation)\b' -- '*.swift' | sed 's/^/::error::type name clashes with Swift Testing: /'
  fail=1
fi
# Swift Testing: a #require inside another #require's argument fails with "recursive expansion of macro".
if git grep -n -E '#require\([^)]*#require\(' -- 'Tests/*.swift' 'UITests/*.swift' >/dev/null; then
  git grep -n -E '#require\([^)]*#require\(' -- 'Tests/*.swift' 'UITests/*.swift' | sed 's/^/::error::nested #require, split it into a let: /'
  fail=1
fi
# A prominent button draws its label in a fixed light color, which vanishes on the mono accent in dark mode. Every file with
# one must put .prominentLabel() on the label (Design/AccentForeground.swift), or say why not with "// prominent-ok: <reason>".
for f in $(git grep -l -E '\.(borderedProminent|glassProminent)([^A-Za-z]|$)' -- 'App/*.swift' 'Core/*.swift' 'Design/*.swift' 'Engines/*.swift' 'Features/*.swift'); do
  if ! grep -q -E '\.prominentLabel\(\)|prominent-ok:' "$f"; then
    echo "::error file=$f::prominent button without .prominentLabel() on its label (white on white in dark mode). Add it, or a '// prominent-ok: <reason>' comment."
    fail=1
  fi
done
exit $fail
