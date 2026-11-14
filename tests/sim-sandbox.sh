#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=common.sh
source "$HERE/common.sh"

SB_EXTRA=()
sbx() {
    local o=$C/out d
    rm -rf "$o"; mkdir -p "$o"
    local a=(--unshare-user --unshare-pid --unshare-ipc --unshare-uts --unshare-net --die-with-parent
        --uid "${SB_UID:-0}" --gid "${SB_UID:-0}" --clearenv
        --setenv PATH /usr/bin --setenv HOME /tmp --setenv TZ UTC --setenv LC_ALL C.UTF-8
        --setenv SETUP "${SETUP-}" --setenv POST "${POST-}" --setenv RUNS "${RUNS:-1}"
        --new-session --tmpfs / --ro-bind /usr /usr --ro-bind-try /etc/alternatives /etc/alternatives --proc /proc --dev /dev --perms 1777 --tmpfs /tmp)
    for d in bin lib lib64 sbin; do
        if [[ -L /$d ]]; then a+=(--symlink "$(readlink "/$d")" "/$d"); elif [[ -d /$d ]]; then a+=(--ro-bind "/$d" "/$d"); fi
    done
    a+=(--ro-bind "$SCRIPT" /.mg/mgrecover.sh --ro-bind "$HERE/inner.sh" /.mg/inner.sh --ro-bind "$Z" "$ZA" --bind "$o" /.mg/out)
    bwrap "${a[@]}" "${SB_EXTRA[@]}" bash /.mg/inner.sh "$@" >"$o/bwrap.log" 2>&1
    if [[ ! -f $o/post ]]; then printf 'bail out! sandbox failed: %s\n' "$(<"$o/bwrap.log")"; exit 1; fi
    RC=$(<"$o/rc1"); LOG=$(<"$o/log1"); TREE=$(<"$o/tree1"); TREE0=$(<"$o/tree0"); PO=$(<"$o/post")
    RC2='' TREE2=''
    if [[ -f $o/rc2 ]]; then RC2=$(<"$o/rc2"); TREE2=$(<"$o/tree2"); fi
    SETUP='' POST='' RUNS=1 SB_UID=0 SB_EXTRA=()
}
node() { awk -F'|' -v p="$1" -v y="$2" -v l="${3-}" '$1 == p && $2 == y && (l == "" || $5 == l) { f = 1 } END { exit !f }' <<<"$TREE"; }
gone() { ! awk -F'|' -v p="$1" '$1 == p { f = 1 } END { exit !f }' <<<"$TREE"; }
sbmk() { fresh; mkzip "$Z" <<<"$1"; }

fresh
mkzip "$Z" <<<'f|x|644|x'
sbx -n "$ZA"
t_eq 'sandbox works: private root is writable and script runs' 0 "$RC"
t_has 'sandbox: the script sees a fake root' "$LOG" 'Root    : /'
POST='id -u' sbx -n "$ZA"
t_eq 'sandbox: runs as uid 0' 0 "$PO"

SPEC='l|srv/media|/mnt/nas
f|srv/media/a.txt|644|media
l|srv/cur|/srv/v2
f|srv/v2/data|644|d
l|srv/rel|v2
l|toplink|/srv/v2
l|srv/nested/deep/lnk|/mnt/exist2'
sbmk "$SPEC"
SETUP='mkdir -p /mnt/nas /mnt/exist2; echo old >/mnt/nas/old.txt' RUNS=2 sbx -y "$ZA"
t_eq 'links: restore succeeds' 0 "$RC"
t_has 'links: summary counts' "$LOG" 'Links   : 5 kept, 0 with content below them converted, 0 skipped'
t_has 'links: final summary' "$LOG" 'Done: 7 entries, 5 links kept, 0 converted, 0 skipped, 0 warnings, 0 errors.'
t_true 'links: existing target is kept as a link' node /srv/media l /mnt/nas
t_true 'links: content below a kept link lands in the target' node /mnt/nas/a.txt f
t_true 'links: a file already under a kept link is kept' node /mnt/nas/old.txt f
t_true 'links: archive-provided target is kept' node /srv/cur l /srv/v2
t_true 'links: archive-provided target is restored' node /srv/v2/data f
t_true 'links: relative link is kept' node /srv/rel l v2
t_true 'links: top-level link is kept' node /toplink l /srv/v2
t_true 'links: nested link is kept' node /srv/nested/deep/lnk l /mnt/exist2
t_eq 're-run: second run succeeds' 0 "$RC2"
t_eq 're-run: tree is idempotent' "$TREE" "$TREE2"
FIRST=$TREE
sbmk "$(tac <<<"$SPEC")"
SETUP='mkdir -p /mnt/nas /mnt/exist2; echo old >/mnt/nas/old.txt' sbx -y "$ZA"
t_eq 'links: reversed archive order gives the same tree' "$FIRST" "$TREE"

sbmk 'l|srv/b|/srv/c
l|srv/c|/srv/missing
f|srv/b/x|644|bx
l|srv/media|/srv/m
l|srv/m|/mnt/nas
f|srv/media/a|644|ma'
sbx -y "$ZA"
t_eq 'broken chains: restore succeeds' 0 "$RC"
t_true 'broken chain with content: converted to a real directory' node /srv/b d
t_true 'broken chain: content restored' node /srv/b/x f
t_true 'unmounted chain with content: converted' node /srv/media d
t_true 'unmounted chain: content restored' node /srv/media/a f
t_true 'broken chain without content: skipped' gone /srv/c
t_true 'unmounted target link without content: skipped' gone /srv/m
t_has 'broken chain: skip is a warning' "$LOG" 'warning: /srv/c -> /srv/missing skipped (target /srv/missing does not exist and is not in the archive)'
t_has 'broken chain: conversion is reported' "$LOG" 'convert /srv/b -> /srv/c'
t_has 'broken chain: summary' "$LOG" '0 links kept, 2 converted, 2 skipped, 2 warnings, 0 errors.'

for pair in 'b a' 'a b'; do
    read -r p q <<<"$pair"
    sbmk "l|srv/$p|/mnt/nas
l|srv/$q|$p/x"
    SETUP='mkdir -p /mnt/nas/x' sbx -y "$ZA"
    t_true "M1 ($p -> /mnt/nas, $q -> $p/x): first link kept" node "/srv/$p" l /mnt/nas
    t_true "M1 ($p -> /mnt/nas, $q -> $p/x): link through it kept" node "/srv/$q" l "$p/x"
    t_has "M1 ($p, $q): summary" "$LOG" '2 links kept'
    SETUP='mkdir -p /mnt/nas' sbx -y "$ZA"
    t_true "M1 ($p, $q) with missing /mnt/nas/x: first link kept" node "/srv/$p" l /mnt/nas
    t_true "M1 ($p, $q) with missing /mnt/nas/x: link through it skipped" gone "/srv/$q"
    t_has "M1 ($p, $q) with missing /mnt/nas/x: warned" "$LOG" "/srv/$q -> $p/x skipped"
done

sbmk 'l|srv/media|/mnt/nas
l|srv/media/lib|/mnt/lib'
SETUP='mkdir -p /mnt/nas /mnt/lib' sbx -y "$ZA"
t_eq 'm-A two-level: restore succeeds' 0 "$RC"
t_true 'm-A: outer link kept' node /srv/media l /mnt/nas
t_true 'm-A: inner link is created in the link target' node /mnt/nas/lib l /mnt/lib

sbmk 'l|srv/b|/mnt/nas
l|srv/a|/srv/b/data
f|mnt/nas/data|644|d'
sbx -y "$ZA"
t_eq 'm-B archive-provided target through a link: restore succeeds' 0 "$RC"
t_true 'm-B: outer link kept' node /srv/b l /mnt/nas
t_true 'm-B: link through it kept' node /srv/a l /srv/b/data
t_true 'm-B: target content restored' node /mnt/nas/data f
t_has 'm-B: no warnings' "$LOG" '0 warnings'

for order in 'f|srv/b/new/q|644|q
f|srv/a/f|644|f' 'f|srv/a/f|644|f
f|srv/b/new/q|644|q'; do
    sbmk "l|srv/b|/mnt/nas
l|srv/a|b/new
$order"
    SETUP='mkdir -p /mnt/nas' sbx -y "$ZA"
    t_eq "kept link to a target below another kept link (${order%%|*} first): restore succeeds" 0 "$RC"
    t_true 'kept link with content: link created' node /srv/a l b/new
    t_true 'kept link with content: target directory created through the outer link' node /mnt/nas/new d
    t_true 'kept link with content: archive content in the target' node /mnt/nas/new/q f
    t_true 'kept link with content: content below the link in the target' node /mnt/nas/new/f f
    t_has 'kept link with content: no errors' "$LOG" '0 errors'
done

sbmk 'l|srv/media|/mnt/nas
f|srv/media/a|644|x'
SETUP='mkdir -p /srv; ln -s /dev/gone /srv/media' sbx -y "$ZA"
t_eq 'dangling device link: restore succeeds' 0 "$RC"
t_true 'dangling device link is replaced by a real directory' node /srv/media d
t_true 'dangling device link: content restored' node /srv/media/a f

sbmk 'l|srv/media|/mnt/nas
f|srv/other|644|o'
SETUP='mkdir -p /srv/media /mnt/nas; echo keep >/srv/media/old' POST='cat /srv/media/old' sbx -y "$ZA"
t_eq 'real data at L: restore succeeds' 0 "$RC"
t_true 'real data at L is kept' node /srv/media d
t_eq 'real data at L: content untouched' keep "$PO"
t_true 'real data at L: old file still there' node /srv/media/old f
t_has 'real data at L: warned' "$LOG" 'warning: /srv/media -> /mnt/nas skipped (/srv/media already exists; real data is kept)'

sbmk 'l|srv/media|/mnt/nas
f|srv/media/a|644|x'
SETUP='mkdir -p /srv/media /mnt/nas; echo keep >/srv/media/old' sbx -y "$ZA"
t_true 'real data at L with content below: both kept in a real directory' node /srv/media/old f
t_true 'real data at L with content below: content restored' node /srv/media/a f
t_true 'real data at L with content below: not a link' node /srv/media d

sbmk 'l|srv/media|/mnt/nas
f|srv/media/a|644|x'
SETUP='mkdir -p /srv /mnt/nas; echo FILE >/srv/media' POST='cat /srv/media' sbx -y "$ZA"
t_eq 'file at L: restore succeeds' 0 "$RC"
t_eq 'file at L: kept untouched' FILE "$PO"
t_true 'file at L: nothing restored below it' gone /srv/media/a
t_has 'file at L: warned' "$LOG" 'is a file: entries below it are not restored'

sbmk 'f|var/run/x.pid|644|1'
SETUP='mkdir -p /run /var; ln -s ../run /var/run' sbx -y "$ZA"
t_true '/var/run link: still a link' node /var/run l ../run
t_true '/var/run link: file written through it' node /run/x.pid f
sbmk 'l|var/run|../run
f|var/run/y.pid|644|2'
SETUP='mkdir -p /run /var; ln -s ../run /var/run' sbx -y "$ZA"
t_eq '/var/run archive link: restore succeeds' 0 "$RC"
t_true '/var/run archive link: link kept' node /var/run l ../run
t_true '/var/run archive link: content in /run' node /run/y.pid f
t_has '/var/run archive link: counted as kept' "$LOG" '1 links kept'

sbmk 'f|srv/ro/x|644|a
f|srv/ok.txt|644|b'
mkdir -p "$C/empty"
SB_EXTRA=(--ro-bind "$C/empty" /srv/ro)
sbx -y "$ZA"
t_eq 'read-only directory: exit status is non-zero' 1 "$RC"
t_has 'read-only directory: bsdtar error reported' "$LOG" 'bsdtar reported errors'
t_has 'read-only directory: summary still printed with the error count' "$LOG" 'Done: 2 entries, 0 links kept, 0 converted, 0 skipped, 0 warnings, 1 errors.'
t_true 'read-only directory: other files still restored' node /srv/ok.txt f

sbmk "$GEN_SPEC"
SETUP='mkdir -p /srv' POST="cd /; stat -c '$STAT_FMT' -- $(printf '%q ' "${GP[@]}")" sbx -y "$ZA"
t_eq 'names: restore succeeds' 0 "$RC"
t_eq 'names: spaces, globs, UTF-8, arrows and backslashes; modes and mtimes preserved' "$GEN_WANT" "$PO"
t_has 'names: summary' "$LOG" 'Done: 9 entries'

sbmk 'l|srv/a -> b|/mnt/nas
f|srv/a -> b/f.txt|644|x
l|gl*b[1]|/mnt/nas
f|gl*b[1]/g|644|g'
SETUP='mkdir -p /mnt/nas' sbx -y "$ZA"
t_eq 'odd link names: restore succeeds' 0 "$RC"
t_true 'link whose name contains " -> " is kept' node '/srv/a -> b' l /mnt/nas
t_true 'link whose name has glob characters is kept' node '/gl*b[1]' l /mnt/nas
t_true 'content below the odd link names lands in the target' node /mnt/nas/f.txt f
t_true 'content below the glob-named link lands in the target' node /mnt/nas/g f

sbmk "$GEN_SPEC
l|srv/media|/mnt/nas
f|srv/media/a.txt|644|a"
SETUP='mkdir -p /srv/sub /mnt/nas; echo old >/srv/old.txt' sbx -n "$ZA"
t_eq 'dry run: exit 0' 0 "$RC"
t_has 'dry run: says nothing was written' "$LOG" 'Dry run: nothing was written.'
t_eq 'dry run: the fake root is byte-identical afterwards' "$TREE0" "$TREE"

sbmk 'f|srv/mediagarrd.db|644|db'
sbx -n "$ZA"
t_has 'sandbox: database warning' "$LOG" 'warning: archive contains mediagarrd.db'

sbmk 'f|a.txt|644|a'
SB_UID=1000 sbx -n "$ZA"
t_eq 'non-root: dry run succeeds' 0 "$RC"
t_has 'non-root: warning about owners' "$LOG" 'warning: not running as root: owners cannot be restored'

sbmk 'f|a.txt|644|a'
sbx -n "$ZA"
t_lacks 'root: no non-root warning' "$LOG" 'not running as root'

sbmk 'f|a.txt|644|a'
sbx "$ZA"
t_eq 'no tty and no -y: refused' 1 "$RC"
t_has 'no tty and no -y: explained' "$LOG" 'no terminal to ask for confirmation; use --yes'
t_eq 'no tty and no -y: nothing written' "$TREE0" "$TREE"

sbmk 'f|bin/su|4755|x
f|bin/sg|2755|x
f|bin/plain|644|x
l|bin/ln|/mnt/x
f|bin/ln/f|644|f'
SETUP='mkdir -p /r' sbx -C /r -y "$ZA"
t_eq 'root under -C: restore succeeds' 0 "$RC"
t_has 'root under -C: setuid warning' "$LOG" 'warning: running as root: setuid/setgid files from the archive keep their bits under /r'
t_true 'root under -C: setuid bit kept' node /r/bin/su f
t_eq 'root under -C: setuid and setgid modes' '2755 4755' "$(awk -F'|' '$1 == "/r/bin/su" || $1 == "/r/bin/sg" { printf "%s%s", s, $3; s = " " }' <<<"$TREE")"
t_true 'root under -C: no link created' node /r/bin/ln d
t_eq 'root under -C: nothing outside /r except the root dir' '' "$(awk -F'|' 'index($0, "|") && $1 != "/r" && index($1, "/r/") != 1 { print $1 }' <<<"$TREE")"
t_eq 'root under -C: files are owned by uid 0 in the sandbox' '0' "$(awk -F'|' '$1 == "/r/bin/plain" { print $4 }' <<<"$TREE")"

finish
