#!/usr/bin/env bash
dump() {
    local skip=(\( -path /usr -o -path /proc -o -path /dev -o -path /tmp -o -path /.mg -o -path /bin -o -path /lib -o -path /lib64 -o -path /sbin -o -path /etc/alternatives \) -prune -o)
    find / -mindepth 1 "${skip[@]}" ! -path /etc -printf '%p|%y|%m|%U|%l\n' | LC_ALL=C sort
    find / -mindepth 1 "${skip[@]}" -type f -exec sha256sum {} + | LC_ALL=C sort
}
cd /
eval "$SETUP"
dump >/.mg/out/tree0
for ((i = 1; i <= ${RUNS:-1}; i++)); do
    bash /.mg/mgrecover.sh "$@" >"/.mg/out/log$i" 2>&1 <"${STDIN:-/dev/null}"
    echo $? >"/.mg/out/rc$i"
    dump >"/.mg/out/tree$i"
done
eval "$POST" >/.mg/out/post 2>&1
exit 0
