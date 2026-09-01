# LUNAR TILT - Star Ball Duels

Mobile physics duel game inspired by the viral table sport **Star Cluster Ball**
(星落球 / 星罗球, a.k.a. UNC Ball / YoTyan). Flick phenolic balls up a
4.99-degree-tilted oak board and land them in star-shaped slots.

> Tagline: **Aim up. Gravity is your rival.**

- Engine: **Godot 4.7** + **Jolt Physics** (license-free, CI-friendly)
- Targets: Android (AAB) first, iOS via GitHub Actions macOS runner
- Status: **M0 - foundation + playable physics prototype**

## The real sport we simulate

| Spec | Value |
|---|---|
| Table | 2.2 m x 1.2 m Northern Red Oak, 4.99 deg tilt (the Lunar Tilt) |
| Balls | 24 phenolic resin balls - 12 red vs 12 black |
| Scoring | 3 Astrolabe Positions: Pos 1 = 1 pt, Pos 2 = 2 pts, Pos 3 = 5 pts |
| Bonuses | Chaining (+1/+2/+5 per extra ball), Grand Slam (x2) |
| Loss | Gutter = ball removed for the round |

## Run (desktop dev)

The engine binary lives in `tools/godot/` (gitignored):

```powershell
tools\godot\Godot_v4.7.2-stable_win64_console.exe --path . # console run
tools\godot\godot.exe --path .                            # editor
```

## Docs

- `docs/GDD.md` - full game design (modes, rules, economy, customization)
- `docs/PHYSICS_SPEC.md` - real-world constants, engine config, calibration gates
- `docs/GO_TO_MARKET.md` - store gates, ASO, Shorts playbook, monetization timeline

## Roadmap

| Milestone | Scope |
|---|---|
| M0 | Repo, docs, engine bootstrap, playable physics prototype |
| M1 | Full rules, turns, AI opponent, coins + save |
| M2 | Cosmetics, AdMob + IAP, replay clip export |
| M3 | Online 1v1 PvP (shot-record-playback), quick match |
| M4 | Android AAB + Play Console submission |
| M5 | iOS via GitHub Actions macOS runner |
