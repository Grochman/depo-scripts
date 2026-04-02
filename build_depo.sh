#!/bin/bash
set -e # Exit on error

# 1. Setup local directories
mkdir -p ~/local/src
mkdir -p ~/local/include
mkdir -p ~/local/lib
mkdir -p ~/repos

# --- DEPENDENCIES ---

# 2. Boost
cd ~/local/src
BOOST_VERSION="1.84.0"
BOOST_DIR="boost_${BOOST_VERSION//./_}"
if [ ! -d "$BOOST_DIR" ]; then
    echo "Downloading Boost..."
    wget -O boost.tar.gz https://downloads.sourceforge.net/project/boost/boost/${BOOST_VERSION}/${BOOST_DIR}.tar.gz
    tar -xzf boost.tar.gz
fi
cd "$BOOST_DIR"
./bootstrap.sh --prefix=$HOME/local
./b2 install -j$(nproc)

# 3. yaml-cpp
cd ~/local/src
if [ ! -d "yaml-cpp" ]; then git clone https://github.com/jbeder/yaml-cpp.git; fi
cd yaml-cpp
mkdir -p build && cd build
cmake -DCMAKE_INSTALL_PREFIX=$HOME/local -DYAML_CPP_BUILD_TESTS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON ..
make -j$(nproc) install

# 4. spdlog
cd ~/local/src
if [ ! -d "spdlog" ]; then git clone https://github.com/gabime/spdlog.git; fi
cd spdlog
mkdir -p build && cd build
cmake -DCMAKE_INSTALL_PREFIX=$HOME/local -DSPDLOG_BUILD_EXAMPLE=OFF ..
make -j$(nproc) install

# 5. Graphviz
cd ~/local/src
GRAPH_VER="12.0.0"
if [ ! -d "graphviz-${GRAPH_VER}" ]; then
    wget -O graphviz.tar.gz https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/${GRAPH_VER}/graphviz-${GRAPH_VER}.tar.gz
    tar -xzf graphviz.tar.gz
fi
cd "graphviz-${GRAPH_VER}"
./configure --prefix=$HOME/local --disable-swig --without-x --without-qt --without-gtk
make -j$(nproc) install

# 6. Fix NVIDIA Linker issue (Link system .so.1 to local .so)
if [ -f /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1 ]; then
    ln -sf /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1 ~/local/lib/libnvidia-ml.so
fi

# --- ENVIRONMENT SETUP ---

# Update Shell Environment (using a marker to avoid duplicate entries)
if ! grep -q "LOCAL_BUILD_PATHS" ~/.bashrc; then
cat << 'EOF' >> ~/.bashrc

# LOCAL_BUILD_PATHS
export PATH="$HOME/local/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/local/lib:$HOME/local/lib64:$LD_LIBRARY_PATH"
export CPATH="$HOME/local/include:$CPATH"
export LIBRARY_PATH="$HOME/local/lib:$HOME/local/lib64:$LIBRARY_PATH"
export PKG_CONFIG_PATH="$HOME/local/lib/pkgconfig:$HOME/local/lib64/pkgconfig:$PKG_CONFIG_PATH"
export CMAKE_PREFIX_PATH="$HOME/local:$CMAKE_PREFIX_PATH"
EOF
fi

# Apply to current session
export PATH="$HOME/local/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/local/lib:$HOME/local/lib64:$LD_LIBRARY_PATH"
export CPATH="$HOME/local/include:$CPATH"
export LIBRARY_PATH="$HOME/local/lib:$HOME/local/lib64:$LIBRARY_PATH"
export CMAKE_PREFIX_PATH="$HOME/local:$CMAKE_PREFIX_PATH"

# --- SPLIT REPO BUILD ---

# 7. Clone and Build SPLiT
cd ~/repos
if [ ! -d "split" ]; then
    git clone https://projects.task.gda.pl/akrz/split.git
fi
cd split
mkdir -p build && cd build
rm -f CMakeCache.txt # Clean start

# Run CMake pointing to local include/lib
cmake -DCMAKE_PREFIX_PATH=$HOME/local \
      -DCMAKE_EXE_LINKER_FLAGS="-L$HOME/local/lib -L/usr/lib/x86_64-linux-gnu/" \
      -DCMAKE_SHARED_LINKER_FLAGS="-L$HOME/local/lib -L/usr/lib/x86_64-linux-gnu/" ..

make -j$(nproc)

echo "------------------------------------------------"
echo "Build Complete! Binaries are in ~/repos/split/build/apps"

ln -s ~/repos/split/build/apps/DEPO/DEPO ~/local/bin/DEPO
echo "Make sure to run 'source ~/.bashrc' if you haven't already."
