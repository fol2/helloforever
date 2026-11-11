# HelloForever export schema

Canonical contract for the offline pipeline (`fol2/wow-data`) and for this
addon. **schemaVersion 6** ships with addon **0.6.0**.

Client: WoW Forever 1.60.1 / TOC 16001. Fight-log *encoding* is still
`fightLog.v = 4` (`FL_VERSION`: JSON → Deflate → Base64). `schemaVersion` is
the *data* envelope and field meanings.

This repository is public: examples use fake names (`FakeHunter` / `TestRealm`)
only.

---

## Export envelope (every snapshot, fight, gap, and the SV root)

Required fields, set by `ns.ExportMeta`:

| Field | Type | Source |
|-------|------|--------|
| `addonVersion` | string | TOC `## Version` (fallback `ns.VERSION_FALLBACK`, must equal the TOC at release) |
| `sourceRevision` | string | `ns.SOURCE_REVISION` — constant bumped at each release (may equal `addonVersion`) |
| `schemaVersion` | number | `ns.SCHEMA_VERSION` — **6** for this document |
| `gameBuild` | string | `select(2, GetBuildInfo())` (the client build, e.g. `"70862"`) |
| `client` | table | `{ version, build, date, toc }` from `GetBuildInfo` (all four returns) |
| `installId` | string | 8 lowercase hex chars, unique per SavedVariables file / machine |

`HelloForeverDB` carries the same envelope at the root so a pipeline that only
reads the file header still sees the version.

Pattern for `installId`: `^[0-9a-f]{8}$`.

---

## schemaVersion history

| schemaVersion | Addon | Notes |
|---------------|-------|--------|
| (none / implicit 4–5) | 0.4.0–0.5.0 | `addonVersion` + `client` on snapshots; fight key `{unix}-{sid}` optionally `-{n}` |
| **6** | **0.6.0** | Envelope above on every export. Fight ID format below. Per-section freshness. Quest states. Hunter pet. Fight context hashes. Profession events. MH observe. |

Importers **must** branch on `schemaVersion` (and still accept records that
only have `addonVersion`, as 0.5.0 files do).

---

## Fight ID

Field: `key` on each fight / gap record (also `fightLog.index` keys and
`fightSummary[].key`).

### Current format (`schemaVersion` ≥ 6, all newly written keys)

```
hf1-<installId>-<unixStart>-<sessionId>-<seq>
```

| Part | Meaning |
|------|---------|
| `hf1` | Format version. Not a suffix on the old two-part id. |
| `installId` | 8 lowercase hex chars from `HelloForeverDB.installId` (one random id per SavedVariables file, so two Macs / two WTF folders never collide) |
| `unixStart` | Fight start, unix seconds (`record.start`) |
| `sessionId` | `C_DamageMeter` session id (`record.sid`) |
| `seq` | Collision counter, **always present**, starting at `1`. A second fight that would share the other three fields gets `2`, `3`, … |

**PCRE (new keys only):**

```
^hf1-[0-9a-f]{8}-\d+-\d+-\d+$
```

Examples (fake data):

```
hf1-a1b2c3d4-1794211200-1-1
hf1-a1b2c3d4-1794211200-1-2
```

`seq` is a required fifth field, not an optional dash-suffix on
`{unix}-{sid}`. That old suffix form (`1794211200-1-2`) is what the
wow-data importer previously rejected.

Addon constant: `ns.FIGHT_KEY_PCRE` is the combined importer pattern below.

### Legacy keys (already stored by 0.4.0 / 0.5.0 — never rewritten)

```
<unixStart>-<sessionId>          e.g. 1794211200-1
<unixStart>-<sessionId>-<n>      e.g. 1794211200-1-2   (old collision suffix)
```

**PCRE (legacy only):**

```
^\d+-\d+(?:-\d+)?$
```

### Combined importer pattern (accept both)

```
^(?:hf1-[0-9a-f]{8}-\d+-\d+-\d+|\d+-\d+(?:-\d+)?)$
```

Lua: `ns.ParseFightKey(key)` returns:

```text
{ format = "hf1"|"legacy"|"legacy_suffix",
  installId? = "<8 hex>",   -- hf1 only
  start = number, sid = number, seq = number }
```

or `nil` if the string is not a fight id.

Gap records use the same `hf1-…` generator (`uniqueKey`). A record's `rev`
is a revision of the **same** key (same fight grown / corrected), not a new
id. A recycled session id that is a different fight gets a new key
(`rekeyOf` names the one it did not overwrite), still in `hf1-…` form.

Lua 5.1 does not have a CSPRNG; `installId` mixes `time()`, `GetTime()` and
`math.random`. Collision across two independent installs is the 32-bit
birthday bound (~2^16 for 50% if millions of installs; two Macs are fine).
