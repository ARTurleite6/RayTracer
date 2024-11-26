#!/bin/bash

# build code

odin build src -out:bin/raytracer -strict-style -vet -debug --show-timings

# bulid the shaders
echo "Building shaders..."
"$HOME/VulkanSDK/1.3.296.0/macOS/bin/glslc" shaders/simple.vert -o shaders/vert.spv
"$HOME/VulkanSDK/1.3.296.0/macOS/bin/glslc" shaders/simple.frag -o shaders/frag.spv
