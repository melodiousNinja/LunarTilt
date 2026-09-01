# LUNAR TILT - Game Design Document (v0.1)

## 1. Premise
A mobile physics duel on the viral table sport **Star Cluster Ball** (Xing Luo
Qiu, a.k.a. UNC Ball / YoTyan): flick phenolic balls up a 4.99-deg tilted oak
board to land them in star-shaped slots. One shot can change everything.

## 2. Design pillars
1. **Real physics, not scripted** - same input, same outcome, everywhere.
2. **Broadcast energy** - slow-mo slot drops, commentator stings, comeback drama
   (the Uncball live-match vibe from the YouTube scene).
3. **60-second learn, lifetime master.**

## 3. Core rules (v1, from the official rules research)
- 2 players, red vs black, 12 balls each.
- Flick from behind the Play Line. Score -> shoot again; miss -> turn passes.
- Points: Pos 1 = 1, Pos 2 = 2, Pos 3 = 5 (farthest = highest).
- **Chain**: adjacent same-color balls within one position: +1/+2/+5 per extra ball.
- **Grand Slam**: fill an entire position (all slots) with your color -> x2.
- **Gutter**: overshoot = ball removed for the round.
- **Knock-ins**: knocking an opponent ball into a slot scores FOR them, turn ends.
- Win: highest total when balls/time run out.

## 4. Modes
| Mode | Length | Purpose |
|---|---|---|
| Blitz | 3 min, 8 balls each | session hook, Shorts virality |
| Classic | 2 x 6-min rounds, official rules | the real-sport fantasy |
| Trick Shot | single-player chain puzzles | D0 retention, tutorial in disguise |
| Ranked 1v1 | wagered coins, escrowed, winner takes pot | the 8BP economy engine |
| Local | pass-and-play | zero-friction social play |

## 5. Controls
- Touch-drag slingshot: pull back = power, sideways = angle.
- Trajectory guide shrinks by league; gone in Diamond+.

## 6. Progression & leagues
Bronze -> Silver -> Gold -> Platinum -> Diamond -> Cosmic.
Cosmetics unlock per league; coin wagers scale with league.

## 7. Customization catalog (the cosmetic revenue engine)
- **Tables/surfaces**: Northern Red Oak (authentic), Walnut, Marble, Carbon,
  Neon Arcade, Galaxy.
- **Balls**: classic phenolic, glass marbles, chrome, Sun-vs-Moon celestial sets.
- **Rooms & lighting**: Warm Lounge, Stadium Broadcast, Neon Club, Minimal
  Daylight - dynamic lighting with real reflections on the balls.
- Trays, star plates, slot-drop FX, table frames.

## 8. Monetization
- Rewarded: 2x points event, extra ball, continue streak.
- Paced interstitials (never mid-shot).
- IAP: coin packs (wagers), Remove Ads, starter pack.
- Month 2+: season pass, leagues. **Never pay-to-win physics.**

## 9. Broadcast energy checklist (the Shorts machine)
- Slow-mo on Grand Slam and near-gutter saves.
- Crowd/commentator audio stings; chain-fire FX.
- Comeback banners: One shot can change everything.
- One-tap 9:16 replay clip export for YouTube Shorts / TikTok.

## 10. Analytics events (day-1)
session_start/end, shot_fired (power, angle), shot_result (points, chain, slam,
gutter), match_end (mode, margin), store_open, ad_watched, iap_purchase, rank_change.
