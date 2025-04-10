#! /usr/bin/python3

from optparse import OptionParser
import subprocess
import platform

RED = '\033[91m'
RESET = '\033[0m'

os = platform.system()

shaders = [
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
    },
    {
        "src": "shaders/shadow.rmiss",
        "out": "shaders/shadow.spv",
    }
]

def print_command_result(result: subprocess.CompletedProcess[str]):
    if result.stdout:
        print(result.stdout)

    if result.stderr:
        print(f"{RED}Error: {result.stderr}{RESET}")

def get_build_command(build_mode):
    os = platform.system()
    file = ""
    if os == "Windows":
        file = "raytracer.exe"
    elif os == "Linux":
        file = "raytracer"
    else:
        raise RuntimeError(f"Unsupported os #{os}")

    command = "odin build src -vet -strict-style -collection:external=external -out:raytracer -show-timings -vet-cast -vet-using-param -disallow-do -warnings-as-errors"
    if build_mode == "debug":
        command += " -debug"
    else:
        command += " -o:speed"

    return command

def build_shaders():
    print("Building shaders...")
    for shader in shaders:
        result = subprocess.run(["glslc", "--target-env=vulkan1.2", shader["src"], "-o", shader["out"]], capture_output=True, text=True)
        print_command_result(result)

def main():
    parser = OptionParser()
    parser.add_option("-b", "--build-mode", dest="build_mode", default="debug", help="Build in release or debug mode")
    parser.add_option("-r", "--run", action="store_true",
                  dest="run", default=False,
                  help="Run program when finished building")

    (options, _) = parser.parse_args()

    build_shaders()

    command = get_build_command(options.build_mode)
    print("Building raytracer...")
    print(command)
    result = subprocess.run(command.split(), capture_output=True, text=True)
    print_command_result(result)

    if options.run:
        subprocess.run(["./raytracer"])

if __name__ == "__main__":
    main()
