# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EKLT (Event-based KLT) is a ROS (catkin) C++11 package that performs asynchronous photometric feature tracking using events from a DVS (Dynamic Vision Sensor) event camera and standard image frames. It implements the IJCV 2019 paper by Gehrig et al. Features are detected on frames (Harris corners via OpenCV `goodFeaturesToTrack`) and tracked asynchronously using events between frames, producing high-temporal-resolution feature tracks.

## Build Commands

This is a catkin package. It is **not** built in-tree — it must live inside a catkin workspace.

### Full setup (devcontainer or fresh environment)
```bash
# Installs system deps, creates catkin workspace at ~/eklt_catkin_ws, clones dependencies, builds
./build_lib.sh
```

### Incremental build (after workspace exists)
```bash
cd ~/eklt_catkin_ws
catkin build eklt
source devel/setup.bash
```

### Run the example
```bash
# Requires data in data/eklt_example/ and a built workspace
./test_example.sh
```

### Run the tracker directly
```bash
roslaunch eklt eklt.launch tracks_file_txt:=/tmp/tracks.txt v:=1
# In another terminal: rosbag play <bag_file>
```

### View configurable parameters
```bash
rosrun eklt eklt_node --help
```

## Architecture

The package has four core components, all under the `tracker` and `nlls` namespaces:

- **`eklt_node.cpp`** — Entry point. Defines all gflags parameters, creates Tracker and Viewer, spins ROS. All tunable parameters are gflags defined here (not ROS params), overridden via `config/eklt.conf` flagfile.

- **`Tracker`** (`tracker.h`/`tracker.cpp`) — Main processing class. Subscribes to `/dvs/events` and `/dvs/image_raw`. Detects Harris corners on frames, assigns each a `Patch`, then processes events in a dedicated thread (`processEvents`). Handles bootstrapping (KLT or event-based), adaptive batch sizing (paper eq. 15), and feature lifecycle (init, track, discard, replace).

- **`Patch`** (`patch.h`) — Data structure for a tracked feature. Holds the event buffer (deque), affine warp matrix, optical flow angle, tracking quality, and the event frame computation (`getEventFramesAndReset`, paper eq. 2). Contains all per-feature state.

- **`Optimizer`** (`optimizer.h`/`optimizer.cpp`) — Uses Ceres solver to optimize the photometric cost function (paper eq. 7) — jointly estimates warp and optical flow direction for each patch against precomputed log-image gradients.

- **`Viewer`** (`viewer.h`/`viewer.cpp`) — Publishes visualization to `/feature_tracks` topic. Controlled by `display_features`, `display_feature_id`, `display_feature_patches` flags.

- **`error.h`** — Defines the Ceres cost functor (ECC-based photometric error).

- **`types.h`** — Type aliases (`ImageBuffer`, `EventBuffer`, `Patches`, `OptimizerData`).

### Key data flow
Events arrive via ROS callback → insertion-sorted into shared deque → worker thread pops events → dispatches to matching Patches → when a Patch accumulates enough events (adaptive batch size) → Optimizer solves for updated warp/flow → Patch center updated → Viewer renders.

## Configuration

- **`config/eklt.conf`** — gflags flagfile loaded by the launch file. Key parameter: `min_corners=0` (paper setting, no re-initialization after first frame; set to ~50 for continuous tracking).
- **`launch/eklt.launch`** — ROS launch file. Supports args: `bag`, `v` (glog verbosity), `tracks_file_txt`.

## Dependencies

Managed via `dependencies.yaml` (consumed by `vcs-import`): catkin_simple, ceres_catkin, eigen_catkin, glog_catkin, gflags_catkin, rpg_dvs_ros (for dvs_msgs), suitesparse, eigen_checks.

## Devcontainer

The `.devcontainer/` setup supports configurable base images, optional CUDA, and ROS 1/2 installation. Use `configure_devcontainer.sh` to reconfigure (supports `--ros noetic`, `--cuda`, `--base ubuntu-20.04`, etc.). The default target is Ubuntu 20.04 with ROS noetic.

## Tests

Test infrastructure uses Catch2 (see `tests/CMakeLists.txt`). Template fixtures and tests are in `tests/template_fixtures/` and `tests/template_test/`.
