#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
for test_file in "$root"/tests/*-test.sh; do
  /bin/sh "$test_file"
done
