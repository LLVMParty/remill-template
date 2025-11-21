#!/bin/bash
apt update
apt install -y gdb
rm -rf build
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
