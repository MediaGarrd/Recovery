#!/usr/bin/env bash
set -euo pipefail

PROG=${0##*/}
SEP=$'\037'
ROOT=/ DRY=0 YES=0 WARNS=0 ERRS=0 FULL=1 ARGS=()

usage() {
    cat <<USAGE
Usage: $PROG [-C DIR] [-n] [-y] <backup.zip>
  -C, --root DIR   restore under DIR, without creating symlinks (inspection)
  -n, --dry-run    show the plan and write nothing
  -y, --yes        do not ask for confirmation
  -h, --help       show this help
Stop the MediaGarrd server first. Run as root to restore owners.
USAGE
}
die() { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; WARNS=$((WARNS + 1)); }
mp() { local c="" x a; IFS=/ read -ra a <<<"$1"; for x in ${a[@]+"${a[@]}"}; do c+=${c:+/}$x; if [[ -n ${KP[$c]+y} ]]; then c=${KP[$c]}; fi; done; MP=$c; }
pat() { sed -e 's/[][\\*?^$]/\\&/g' -e "s|^|$1|" -e "s|\$|$2|"; }
chk() { LC_ALL=C awk -v d="$1" -v S="$SEP" 'function par(s) { if (!sub(/\/[^\/]*$/, "", s)) s = ""; return s }
function rs(s,  o, i) { while ((i = index(s, "\001"))) { o = o substr(s, 1, i - 1) "\\"; s = substr(s, i + 1) } return o s }
function rk(l,  r, s, p, i, v) {
    if (l in rank) return rank[l]
    rank[l] = 0
    for (i = 1; i <= 2; i++) {
        p = (i == 1) ? par(l) : pp[l]
        while (p != "") { if (p in tg) { v = rk(p) + 1; if (v > r) r = v } p = par(p) }
    }
    return rank[l] = r + 0
}
function norm(p,  n, a, i, k, o, r) {
    n = split(p, a, "/"); k = 0
    for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == "..") { if (k > 0) k--; continue }
        o[++k] = a[i]
    }
    for (i = 1; i <= k; i++) r = r (i > 1 ? "/" : "") o[i]
    return r
}
NR == FNR { nm[FNR] = $0; nn = FNR; next }
{
    raw = nm[FNR]; ln = $0
    gsub(/\\\\/, "\001", raw); gsub(/\\\\/, "\001", ln)
    if (index(raw, "\\") || index(ln, "\\")) { print "unsupported name or link target (control character): " nm[FNR] > "/dev/stderr"; bad = 1; next }
    raw = rs(raw); ln = rs(ln)
    c = raw; sub(/\/$/, "", c)
    if (c == "" || index("/" c "/", "//") || index("/" c "/", "/./") || index("/" c "/", "/../")) { print "unsafe entry name: " raw > "/dev/stderr"; bad = 1; next }
    total++; bytes += $5
    if (c ~ /(^|\/)mediagarrd\.db$/) db = 1
    if (substr($0, 1, 1) == "l") {
        i = index(ln, " " raw " -> ")
        if (!i) { print "cannot parse link entry: " raw > "/dev/stderr"; bad = 1; next }
        tg[c] = substr(ln, i + length(raw) + 5); u[c] = $3; g[c] = $4
    } else {
        nl[c] = 1
        p = par(c); while (p != "" && !(p in nla)) { nla[p] = 1; p = par(p) }
    }
    p = par(c); while (p != "" && !(p in all)) { all[p] = 1; p = par(p) }
}
END {
    if (FNR != nn) { print "archive listing is inconsistent (newline in a name?)" > "/dev/stderr"; bad = 1 }
    printf "%d %.0f %d %d\n", total, bytes, db, bad > (d "/stats")
    if (bad) exit 3
    for (p in nl) print p > (d "/prov")
    for (p in nla) print p > (d "/prov")
    for (l in tg) {
        cur = l; h = 0; ok = 1; P = ""
        while (1) {
            t = tg[cur]
            if (t == "") { ok = 0; break }
            P = (t ~ /^\//) ? norm(t) : norm(par(cur) "/" t)
            if (!(P in tg)) break
            if (++h > 8) { ok = 0; break }
            cur = P
        }
        pp[l] = P; okk[l] = ok
    }
    for (l in tg) print rk(l) S l S tg[l] S pp[l] S okk[l] S ((pp[l] in nl) || (pp[l] in nla) ? 1 : 0) S ((l in all) ? 1 : 0) S u[l] S g[l] > (d "/links.raw")
}' "$1/n" "$1/v"; }
if [[ ${BASH_SOURCE[0]-$0} != "$0" ]]; then return 0; fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/mgrecover.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while (($#)); do
    case $1 in
        -C | --root) (($# > 1)) || die "$1 needs an argument"; ROOT=$2; shift ;;
        --root=*) ROOT=${1#*=} ;;
        -n | --dry-run) DRY=1 ;;
        -y | --yes) YES=1 ;;
        -h | --help) usage; exit 0 ;;
        --) shift; ARGS+=("$@"); break ;;
        -?*) usage >&2; exit 2 ;;
        *) ARGS+=("$1") ;;
    esac
    shift
done
((${#ARGS[@]} == 1)) || { usage >&2; exit 2; }
ARCH=${ARGS[0]}

command -v bsdtar >/dev/null || die "bsdtar not found (Debian/Ubuntu: apt install libarchive-tools; Arch: pacman -S libarchive; Fedora: dnf install bsdtar)"
[[ -f $ARCH && -r $ARCH ]] || die "cannot read $ARCH"
[[ $(head -c2 -- "$ARCH") == PK ]] || die "not a zip archive: $ARCH"
[[ -n $ROOT ]] || die "empty root"
if [[ -d $ROOT ]]; then ROOT=$(CDPATH='' cd -- "$ROOT" && pwd -P); elif [[ -e $ROOT ]]; then die "not a directory: $ROOT"; fi
if [[ $ROOT =~ ^/+$ ]]; then ROOT=/; else FULL=0; fi

u=0
if [[ $(locale charmap 2>/dev/null) == UTF-8 ]]; then u=1; fi
for l in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if ((u)); then break; fi
    if ! command -v locale >/dev/null || locale -a 2>/dev/null | grep -xF "$l" >/dev/null; then export LC_ALL=$l; u=1; fi
done
((u)) || warn "no UTF-8 locale found; non-ASCII names may fail"

bsdtar -tf "$ARCH" >"$TMP/n" || die "bsdtar cannot read $ARCH"
bsdtar --numeric-owner -tvf "$ARCH" >"$TMP/v" || die "bsdtar cannot read $ARCH"
[[ -s $TMP/n ]] || die "archive is empty"
: >"$TMP/links.raw"; : >"$TMP/prov"

chk "$TMP" || die "archive has entries this tool refuses to restore; nothing was written"
read -r TOTAL BYTES DB _ <"$TMP/stats"
LC_ALL=C sort -n -t "$SEP" -k1,1 "$TMP/links.raw" >"$TMP/links"

: >"$TMP/all"; : >"$TMP/kept"; : >"$TMP/sub"; : >"$TMP/nofile"; : >"$TMP/inc"; : >"$TMP/rm"
declare -A KP=()
D=${ROOT%/}
nk=0 nc=0 ns=0
while IFS=$SEP read -r _ L T P OK PROV KIDS U G; do
    printf '%s\n' "$L" >>"$TMP/all"
    mp "$P"; pm=$MP; mp "$L"; lm=$MP
    why=""
    if ((!FULL)); then why="no links under --root"
    elif ((!OK)); then why="broken link chain"
    elif ((!PROV)) && [[ ! -e /$pm ]] && ! { [[ $pm != "$P" ]] && grep -qxF -- "$pm" "$TMP/prov"; }; then why="target /$P does not exist and is not in the archive"
    elif [[ -e /$lm && ! -L /$lm ]]; then why="$D/$L already exists; real data is kept"
    fi
    if [[ -z $why ]]; then
        printf '%s\n' "$L" >>"$TMP/sub"
        if ((KIDS)); then printf '%s\n' "$L" >>"$TMP/inc"; fi
        printf '%s\n' "$L$SEP$T$SEP$P$SEP$KIDS$SEP$U$SEP$G" >>"$TMP/kept"
        KP[$L]=$pm
        echo "keep    $D/$L -> $T"
        ((++nk))
    elif ((KIDS)); then
        if ((FULL)) && [[ -e /$lm && ! -L /$lm && ! -d /$lm ]]; then
            printf '%s\n' "$L" >>"$TMP/nofile"
            warn "$D/$L is a file: entries below it are not restored (link to $T not created)"
            ((++ns))
        else
            how="restored as a real directory"
            if ((FULL)) && [[ -L /$lm ]]; then
                if [[ -e /$lm ]]; then how="written through the existing link"; else printf '%s\n' "/$lm" >>"$TMP/rm"; fi
            fi
            echo "convert $D/$L -> $T ($why): contents $how"
            ((++nc))
        fi
    else
        if ((FULL)); then warn "$D/$L -> $T skipped ($why)"; else echo "skip    $D/$L -> $T ($why)"; fi
        ((++ns))
    fi
done <"$TMP/links"
pat '^' '$' <"$TMP/all" >"$TMP/x1"
pat '^' / <"$TMP/sub" >"$TMP/x2"
pat '^' / <"$TMP/nofile" >"$TMP/x4"
pat '' '/*' <"$TMP/inc" >"$TMP/x3"

echo "Archive : $ARCH ($TOTAL entries, $(numfmt --to=iec "$BYTES"))"
echo "Root    : $ROOT"
echo "Links   : $nk kept, $nc with content below them converted, $ns skipped"
if ((DB)); then warn "archive contains mediagarrd.db: the MediaGarrd server must be stopped before restoring"; fi
if ((FULL && EUID != 0)); then warn "not running as root: owners cannot be restored and some paths may fail"; fi
if ((!FULL && EUID == 0)); then warn "running as root: setuid/setgid files from the archive keep their bits under $D"; fi
if ((DRY)); then echo "Dry run: nothing was written."; exit 0; fi

if ((!YES)); then
    [[ -t 0 ]] || die "no terminal to ask for confirmation; use --yes"
    read -r -p "Restore now? [y/N] " a || a=
    [[ $a == [yY]* ]] || die "aborted"
fi

mkdir -p -- "$ROOT"
xt=(bsdtar -xpf "$ARCH" -C "$ROOT")
if ((FULL)); then xt+=(-P); else xt+=(--no-same-owner); fi
while IFS= read -r p; do rm -f -- "$p" || ERRS=$((ERRS + 1)); done <"$TMP/rm"
cat "$TMP/x1" "$TMP/x2" "$TMP/x4" >"$TMP/xa"
cat "$TMP/x1" "$TMP/x4" >"$TMP/xc"
"${xt[@]}" -X "$TMP/xa" || { ERRS=$((ERRS + 1)); echo "$PROG: bsdtar reported errors" >&2; }
if [[ -s $TMP/kept ]]; then
    while IFS=$SEP read -r L T P KIDS U G; do
        if ! mkdir -p -- "$(dirname -- "/$L")" || { ((KIDS)) && [[ ! -e /$P ]] && ! mkdir -p -- "/$P"; }; then
            ERRS=$((ERRS + 1)); continue
        fi
        ln -sfnT -- "$T" "/$L" || ERRS=$((ERRS + 1))
        if ((EUID == 0)); then chown -h "$U:$G" "/$L" || true; fi
    done <"$TMP/kept"
fi
if [[ -s $TMP/inc ]]; then
    "${xt[@]}" -X "$TMP/xc" -T "$TMP/x3" || { ERRS=$((ERRS + 1)); echo "$PROG: bsdtar reported errors" >&2; }
fi

echo "Done: $TOTAL entries, $nk links kept, $nc converted, $ns skipped, $WARNS warnings, $ERRS errors."
((ERRS == 0))
