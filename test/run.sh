#!/usr/bin/env bash
# Run every spec under test/spec with the real config loaded.
#
#   ./test/run.sh              # all specs
#   ./test/run.sh work         # only specs matching "work"
#
# Stubs are put first on PATH so specs never touch the real `linear` or GitHub.
# test/stub/gh is inert unless a GH_STUB_* variable is set, so specs that want
# real git behavior still get it.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

export PATH="$PWD/test/stub:$PATH"

filter="${1:-}"
status=0

for spec in test/spec/*_spec.lua; do
  [ -e "$spec" ] || continue
  if [ -n "$filter" ] && [[ "$spec" != *"$filter"* ]]; then continue; fi

  echo "$(basename "$spec")"
  if ! nvim -l "$spec"; then status=1; fi
done

if [ "$status" -eq 0 ]; then echo "all specs passed"; else echo "SPEC FAILURES"; fi
exit "$status"
