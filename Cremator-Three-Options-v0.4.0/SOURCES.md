# v0.4.0 — third option: native range + 3/3 + BurningHeavy

User authorized appending BurningHeavy while retaining Fire, and explicitly
accepted sharing the new effect with Flame Sentry and EXO-51. A and B retain
the v0.3.1 behaviors; C reuses A's particle archive byte for byte.

Evidence: `analysis/burning-live.json`, read-only current game.dll, SHA256
2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e.
Read the established damage-pointer map (548 slots, 547 valid 76-byte rows),
not a heap scan. The running old A option had 4/4 in row17; every other byte
matches the original recorded 3/3 row. Original statuses at offsets44/52/60
are type5/value3, type67/value2, type6/value4; offset68 is None/0.
Schema `DamageInfo`/`DamageStatusEffectInfo` gives four inline (u32,float) slots.

Beware stale enum lists: FileDiver's bundled enum says BurningHeavy31, whereas
the current napalm-pattern damage rows266 and390 use type32/value50, together
with Fire5/value100. Their damage/penetration/demolition/force signatures match
the named orbital/eagle napalm records in HelldiversData (element differs in
current data). This cross-reference supports type32 as current BurningHeavy;
we did not use the stale31. Current row6 additionally has direct4/4 and the
Fire5/value2 + type32/value2 pair. C takes the exact eight-byte32/2 payload
from row6, rather than copying an explosion's50 into a repeated spray hit.
The value is an application quantity, not a DPS declaration. The engine's
susceptibility/stacking/duration rules are unchanged and need gameplay testing.

C makes exactly one eight-byte write at row17+68, preserving all first68 bytes,
including direct3/3, elemental Fire, all three existing statuses and penetration.
Shutdown restores only its own field if the full modified row and pointer still
match. Occupied/different original records fail closed. Existing hash and code
signature guards remain. No new process writer, allocation, hook or scan.

The build checks the read-only evidence and source row payload. Tests cover the
third packaged policy, unchanged other bytes, occupied status rejection, delayed
loading, restoration, original callbacks and real Loader discovery for all three.
This option has not been deployed or tested against live enemies by the assistant.

Earlier release notes follow as historical records.

---

# v0.3.1 repack — 2026-09-25

User confirmed v0.3.0 native-range testing succeeded and requested two alternatives:
NativeRange + 4/4, and the previous lower-damage sentry effect (RangeOnly + 3/3).
No new gameplay tuning: native particle payload must be byte-identical to v0.3.0;
RangeOnly retains the v0.2.0 effect-only policy and unchanged 3/3 damage.
The old DamageOnly option is removed from the new selector. Same GUID/module.

Latest local log confirms v0.3.0 variant=native_range APPLIED at 2026-09-25
11:34:16, original effect + shared 4/4; shutdown restored damage with cleanup=true.
The user supplies the gameplay-success evidence, not the APPLIED line. Exact
35m range, all multiplayer roles, and elimination of every prior issue are not
independently established. RangeOnly's known close-range/visual limitations are
retained at the user's request. The repack itself is not deployed by the assistant.

Prior research and release notes follow as historical records.

---

# v0.3.0 original-particle range experiment — 2026-09-25

User feedback: v0.2.0 A (original flame + 4/4) successfully increases damage; B
(borrowed sentry/Lumberer flame + 3/3) has poor damage. The current package keeps
A and replaces B with an original-resource experiment, both using 4/4.

## Provenance and decoding

Extracted installed DSAR/DSAA slim archives with `analysis/slim_resources.py`,
based on FileDiver `stingray/slim_edition.go`. Original Cremator resource
`a4f17daba8ecd8e5`, type `a8193123526fad64` (particles), archive `df16f5c644edc2b1`.
32,360-byte v0x73 payload SHA256:
`a1cf46aa69383df2ef2804d51dc4448f80bb2348cb62ba1857b2e8af5f9d409f`.
No stream/GPU payload. Sentry/Lumberer payload has 12 systems, Cremator 14.
The upstream structural parser identifies forward positions 4/2.5/1/3m in the
first four Cremator systems versus 15/12/7/7m for sentry. This is a plausible
contributor to near misses; it is not proof of the entire low-DPS mechanism.

Structural reference: https://github.com/RaidingForPants/hd2-particle-modder
commit `a8193322d6b6e3a50ab460500341e7bc97e657fb` (`particle_modder.py`,
`imhex_pattern.txt`). The upstream parser leaves many initializer/simulator
fields opaque; the following semantics were additionally checked in the engine.

## Current-engine evidence, read only

Started the game with the user's authorization. CE tools were not exposed to
this conversation, so used the existing read-only Windows reader. Reads were
limited to the EXE constant/code/unwind sections (~27 MB total), no private heap
scan, debugger, injection or process writes. Saved module snapshots are local
analysis evidence and are NOT included in the release ZIP.
EXE SHA256 `f5fee03dcfdb2e553a4752c283590950ac13316b376d8196aa556ff0400d5f06`.

- Simulator dispatch: RVA 0x183c8d indexes table 0x16765b0.
- Opcode 0: RVA 0x2aeed0. It reads age/lifetime channel offsets from its operands,
  adds delta-time, clamps to the lifetime, and queues an expiry event.
  See `particle_engine/lifetime.txt`.
- Initializer opcode 1: table 0x167f6d0 -> RVA 0x3c9d70. It writes a random float
  interpolated between two operands into the selected channel. This confirms
  the min/max lifetime initializer by cross-reference to opcode 0, not by
  searching for guessed floating-point values. See `initializer-range.txt`.
- Initializer skip table 0x167f500 and simulator skip table 0x1676820 confirm
  bytecode widths. `particle_format.py` validates all section ends and counts
  for both extracted resources, including the disabled empty system.
- Simulator 28 (RVA 0x2af7b0) applies damping to the velocity vector. Its rate
  uses pow(clamp(1 - coefficient * graph / 60), delta_time * 60), with age/life
  driving the graph for these systems. See `velocity-scale.txt`.
- Simulator 32 (RVA 0x2b5330) processes the collision-result list, updates a
  per-particle channel, and can queue events. See `collision.txt`. This confirms
  that these systems retain collision processing, but does not establish equal
  damage contribution from every system or their multiplayer ownership.

## Experiment and limits

`native_particles.py` changes only 30 fixed-width fields across original systems
0,1,2,3,4,8,12,13: lifetime min/max x1.4, capacity ceil(original x1.4), and simulator
28 coefficient /1.4 where present. Exact changes/hashes are in
`build/particle-report.json` and the packaged `Source/particle-changes.json`.
Initial speed, spawn position, rate, burst counts, materials, collision settings,
child effects and other systems remain byte-identical. Lifetime/capacity scaling
is intended to extend travel without accelerating particles or reducing spatial
density near the weapon. This is an approximation: damping curves, turbulence,
collisions and capacity behavior mean 25 * 1.4 does NOT prove 35m effective range.
Capacity headroom may also change actual throughput if the original was capped.
Longer flight may change flame shape or vertical drift; gameplay testing needed.

B overrides the SAME original particle resource with an ordinary patch archive;
it does not swap to a foreign effect or need its foreign materials. The Lua addon
only changes shared damage 17 to 4/4. Existing GUID/module are preserved. A ships
no particle override. Both options require a full restart/deploy when switched.
The Lua build lock does not gate native asset loading; disable/recheck after game
updates. This version has not been deployed by the assistant. Offline checks do
not establish successful in-game loading, exact range, close DPS or client parity.

Historical v0.2.0 evidence follows unchanged.

---

# Cremator two-option package evidence (v0.2.0)

## Current build and preserved evidence

Supported EXE: 1.8.46015.0 / Steam build 25480438.
EXE SHA-256: f5fee03dcfdb2e553a4752c283590950ac13316b376d8196aa556ff0400d5f06.
game.dll SHA-256: 2e2c3b7c2500646dadd5f2b4c6e0504dbb7e7896139f64cddc0d1813c718f51e.

`analysis/live-links.json` captured the previous build's complete spray rows
and damage record. The subsequent read-only current-build adaptation in
`../QuasarAutoChargePrototype/analysis/build-25480438/tables.json` and
`scout.json` verifies the same full spray table fingerprint, damage record 17,
and native code anchor. The builder checks these evidence links before packaging.

Cremator resource 0x78a8185f63a70795 maps to spray row 21; Flame Sentry
0x820cc3bafe962858 to row 11; EXO-51 Lumberer 0x0736bee2d6328726 to row 7.
All use damage record 17, originally normal/durable 3/3 Fire. The user
accepted shared damage changes across all three weapons.

The original Cremator firing effect is 0xa4f17daba8ecd8e5. Sentry and Lumberer
share 0xe3d15622a42863c4. The effect reference is row offset 112. The spray
schema uses particle collision events when projectile_type is None.

## Variant behavior

DamageOnly retains the original Cremator flame and changes only the eight
normal/durable damage bytes to 4/4. It does not invoke the spray-table locator.
RangeOnly changes only the eight-byte Cremator firing effect reference. It
requires the original 3/3 damage record and observes it without writing it,
including on cleanup. Each option restores only its own unchanged modification.

Both use the same loader module and manager GUID as previous releases, and
are nested under one Arsenal SubOptions selector. The package layout follows
the established local Quasar two-option package. Only one option is selected.

The range locator checks allocation base + 0x2c38cfc, validated across two
launches in `analysis/locator-live.json` and `locator-validation.json`. It
queries memory metadata and reads bounded records, not memory blocks. It waits
up to ten minutes for loading and rejects mismatched/ambiguous data.

The writer temporarily changes protection of the containing data page for
its eight-byte effect write, restores page protection, and conditionally
restores the original bytes on shutdown. It does not change executable pages.

## Observed limitations

Prior combined versions reached APPLIED in local logs. User feedback reports
longer reach but reduced direct damage, close-range misses, and black boxes
for some players. These observations prompted separate options; v0.2.0 does
not claim to fix the reported effect-resource or collision problems. The
black-box dependency hypothesis and multiplayer influence remain unverified.

Arrowhead's known-issues page, checked 2026-09-25, lists incorrect Lumberer
flamethrower damage. This supports investigating the borrowed effect but does
not establish this mod's exact failure mechanism:
https://arrowhead.zendesk.com/hc/en-us/articles/15916898652700--HELLDIVERS-2-Known-Issues

A 0.5 m damage exclusion is not included. Neither the inspected spray schema
nor damage record exposes a simple minimum damage-distance switch.

## Verification

Tests execute each packaged Lua policy with snapshot-backed memory, verifying
exclusive writes, unchanged fields, delay/retry, conflict handling, restoration,
callback returns, and option packaging. A separate isolated-process test checks
the production locator and protected writer. These are offline checks; the
new two-option build still requires gameplay testing.
