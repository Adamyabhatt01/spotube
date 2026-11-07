#!/usr/bin/env python3
"""Pack a Debian package from a fastforge deb staging tree, without dpkg-deb.

fastforge (flutter_app_packager's deb maker) stages a valid DEBIAN/ tree
but invokes `dpkg-deb` to bundle it, which Arch and minimal CI images
don't ship. A .deb is just an `ar` archive of three members:

  debian-binary  "2.0\\n"
  control.tar.gz (DEBIAN/ only)
  data.tar.gz    (everything except DEBIAN/)

so we tar both trees with gzip and write the ar members ourselves.
dpkg-deb on Debian/Ubuntu reads the result identically.

Usage:
  make-deb <staging-dir> <output.deb>

`--data-prefix` (default `.`) re-roots the staged data tree inside the
package payload (used when the bundle payload lives under a subdir).
"""
from __future__ import annotations

import os
import sys
import tarfile
from pathlib import Path

AR_GLOBAL_HEADER = b"!<arch>\n"


def ar_member(name: str, data: bytes) -> bytes:
    """One ar archive member (System V format)."""
    header = (
        f"{name:<16}"  # name (16)
        f"{0:<12}"  # mtime (12)
        f"{'0':<6}"  # uid (6)
        f"{'0':<6}"  # gid (6)
        f"{'100644':<8}"  # mode octal (8)
        f"{len(data):<10}"  # size (10)
        "`\n"  # magic (2)
    ).encode()
    assert len(header) == 60, f"bad ar header for {name}"
    pad = b"\n" if len(data) % 2 else b""
    return header + data + pad


def tgz(members: list[tuple[str, bytes] | tuple[str, Path]]) -> bytes:
    """Deterministic gzip tar of (arname, content) pairs."""
    import gzip
    import io

    out = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", compresslevel=6, mtime=0, fileobj=out) as gz:
        with tarfile.open(fileobj=gz, mode="w") as tar:
            for name, content in members:
                data = content.read_bytes() if isinstance(content, Path) else content
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.mtime = 0
                info.uid = 0
                info.gid = 0
                info.uname = ""
                info.gname = ""
                info.mode = 0o755 if name.endswith(("postinst", "postrm", "prerm")) else 0o644
                tar.addfile(info, io.BytesIO(data))
    return out.getvalue()


def pack(staging: Path, out_path: Path, data_prefix: str = ".") -> int:
    debian = staging / "DEBIAN"
    if not debian.is_dir():
        print(f"{staging}: no DEBIAN/ tree", file=sys.stderr)
        return 1

    control_files: list[tuple[str, bytes | Path]] = []
    for f in sorted(debian.iterdir()):
        if f.is_file():
            control_files.append((f"./{f.name}", f.read_bytes()))

    data_files: list[tuple[str, bytes | Path]] = []
    for root, dirs, files in sorted(os.walk(staging)):
        if "DEBIAN" in Path(root).relative_to(staging).parts:
            continue
        for name in sorted(files):
            path = Path(root) / name
            rel = path.relative_to(staging)
            prefix = "" if data_prefix == "." else data_prefix.strip("/") + "/"
            data_files.append((f"./{prefix}{rel}", path))

    ar = b"".join(
        [
            AR_GLOBAL_HEADER,
            ar_member("debian-binary", b"2.0\n"),
            ar_member("control.tar.gz", tgz(control_files)),
            ar_member("data.tar.gz", tgz(data_files)),
        ]
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(ar)
    print(f"wrote {out_path} ({len(ar)} bytes)")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if len(args) != 2:
        print(__doc__)
        return 2
    staging, output = Path(args[0]), Path(args[1])
    return pack(staging, output)


if __name__ == "__main__":
    raise SystemExit(main())
