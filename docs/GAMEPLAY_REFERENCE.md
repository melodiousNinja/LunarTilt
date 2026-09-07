# Gameplay Reference — Canonical Ground Truth (2026-09-06)

Source: the owner's verbal spec + the close-up image + the reference video
(https://www.youtube.com/watch?v=ph4sbVJ4BnA) described as "exactly what we
are looking for, the only difference being the throwing happens from the
lower half".

This file is the SINGLE SOURCE OF TRUTH for how the table, the fans, and the
rules must behave. Every implementation decision defers to this.

## 1. Structure of one scoring unit ("Astrolabe" / fan)

From the close-up, in the owner's own words:

> "It needs to be an arc (like the bowl it was previously), but on top of
>  the bowl - so basically on top of the semi-circular wooden plank, there
>  is a triangular plank and on top of it there are wooden spikes of equal
>  length (so they form a slight slant, with the center spike at slightly
>  higher height than its neighbors)."

Therefore a scoring unit has THREE stacked layers:

1. **Semi-circular wooden base plank** ("the bowl") - a half-disc arc whose
   flat edge is the back and whose arc mouth faces the thrower.
2. **Triangular plank** on top of the bowl - a gentle gable/ridge, the
   centre line highest, laid across the arc width.
3. **Equal-length wooden spikes** standing on the triangular plank, spaced
   along the arc - because they sit on the gable, their TIPS form a slight
   slant with the CENTER SPIKE PROUDEST (tallest tip) and the outer spikes
   lower.

The ball passes BETWEEN two neighbouring spikes and nests on the plank
surface between them. That gap is the scoring "slot".

## 2. The throwing/the thrower (the one difference from the video)

In the video the throw happens the same way as the real sport; in our game
the throw happens from the LOWER HALF of the screen/table:

- The thrower stands at the bottom (player end, z=0).
- The ball is TOSSED in a parabolic arc from the tray/serve area
  (NOT pushed horizontally) up the 5-degree slope toward the far end.
- The serve lane alternates left lane → right lane per throw (single-screen
  duel: each player throws from their own lane).
- Aiming: the player may slide their serve position left/right before
  throwing, and sees a short aiming line + landing ring.
- The table rises AWAY from the thrower (the far end is higher).

## 3. Ball behaviour (physics truth, everything persists)

- A tossed ball lands ON or BEYOND a fan, then rolls BACK down the slope
  and drops into a gap FROM THE TOP (the up-slope side - the owner's
  explicit rule: "the ball should always enter from the top"). The gap's
  front wall (toward the thrower) stops it. OR:
  - clips a spike and DEFLECTS (real rigid-body bounce), OR
  - loses momentum short of the fans / on the marble and ROLLS BACK DOWN
    to the thrower (Returned-Ball rule: the ball comes back to hand and the
    turn is NOT spent).
- NOTHING teleports. NOTHING magically replaces anything. The full
  up-and-back path is always visible.
- On a 5-degree slope an open-felt ball never rests: it always rolls back.

## 4. Scored slots are PERMANENT (owner's explicit rule)

> "If a slot is booked, it can't be recaptured."

- A gap that holds a ball is booked FOREVER (glows the owner's colour).
- A later ball entering that gap simply BOUNCES off the sitting ball (the
  frozen body stays a solid, hittable obstacle) and rests against it as a
  grouping wall - it CANNOT take the slot, displace the ball, or re-score.
- There is NO displacement / take-a-socket rule in the mobile game.

## 5. Scoring (from the close-up, matching the owner)

- 3 fans: near (widest) = 1 point/slot, middle = 2 points/slot, far
  (narrowest) = 3 points/slot.
- 7 slits on the near fan, 5 on the middle ("C B A C B"), 3 on the far
  ("B A B") summed across the whole fan (the centre gap is A, outward B,
  then C).
- Chains/Grand Slam rules still apply via the official point table.

## 6. What the video adds that we must preserve "feel" of

- Broadcast-style table: glossy marble, warm wood, fans that read as real
  raised hardware, deep dark room.
- Satisfying contact: ball-on-ball clacks, fan-on-ball thock, capture
  settle, crowd/commentary energy (juice layer).
- Full path persistence: you ALWAYS see the ball climb, stall, drop or roll
  back - nothing vanishes, nothing freezes mid-board.