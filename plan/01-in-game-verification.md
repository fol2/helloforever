# Verify 0.6.0 in the WoW Forever client

**Why.** Everything in 0.6.0 has only run against the mock client in `tests/`. Event names
and API shapes on Forever 1.60.1 are assumptions until the game confirms them. The addon
treats every client API as optional, so a wrong assumption does not break it: it shows up
as a missing section or event. `/hello selftest` lists exactly those.

**Install.** `reader/target/release/hellolink package --root <dir>`, with `<dir>` the 0.6.0 tree (`git archive <0.6.0's commit> | tar -x -C <dir>`; that tree has no packer of its own), builds `<dir>/dist/HelloForever-0.6.0.zip` and prints
SHA-256 sums; unzip into `Interface/AddOns/`, `/reload`. Do this on every machine that
plays, with the same build (the offline pipeline reports it when they differ).

**State on 12 Nov 2026.** 0.6.0 was installed on the development Mac (a real folder now,
not a symbolic link; the SavedVariables of before are in `dist/sv-backup-before-0.6.0/`).
0.7.0 was installed the same day. Seen in the saved data since then: spell names are real
(section 8), Matty Hunter is recorded with `status = "ok"`, and fights were filed again at
every login (fixed in 0.7.1, section 2). No fight has been pulled under 0.7.0 yet, so the
rest of section 8 is open.

## 1. Selftest first

Play normally for a few minutes: a couple of fights, loot something, hand in a quest. Then:

```
/hello selftest
```

| Line | Healthy | If not |
|------|---------|--------|
| events unknown to this client | `PLAYER_TALENT_UPDATE` and/or `CHARACTER_POINTS_CHANGED` may be listed (Classic-era fallbacks). `BAG_UPDATE_DELAYED` listed is fine too: the addon falls back to `BAG_UPDATE`. | `QUEST_TURNED_IN` listed: repeatable-quest turn-ins will be recorded as abandoned (see 3). `TRAIT_CONFIG_UPDATED` listed **and** both talent fallbacks listed: talents only refresh on login / level-up. `DAMAGE_METER_*` listed: fight capture cannot work; stop and report. |
| events registered but not fired yet | Only events whose trigger you have not done yet. | An event still silent after you did its trigger (looted → `BAG_UPDATE_DELAYED`, handed in a quest → `QUEST_TURNED_IN`, spent a talent point → `TRAIT_CONFIG_UPDATED`) does not work the way the addon expects: note which. |
| APIs present | Most of 24. `C_QuestLog.IsComplete` and one of the pet APIs may be missing. | Missing `C_DamageMeter.*` or `C_EncodingUtil.*`: fights are not captured or not compressed. Missing `C_QuestLog.GetQuestObjectives` **and** no quest states other than `unknown`: see 3. |
| snapshot sections not ok | `none`, or `timePlayed=stale` right after login. | A section `unavailable` means its API did not answer: note which. |
| Matty Hunter | `unavailable` without MH; with MH see `04-matty-hunter-contract.md`. | |

The result is also saved as `HelloForeverDB.selftest`, so after a `/reload` the offline
pipeline's copy of the SavedVariables has it. Paste the chat output into the pull request
or issue that tracks this.

## 2. Identity and fight keys

- [ ] `/hello debug` shows the installed version twice (`addon=` and `sourceRevision=`), `schemaVersion=6` and an 8-hex
      `installId` that is the same after a second `/reload`. Seen on 16 Nov 2026 on the bank
      character (0.18.1): the panel's menu is titled `HelloForever 0.18.1`; the chat's trade lines
      pushed the first lines of `/hello debug` out of sight, so the values were read where the
      addon writes them: after `/reload`, `addonVersion` and `sourceRevision` are `0.18.1` (twice
      each), `schemaVersion` 6, and `installId` `2a713bc6`, as before the reload. Seen on 16 Nov
      2026 on the owner's hunter, in `/hello debug`'s own output (the owner's screenshots, after
      the `.lua` files of 0.18.3 were copied in and one `/reload`): `addon=0.18.2
      sourceRevision=0.18.3`, `schemaVersion=6 installId=2a713bc6`. The two versions differ there
      as `docs/code-standards.md` says they do between the copy and the next close. Still to see
      in that output: the same version twice (after the folder is replaced), and the
      `installId` after a second `/reload`.
- [ ] A new fight's key (SavedVariables, `fightLog.days[...].keys`) looks like
      `hf1-<installId>-<unix>-<sid>-1`. Keys written by 0.5.0 are unchanged.
- [ ] A few pulls, a chain pull, and a `/reload` in between: every fight is there once, and
      `/hello fights` lists them.
- [ ] Note the number of fights (`/hello debug`, or the fight window). Quit the game, start
      it again and log in: the number is the same. Before 0.7.1 every login filed the last
      session's fights again (about 30 copies each time).

## 3. Quests

- [ ] A quest with partial progress is `in_progress`; one with everything done is `ready`;
      a fresh one is `accepted`. `unknown` only for quests with no objectives.
- [ ] Abandon a quest: it appears in `snapshot.quests.abandoned`.
- [ ] Hand one in: it does **not** appear in `abandoned`, and its id is in `completed`.
- [ ] Hand in a **repeatable** quest: not in `abandoned` (this is what `QUEST_TURNED_IN` is for).
- [ ] Take an abandoned quest again: its `abandoned` entry goes away.

## 4. Fight context

- [ ] Swap a piece of gear, pull: the fight's `context.gear` is the hash `/hello debug`
      showed before the pull. A second pull in the same gear has the same hash.
- [ ] Two pulls back to back with a gear swap between them: each has its own `context.gear`.
- [ ] Spend a talent point (or respec), pull: `context.talents` changed.
- [ ] No hitch at the start of combat.

## 5. Pet (hunter)

- [ ] `snapshot.pet`: `kind = "hunter"`, name, family, level, Growl with its rank and
      autocast state, happiness, training points.
- [ ] A temporary summon is `kind = "temporary"`; no pet is `kind = "none"`.

## 6. Professions and bags

- [ ] Out of combat, cast a class spell whose name contains a skill-line name (for a
      hunter, Arcane Shot): **no** `profession_cast` event.
- [ ] Fish, mine, skin or pick a herb: one `profession_cast`, then `profession_loot`.
- [ ] A skill-up appears once in `events` as `skill_up` with `skill` and `rank`.
- [ ] Loot several items at once: `snapshot.bags` is up to date after about ten seconds.

## 7. Must not regress

- [ ] `/hello export`: the fight log stays within its budget. Seen on 16 Nov 2026 on the bank
      character: `0 fights, 0 day(s) since -, 0 KB of 3072 KB budget, 0 day(s) trimmed` (it has
      never fought). Still to see: a character with fights, against its budget.
- [ ] Logging out and in keeps the last good snapshot (no zeroed money / level). Seen on
      16 Nov 2026, the logging out half: after a `/reload` and a quit, the bank character's
      snapshot has its money and level 1, every section `ok`. The logging in half is open.

## 8. Pull stats (0.7.0)

Fight a few mobs, `/reload`, and look at a fight's `pull` block in the SavedVariables (or in
the offline pipeline's fight file).

- [ ] `pull.start` and `pull.stop` have `hp`, `mp` and (with a pet out) `petHp`. If they are
      missing, the client keeps them secret at the combat events: note which.
- [ ] `pull.stop.xp - pull.start.xp` is the XP the kill gave (compare with the chat line). If
      it is 0 and the next fight's `start.xp` has it, the XP arrives after combat ends: note it.
- [ ] `pull.target` is the mob you pulled, with its level. Try a pet pull and a mob that
      attacks first: note what the target is then.
- [ ] `pull.casts` has Auto Shot (spell 75) with a plausible count, and the shot that opened
      the fight (`lead` is 1 for an Aimed Shot opener).
- [ ] `pull.petCasts` has the pet's abilities (Growl, Bite or Claw).
- [ ] `spellNames` gives real names.
- [ ] No hitch at the start or end of combat.

## 9. AFK reload (0.8.0): checked, does not work, removed in 0.8.1

Seen on 12 Nov 2026 with `/hlink reloadtest` (HelloLink): `ReloadUI` called from a timer
gave "Interface action failed because of an AddOn" and the UI stayed. A reload needs a key
press or a click on this client.

Still to check, with 0.8.1 installed (a file from 0.8.0 may have the switch on):

- [ ] `/afk` out of combat: no "reloading in 5 s" line, no reload, no error.
- [ ] `/hello afkreload on`: one line saying the reload when AFK is gone and why.
- [ ] `/hello` (the help list) has no `afkreload` line.


## 10. The combat log on by default (0.20.0, #354; 0.20.1, #356)

With 0.20.0 installed (the account held `"auto"` before). Boxes 1 and 3 on the level 1 test character; box 2 in the owner's play (no combat on the test character):

- [ ] `/hello combatlog` says `combatlog = on` after the first load (the one-time switch).
      Not yet seen as output. The saved data of 18:12 holds `combatLog = "on"` and `combatLogOnce = true`.
- [x] The owner's next solo fight in the open world makes the newest `Logs/WoWCombatLog-*.txt` grow.
      Seen on 28 Nov 2026: `WoWCombatLog-112826_144558.txt` began at 14:45:58 and was 14.3 MB at 18:51, after the
      owner's play with 77 pulls.
- [ ] `/hello combatlog off`, then `/reload`: it still says `off`. Then `/hello combatlog on` again.
- [x] With 0.20.1: the first line of the newest `Logs/WoWCombatLog-*.txt` says `ADVANCED_LOG_ENABLED,1` (#356).
      Seen on 28 Nov 2026: `COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,1.60.1,PROJECT_ID,18`.

**Done when.** The selftest output is recorded, every box above is ticked or has a note
saying what the client did instead, and any event or API that turned out different has an
issue describing it.
