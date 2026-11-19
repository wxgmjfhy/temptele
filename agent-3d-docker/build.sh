#!/usr/bin/env bash
set -euo pipefail

bundle_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
docker_cli=${DOCKER:-docker}
base_tag=agent3d-validation:ubuntu-24.04-base-20261119
base_identity='linux/amd64 sha256:7da97f743f397971f35dd21cd2d19a7da070a150e0cfa3eda559e71891ec7533'
if [ "$#" -eq 0 ]; then
    set -- all godot-preview
fi

for target; do
    case "$target" in
        all|blender|cad|godot|godot-preview) ;;
        *) printf 'Unknown build target: %s\n' "$target" >&2; exit 1 ;;
    esac
done

if ! actual=$("$docker_cli" image inspect --format '{{.Os}}/{{.Architecture}} {{.Id}}' "$base_tag") || [ "$actual" != "$base_identity" ]; then
    printf 'Run bash prepare.sh with the Docker daemon used by build.sh to obtain the pinned Ubuntu base image.\n' >&2
    exit 1
fi
(
    cd -- "$bundle_dir"
    sha256sum --quiet --check SHA256SUMS
)

for target; do
    "$docker_cli" buildx build --builder default --platform linux/amd64 --load \
        --progress=plain --network=none --pull=false --provenance=false \
        --build-context "apt-repo=$bundle_dir/inputs/apt" \
        --build-context "releases=$bundle_dir/inputs/releases" \
        --build-context "wheelhouse=$bundle_dir/inputs/wheelhouse" \
        --target "$target" -t "agent3d-smoke:$target" "$bundle_dir"
done
