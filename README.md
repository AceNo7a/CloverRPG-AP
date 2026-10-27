# CloverRPG-AP

Experimental automatic F input using learned `HitWindow` and `Attack` positions. Auto parry starts **OFF**; learning, discovery, recording, periodic auditing and timing reporting run automatically while the script is loaded.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/AceNo7a/CloverRPG-AP/main/clover_auto_parry.lua"))()
```

The GUI has four controls: **Auto parry**, **Test F**, **Copy logs**, and **Unload**. F7 toggles auto parry; F8 hides the panel. There are no target, distance, delay, learning or audit settings. All nearby NPCs and players are eligible targets. Losing focus or respawning turns automatic input OFF while background features continue. Unload stops the script and its background work.

## Automatic learning

Two consistent completed combat playbacks establish a local timing profile. Continued observations update the median and spread of the last five samples. Ready local profiles override the seven bundled candidates and guard presets. Collecting, variable or multiple-marker local profiles suppress preset fallback until qualified. Executions, movement, reactions, unclassified animations, loops, interrupted clips and detected seeks remain excluded.

v6.1 accepts exact `HitWindow` and `Attack` marker names, plus identically named keyframes. This enables learning for the observed Wolf Bite Pounce and Tail Sweep animations without hardcoding their timings. Distinct signals within 25 ms of animation time count as one impact; repeated signals or separated impacts block that profile as ambiguous. Attack profiles use the same cache and reporting queue as HitWindow profiles.

Distance and timing bounds remain internal: 8-stud input range, 40-stud observation radius, 0.7-second missed-attempt cooldown, 0.12-second F hold and 120 ms predictive lead converted using current playback speed. These are implementation defaults, not a guaranteed parry window. Bundled candidates require place 8248288152/version 68598 and current combat classification. The script does not infer authoritative parry success or automatically optimize the lead based on success.

New attacks need usable markers and completed observations; first encounters are not protected. Nearby attacks may target somebody else. There is no invulnerability or universal parry guarantee.

Profiles and successful-report fingerprints persist in `clover_timings_v5_<place>.json` (the existing compatible cache format). Entries expire after seven days and are rejected on place-version changes. Unsupported file APIs leave session-only learning. Background audits run after startup and approximately every five minutes; they are bounded and do not stop auto parry.

## Automatic Discord reporting

[The public relay is live](https://clover-timing-relay.indigoamber16384.chatgpt.site). Every compatible installation automatically sends new or changed ready timing candidates to its `/report` endpoint. No private configuration or webhook token is needed in the client. The Discord webhook is stored as a server secret.

Reports contain place/version, animation ID, marker position, sample count and spread. They omit player names, Roblox user IDs, server IDs, chat, raw discovery/audit logs and video. The GUI displays this behavior. **Unload** stops future reports; pressing Auto parry OFF only stops F input.

The client sends at most six changed profiles per batch, at least 60 seconds apart, with persisted 10 ms fingerprints and delivery retry/backoff. The relay validates payloads, strips arbitrary text, disables Discord mentions and uses one anonymous global request counter to limit intake to 15 requests/minute. Failed reports remain pending client-side, subject to cache availability. Network/executor shutdowns can interrupt delivery. The hosting provider handles ordinary request metadata; no player-profile database is maintained.

Reports are untrusted candidates, not proof of successful parries or independent observers. They **do not automatically modify GitHub**. Maintainers review Discord evidence before updating `bundledProfiles` and its game-version scope. Rerun the loader to receive a release update.

## Verification

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
node relay/checks.mjs
```
