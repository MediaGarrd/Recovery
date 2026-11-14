#!/usr/bin/env bash
# shellcheck disable=SC2034
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
source "$SCRIPT"
set +euo pipefail
export LC_ALL=C.UTF-8

declare -A KP=()

t_eq 'pat escapes regex and glob specials' '^a.b\*\[c\]\\d\$\^\?$' "$(printf '%s\n' 'a.b*[c]\d$^?' | pat '^' '$')"
t_eq 'pat keeps spaces and applies prefix and suffix' 'x y/*' "$(printf '%s\n' 'x y' | pat '' '/*')"
t_eq 'pat handles one pattern per line' $'^a/\n^b c/' "$(printf '%s\n' a 'b c' | pat '^' /)"

KP=()
mp 'a/b/c'; t_eq 'mp without kept links is the identity' 'a/b/c' "$MP"
mp ''; t_eq 'mp of an empty path is empty' '' "$MP"
KP=([srv/media]=mnt/nas)
mp srv/media; t_eq 'mp maps a kept link to its target' mnt/nas "$MP"
mp srv/media/a/b; t_eq 'mp maps paths below a kept link' mnt/nas/a/b "$MP"
mp srv/other/a; t_eq 'mp leaves unrelated paths alone' srv/other/a "$MP"
mp srv/mediax; t_eq 'mp matches whole components only' srv/mediax "$MP"
KP=([a]=b [b/c]=d)
mp a/c/e; t_eq 'mp resolves through a chain of kept links' d/e "$MP"
KP=([srv/b]=mnt/nas [srv/a]=mnt/nas/x)
mp srv/a/y; t_eq 'mp resolves a link that points through a kept link' mnt/nas/x/y "$MP"

fresh
AD=$C/awk
awk_on() {
    rm -rf "$AD"; mkdir -p "$AD"
    mkzip "$Z"
    bsdtar -tf "$Z" >"$AD/n" 2>/dev/null
    bsdtar --numeric-owner -tvf "$Z" >"$AD/v" 2>/dev/null
    chk "$AD" >/dev/null 2>&1
    ARC=$?
    ASTATS=''
    if [[ -f $AD/stats ]]; then ASTATS=$(<"$AD/stats"); fi
}
lf() { LN=$1 awk -F"$SEP" -v n="$2" '$2 == ENVIRON["LN"] { print $n }' "$AD/links.raw"; }
numeric() { [[ $1 =~ ^[0-9]+$ && $2 =~ ^[0-9]+$ ]]; }

awk_on <<'EOF2'
f|srv/a.txt|644|hello
d|srv/dir
l|srv/l|/mnt
EOF2
t_eq 'awk accepts canonical names' 0 "$ARC"
t_eq 'awk counts entries and bytes' '3 5 0 0' "$ASTATS"
t_eq 'awk lists non-link entries and their parents as provided paths' $'srv\nsrv/a.txt\nsrv/dir' "$(LC_ALL=C sort "$AD/prov")"

awk_on <<'EOF2'
f|srv/mediagarrd.db|644|db
EOF2
t_eq 'awk flags mediagarrd.db' '1 2 1 0' "$ASTATS"
awk_on <<'EOF2'
f|srv/mediagarrd.db.bak|644|db
f|srv/xmediagarrd.db|644|db
EOF2
t_eq 'awk does not flag lookalike names' '2 4 0 0' "$ASTATS"

for spec in 'f|../evil' 'f|a/../b' 'f|a/..' 'f|/abs/x' 'f|a//b' 'f|a/./b' 'f|./a' 'f|a\tb' 'f|a\x07b' 'f|a\nb' 'f|x/\x1b[2J'; do
    awk_on <<<"$spec"
    t_eq "awk rejects ${spec#f|}" 3 "$ARC"
    t_true "awk writes no provided list for ${spec#f|}" test ! -e "$AD/prov"
done
awk_on <<<'l|a/b|../../x'
t_eq 'awk accepts relative link targets with ..' 0 "$ARC"
awk_on <<<'f|dir/we\\ird|644|b'
t_eq 'awk accepts a backslash in a name' 0 "$ARC"
t_eq 'awk counts the backslash name' '1 1 0 0' "$ASTATS"
awk_on <<<'l|a/we\\ird|/mnt/x'
t_eq 'awk keeps a backslash in a link name' 0 "$ARC"
t_eq 'awk reads the target of a link with a backslash name' /mnt/x "$(lf 'a/we\ird' 3)"

awk_on <<<'l|srv/a -> b|/mnt/x -> y'
t_eq 'awk parses names and targets containing " -> "' '/mnt/x -> y' "$(lf 'srv/a -> b' 3)"

awk_on <<'EOF2'
l|l1|l2
l|l2|/abs/dir
EOF2
t_eq 'chain l1 -> l2 -> /abs/dir resolves to the final path' abs/dir "$(lf l1 4)"
t_eq 'chain l1 is ok' 1 "$(lf l1 5)"
t_eq 'chain l2 resolves to the same path' abs/dir "$(lf l2 4)"

awk_on <<'EOF2'
l|a|b
l|b|a
EOF2
t_eq 'link loop is not ok' 0 "$(lf a 5)"

awk_on <<'EOF2'
l|l0|l1
l|l1|l2
l|l2|l3
l|l3|l4
l|l4|l5
l|l5|l6
l|l6|l7
l|l7|l8
l|l8|l9
l|l9|/x
EOF2
t_eq 'chain of 9 hops is not ok' 0 "$(lf l0 5)"
t_eq 'chain of 8 hops is ok' 1 "$(lf l1 5)"

awk_on <<'EOF2'
l|srv/a|../x/y
l|srv/b|./c/../d
l|srv/c|/p//q/./r/..
l|d|.
l|x|d/d/../../..
EOF2
t_eq 'relative target with .. is normalized' x/y "$(lf srv/a 4)"
t_eq 'relative target with . and .. is normalized' srv/d "$(lf srv/b 4)"
t_eq 'absolute target is normalized' p/q "$(lf srv/c 4)"
t_eq 'link to . resolves to the root' '' "$(lf d 4)"
t_eq 'escaping relative target cannot climb above the root' '' "$(lf x 4)"

awk_on <<'EOF2'
l|srv/b|/mnt/nas
l|srv/a|b/x
EOF2
t_eq 'rank of a link with no link in its path is 0' 0 "$(lf srv/b 1)"
t_eq 'rank of a link pointing through another link is 1' 1 "$(lf srv/a 1)"
t_eq 'relative target through a link is resolved by name' srv/b/x "$(lf srv/a 4)"
awk_on <<'EOF2'
l|srv/media|/mnt/nas
l|srv/media/lib|/mnt/lib
l|srv/media/lib/deep|/mnt/deep
EOF2
t_eq 'rank counts links in the parent path' 1 "$(lf srv/media/lib 1)"
t_eq 'rank increases with each level' 2 "$(lf srv/media/lib/deep 1)"

awk_on <<'EOF2'
l|srv/m|/mnt/nas
f|srv/m/a|644|a
f|mnt/nas/q|644|q
l|srv/n|/mnt/none
EOF2
t_eq 'link target provided by the archive is flagged' 1 "$(lf srv/m 6)"
t_eq 'link with entries below it has children' 1 "$(lf srv/m 7)"
t_eq 'link target not in the archive is not flagged' 0 "$(lf srv/n 6)"
t_eq 'link without entries below it has no children' 0 "$(lf srv/n 7)"
t_true 'owner and group columns are numeric' numeric "$(lf srv/m 8)" "$(lf srv/m 9)"

run_cli() { OUT=$(bash "$SCRIPT" "$@" 2>&1 </dev/null); RC=$?; }
mkzip "$Z" <<<'f|a|644|x'
run_cli -C "$R"; t_eq 'no archive is a usage error' 2 "$RC"; t_has 'usage text is printed' "$OUT" 'Usage:'
run_cli -C "$R" -x "$Z"; t_eq 'unknown short option is a usage error' 2 "$RC"
run_cli -C "$R" --bogus "$Z"; t_eq 'unknown long option is a usage error' 2 "$RC"
run_cli -C "$R" "$Z" "$Z"; t_eq 'two archives are a usage error' 2 "$RC"
run_cli -C; t_eq 'missing -C argument is an error' 1 "$RC"; t_has 'missing -C argument is explained' "$OUT" 'needs an argument'
run_cli -C "$R" -h; t_eq '-h exits 0' 0 "$RC"; t_has '-h prints usage' "$OUT" 'Usage:'
run_cli -C "$R" --help -x; t_eq '--help wins before later bad options' 0 "$RC"
run_cli -C "$R" -n "$C/missing.zip"; t_eq 'unreadable archive is an error' 1 "$RC"; t_has 'unreadable archive is named' "$OUT" 'cannot read'
run_cli --root="$R" -n -y "$Z"; t_eq '--root=DIR is accepted' 0 "$RC"; t_has '--root=DIR is used' "$OUT" "Root    : $R"
run_cli -C "$R" --dry-run --yes "$Z"; t_eq 'long dry-run and yes options are accepted' 0 "$RC"
run_cli -C "$R" -- -n; t_eq 'an archive named like an option is taken after --' 1 "$RC"; t_has 'it is treated as an archive' "$OUT" 'cannot read -n'
run_cli -C '' -n "$Z"; t_eq 'empty root is rejected' 1 "$RC"; t_has 'empty root is explained' "$OUT" 'empty root'
: >"$C/file"
run_cli -C "$C/file" -n "$Z"; t_eq 'a root that is a file is rejected' 1 "$RC"; t_has 'it is explained' "$OUT" 'not a directory'

OUT=$(bash -s -- -C "$R" -h <"$SCRIPT" 2>&1); RC=$?
t_eq 'script read from stdin: -h exits 0' 0 "$RC"; t_has 'script read from stdin: usage printed' "$OUT" 'Usage:'
OUT=$(bash -s -- -C "$R" --bogus <"$SCRIPT" 2>&1); RC=$?
t_eq 'script read from stdin: bad option exits 2' 2 "$RC"
OUT=$(bash -c "$(<"$SCRIPT")" mgrecover -C "$R" --bogus 2>&1); RC=$?
t_eq 'script run through bash -c: bad option exits 2' 2 "$RC"

finish
