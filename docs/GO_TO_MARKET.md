# Go-To-Market (v0.1)

## Launch gates (external clocks - start them NOW)
1. **Google Play**: personal accounts created after Nov 13 2023 require a closed
   test with **12 testers opted-in for 14 days** before production access.
   The build will be ready long before this gate; recruit testers this week.
2. **Apple**: $99/yr account; iOS builds via GitHub Actions macOS runner
   (Windows machines cannot produce iOS builds natively).
3. Networking: PUN2 free tier = 20 CCU (deferred). Our netcode is
   transport-agnostic: ENet direct/LAN first, WebSocket relay next.

## Accounts checklist (owner: Lalit)
- [ ] Play Console account - note its creation date (gate #1 applies or not)
- [ ] Apple Developer account
- [ ] GitHub: create empty repo `lunar-tilt`, then:
      git remote add origin https://github.com/<you>/lunar-tilt.git
      git push -u origin main
- [ ] AdMob account (placeholder IDs until submission)
- [ ] Recruit 12 Android testers (Google accounts)

## ASO
Title: **Lunar Tilt - Star Ball Duels**. Keywords: star cluster ball, unc ball,
xing luo qiu, tilt pool, slope billiards, physics duel. The brand is ownable
(IP-safe); the sport name lives in keywords to catch existing search demand.

## Shorts playbook (the growth engine)
1. In-game 9:16 replay export with slow-mo and streak captions.
2. Formats: ASMR slot-drops; one-shot comebacks; physics explainers; AI fails.
3. Seed the channels where the sport already lives (Uncball, match broadcasts) -
   engage as the game, never spam.
4. Cadence: 1 clip/day during launch month.

## Market order
Tier 1: India (volume + home advantage), SEA/HK/TW (sport awareness).
Tier 2: US early adopters, Brazil, MENA. China: later (license/ISBN required).

## Monetization rollout
- Day 1: rewarded + paced interstitials, Remove Ads IAP, starter pack.
- Week 2-4: coin wagers + cosmetic shop.
- Month 2+: season pass, leagues.
- UA spend gates: D1 >= 40%, D7 >= 15%, crash-free >= 99.5%.

## Risk register
| Risk | Mitigation |
|---|---|
| Trend fades | ship M4 in days, weekly live-ops content |
| IP (YoTyan trademarks on physical product) | ownable brand, sport name as keyword only, no trade-dress copying |
| Low Western awareness | fully self-explanatory game, Trick Shot teaches |
| Solo bandwidth | AI-driven pipeline + CI builds |
