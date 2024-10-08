build:
  odin build src -vet -strict-style -out:raytracer -show-timings -o:speed

test:
  odin test tests -all-packages

run: build
  ./raytracer && open image.ppm
