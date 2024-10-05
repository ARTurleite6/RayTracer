build:
  odin build src -vet -strict-style -out:raytracer -show-timings -o:speed

run: build
  ./raytracer && open image.ppm
