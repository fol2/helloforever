# Tag and publish releases

**Why.** Git tags stop at `v0.4.0`; 0.5.0 and 0.6.0 exist only as commits on `main`. There
is no packaged download, so what is installed on a machine cannot be compared with a
release.

**The tool.** `python3 tools/package.py` checks that the TOC version, `VERSION_FALLBACK`,
`SOURCE_REVISION` and `CHANGELOG.md` agree, runs the tests, builds
`dist/HelloForever-<version>.zip` (a `HelloForever/` folder ready for `Interface/AddOns`),
and prints SHA-256 sums of the zip and of each file. `--check` does the checks without
building.

**Do.**

1. Tag 0.5.0 where it was merged (`git log --oneline --grep "v0.5.0"` finds
   "HelloForever v0.5.0: new UI, modules, cheaper capture, edge-case fixes (#1)"):
   `git tag -a v0.5.0 <that commit> -m "HelloForever 0.5.0"`.
2. Finish `01-in-game-verification.md` first. If it needs code changes, land them, bump the
   version in the TOC, `VERSION_FALLBACK`, `SOURCE_REVISION` and add a changelog section.
3. On the commit to release: `python3 tools/package.py`, then
   `git tag -a v<version> -m "HelloForever <version>"` and `git push origin v0.5.0 v<version>`.
4. Publish: `gh release create v<version> dist/HelloForever-<version>.zip --notes-file <the
   changelog section>`, with the printed SHA-256 lines in the notes.

**For each later release:** bump the three version strings together (the test suite and
`package.py --check` fail when they differ), add the changelog section, then steps 3 and 4.

**Done when.** `git tag` lists `v0.5.0` and the verified 0.6.x, and the latest release has
the zip attached.
