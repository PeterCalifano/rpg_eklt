#!/bin/bash
# Simple script to run example and start web video server to see ros topic output from tracker node

set -eou pipefail
cd $HOME

if [ -d eklt_catkin_ws ]; then
    cd eklt_catkin_ws
else
    echo "eklt_catkin_ws folder not found in $HOME. Please run build_lib.sh first to create the catkin workspace."
    exit 1
fi

cd eklt_catkin_ws
source devel/setup.bash
cd src/eklt/

# Check existence of data/eklt_example
if [ ! -d data/eklt_example ]; then
    echo "Data not found. Please download and unzip the data files into data/eklt_example folder."
    exit 1
fi

# Start eklt example launch file
roslaunch eklt eklt.launch bag:=boxes_6dof.bag tracks_file_txt:=tracks.txt v:=1 & # Run in background

# Start web video server (topics will be available at http://localhost:8080/)
rosrun web_video_server web_video_server & # Runs on port 8080 by default
