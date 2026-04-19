# EKLT ROS2 Porting Plan

## Summary

Implement the ROS2 migration in three gated stages, with tests added and run at the end of each stage before moving on.

Defaults chosen for the final design:

- [ ] Final ROS2 event interface: `event_camera_msgs/msg/EventPacket`
- [ ] Final ROS2 config surface: native ROS2 parameters, not `gflags`
- [ ] Final port shape: clean ROS2-only cutover in this repo, no dual ROS1/ROS2 build
- [ ] Stage-2 hybrid path: ROS2-native raytracer source plus a small ROS1 relay for the existing EKLT node

Public interface targets:

- [ ] Stage 2 ROS2 topics: `/eklt/events` as `event_camera_msgs/msg/EventPacket`, `/eklt/image_raw` as `sensor_msgs/msg/Image` in `mono8`
- [ ] Stage 2 ROS1 relay output: `/dvs/events` as `dvs_msgs/EventArray`, `/dvs/image_raw` as `sensor_msgs/Image`
- [ ] Stage 3 EKLT ROS2 node: keep internal subscription names `events` and `images`, with ROS2 launch remaps defaulting to `/eklt/events` and `/eklt/image_raw`
- [ ] Stage 3 config: preserve current parameter names where practical, but expose them as declared ROS2 params and YAML/launch config

## Stage 1: Catch2 and regression seams

- [ ] Treat Catch2 as partially present already: reuse the existing `cmake/HandleCatch2.cmake`, `cmake_utils.cmake`, and test scaffolding, and wire them into the top-level build with the smallest possible CMake delta.
- [ ] Copy only the minimal top-level patterns needed from the template project: `ENABLE_TESTS`, `ENABLE_FETCH_CATCH2`, inclusion of Catch2 helpers, and `add_subdirectory(tests)` when tests are enabled.
- [ ] Remove the template placeholder tests and replace them with focused regression tests for logic that will be touched later.
- [ ] Keep test seams minimal and local. Only extract pure helpers where current behavior is otherwise untestable without a ROS runtime.

Regression coverage to add now:

- [ ] `Patch` event-buffer behavior: insertion order preservation inside the patch buffer, batch-size clipping, timestamp update after `getEventFramesAndReset()`, and deterministic event-frame accumulation for a small hand-checked event set.
- [ ] Event ordering helper: the current sorted event insertion behavior used before processing should be pinned with out-of-order and equal-timestamp cases.
- [ ] Image selection helper: the “latest frame before current event time” behavior should be pinned so ROS2 callback refactors do not change it.

Acceptance for stage 1:

- [ ] Catkin build still succeeds.
- [ ] Catch2 tests build and pass under `ctest`.
- [ ] No algorithm or runtime ROS behavior changes beyond testability seams.

## Stage 2: ROS2 raytracer source and ROS1 relay

Stage 2 is split into substeps so the generic bridge lands first, then the concrete two-body demo is added on top without bloating the base design.

Build stage 2 as a small installable Python package inside this repo, not as one monolithic script.

Python package layout:

- [ ] `python/eklt_bridge/raytracer/`: wrapper around `spectral_rt_py`, scene setup, frame stepping, event stepping, and deterministic sample-scene helpers
- [ ] `python/eklt_bridge/messages/`: conversion helpers for raytracer events and rendered frames
- [ ] `python/eklt_bridge/ros2_source/`: ROS2 publisher node and CLI entrypoint
- [ ] `python/eklt_bridge/ros1_relay/`: ROS1 relay node and CLI entrypoint
- [ ] `python/eklt_bridge/config/`: typed config loading for paths, timing, frame size, topic names, and simulator settings

Stage-2 substeps:

- [ ] Stage 2A: land the reusable Python package, message converters, and config layer with unit tests only.
- [ ] Stage 2B: land the generic ROS2 source and ROS1 relay path for a minimal synthetic scene and verify EKLT can consume it.
- [ ] Stage 2C: add the full Didymos-Dimorphos example on top of the generic source path, reusing the existing raytracer two-body scene contract.
- [ ] Stage 2D: add one command or launch-driven end-to-end demo that starts the full chain and writes EKLT tracks for the Didymos example.

Stage-2 data flow:

- [ ] ROS2 source node uses `spectral_rt_py` from the user-provided build path or conda env.
- [ ] It renders grayscale frames and event batches from the raytracer.
- [ ] It publishes `/eklt/events` as `event_camera_msgs/msg/EventPacket`.
- [ ] It publishes `/eklt/image_raw` as `sensor_msgs/msg/Image`.
- [ ] Standard `ros1_bridge` is used only for shared message types across ROS1 and ROS2.
- [ ] A small ROS1 relay node subscribes to bridged ROS1 `event_camera_msgs/EventPacket` and ROS1 `sensor_msgs/Image`, converts the event packets to `dvs_msgs/EventArray`, and republishes to the current EKLT ROS1 topics.

Stage-2 environment contract:

- [ ] The ROS2 source runs inside a conda environment where `spectral_rt_py` is importable.
- [ ] The source accepts a `spectral_raytracer_root` path for resolving non-package assets such as example meshes and manifests.
- [ ] The source does not depend on local developer shell state beyond the selected conda env and explicit config paths.
- [ ] If the conda package alone is insufficient to resolve the Didymos assets, the example requires `spectral_raytracer_root` pointing to a checkout that contains the fixture manifest and OBJ files.

Encoding and conversion decisions:

- [ ] Stage 2 writes `EventPacket` using the documented `mono` encoding because it is simple, explicit, and easy to produce deterministically from simulated `(x, y, t, polarity)` events in Python.
- [ ] The ROS1 relay decodes only the `mono` packets produced by this source.
- [ ] Images are published as `mono8` with preserved timestamps shared with the event timeline.

CLI entrypoints to provide:

- [ ] `eklt-raytracer-source`
- [ ] `eklt-ros1-relay`
- [ ] `eklt-run-didymos-demo`

Stage-2 scope limits:

- [ ] No attempt to make the ROS1 relay generic for arbitrary event-camera encodings.
- [ ] No devcontainer overhaul unless a missing dependency blocks reproducible testing.
- [ ] No changes to EKLT’s tracking algorithm.

### Stage 2C: Didymos-Dimorphos full example

Use the existing two-body preview assets and motion model from the raytracer tree as the concrete stage-2 example.

Didymos example asset contract:

- [ ] Resolve the default manifest from `matlab/tests/fixtures/didymos_dimorphos/didymos_dimorphos_preview_manifest.json` under `spectral_raytracer_root`.
- [ ] Resolve the primary mesh from the manifest entry for `didymos_primary.obj`.
- [ ] Resolve the secondary mesh from the manifest entry for `dimorphos_secondary.obj`.
- [ ] Use the manifest quick-demo defaults as the initial example timing model unless explicitly overridden.

Didymos example motion model:

- [ ] Load Didymos as the primary body at the origin.
- [ ] Load Dimorphos as the secondary body using the preview fixture placement and separate rigid-body state.
- [ ] Apply primary spin about world `+Z`.
- [ ] Apply Dimorphos orbit and spin using the accelerated preview defaults already documented by the raytracer fixtures.
- [ ] Preserve a deterministic start phase so the example repeatedly sweeps through a visually interesting eclipse or shadow transition.

Didymos example default scene parameters:

- [ ] Default to the accelerated preview regime from the manifest: Didymos spin period about `11.3744 s`, Dimorphos orbit or spin period `60 s`.
- [ ] Default to an explicit directional Sun, matching the current quick-demo convention.
- [ ] Default to an explicit camera direction and camera-distance scale derived from the existing raytracer demo.
- [ ] Default to `mono8` rendered frames and event packets generated from the raytracer event path for the same simulated timeline.

Didymos example code shape:

- [ ] Keep the generic source node scene-agnostic.
- [ ] Add a small scene adapter module for the Didymos example rather than hard-coding Didymos logic into the generic publisher.
- [ ] Add a typed example config file for the Didymos scene, including asset paths, motion defaults, frame size, event settings, ROS topic names, and EKLT output path.
- [ ] Add one thin demo runner that wires together the scene adapter, ROS2 source, `ros1_bridge`, ROS1 relay, and ROS1 EKLT launch.

Didymos demo runtime flow:

- [ ] Activate the conda env containing `spectral_rt_py`.
- [ ] Start the ROS1 core and ROS1 EKLT node.
- [ ] Start `ros1_bridge` for `sensor_msgs/Image` and `event_camera_msgs/EventPacket`.
- [ ] Start the ROS2 source configured with the Didymos manifest, primary and secondary meshes, accelerated body motion, and event settings.
- [ ] Start the ROS1 relay to convert bridged `EventPacket` traffic into `dvs_msgs/EventArray`.
- [ ] Run the sequence long enough to cover at least one meaningful Dimorphos motion segment and produce non-empty EKLT tracks.

Acceptance for stage 2:

- [ ] Python unit tests pass for packet packing, packet unpacking, timestamp mapping, frame conversion, and config parsing.
- [ ] End-to-end smoke test passes: raytracer source -> `ros1_bridge` -> ROS1 relay -> current ROS1 EKLT.
- [ ] Smoke-test success criterion: EKLT receives frames and events, runs without waiting forever for the first image, and produces a non-empty tracks output on the deterministic sample run.
- [ ] Didymos example smoke test passes with the full two-body scene, including Dimorphos motion, and writes a non-empty EKLT tracks file.
- [ ] Didymos example is runnable through one documented command path rather than a manual multi-terminal recipe only.

## Stage 3: clean ROS2 port of EKLT interfaces

Port the package to ROS2 as a clean cutover, keeping the tracking algorithm unchanged.

Build and package changes:

- [ ] Replace catkin build plumbing with `ament_cmake`.
- [ ] Keep the package name `eklt`.
- [ ] Keep the node executable name `eklt_node`.
- [ ] Move launch to ROS2 Python launch files.
- [ ] Drop ROS1-only launch conveniences such as in-launch `rosbag play`; ROS2 bag playback stays external.

ROS2 interface changes:

- [ ] Replace `ros::NodeHandle`, `ros::Subscriber`, `ros::Time`, `ros::Rate`, and ROS1 spin/thread patterns with ROS2 equivalents.
- [ ] Replace `dvs_msgs/EventArray` ingestion with `event_camera_msgs/msg/EventPacket`.
- [ ] Use `event_camera_codecs` in C++ so the ROS2 node decodes packets through the standard codec layer rather than project-local packet parsing.
- [ ] Keep `sensor_msgs/msg/Image` input unchanged conceptually, using ROS2 `cv_bridge`.

Configuration changes:

- [ ] Replace `gflags` at the node boundary with declared ROS2 parameters.
- [ ] Convert `config/eklt.conf` into a ROS2 YAML params file with matching names where practical.
- [ ] Keep parameter meaning stable unless ROS2 integration requires a rename for clarity.
- [ ] Preserve topic remap flexibility through launch, not custom wrapper code.

Code-structure guidance:

- [ ] Keep core tracker, patch, optimizer, and viewer logic as close as possible to the current implementation.
- [ ] Isolate ROS2 transport, time, and parameter changes at the node, subscriber, and buffer boundary.
- [ ] Prefer a thin translation layer from decoded ROS2 events into the existing internal event representation before touching core tracking code.

Stage-3 useful cleanup that is in scope:

- [ ] Replace ROS1 time aliases in shared types with a project-local time alias or direct ROS2 time usage where needed.
- [ ] Normalize callback and worker-thread ownership so the ROS2 node is explicit about lifecycle and shutdown.
- [ ] Keep the stage-2 relay package as an optional hybrid-validation tool only if it stays small; it must not constrain the ROS2 node design.

Acceptance for stage 3:

- [ ] ROS2 build succeeds with `colcon`.
- [ ] Existing Catch2 regression tests still pass after the transport refactor.
- [ ] New ROS2-side tests pass for parameter loading, `EventPacket` decode to internal events, image callback ingestion, and event ordering/buffering invariants.
- [ ] End-to-end ROS2 smoke test passes: raytracer source -> ROS2 EKLT, with non-empty tracks output on the deterministic sample run.

## Test plan

Stage 1:

- [ ] Run `ctest` for the new Catch2 suite.
- [ ] Gate stage 2 work on green unit tests.

Stage 2:

- [ ] Add `pytest` for the Python package.
- [ ] Add one scripted hybrid smoke test that launches ROS1 EKLT, ROS2 raytracer source, `ros1_bridge`, and the ROS1 relay.
- [ ] Check for non-empty tracks output and monotonic timestamps.
- [ ] Add one Didymos-specific integration test or smoke script that uses the fixture manifest, primary and secondary OBJ files, accelerated motion defaults, and the full ROS bridge chain.
- [ ] Check that the Didymos demo publishes both frames and events over a shared simulated timeline and that EKLT produces non-empty tracks.
- [ ] Keep the Didymos example deterministic enough that repeated runs have stable event counts and broadly stable track-output size.

Stage 3:

- [ ] Keep stage-1 Catch2 tests as regression guards.
- [ ] Add ROS2-focused unit tests and launch or integration smoke tests.
- [ ] Reuse the same deterministic raytracer scenario as stage 2 so behavior is comparable across the cutover.
- [ ] Compare stage-2 and stage-3 outputs at least at the level of non-empty tracks, monotonic timestamps, and broadly comparable track count or runtime completion on the same sample run.

## Assumptions and defaults

- [ ] Stage 2 runs inside a conda environment where `spectral_raytracer` and `spectral_rt_py` are available to Python.
- [ ] The user supplies `spectral_raytracer_root` when example assets such as the Didymos manifest and OBJ files are not available from the installed package alone.
- [ ] A working mixed ROS1/ROS2 environment already exists for stage 2, so repo changes will not try to solve general multi-distro environment management.
- [ ] `event_camera_msgs` and `event_camera_codecs` are acceptable new dependencies for the ROS2 target.
- [ ] The final repo is allowed to stop being catkin-first once stage 3 lands.
- [ ] Backward-compatibility code is kept only where it is directly useful for validation or migration; no dual-build compatibility layer is planned.
