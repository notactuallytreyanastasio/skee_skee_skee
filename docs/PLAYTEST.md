# Playtest: one run by hand

Seed 2026, through `skee play`. Decisions are mine. From the Feature Game on,
throws went through `--hand regular` so they wobble like a thumb would.

## Warm-up (target 300)

- Ball 1: aimed at the 50, which showed a cherry. In.
- The 10 also showed a cherry. I took it for a pair instead of the 50's seven.
  Then the 10 came up cherry again: **three cherries, 100 chips × 4 = 400**.
  Round cleared in one frame.
- Frame 2: two sevens in the 50. Then the 50 spun to a bell, but the right-hand
  100 pocket showed a seven. The pocket window is 2.5% of the power range, and
  the safe 50 would pay 150 × 4 = 600. I went for the pocket. **Jackpot: 200 ×
  11 = 2200.**

This was the moment the design was for. The reels changed the best target
between throws, and the decision was a real risk/reward call made with the
same physics I'd been using all round.

Overkill paid the maximum 5 tickets. At ante 1 a good player crushes the
target; see [BALANCE.md](BALANCE.md).

## Prize counter

Bought Purge on the 50 (its reel went from `seven bar seven bell cherry` to
`seven seven bell cherry`) and Ticket Muncher. Next visit: Seven Seas and
Heavy Hand. A sevens build on purpose. Reel editing felt meaningful because I
knew I could aim at the 50.

## Feature Game (target 450), with a regular hand

The wobble changed everything. Aiming at the 50 at power 0.62 came out as 0.57
(a 40) and later as aim −0.06 (also a 40). Two bells, then a third ball into
the 40 showing a seven: pair of bells, 360. Next frame 90. **450 / 450
exactly**, with a frame to spare. Tense, in a good way.

## Boss: Slick Lane (target 600)

I deliberately kept the old muscle memory (power 0.62). Under the
strengthened Slick Lane that went into the gutter, the gutter, then the 20.
**Failed, 200 / 600.**

## What changed because of this

1. **Slick Lane had no bite** under the original rule: the 50 moved by 0.03
   power. Strengthened. It now moves to 0.56.
2. **Swipe power was invisible.** With a bigger shift there was no way to
   recalibrate except by feel. Added the lane power gauge: a tick per recent
   throw at its power, coloured by result.
3. **Exact keyboard throws said nothing about fun.** Added `--hand`.

## Verdict so far

The core loop works. Reading the reels, choosing a target and then executing
it is fun, and the jackpot shot was a highlight. Physics repeatability makes
practice pay. Bosses that move the sweet spot are the "edge", and they need
the gauge to stay fair.

Not judged yet: how a real flick feels. That needs the hardware.
