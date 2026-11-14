# MediaGarrd Recovery

`mgrecover.sh` restores a [MediaGarrd](https://mediagarrd.github.io/MediaGarrd/) backup archive (`<timestamp>-media-backup.zip`) to the original paths of its files, with contents, permissions, owners (as root) and file modification times.

## Requirements

- bash 4+, `bsdtar` (Debian/Ubuntu: `apt install libarchive-tools`, Arch: `pacman -S libarchive`, Fedora: `dnf install bsdtar`), coreutils, `awk`, `sed`

## Install
For a minimal download of the tool:
```sh
wget https://github.com/MediaGarrd/Recovery/releases/latest/download/mgrecover.sh
```
To download the full repo:
```sh
git clone --depth 1 https://github.com/MediaGarrd/Recovery.git
cd Recovery
```

Optional: `sudo install -m 755 mgrecover.sh /usr/local/bin/mgrecover`.

## Usage

```sh
sudo ./mgrecover.sh 20261112-140649-938-media-backup.zip
./mgrecover.sh -n 20261112-140649-938-media-backup.zip
./mgrecover.sh -C /tmp/restore 20261112-140649-938-media-backup.zip
```

| Option | Meaning |
| --- | --- |
| `-C, --root DIR` | Restore under `DIR` instead of `/`. For inspection: no symlinks are created. |
| `-n, --dry-run` | Print the plan and write nothing. |
| `-y, --yes` | Do not ask for confirmation (required without a terminal). |
| `-h, --help` | Show usage. |

Exit status is `0` on success (also with warnings) and non-zero on errors.

## Symlinks

- Restoring to `/`: a link `L -> T` is recreated only if its target (following links stored in the archive, up to 8 hops) exists on the machine or is stored in the archive. Otherwise the link is not created, files stored below it go to a real directory at `L` (a dangling link already there is removed), and a link with nothing below it is skipped with a warning. Real files or directories already at `L` are never replaced. Links already on the machine, such as `/var/run`, are followed. Relative `..` targets are judged by name, not through other links. Link times are not restored, link owners only as root, and directories that receive content through kept links (the link targets) get the current time.
- With `-C DIR`: no link is created; files stored below a link are restored as a real directory. Existing symlinks under `DIR` are not followed. Files are restored without owners, but setuid/setgid bits are kept, so as root review the tree before making it reachable by others.
- Both modes refuse the whole archive, before writing anything, if a name has `..`, empty or `.` components, a leading `/`, a control character or a newline.

## Testing

`make test` runs shellcheck, unit tests and simulated restores (some inside a `bwrap` sandbox with a private fake `/`; the real `/` is never touched). It needs `shellcheck`, `bubblewrap`, `bsdtar` and `python3` (Debian/Ubuntu: `apt install shellcheck bubblewrap libarchive-tools python3`). Link owners (`chown -h`) are not tested, since the sandbox maps only uid 0.

## Stop the server first

The archive contains the MediaGarrd server's database (`mediagarrd.db`). Stop the server before restoring, or the live database is corrupted.

## Links

- Website: <https://mediagarrd.github.io/MediaGarrd/>
- Server: <https://github.com/MediaGarrd/Server>

## License

MIT, see [LICENSE](LICENSE).
