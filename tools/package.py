#!/usr/bin/env python3
"""Check and package a HelloForever release.

    python3 tools/package.py            # check, run the tests, build dist/HelloForever-<version>.zip
    python3 tools/package.py --check    # checks and tests only, no zip
    python3 tools/package.py --no-tests # skip the test suite (CI already ran it)

Checks, before anything is built:
  * the TOC version, ns.VERSION_FALLBACK and ns.SOURCE_REVISION in Core.lua are the same;
  * CHANGELOG.md has a section for that version;
  * every file the TOC loads exists.

The zip holds a top-level HelloForever/ folder (the TOC plus the files it loads), ready to
drop into Interface/AddOns. File times and order are fixed, so the same source gives the
same zip on the same Python/zlib; the per-file SHA-256 lines are what to compare with an
installed copy on any machine.

Tagging and publishing are not done here; see plan/ for the release steps.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "HelloForever"
FIXED_TIME = (2020, 1, 1, 0, 0, 0)


def toc_info() -> tuple[str, list[str]]:
    version, files = None, []
    for line in (ADDON / "HelloForever.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        m = re.match(r"^##\s*Version:\s*(\S+)", line)
        if m:
            version = m.group(1)
        elif line and not line.startswith("#"):
            files.append(line)
    if not version:
        raise SystemExit("HelloForever.toc has no ## Version")
    return version, files


def check() -> tuple[str, list[str]]:
    version, files = toc_info()
    problems = []
    core = (ADDON / "Core.lua").read_text(encoding="utf-8")
    for name in ("VERSION_FALLBACK", "SOURCE_REVISION"):
        m = re.search(rf'ns\.{name}\s*=\s*"([^"]+)"', core)
        if not m:
            problems.append(f"Core.lua has no ns.{name}")
        elif m.group(1) != version:
            problems.append(f"ns.{name} is {m.group(1)!r} but the TOC says {version!r}")
    if not re.search(rf"^## HelloForever {re.escape(version)}\b", (ROOT / "CHANGELOG.md").read_text(encoding="utf-8"), re.M):
        problems.append(f"CHANGELOG.md has no '## HelloForever {version}' section")
    for name in files:
        if not (ADDON / name).is_file():
            problems.append(f"the TOC loads {name}, which does not exist")
    if problems:
        raise SystemExit("release check failed:\n  " + "\n  ".join(problems))
    return version, files


def run_tests() -> None:
    for cmd in (["lua5.1", "tests/id_freshness.lua"], ["lua5.1", "tests/fights_harness_v4.lua"]):
        done = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        tail = (done.stdout.strip().splitlines() or ["(no output)"])[-1]
        print(f"  {' '.join(cmd)}: {tail}")
        if done.returncode != 0:
            raise SystemExit(f"tests failed: {' '.join(cmd)}")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(version: str, files: list[str]) -> Path:
    out = ROOT / "dist" / f"HelloForever-{version}.zip"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name in ["HelloForever.toc", *sorted(files)]:
            info = zipfile.ZipInfo(f"HelloForever/{name}", date_time=FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, (ADDON / name).read_bytes())
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="checks and tests only")
    ap.add_argument("--no-tests", action="store_true")
    args = ap.parse_args()
    version, files = check()
    print(f"HelloForever {version}: TOC, VERSION_FALLBACK, SOURCE_REVISION and CHANGELOG agree")
    if not args.no_tests:
        run_tests()
    if args.check:
        return 0
    out = build(version, files)
    print(f"{sha256(out)}  {out.relative_to(ROOT)}")
    for name in ["HelloForever.toc", *sorted(files)]:
        print(f"{sha256(ADDON / name)}  HelloForever/{name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
