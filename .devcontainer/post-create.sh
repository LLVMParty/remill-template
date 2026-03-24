#!/bin/bash
# Configure CMake project
rm -rf build
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -G Ninja

# Remove kitware.list (signature rotation is problematic)
sudo rm -f /etc/apt/sources.list.d/kitware.list

# Install gdb
apt update
apt install -y gdb
