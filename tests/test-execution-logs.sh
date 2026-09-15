#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export LINUX_SETUP_LOG_DIR="$TEST_ROOT/logs"

# shellcheck source=../linux-setup.sh
source "$(dirname "$0")/../linux-setup.sh"
DRY_RUN=1
start_logging
WORK_DIR="$(mktemp -d)"
trap cleanup EXIT
log_event resolution FOUND 'app=teste method=repository'
[[ -L "$LOG_DIR/latest.log" ]]
[[ "$(stat -c %a "$LOG_FILE")" == 600 ]]
grep -Fq $'\tresolution\tFOUND\tapp=teste method=repository' "$LOG_FILE"
printf 'OK: logs de execucao\n'