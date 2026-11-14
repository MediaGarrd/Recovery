#!/usr/bin/env bash
# shellcheck disable=SC2034
GP=('gen/sp dir' 'gen/sp dir/a b.txt' 'gen/glob/*[x]?.txt' 'gen/glob/[a]' 'gen/utf8/héllo-日本.txt' 'gen/arrow/a -> b.txt' 'gen/back/we\ird.txt' 'gen/mode/exec.sh' 'gen/mode/secret')
GEN_SPEC='d|gen/sp dir|750
f|gen/sp dir/a b.txt|600|spaces
f|gen/glob/*[x]?.txt|644|glob
f|gen/glob/[a]|755|bracket
f|gen/utf8/héllo-日本.txt|644|utf8
f|gen/arrow/a -> b.txt|644|arrow
f|gen/back/we\\ird.txt|644|backslash
f|gen/mode/exec.sh|755|exec
f|gen/mode/secret|600|secret'
GEN_WANT='gen/sp dir|directory|750|1577836800
gen/sp dir/a b.txt|regular file|600|1577836800
gen/glob/*[x]?.txt|regular file|644|1577836800
gen/glob/[a]|regular file|755|1577836800
gen/utf8/héllo-日本.txt|regular file|644|1577836800
gen/arrow/a -> b.txt|regular file|644|1577836800
gen/back/we\ird.txt|regular file|644|1577836800
gen/mode/exec.sh|regular file|755|1577836800
gen/mode/secret|regular file|600|1577836800'
STAT_FMT='%n|%F|%a|%Y'
