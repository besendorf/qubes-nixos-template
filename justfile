# run linting checks against repo
lint:
  nix flake check --all-systems

alias check := lint

# build template rpm via nix flake
build:
  nix build .#rpm
  # built rpm available at:
  find result/ -type f -iname '*.rpm'

alias rpm := build
