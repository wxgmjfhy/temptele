#!/usr/bin/env bash
set -euo pipefail

smoke_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
output=$(realpath -m -- "${1:?Usage: smoke/run.sh NEW_OUTPUT_DIRECTORY}")
docker_cli=${DOCKER:-docker}
image=${SMOKE_IMAGE:-agent3d-smoke:all}
preview_image=${SMOKE_PREVIEW_IMAGE:-agent3d-smoke:godot-preview}
uid=$(id -u)
gid=$(id -g)
mkdir -- "$output"
if [ "$uid" -eq 0 ]; then
    uid=1000
    gid=1000
    chown "$uid:$gid" "$output"
fi

run_image() {
    local image=$1
    shift
    "$docker_cli" run --rm --init --pull never --platform linux/amd64 \
        --user "$uid:$gid" --network none --read-only \
        --cpus 4 --memory 6g --pids-limit 256 \
        --tmpfs /tmp:rw,exec,nosuid,size=512m \
        --mount "type=bind,source=$smoke_dir,target=/smoke,readonly" \
        --mount "type=bind,source=$output,target=/out" \
        -e HOME=/tmp/agent -e XDG_DATA_HOME=/tmp/agent/data \
        -e XDG_CONFIG_HOME=/tmp/agent/config -e XDG_CACHE_HOME=/tmp/agent/cache \
        -e XDG_STATE_HOME=/tmp/agent/state \
        "$image" "$@"
}

run_image "$image" sh -ec '
    mkdir -p "$XDG_CACHE_HOME/fontconfig"
    ldd /opt/blender/blender > /out/blender-ldd.txt
    if grep "not found" /out/blender-ldd.txt; then
        exit 1
    fi
    timeout 120 blender --background --factory-startup --disable-autoexec \
        --threads 4 --python-exit-code 1 --python /smoke/blender_asset.py -- /out
' 2>&1 | tee "$output/blender.log"
grep -q BLENDER_OK "$output/blender.log"

run_image "$image" sh -ec '
    mkdir -p "$HOME"
    timeout 120 /opt/cadquery/bin/python /smoke/cad_part.py /out
' 2>&1 | tee "$output/cad.log"
grep -q CADQUERY_OK "$output/cad.log"

godot_test='
    mkdir -p "$XDG_CACHE_HOME/fontconfig" /tmp/project
    cp /smoke/project.godot /smoke/main.tscn /smoke/main.gd /out/asset.glb /tmp/project
    ldd /usr/local/bin/godot
    timeout 90 godot --headless --path /tmp/project --import
    if [ "$1" = "preview" ]; then
        LIBGL_ALWAYS_SOFTWARE=true LP_NUM_THREADS=2 timeout 90 xvfb-run -a \
            -s "-screen 0 640x480x24" godot --display-driver x11 --audio-driver Dummy \
            --rendering-method gl_compatibility --path /tmp/project -- --capture
    else
        timeout 90 godot --headless --path /tmp/project
    fi
'

run_image "$image" sh -ec "$godot_test" smoke headless 2>&1 | tee "$output/godot.log"
grep -q GODOT_OK "$output/godot.log"
run_image "$preview_image" sh -ec "$godot_test" smoke preview 2>&1 | tee "$output/godot-preview.log"
grep -q "GODOT_PIXELS_OK .*llvmpipe" "$output/godot-preview.log"
grep -q GODOT_OK "$output/godot-preview.log"

run_image "$image" sh -ec '
    mkdir -p "$XDG_CACHE_HOME/fontconfig"
    opencode --version
    opencode run --help > /out/opencode-run-help.txt
    blender --version | head -1
    godot --version
    /opt/cadquery/bin/python -c "import cadquery; print(cadquery.__version__)"
    python3 /smoke/opencode_fixture.py
' 2>&1 | tee "$output/all.log"
grep -q OPENCODE_OK "$output/all.log"
