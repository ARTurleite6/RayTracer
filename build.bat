odin build src -out:bin\raytracer.exe -strict-style -vet -debug --show-timings

:: build the shaders
echo "Building shaders..."
"C:\VulkanSDK\1.3.296.0\Bin\glslc" shaders/simple.vert -o shaders/vert.spv
"C:\VulkanSDK\1.3.296.0\Bin\glslc" shaders/simple.frag -o shaders/frag.spv
