# CloverRPG-AP

Experimental automatic F input using learned `HitWindow` and `Attack` positions. Auto parry starts **OFF**; learning, discovery, recording, periodic auditing and timing reporting run automatically while the script is loaded.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/AceNo7a/CloverRPG-AP/main/clover_auto_parry.lua"))()
```

The GUI has four controls: **Auto parry**, **Test F**, **Copy logs**, and **Unload**. F7 toggles auto parry; F8 hides the panel. There are no target, distance, delay, learning or audit settings. All nearby NPCs and players are eligible targets. Losing focus or respawning turns automatic input OFF while background features continue. Unload stops the script and its background work.

## Automatic learning

Two consistent completed combat playbacks establish a local timing profile. Continued observations update the median and spread of the last five samples. Ready local profiles override bundled candidates and guard presets. Collecting, variable or multiple-marker local profiles suppress fallback until qualified. Executions, movement, reactions, unclassified animations, loops, interrupted clips and detected seeks remain excluded.

v6.5.1 includes **18 reviewed learned candidates and 20 asset candidates across 20 animation IDs**, scoped to place 8248288152/version 68598. Fresh installations can use these immediately once their combat paths are classified, before local sampling or asset fetch completes. Bite Pounce and Tail Sweep now have reviewed learned candidates as well as their retained asset candidates; single-sample local entries are not promoted to learned evidence. `timing_candidates.json` records the reviewed source values and provenance. Bundles do not create fictitious local samples or report acknowledgements. Existing local validation takes priority, followed by fetched/restored assets, bundled learned timings, then bundled asset timings.

v6.1 accepts exact `HitWindow` and `Attack` marker names, plus identically named keyframes. This enables learning for the observed Wolf Bite Pounce and Tail Sweep animations without hardcoding their timings. Distinct signals within 25 ms of animation time count as one impact; repeated signals or separated impacts block that profile as ambiguous. Attack profiles use the same cache and reporting queue as HitWindow profiles.

Distance and timing bounds remain internal: 8-stud input range, with a 12-stud allowance only for the four identified attacks on NPCs named Wolf, 40-stud observation radius, 0.7-second missed-attempt cooldown, 0.12-second F hold and 120 ms predictive lead converted using current playback speed. Players and other moves retain 8 studs. The wolf allowance addresses captured 8.03/9.63-stud skips; it is a bounded estimate, not a measured universal hitbox. Bundled candidates require place 8248288152/version 68598 and current combat classification. The script does not infer authoritative parry success or automatically optimize the lead based on success.

v6.3 also reads exact timing markers from animation assets when live callbacks are unavailable. Empty primary-provider clips trigger the sequence-provider fallback. All returned provider objects are cloned before inspection/cleanup; destroying shared provider instances could empty the local animation cache. The same combat classification applies, and looping, empty, oversized or ambiguous multi-impact clips are rejected. Up to 32 distinct combat assets are fetched per run with at most two outstanding requests. The four wolf IDs are requested at startup; other eligible IDs are requested when observed. Nothing is queued retroactively after a late asset result.

Ready live observations take priority. Collecting/blocked/variable live profiles suppress the asset fallback. Asset profiles retain separate `asset marker` provenance and never fabricate completed samples. Starting in v6.4, ready asset profiles are saved in a separate `assets` section of the existing cache and reported to Discord as **ASSET** candidates. They can support future playback without waiting for two live callbacks; first encounters are not guaranteed to be protected. Nearby attacks may target somebody else. There is no invulnerability or universal parry guarantee.

**Updating from v6.2 or earlier:** restart Roblox before running v6.3, because earlier audit cleanup may have emptied shared animation objects in the current process. Reloading the script cannot restore destroyed cached clip contents. Existing learned timing files are preserved. Confirm v6.3, enable Auto parry, and avoid Test F during the encounter: that button deliberately switches auto OFF for a single manual test.

Learned profiles, up to 32 ready asset profiles, and separate report fingerprints persist in `clover_timings_v5_<place>.json`. Older learned-only files remain compatible. Both types expire on cache restore after seven days and are rejected on place-version changes; asset restore validates finite marker/duration values and provider names. Current combat classification still gates use/reporting. Unsupported file APIs leave session-only operation. Background audits run after startup and approximately every five minutes; they are bounded and do not stop auto parry.

## Automatic Discord reporting

[The public relay is live](https://clover-timing-relay.indigoamber16384.chatgpt.site). Every compatible installation automatically sends new or changed ready timing candidates to its `/report` endpoint. No private configuration or webhook token is needed in the client. The Discord webhook is stored as a server secret.

Reports contain place/version, animation ID and marker position, with separate **Clover LEARNED timing candidates** and **Clover ASSET timing candidates** Discord headings. Learned reports include sample count/spread; asset reports include clip length/provider and explicitly state there are no live playback samples. The same animation can have both types, with independent deduplication. They omit player names, Roblox user IDs, server IDs, chat, raw discovery/audit logs and video. **Unload** stops future reports; pressing Auto parry OFF only stops F input.

The client sends at most six changed profiles per batch, at least 60 seconds apart, with persisted 10 ms fingerprints and delivery retry/backoff. The relay validates payloads, strips arbitrary text, disables Discord mentions and uses one anonymous global request counter to limit intake to 15 requests/minute. Failed reports remain pending client-side, subject to cache availability. Network/executor shutdowns can interrupt delivery. The hosting provider handles ordinary request metadata; no player-profile database is maintained.

Reports are untrusted candidates, not proof of successful parries or independent observers. They **do not automatically modify GitHub**. Maintainers review Discord evidence before updating `bundledProfiles` and its game-version scope. Rerun the loader to receive a release update.

Values matching the current release's bundled fingerprints are not resubmitted as new discoveries. New qualifying IDs and materially changed marker timings still report automatically through the relay, labeled LEARNED or ASSET. This is per-client deduplication; independent clients may report the same new candidate. Reports remain subject to rate limits, retry, client uptime and request-API availability. After review, a maintainer must publish another release to distribute new entries to everyone.

## Verification

v6.5.1 adds the reported three-sample Bite Pounce and Tail Sweep learned candidates, corroborated by the new capture. Their independent asset metadata is retained.

v6.5 (2026-10-27): 192 Lua assertions pass, including fresh-install access to collected player/wolf timings, game-version scoping, separate bundle provenance, local validation precedence, suppression of known bundled reports, and reporting of new/changed timings. No relay change is required.

v6.4 (2026-10-27): 182 Lua and 25 relay assertions pass, including asset-cache round trips, separate deduplication, source labeling, rejected fabricated sample counts, expiry, legacy cache/report compatibility and retry handling. Learned and asset batches alternate when both have changes, sharing the same rate limit. No auto-parry timing or classification change.

v6.3 (2026-10-27): 171 Lua assertions passed, including shared-cache preservation, empty-provider fallback, asset validation, zero-length playback prediction, movement/execution filtering and bounded NPC-only wolf reach. Live provider probes recovered Bite Pounce's Attack at 0.957916677 and Tail Sweep's Attack at 1.003749967 animation seconds before old cleanup emptied those provider objects. Repeated provider calls returned the same Instance; cleaning private copies preserved 10- and 47-frame test assets. The already affected session still needs restart; restored live callbacks and new combat outcomes have not been verified.

v6.2 adds bounded local diagnostics for missing markers: track starts, subscription results/errors, delayed snapshots at 0.25/1.25/3 seconds, length becoming available, playing-state changes, named keyframes, Stopped/Ended callbacks, reused tracks, seeks, expiry and active tracks at export. Successful subscription does not prove a marker exists or will fire. The 300-line learner buffer reports overwritten lines. Diagnostics stay in **Copy logs** and are not sent to Discord.

Range skips now include actual root-to-root distance, the unchanged 8-stud limit, playback position and speed. This release does not alter learning qualification, parry timing or reach. To test: rerun the loader, confirm v6.2, observe a short wolf encounter, wait about 13 seconds after the last attack for expiry diagnostics, then select **Copy logs**. Send those logs with the matching video. Auto starts OFF; turn it ON when testing input/range skips.

v6.2 (2026-10-27): 149 Lua assertions passed, including subscription failures, zero-length/delayed-loading tracks, missing stop callbacks, lifecycle expiry without false learning, range measurements and diagnostic-buffer bounds. Actual missing-marker cause remains under investigation.

v6.1 (2026-10-27): 74 auto-parry assertions passed, including simulated Bite Pounce and Tail Sweep learning, playback-speed conversion, duplicate signals, multiple impacts, and movement/execution exclusions. Live combat performance of these two moves remains unverified.

v6 (2026-10-27): 119 Lua assertions and 17 relay assertions passed. Live Madium checks confirmed four buttons, zero settings fields, learning/recording/reporting ON, a completed 1,442-line bounded audit, and delivery of one real learned profile through the public relay to Discord. Public unauthenticated GET returned 200 and invalid POST returned 400. Auto input was left OFF.

Successful automatic combat parries and PvP remain unverified. Earlier v5 testing verified learning and cache persistence; a single F-input attempt released the key but did not produce an observed self animation in that trial.

Offline checks from this repository root:

```text
lua tests/auto_parry_checks.lua clover_auto_parry.lua
lua tests/hitwindow_model_checks.lua clover_auto_parry.lua
lua tests/timing_audit_checks.lua clover_auto_parry.lua
lua tests/profile_support_checks.lua clover_auto_parry.lua
lua tests/asset_marker_checks.lua clover_auto_parry.lua
node relay/checks.mjs
```
