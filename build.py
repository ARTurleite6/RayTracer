#! /usr/bin/python3

from optparse import OptionParser
import subprocess

build_odin_commands = {
    'release': "odin build src -vet -strict-style -collection:external=external -out:raytracer -show-timings -o:speed",
    'debug': "odin build src -vet -strict-style -collection:external=external -out:raytracer -show-timings -debug"
  }

def main():
    parser = OptionParser()
    parser.add_option("-b", "--build-mode", dest="build_mode", default="release", help="Build in release or debug mode")
    parser.add_option("-r", "--run", action="store_true",
                  dest="run", default=False,
                  help="Run program when finished building")

    (options, _) = parser.parse_args()

    command = build_odin_commands[options.build_mode]
    result = subprocess.run(command.split(), capture_output=True, text=True)

    print("Output:", result.stdout)
    print("Error:", result.stderr)

    if options.run:
        subprocess.run(["./raytracer"])

if __name__ == "__main__":
    main()
