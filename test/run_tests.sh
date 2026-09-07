#!/usr/bin/env bash
# Runs the vim-sgcomplete test suite headlessly and exits non-zero on failure.
set -uo pipefail
cd "$(dirname "$0")/.."

export SGCOMPLETE_TEST_OUT="$(mktemp)"
trap 'rm -f "$SGCOMPLETE_TEST_OUT"' EXIT

vim -Nu NONE -i NONE --not-a-term \
  -c 'set rtp+=.' \
  -c 'runtime plugin/sgcomplete.vim' \
  -c 'source test/test_sgcomplete.vim' \
  < /dev/null > /dev/null 2>&1
status=$?

echo "---- test output ----"
cat "$SGCOMPLETE_TEST_OUT" 2>/dev/null || echo "(no output file written; vim likely crashed)"
echo "----------------------"

if [ $status -eq 0 ] && grep -q 'ALL TESTS PASSED' "$SGCOMPLETE_TEST_OUT" 2>/dev/null; then
  echo "OK"
  exit 0
else
  echo "FAILED"
  exit 1
fi
