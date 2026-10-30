# Balance

## Method

`skee balance --runs 100` plays 100 seeded runs per skill level. Hand noise is
Gaussian:

| Skill | power σ | aim σ |
|-------|---------|-------|
| expert | 0.012 | 0.04 |
| regular | 0.025 | 0.08 |
| novice | 0.05 | 0.15 |

How these map to real thumbs is unknown until someone plays on hardware. My
guess is that "regular" is a practised player.

## Current numbers (100 runs each)

| | novice | regular | expert |
|-|--------|---------|--------|
| win rate | 2% | 14% | 21% |
| reached ante 8 | 6% | 30% | 33% |
| 50s / 40s | 14% / 28% | 29% / 41% | 43% / 24% |
| pockets | 0.5% | 1% | 13% |
| gutters | 4% | 3% | 14% |
| frames with a pair | 56% | 57% | 49% |
| frames with a triple | 12% | 25% | 33% |
| jackpots per run | 0.4 | 3.6 | 7.9 |
| close rounds (±15%) | 7% | 4% | 3% |

Score/target, regular player, p10 / p50 / p90:

```
ante 1: 1.95 / 3.93 / 7.25
ante 4: 1.44 / 3.19 / 7.17
ante 6: 1.02 / 2.21 / 4.49
ante 8: 0.84 / 1.90 / 3.64
```

## History

1. **Fixed symbols per hole.** The expert bot sent 77% of balls into the 50 and
   hit 46 triple-seven jackpots per run. The median score was 10x the target. It
   was boring before it was easy. Led to per-hole spinning reels.
2. **Spinning reels, pockets still funnelled.** Bots sent three quarters of their
   balls to the pockets. Led to the clean-flight pocket rule.
3. **Targets x2.** Experts died at ante 1 with a median of 2.9x. Round scores
   spanned 0.7x to 8x the target, because multiplicative lines make rounds
   bimodal. Led to flatter triples for the low symbols (cherry and lemon 3,
   bell 4, bar and clover 5) and a gentler start.
4. **The House paid nothing at all** for lines and was the top killer. Now it
   only blocks pairs.
5. Current targets per ante (warm-up; feature x1.5, boss x2):
   `300, 650, 1100, 1600, 2300, 3100, 4000, 5200`.

## Open problems

- **Close rounds are rare** (about 4%). Early antes are too easy: a regular
  player's median is 4-5x the target. Rounds end mostly as blowouts or
  failures. Balatro has the same shape early on, but the middle antes here
  should be tighter.
- **The Miser is the top killer for 50-heavy builds** (Heavy Hand, Seven Seas,
  the purged 50 reel). It is a fair counter, but it comes up as often as any
  other boss. Weighting boss draws by ante, or not repeating them, would help.
- **The expert bot dies at ante 1 about 7% of the time** because it gambles on
  pockets with a risk-neutral expected-value rule. A human would probably play
  safer when the target is in sight. The game is fine here; the bot is
  simplistic.
- **Economy:** regular players earn about 210 tickets per run and buy 27 items.
  There is probably too much money mid-run; nothing costs more than 8.
