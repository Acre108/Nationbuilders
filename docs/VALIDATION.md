# Milestone 1 validation

Validated on 11 October 2026 with the installed Godot **4.7.2 stable official (`ed1daf0bf`)**, Windows, NVIDIA RTX 3060 Ti / Forward+.

- Simulation: **76 checks, zero failures**. No scene or rendering is created by this runner.
- GPU/input suite: **30 checks, zero failures**. Actual viewport input covers the three-button HUD, build-menu placement, rejecting overlap, compact inspection, demolition, deposits, camera rotation, pausing and pipeline toggles.
- Starter house promotion: tick **237**, 23.7 simulated seconds.
- First produced bread: tick **359**, 35.9 simulated seconds; zero initial wheat/flour/bread.
- Continued chain: **25 bread stored** at the five-minute verification point after unlocking the chain, with the house still Tier 2 and satisfied.
- Conservation checks cover all six goods, including source reservations, in-flight cargo, input consumption, building demolition and recovery after road reconnection.
- Render assertions verify at most 32 world colours, exact 2×2 native-pixel blocks, and a depth/normal outline pass that measurably changes native pixels.

Reproduce with `tools/run_tests.ps1` and `tools/run_tests.ps1 -View`. The latter writes `artifacts/view-tested.png`, `artifacts/raw-toon.png`, and `artifacts/native-toon-outline.png`. A reviewed screenshot is retained as `docs/first-bread.png`.

The headless suite is additionally checked on official **4.3 stable (`77dcf97d8`)** for minimum-version compatibility. Linux execution is not claimed; this host has no WSL installation.

The first sandboxed runs emitted engine certificate-store and shader-cache access errors. The final installed-engine runs use normal engine access and complete without those errors. No game network services are used.
