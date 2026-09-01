# Physics Specification (v0.1)

Goal: balls react like real life. Constants from the physical YoTyan table,
calibrated by headless tests, never hand-tuned per device.

## Real-world constants
| Quantity | Value | Source |
|---|---|---|
| Table | 2.2 m x 1.2 m, tilt = 4.99 deg | YoTyan table spec |
| Surface | Northern red oak, lacquered | YoTyan |
| Balls | phenolic resin + mineral fillers, d = 40 mm, m = 45 g | YoTyan ball set |
| g | 9.81 m/s^2 | - |

## Simulated material model (final for M0; calibrate via tests/test_physics.gd)
| Parameter | Value |
|---|---|
| ball restitution (PhysicsMaterial.bounce) | 0.55 |
| ball friction (PhysicsMaterial.friction) | 0.49 (static hold >> tan 5 deg) |
| rolling resistance (angular_damp) | 0.05 (smooth phenolic roll) |
| linear damp | 0.02 |
| CCD | OFF (60 Hz fixed step, 5.7 cm max/frame; Jolt CCD sweeps from new bodies tunneled on spawn) |

## Engine
- Godot 4.7 + **Jolt Physics**, fixed 60 Hz tick.
- `surface_y_at()` is the EXACT rotated-box top-surface plane, verified by an
  in-engine raycast (a naive `cy + tan*z` formula was 30 mm off and spawned
  balls inside the board, which then tunneled through it).
- Fairness model: same-device replay (ghost shots) is deterministic; cross-device
  PvP uses **shot-record-playback** (shooter records compressed trajectory,
  opponent plays it back) so cross-device determinism is never required.

## Behavior model (matches the official sport rules)
- Balls decelerate climbing the slope via the real gravity component
  (g * sin 4.99 = 0.85 m/s^2) - nothing artificial.
- A ball entering a slot band at speed < `SLOT_CAPTURE_SPEED` (0.5 m/s) is
  captured and frozen (the pocket catches a settling ball). Faster balls roll
  over the band and continue up-table.
- Balls that never score ROLL BACK DOWN to the player end (the sport's
  "Returned Ball" rule) and drop into the front tray.

## Calibration gates (asserted by tests/test_physics.gd)
- 2.0 m/s from the Play Line (z=0.35): crosses Pos1/Pos2 and dies in the deep
  zone (final z ~ 1.7). Gate: z in [1.4, 2.4].
- Ball center never sinks below the lowest legal surface (tray floor at
  y=-0.13); the tunnel regression gate is min_y >= -0.135.
- A near-rest ball at a slot band is captured within 60 frames.
