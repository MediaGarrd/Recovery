#!/usr/bin/env bash
# shellcheck disable=SC2034
export PYTHONDONTWRITEBYTECODE=1
export TZ=UTC
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT=${HERE%/*}/mgrecover.sh
ZA=/.mg/a.zip
PASS=0 FAIL=0 N=0
W=$(mktemp -d "${TMPDIR:-/tmp}/mgtest.XXXXXX")
cleanup() { chmod -R u+rwX -- "$W" 2>/dev/null; rm -rf -- "$W"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

pass() { PASS=$((PASS + 1)); printf 'ok %d - %s\n' "$((PASS + FAIL))" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'not ok %d - %s\n' "$((PASS + FAIL))" "$1"; }
t_eq() { if [[ $2 == "$3" ]]; then pass "$1"; else fail "$1"; printf '#   expected: %q\n#   actual:   %q\n' "$2" "$3"; fi; }
t_has() { if [[ $2 == *"$3"* ]]; then pass "$1"; else fail "$1"; printf '#   missing: %q\n#   in: %q\n' "$3" "$2"; fi; }
t_lacks() { if [[ $2 != *"$3"* ]]; then pass "$1"; else fail "$1"; printf '#   unexpected: %q\n#   in: %q\n' "$3" "$2"; fi; }
t_true() { local d=$1; shift; if "$@"; then pass "$d"; else fail "$d"; fi; }
t_false() { local d=$1; shift; if "$@"; then fail "$d"; else pass "$d"; fi; }
finish() { printf '%d passed, %d failed\n' "$PASS" "$FAIL"; ((FAIL == 0)); }

is_dir() { [[ -d $1 && ! -L $1 ]]; }
is_file() { [[ -f $1 && ! -L $1 ]]; }
is_link() { [[ -L $1 ]]; }
absent() { [[ ! -e $1 && ! -L $1 ]]; }

mkzip() { python3 "$HERE/mkzip.py" "$1"; }
fresh() { N=$((N + 1)); C=$W/c$N; R=$C/root; Z=$C/a.zip; mkdir -p "$R" "$C/abs"; }
runc() { OUT=$(bash "$SCRIPT" -C "$R" "$@" 2>&1 </dev/null); RC=$?; }
runpty() { local in=$1; shift; OUT=$(python3 "$HERE/ptyrun.py" "$in" bash "$SCRIPT" -C "$R" "$@" 2>&1); RC=$?; }
snap() {
    (
        cd -- "$1" || exit 1
        find . -printf "%p|%y|%m|%l${2:+|%T@}\n" | LC_ALL=C sort
        find . -type f -exec sha256sum {} + | LC_ALL=C sort
    )
}
names() { find "$1" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort; }
confined() { t_eq "$1: nothing written outside the root" "a.zip abs root" "$(names "$C" | paste -sd' ')"; t_eq "$1: escape target untouched" "" "$(names "$C/abs")"; }
