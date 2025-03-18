#! /usr/bin/python3

from optparse import OptionParser
import subprocess

build_odin_commands = {
    'release': "odin build src -vet -strict-style -collection:external=external -out:raytracer -show-timings -o:speed",
    'debug': "odin build src -vet -strict-style -collection:external=external -out:raytracer -show-timings -debug"
  }

shaders = [
    {
        "src": "shaders/simple.vert",
        "out": "shaders/vert.spv",
    },
    {
        "src": "shaders/simple.frag",
        "out": "shaders/frag.spv",
    },
    {
        "src": "shaders/simple.rgen",
        "out": "shaders/rgen.spv",
    },
    {
        "src": "shaders/simple.rmiss",
        "out": "shaders/rmiss.spv",
    },
    {
        "src": "shaders/simple.rchit",
        "out": "shaders/rchit.spv",
    }
]

def build_shaders():
    print("Building shaders...")
    for shader in shaders:
        result = subprocess.run(["glslc", "--target-env=vulkan1.2", shader["src"], "-o", shader["out"]], capture_output=True, text=True)
        print("Output:", result.stdout)
        print("Error:", result.stderr)

def main():
    parser = OptionParser()
    parser.add_option("-b", "--build-mode", dest="build_mode", default="debug", help="Build in release or debug mode")
    parser.add_option("-r", "--run", action="store_true",
                  dest="run", default=False,
                  help="Run program when finished building")

    (options, _) = parser.parse_args()

    build_shaders()

    command = build_odin_commands[options.build_mode]
    print("Building raytracer...")
    result = subprocess.run(command.split(), capture_output=True, text=True)

    print("Output:", result.stdout)
    print("Error:", result.stderr)

    if options.run:
        subprocess.run(["./raytracer"])

if __name__ == "__main__":
    main()
