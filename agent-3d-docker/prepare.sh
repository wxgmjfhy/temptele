#!/usr/bin/env bash
set -euo pipefail

demo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
input_dir="$demo_dir/inputs"
docker_cli=${DOCKER:-docker}
ubuntu_image=docker.io/library/ubuntu@sha256:77eb101c607d6e3d4f5ad0c8a02c2136c689b98aba1f359e6502ba517e5c57ec
ubuntu_snapshot=https://snapshot.ubuntu.com/ubuntu/20261118T180000Z

command -v "$docker_cli" >/dev/null || {
    printf 'Docker CLI not found: %s\n' "$docker_cli" >&2
    exit 1
}

mkdir -p "$input_dir/apt/debs" "$input_dir/releases" "$input_dir/wheelhouse"

fetch() (
    local destination=$1 url=$2 algorithm=$3 checksum=$4 fallback=${5:-}
    local tool="${algorithm}sum" partial
    if [ -f "$destination" ] && printf '%s  %s\n' "$checksum" "$destination" | "$tool" --check --status; then
        return
    fi
    partial=$(mktemp "${destination}.part.XXXXXX")
    trap 'rm -f -- "$partial"' EXIT
    printf 'Downloading %s\n' "${destination##*/}"
    if ! curl -fLSs --connect-timeout 15 --retry 2 -o "$partial" "$url"; then
        if [ -z "$fallback" ]; then
            return 1
        fi
        curl -fLSs --connect-timeout 15 --retry 2 -o "$partial" "$fallback"
    fi
    printf '%s  %s\n' "$checksum" "$partial" | "$tool" --check --quiet
    chmod 0644 "$partial"
    mv -f -- "$partial" "$destination"
)

while IFS=$'\t' read -r package version checksum path url; do
    fetch "$input_dir/apt/$path" "$ubuntu_snapshot/${url#https://archive.ubuntu.com/ubuntu/}" sha256 "$checksum" "$url"
done < "$input_dir/apt/upstream-sha256.tsv"

while IFS=$'\t' read -r checksum path url; do
    fetch "$input_dir/$path" "$url" sha256 "$checksum"
done < "$input_dir/wheels.tsv"

fetch "$input_dir/releases/blender.tar.xz" \
    https://download.blender.org/release/Blender4.5/blender-4.5.16-linux-x64.tar.xz \
    sha256 23432b064977908beb1ab4b7f32f024e7331105c875c187dce002aff84b10c11
fetch "$input_dir/releases/godot.zip" \
    https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip \
    sha256 cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4
fetch "$input_dir/releases/opencode-npm.tar.gz" \
    https://registry.npmjs.org/@opencode/cli-linux-x64-baseline/-/cli-linux-x64-baseline-2.2.7.tgz \
    sha512 d57e9f153e155b2cccc481962b52e0dbd344afa5c43986145cc5d23db7d299b10776a4cb0dc3bd0e54d369e6eae2e05b570fed429206270e2c041aca6fdb4a30

(
    cd -- "$demo_dir"
    sha256sum --quiet --check SHA256SUMS
)
"$docker_cli" image pull --platform linux/amd64 "$ubuntu_image"
"$docker_cli" image tag "$ubuntu_image" agent3d-validation:ubuntu-24.04-base-20261119
