#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cache_root="${XDG_CACHE_HOME:-${HOME:?HOME must be set}}/qubes-rpm-build"
store="$cache_root/nix"
result_link="$repo_dir/result"

mkdir -p "$store"

nix \
  --extra-experimental-features 'nix-command flakes' \
  --store "$store" \
  build "path:$repo_dir#rpm" \
  --out-link "$result_link" \
  --print-build-logs \
  --option sandbox false

result_name=$(basename -- "$(readlink -- "$result_link")")
rpm_path=$(find "$store/nix/store/$result_name" -maxdepth 1 -type f -name '*.rpm' -print -quit)
if [[ -z "$rpm_path" ]]; then
  echo "error: build completed but no RPM was found in $store/nix/store/$result_name" >&2
  exit 1
fi

cp -- "$rpm_path" "$repo_dir/"
echo "RPM: $repo_dir/$(basename -- "$rpm_path")"
