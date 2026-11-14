#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=common.sh
source "$HERE/common.sh"
export LC_ALL=C.UTF-8

fresh
mkzip "$Z" <<EOF2
l|srv/media|/mnt/nas
f|srv/media/a.txt|644|hello
f|srv/other/b.txt|644|bye
l|srv/solo|/mnt/x
l|srv/chain|/srv/media
EOF2
runc -y "$Z"
t_eq 'root: restore succeeds' 0 "$RC"
t_eq 'root: no symlink is created' '' "$(find "$R" -type l)"
t_true 'root: content stored under a link becomes a real directory' is_dir "$R/srv/media"
t_eq 'root: content under the link is restored' hello "$(<"$R/srv/media/a.txt")"
t_true 'root: link without content is not created' absent "$R/srv/solo"
t_has 'root: skipped link is reported' "$OUT" 'skip    '
t_has 'root: skip reason names --root' "$OUT" 'no links under --root'
t_has 'root: converted link is reported' "$OUT" 'convert '
t_has 'root: summary is printed' "$OUT" 'Done: 5 entries, 0 links kept, 1 converted, 2 skipped, 0 warnings, 0 errors.'
confined 'root links'

for name in '../evil' 'a/../../evil' '/abs-escape' 'srv//a' 'srv/./a' 'srv/..'; do
    fresh
    case $name in /*) name=$C/abs-name ;; esac
    mkzip "$Z" <<<"f|$name|644|pwn
f|ok.txt|644|ok"
    runc -y "$Z"
    t_eq "root: archive with $name is refused" 1 "$RC"
    t_has "root: refusal for $name is explained" "$OUT" 'unsafe entry name'
    t_true "root: nothing was extracted for $name" absent "$R/ok.txt"
    confined "root $name"
done

fresh
mkzip "$Z" <<EOF2
l|l1|l2
l|l2|$C/abs
f|l1/x|644|pwn
EOF2
runc -y "$Z"
t_eq 'root chain l1 -> l2 -> /abs: restore succeeds' 0 "$RC"
t_true 'root chain: l1 is a real directory' is_dir "$R/l1"
t_eq 'root chain: content restored in the root' pwn "$(<"$R/l1/x")"
confined 'root chain'

fresh
mkzip "$Z" <<'EOF2'
l|d|.
l|x|d/d/../../..
f|x/pwn|644|pwn
f|d/dd|644|dd
EOF2
runc -y "$Z"
t_eq 'root d -> . with x -> d/d/../../..: restore succeeds' 0 "$RC"
t_true 'root: x is a real directory' is_dir "$R/x"
t_eq 'root: x/pwn is inside the root' pwn "$(<"$R/x/pwn")"
t_eq 'root: no link anywhere' '' "$(find "$R" -type l)"
confined 'root dot chain'

fresh
mkzip "$Z" <<EOF2
l|cur|v2
l|v2/data|$C/abs
f|cur/data/x|644|pwn
EOF2
runc -y "$Z"
t_eq 'root cur -> v2 with v2/data -> /abs: restore succeeds' 0 "$RC"
t_true 'root: cur is a real directory' is_dir "$R/cur"
t_true 'root: cur/data is a real directory' is_dir "$R/cur/data"
t_eq 'root: cur/data/x is inside the root' pwn "$(<"$R/cur/data/x")"
confined 'root nested links'

fresh
ln -s "$C/abs" "$R/esc"
mkzip "$Z" <<<'f|esc/x|644|pwn
f|fine.txt|644|ok'
runc -y "$Z"
t_eq 'root: a pre-existing escaping link makes the run fail' 1 "$RC"
t_has 'root: the failure is reported' "$OUT" 'bsdtar reported errors'
t_true 'root: a pre-existing escaping link is not followed' test ! -e "$C/abs/x"
t_eq 'root: escape target stays empty' '' "$(names "$C/abs")"
t_eq 'root: the rest of the archive is still restored' ok "$(<"$R/fine.txt")"

fresh
mkzip "$Z" <<<"$GEN_SPEC"
runc -y "$Z"
t_eq 'root names: restore succeeds' 0 "$RC"
t_eq 'root names: modes, types and mtimes are preserved' "$GEN_WANT" "$(cd "$R" && stat -c "$STAT_FMT" -- "${GP[@]}")"
t_eq 'root names: contents are intact' 'glob|utf8|arrow|backslash|' "$(cd "$R" && for f in 'gen/glob/*[x]?.txt' 'gen/utf8/héllo-日本.txt' 'gen/arrow/a -> b.txt' 'gen/back/we\ird.txt'; do printf '%s|' "$(<"$f")"; done)"
t_eq 'root names: no extra paths appear' 'a b.txt' "$(names "$R/gen/sp dir")"

fresh
mkzip "$Z" <<<"$GEN_SPEC
l|srv/media|/mnt/nas
f|srv/media/a.txt|644|a"
printf 'old\n' >"$R/keep.txt"
mkdir -p "$R/srv/sub"
B=$(snap "$R" t)
runc -n -y "$Z"
t_eq 'root dry run: exit 0' 0 "$RC"
t_has 'root dry run: says nothing was written' "$OUT" 'Dry run: nothing was written.'
t_eq 'root dry run: tree is byte-identical, including times' "$B" "$(snap "$R" t)"
runc -n "$Z"
t_eq 'root dry run: does not ask for confirmation' 0 "$RC"
t_eq 'root dry run: tree still identical' "$B" "$(snap "$R" t)"

fresh
mkzip "$Z" <<<"$GEN_SPEC
l|srv/media|/mnt/nas
f|srv/media/a.txt|644|a"
runc -y "$Z"; first=$RC
A=$(snap "$R")
runc -y "$Z"
t_eq 'root re-run: both runs succeed' '0 0' "$first $RC"
t_eq 'root re-run: tree is unchanged' "$A" "$(snap "$R")"

fresh
mkzip "$Z" <<<'f|srv/mediagarrd.db|644|db'
runc -n -y "$Z"
t_has 'root: database warning' "$OUT" 'warning: archive contains mediagarrd.db'

fresh
mkzip "$Z" <<<'f|a.txt|644|a'
runc "$Z"
t_eq 'root: without a tty and without -y the script refuses' 1 "$RC"
t_has 'root: refusal says why' "$OUT" 'no terminal to ask for confirmation; use --yes'
t_true 'root: refusal writes nothing' absent "$R/a.txt"

runpty '\x04' "$Z"
t_eq 'root: EOF at the prompt aborts' 1 "$RC"
t_has 'root: the prompt was shown' "$OUT" 'Restore now? [y/N]'
t_has 'root: abort is reported' "$OUT" 'aborted'
t_true 'root: EOF writes nothing' absent "$R/a.txt"
runpty 'n\n' "$Z"
t_eq 'root: answering n aborts' 1 "$RC"
t_true 'root: n writes nothing' absent "$R/a.txt"
runpty 'y\n' "$Z"
t_eq 'root: answering y restores' 0 "$RC"
t_eq 'root: y restores the file' a "$(<"$R/a.txt")"

fresh
printf 'this is not a zip\n' >"$C/plain.zip"
runc -y "$C/plain.zip"
t_eq 'root: non-zip input is rejected' 1 "$RC"
t_has 'root: non-zip input is named' "$OUT" 'not a zip archive'
printf 'PKnot really a zip archive at all' >"$C/fake.zip"
runc -y "$C/fake.zip"
t_eq 'root: corrupt input is rejected' 1 "$RC"
t_has 'root: corrupt input is reported' "$OUT" 'bsdtar cannot read'
mkzip "$Z" <<<'f|a.txt|644|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
f|b.txt|644|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
head -c 100 "$Z" >"$C/trunc.zip"
runc -y "$C/trunc.zip"
t_true 'root: truncated input is rejected' test "$RC" -ne 0
t_eq 'root: truncated input writes nothing' '' "$(names "$R")"
python3 -c 'import zipfile,sys; zipfile.ZipFile(sys.argv[1],"w").close()' "$C/empty.zip"
runc -y "$C/empty.zip"
t_eq 'root: an empty archive is rejected' 1 "$RC"
t_has 'root: empty archive is reported' "$OUT" 'archive is empty'
runc -y "$C/missing.zip"
t_eq 'root: missing input is rejected' 1 "$RC"

fresh
mkzip "$Z" <<<'f|loc/é-日本.txt|644|u'
OUT=$(env -u LC_ALL -u LANG -u LC_CTYPE LC_CTYPE=UTF-8 bash "$SCRIPT" -C "$R" -y "$Z" 2>&1 </dev/null); RC=$?
t_eq 'root locale: LC_CTYPE=UTF-8 with a non-ASCII archive succeeds' 0 "$RC"
t_lacks 'root locale: no locale warning' "$OUT" 'no UTF-8 locale'
t_eq 'root locale: non-ASCII name is restored intact' u "$(<"$R/loc/é-日本.txt")"

finish
