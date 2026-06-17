#!/bin/bash
mkdir build && cd build

# Conda automatically sets $PREFIX to the installation directory
cmake .. \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DOPENMP=ON # Add other FMS-specific CMake flags here

make -j${CPU_COUNT}

# Run the repo's quick unit tests before installing
ctest --output-on-failure

make install
