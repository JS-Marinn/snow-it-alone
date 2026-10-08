# Runtime architecture and refactor status

This document records code boundaries and contracts. The supplied `GAME_SPEC.md` remains the
source for player-facing design rules; this file describes how the implementation is separated.

## Runtime boundaries

- The level root composes the snow field, players, props, disposal machine, and HUD. It should
  wire systems together, not own tool physics or duplicate economy rules.
- `SnowField` owns the GPU simulation, its bounded operation queue, coarse gameplay mirror,
  and asynchronous operation results. Gameplay must never read the 512×512 texture directly.
- Player movement, aim/interaction, state reactions, tools, and first-person presentation are
  separate responsibilities. Until extraction is complete, `player_controller.gd` remains the
  compatibility façade. `player_aim_rules.gd` and `player_movement_model.gd` are extracted pure
  policy/math modules; the reticle/actions share aim predicates and the controller delegates
  friction/acceleration equations. `player_snowball_packer.gd` owns the asynchronous hand-harvest
  to ball/payload transaction; the controller delegates its aim sample and result callback.
- Test batteries belong in `tools/` or `tests/`, not in per-frame gameplay code. GPU tests run
  the real field; domain tests run headless without a scene or GPU.

## Snow operation contract

The GPU dispatch limit (`MAX_OPS`) is throughput, not queue capacity. Requests enter a FIFO
bounded queue and receive a stable ticket. The field drains at most `MAX_OPS` requests only when
an asynchronous result slot is available. A full queue returns ticket `0`, emits
`operation_rejected`, and leaves the field unchanged. Accepted work remains queued until it can
be dispatched.

- `dump_snow(...) -> bool` reports admission, not completion.
- `request_harvest(..., role) -> bool` reports admission; its measured result arrives through
  `op_volume_ready(role, owner, kg)` and `operation_completed(ticket, role, owner, actual_kg)`.
- `operation_mass_accounted(ticket, role, owner, removed_kg, added_kg, retained_kg)` reports the
  operation's measured source removal, field deposit, and shovel-retained share. The shovel shader
  normalizes its deposit pass to the measured source mass before the player credits the blade.
- `request_shovel()` and `carve_shovel()` return admission tickets; measured removed/deposited/
  retained mass arrives through the operation receipt. `carve()` is a compatibility guard: it
  still applies salt when requested, but refuses the former destructive radial clear.
- `clear_for_diagnostics()` is reserved for test/demo fixture setup and intentionally resets mass
  outside gameplay accounting. Gameplay removal must use a payload-producing `request_harvest()`
  or `request_shovel()` operation.
- The GPU statistics result has fixed-point quantization. Tests must state a tolerance for that
  representation and must not use a whole-field coarse-mirror integral as the accounting source.

## Mass accounting

`scripts/snow_mass_ledger.gd` is a scene-independent domain module. `SnowField` owns a runtime
instance: initial field mass is a source; measured harvest/shovel receipts move mass from the
field account into payload accounts; owner-tagged dumps transfer it back at queue admission; and
the disposal machine records the only delivery sink. The shovel uses a temporary operation escrow
so field deposit plus retained payload reconcile before the receipt is emitted. The ledger never
uses a coarse-mirror integral.

`register_payload_mass`, `transfer_payload_mass`, and `deliver_payload_mass` are the entity-boundary
APIs. Diagnostic spawns and unowned fixture dumps are recorded as explicit sources; the separate
`diagnostic_fixture` account marks intentional test-scene field resets. The Playground keeps its
receipt-reference ledger and also checks that the SnowField runtime ledger remains balanced with no
unassigned removal. Use `mass_ledger_snapshot()` for diagnostics.

## Migration order

1. Keep the queue and operation-result boundary stable while migrating callers.
2. Keep every new payload producer, transfer, return, and delivery on the SnowField ledger APIs;
   the machine is the only sink, and banks are scenery.
3. Continue extracting `PlayerMotor`, `AimService`, `PlayerState`, interactions, and remaining tool
   behaviors from the compatibility player controller. Hand-packing is already a separate
   `PlayerSnowballPacker` component.
4. Compose the shared HUD and reusable level services once; keep the Playground as a development
   fixture using the same production components.
5. Add local two-player coverage before any online transport implementation.

## Verification

GPU-free domain checks:

```powershell
& $godot --headless --path . --script res://tools/test_domain_core.gd
```

GPU-backed tests must be identified as such in `tools/run_batteries.ps1`. A missing verdict,
timeout, script error, or rejected operation without an explicit caller response is a failure.
