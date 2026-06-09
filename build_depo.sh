#!/bin/bash
set -e # Exit on error

# 1. Setup local directories
mkdir -p ~/local/src
mkdir -p ~/local/include
mkdir -p ~/local/lib
mkdir -p ~/repos

# --- DEPENDENCIES ---

# 2. Boost
if [ ! -d "$HOME/local/include/boost" ]; then
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
else
    echo "Boost is already installed in ~/local/include/boost, skipping."
fi

# 3. yaml-cpp
if [ ! -d "$HOME/local/include/yaml-cpp" ]; then
    cd ~/local/src
    if [ ! -d "yaml-cpp" ]; then git clone https://github.com/jbeder/yaml-cpp.git; fi
    cd yaml-cpp
    mkdir -p build && cd build
    cmake -DCMAKE_INSTALL_PREFIX=$HOME/local -DYAML_CPP_BUILD_TESTS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON ..
    make -j$(nproc) install
else
    echo "yaml-cpp is already installed in ~/local/include/yaml-cpp, skipping."
fi

# 4. spdlog
if [ ! -d "$HOME/local/include/spdlog" ]; then
    cd ~/local/src
    if [ ! -d "spdlog" ]; then git clone https://github.com/gabime/spdlog.git; fi
    cd spdlog
    mkdir -p build && cd build
    cmake -DCMAKE_INSTALL_PREFIX=$HOME/local -DSPDLOG_BUILD_EXAMPLE=OFF ..
    make -j$(nproc) install
else
    echo "spdlog is already installed in ~/local/include/spdlog, skipping."
fi

# 5. Graphviz
if [ ! -f "$HOME/local/bin/dot" ]; then
    cd ~/local/src
    GRAPH_VER="12.0.0"
    if [ ! -d "graphviz-${GRAPH_VER}" ]; then
        wget -O graphviz.tar.gz https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/${GRAPH_VER}/graphviz-${GRAPH_VER}.tar.gz
        tar -xzf graphviz.tar.gz
    fi
    cd "graphviz-${GRAPH_VER}"
    ./configure --prefix=$HOME/local --disable-swig --without-x --without-qt --without-gtk
    make -j$(nproc) install
else
    echo "Graphviz is already installed in ~/local/bin/dot, skipping."
fi

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

# Apply compatibility patches:
#   - PCM: switch from opcm/pcm@202107 (Makefile-based) to intel/pcm@202604 (CMake-based)
#   - injection_2.cpp: add cuLaunchKernelEx callbacks for Ada Lovelace / modern PyTorch
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if git apply --check "$SCRIPT_DIR/split.patch" 2>/dev/null; then
    git apply "$SCRIPT_DIR/split.patch"
    echo "Applied split.patch successfully."
else
    echo "split.patch already applied or not applicable, skipping."
fi

# Build injection library for GPU kernel counting (must happen before DEPO is run)
cd ~/repos/split/profiling_injection
# Determine local CUDA paths dynamically
CUDA_PATH="/usr/local/cuda"
if [ ! -d "$CUDA_PATH" ]; then
    CUDA_PATH="/usr"
fi
CUDA_LIB_PATH="/usr/lib/x86_64-linux-gnu"
if [ ! -d "$CUDA_LIB_PATH" ]; then
    CUDA_LIB_PATH="$CUDA_PATH/lib64"
fi
make clean
make CUDA_INSTALL_PATH="$CUDA_PATH" LIB_PATH="$CUDA_LIB_PATH" NVCC_FLAGS="--std=c++11 -Xcompiler -fPIC -Xcompiler -include,cstdint"
cd ~/repos/split

mkdir -p build && cd build
rm -f CMakeCache.txt # Clean start

# Run CMake pointing to local include/lib
cmake -DCMAKE_PREFIX_PATH=$HOME/local \
      -DCMAKE_CXX_FLAGS="-include cstdint" \
      -DCMAKE_EXE_LINKER_FLAGS="-L$HOME/local/lib -L/usr/lib/x86_64-linux-gnu/" \
      -DCMAKE_SHARED_LINKER_FLAGS="-L$HOME/local/lib -L/usr/lib/x86_64-linux-gnu/" ..

make -j$(nproc)

echo "------------------------------------------------"
echo "Build Complete! Binaries are in ~/repos/split/build/apps"

# Set up local (non-NFS) kernels_count to avoid NFS I/O overhead from the injection library.
# The injection writes this file on every GPU kernel launch; using /tmp keeps it on fast local storage.
mkdir -p /tmp/depo_kernelcount
echo 0 > /tmp/depo_kernelcount/kernels_count
ln -sf /tmp/depo_kernelcount/kernels_count ~/repos/split/kernels_count
echo "kernels_count symlink: ~/repos/split/kernels_count -> /tmp/depo_kernelcount/kernels_count"

# Set up local directory containing host-compatible symlinks for CUPTI/NVPerf libraries
echo "Searching for libcupti.so and libnvperf_host.so on the host..."
CUPTI_PATH=$(find /usr/lib/x86_64-linux-gnu /usr/local/cuda* /usr/lib -name "libcupti.so*" 2>/dev/null | grep -v "nsight" | head -n 1)
NVPERF_PATH=$(find /usr/lib/x86_64-linux-gnu /usr/local/cuda* /usr/lib -name "libnvperf_host.so*" 2>/dev/null | grep -v "nsight" | head -n 1)

if [ -z "$CUPTI_PATH" ] || [ -z "$NVPERF_PATH" ]; then
    echo "WARNING: Could not find libcupti or libnvperf_host on the host."
else
    echo "Found CUPTI at: $CUPTI_PATH"
    echo "Found NVPerf at: $NVPERF_PATH"
    rm -rf ~/local/cuda-libs
    mkdir -p ~/local/cuda-libs
    # Copy files dereferencing symlinks to have real binaries instead of broken absolute symlinks inside docker
    cp -fL "$NVPERF_PATH" ~/local/cuda-libs/libnvperf_host.so
    cp -fL "$CUPTI_PATH" ~/local/cuda-libs/libcupti.so
    # Create relative symlinks within the folder to satisfy any loader linkage requirements
    (
        cd ~/local/cuda-libs
        ln -sf libcupti.so libcupti.so.11
        ln -sf libcupti.so libcupti.so.12
        ln -sf libcupti.so libcupti.so.13
    )
    echo "Copied and linked host CUDA libs in ~/local/cuda-libs"
fi

ln -sf ~/depo-scripts/run_depo.sh ~/local/bin/DEPO
echo "Make sure to run 'source ~/.bashrc' if you haven't already."
