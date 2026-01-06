set -eou pipefail

REPO_DIR=$(pwd)
BUILD_DIR=$HOME

# Environment and system dependencies (for simplicity)
sudo apt update
sudo apt install -y \
    python3-catkin-tools \
    python3-vcstool \
    build-essential \
    python3-empy \
    liblapack-dev \
    libblas-dev \
    gfortran

# Remove previous catkin workspace if exists
if [ -d $BUILD_DIR/eklt_catkin_ws ]; then
    rm -rf $BUILD_DIR/eklt_catkin_ws
fi

# Make catkin workspace
mkdir -p $BUILD_DIR/eklt_catkin_ws/src

# Create symlink to eklt package for catkin
if [ -L $BUILD_DIR/eklt_catkin_ws/src/eklt ]; then
    rm $BUILD_DIR/eklt_catkin_ws/src/eklt
fi
ln -s /workspaces/rpg_eklt $BUILD_DIR/eklt_catkin_ws/src/eklt

cd $BUILD_DIR/eklt_catkin_ws
# Set conveniency path
export EKLT_CATKIN_WS=$(pwd)
echo "Workspace path set to $EKLT_CATKIN_WS"

# Notes: build using system python3
catkin config --init --mkdirs --extend /opt/ros/noetic --cmake-args -DCMAKE_BUILD_TYPE=Release -DPYTHON_EXECUTABLE=/usr/bin/python3

# Import src dependencies
# Check file dependencies.yaml exists
if [ ! -f $REPO_DIR/dependencies.yaml ]; then
    echo "Error: dependencies.yaml file not found in folder $REPO_DIR."
    exit 1
fi

cd $EKLT_CATKIN_WS/src
vcs-import < $REPO_DIR/dependencies.yaml

# Build catkin workspace
catkin build eklt
source $EKLT_CATKIN_WS/devel/setup.bash