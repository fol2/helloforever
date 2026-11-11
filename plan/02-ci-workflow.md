# Add the CI workflow

**Why.** The tests and luacheck are only run by hand. The cloud session's GitHub access may
not create files under `.github/workflows/`, so the workflow is parked in `plan/ci.yml`.

**Do.**

```bash
mkdir -p .github/workflows
git mv plan/ci.yml .github/workflows/ci.yml
git commit -m "Run the tests, luacheck and release checks on every pull request."
```

**What it does.** On every pull request and every push to `main`, on Ubuntu with Lua 5.1:
`lua5.1 tests/id_freshness.lua`, `lua5.1 tests/fights_harness_v4.lua`,
`luacheck HelloForever tests`, and `python3 tools/package.py --check --no-tests` (TOC
version, `VERSION_FALLBACK`, `SOURCE_REVISION` and the changelog agree; every file the TOC
loads exists).

**Done when.** A pull request shows a green "CI / test" check.
