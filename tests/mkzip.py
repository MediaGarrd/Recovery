import re
import sys
import zipfile

ESC = re.compile(r"\\(x[0-9a-fA-F]{2}|n|t|\\)")
SIMPLE = {"n": "\n", "t": "\t", "\\": "\\"}
STAMP = (2020, 1, 1, 0, 0, 0)


def dec(s):
    return ESC.sub(lambda m: SIMPLE.get(m.group(1)) or chr(int(m.group(1)[1:], 16)), s)


def entry(kind, name, a, b):
    if kind == "d":
        info = zipfile.ZipInfo(name.rstrip("/") + "/", STAMP)
        info.external_attr = ((0o40000 | int(a or "755", 8)) << 16) | 0x10
        return info, b""
    info = zipfile.ZipInfo(name, STAMP)
    if kind == "l":
        info.external_attr = (0o120777 << 16)
        return info, a.encode()
    info.external_attr = (0o100000 | int(a or "644", 8)) << 16
    return info, (b if b is not None else "x").encode()


def main():
    with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_STORED) as z:
        for line in sys.stdin.read().split("\n"):
            if not line:
                continue
            f = [dec(x) for x in line.split("|")]
            f += [None] * (4 - len(f))
            info, data = entry(f[0], f[1], f[2], f[3])
            info.create_system = 3
            z.writestr(info, data)


main()
