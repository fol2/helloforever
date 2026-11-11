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
