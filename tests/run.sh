#!/bin/sh
# Fail-fast offline suite. A failing script exits this runner with its status.
set -eu
cd "$(dirname "$0")/.."
for t in tests/*.sh; do
  [ "$t" = tests/run.sh ] && continue
  echo "== $t"
  sh "$t"
done
echo SUITE_PASS
