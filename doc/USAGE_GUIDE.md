# EKLT Usage Guide

## ROS Interfaces

EKLT subscribes to two standard ROS topics:

| Topic (internal name) | Message type             | Remapped to (default) | Description                        |
|:---------------------:|:------------------------:|:---------------------:|:----------------------------------:|
| `events`              | `dvs_msgs/EventArray`    | `/dvs/events`         | Stream of asynchronous events      |
| `images`              | `sensor_msgs/Image`      | `/dvs/image_raw`      | Grayscale frames (MONO8 encoding)  |

These are configured in `launch/eklt.launch`:

```xml
<remap from="events" to="/dvs/events"/>
<remap from="images" to="/dvs/image_raw"/>
```

The sensor size is auto-detected from the first received message on either topic.

## Online vs Offline Usage

There is nothing rosbag-specific in the implementation. The rosbag example in the README is simply a convenient way to replay recorded data. Any ROS node that publishes the two topics above will work, whether it is a live camera driver, a simulator, or a custom data source.

The only timing assumption is that events and images arrive roughly in chronological order. Events are insertion-sorted into an internal buffer, and the tracker always uses the most recent frame before the current event time.

### Running with a rosbag (offline)

```bash
# Terminal 1: start EKLT
roslaunch eklt eklt.launch tracks_file_txt:=/tmp/tracks.txt v:=1

# Terminal 2: play the bag
rosbag play /path/to/recording.bag
```

Or pass the bag directly via the launch file:

```bash
roslaunch eklt eklt.launch bag:=/path/to/recording.bag tracks_file_txt:=/tmp/tracks.txt v:=1
```

### Running with a live DAVIS camera

The `rpg_dvs_ros` driver (included in `dependencies.yaml`) publishes `/dvs/events` and `/dvs/image_raw` by default, which match the default remappings in the launch file. No configuration changes are needed:

```bash
# Terminal 1: start the DAVIS driver
roslaunch dvs_ros_driver davis_ros_driver.launch

# Terminal 2: start EKLT
roslaunch eklt eklt.launch tracks_file_txt:=/tmp/tracks.txt v:=1
```

### Running with a DVXplorer

The `rpg_dvs_ros` package also includes a driver for iniVation DVXplorer cameras (via `libcaer`, which `build_lib.sh` already installs). The DVXplorer driver publishes on different default topic names, so you need to adjust the remappings:

```bash
# Terminal 1: start the DVXplorer driver
roslaunch dvxplorer_ros_driver dvxplorer_ros_driver.launch

# Terminal 2: start EKLT with remapped topics
roslaunch eklt eklt.launch tracks_file_txt:=/tmp/tracks.txt v:=1 \
  _events:=/dvxplorer/events _images:=/dvxplorer/image_raw
```

Alternatively, edit the remappings in `launch/eklt.launch`:

```xml
<remap from="events" to="/dvxplorer/events"/>
<remap from="images" to="/dvxplorer/image_raw"/>
```

**Important caveat:** unlike the DAVIS, the DVXplorer does **not** have a built-in frame (APS) sensor. EKLT requires both events and grayscale frames -- frames are used for Harris corner extraction and KLT bootstrapping, while events drive the asynchronous tracking between frames. If your DVXplorer model does not produce synthetic grayscale frames, you will need a separate standard camera co-located with the DVXplorer, publishing `sensor_msgs/Image` on the `images` topic.

### Running with a custom data source

Any node publishing the correct message types will work. At minimum you need:

1. A publisher of `dvs_msgs/EventArray` (events with x, y, timestamp, polarity)
2. A publisher of `sensor_msgs/Image` in MONO8 encoding (grayscale frames)

Remap the EKLT subscriptions to match your publisher topic names, either via the launch file or on the command line.

## Configuration

All tunable parameters are defined as gflags in `src/eklt_node.cpp` and loaded from `config/eklt.conf` via the `--flagfile` argument in the launch file. To see all available parameters:

```bash
rosrun eklt eklt_node --help
```

### Key parameters

| Parameter            | Default | Description                                                                 |
|:--------------------:|:-------:|:---------------------------------------------------------------------------:|
| `min_corners`        | 0       | Minimum tracked features before re-detection. 0 = no re-init (paper setting). Set ~50 for continuous tracking. |
| `max_corners`        | 100     | Maximum features to track.                                                  |
| `batch_size`         | 300     | Maximum event buffer size per patch.                                        |
| `patch_size`         | 25      | Side length of the patch around each corner.                                |
| `tracking_quality`   | 0.6     | Minimum quality (0-1) before a feature is discarded.                        |
| `bootstrap`          | `klt`   | Bootstrapping method: `klt` (uses two frames) or `events` (uses first event batch). |
| `displacement_px`    | 0.6     | Scaling factor for adaptive batch size (1/Cth in paper eq. 15).             |
| `first_image_t`      | -1      | Discard all images before this timestamp. -1 = disabled.                    |

### Launch file arguments

| Argument           | Default | Description                              |
|:------------------:|:-------:|:----------------------------------------:|
| `v`                | 0       | glog verbosity level (0=quiet, 1+=verbose) |
| `bag`              | (empty) | Path to rosbag for automatic playback    |
| `tracks_file_txt`  | (empty) | Output file path for feature tracks      |

## Output

### Feature tracks file

When `tracks_file_txt` is set, EKLT writes feature track updates with one row per update:

| Column     | Description                |
|:----------:|:--------------------------:|
| feature id | Integer ID of the feature  |
| timestamp  | ROS time in seconds        |
| x          | Subpixel x position        |
| y          | Subpixel y position        |

### Visualization

When `display_features` is enabled (default), EKLT publishes an annotated image to the `/feature_tracks` topic showing tracked features with optical flow arrows. Toggle display elements via flags:

- `display_features` -- show/hide feature tracks
- `display_feature_id` -- show/hide feature ID labels
- `display_feature_patches` -- show/hide patch overlays

A web-based viewer is also available via `ros-<distro>-web-video-server` (installed by `build_lib.sh`), accessible at `http://localhost:8080/`.
