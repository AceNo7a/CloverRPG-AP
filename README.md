# CloverRPG-AP

Experimental automatic F input using learned HitWindow positions. Starts **OFF**; passive learning starts ON. This is not an invulnerability script and does not guarantee successful parries.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/AceNo7a/CloverRPG-AP/main/clover_auto_parry.lua"))()
```

F7 toggles auto parry. F8 hides the panel. F6 toggles discovery recording. Start with **Test F**, then test one nearby mob. Keep Roblox focused; losing focus or respawning switches auto OFF.

## Learning

- Seven consistent marker candidates from the supplied capture are bundled for place `8248288152`, version `68598`. The live animation registry must still classify each as combat. Bundled candidates are disabled on other game versions.
- Two consistent, completed combat playbacks establish a local profile. The last five observations continuously update its median and spread. Ready local timings override bundled timings and guard presets.
- Executions, movement, reactions, unclassified animations, loops, incomplete playbacks, detected seeks and multiple HitWindows are excluded. A collecting, variable or multiple-marker local profile also blocks the old preset fallback until it qualifies again.
- Prediction uses the current playback speed and a configurable lead, initially 120 ms. This lead is a starting estimate. The script does **not** learn server success, automatically optimize that lead, or infer successful-parry cooldown resets.
- Unknown first encounters cannot be predicted before learning. Attacks without usable markers/classification are not covered. Nearby attacks can target somebody else; target intent and line of sight are not established.
- Local profiles save through the executor file API to `clover_timings_v5_<place>.json`. Cache entries expire after seven days and are rejected after a place-version change. Unsupported file APIs leave session-only learning.

Attempt logs explain cooldown, range, invalid playback and late-timing skips. An F attempt or a ready profile is **not** a confirmed parry.

## Discord reports and reviewed releases

The workflow is: learn locally → submit timing candidates to Discord → review candidates → update the bundled table in this repository. Reports do not modify GitHub automatically. Existing sessions need to rerun the loader to receive a changed public script.

Public reporting defaults OFF and the public endpoint is currently **unconfigured**. To enable reports from other users without publishing your webhook token, deploy the optional stateless relay in `relay/`, set `PUBLIC_REPORT_URL` in the Lua file to its HTTPS `/report` URL, then release the script. Users explicitly enable **Share timing candidates**. No timing database is required.

For private owner testing, put this JSON in the executor workspace as `clover_private_reporting.json`, replacing the placeholder locally:

```json
{"webhookUrl":"YOUR_PRIVATE_DISCORD_WEBHOOK_URL","enabled":true}
```

Never commit that file or put a Discord token in a public loader. This private configuration enables reporting only on the installation containing it. The supplied owner's installation has been configured separately; no secret is in this repository.

Reports contain place/version, animation ID, marker position, sample count and spread. They omit player names, Roblox user IDs, server IDs, chat, raw discovery logs and video. At most six changed ready profiles are sent per minute; successful submissions are deduplicated locally at 10 ms position precision. Failed deliveries remain pending, with backoff and Discord retry delays. There is no durable delivery guarantee if the executor exits before saving.

Client reports are untrusted candidates. They do not prove parryability, and a sample count does not prove independent users. Review classifications and repeatable combat evidence before adding them to `bundledProfiles`; update the corresponding place version deliberately. Do not promote collecting, excluded, variable or multiple-marker observations.

## Verification

On 2026-10-27: 178 Lua offline assertions and 15 relay assertions passed. Live Madium loaded v5, found all seven eligible bundled IDs, excluded tested execution/movement IDs, created the GUI and round-tripped the JSON cache. Live passive learning produced three ready guard profiles, which were saved and automatically reported. Two additional messages containing the seven imported timing summaries reached Discord with HTTP 200.

A live F test recorded one attempted press and released F, but no self animation was observed during that test. Successful automatic combat parries and PvP remain unverified. A subsequent alternative-backend comparison stopped because Roblox was not focused. Metadata inspection of CombatInfo/WeaponInfo did not establish a universal hit-timing table. No full game export or Studio reconstruction was made.

Offline tests from the repository root (Lua 5.1 and Node):

```text
lua tests/auto_parry_checks.lua clover_auto_parry.lua
lua tests/hitwindow_model_checks.lua clover_auto_parry.lua
lua tests/timing_audit_checks.lua clover_auto_parry.lua
lua tests/profile_support_checks.lua clover_auto_parry.lua
node relay/checks.mjs
```
