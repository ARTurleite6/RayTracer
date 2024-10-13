build-debug:
  odin build src -vet -strict-style -out:raytracer -show-timings -debug

build-release:
  odin build src -vet -strict-style -out:raytracer -show-timings -o:speed

test:
  odin test tests -all-packages

run: build-release
  ./raytracer
