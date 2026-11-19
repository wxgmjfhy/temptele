#!/bin/sh
set -eu

sources=$(mktemp /tmp/agent3d-apt.XXXXXX.list)
trap 'rm -f "$sources"' EXIT
printf 'deb [trusted=yes] file:/apt-repo ./\n' > "$sources"
chmod 644 "$sources"

export DEBIAN_FRONTEND=noninteractive
apt-get -o "Dir::Etc::sourcelist=$sources" -o Dir::Etc::sourceparts=- \
    -o Acquire::Languages=none update
apt-get -o "Dir::Etc::sourcelist=$sources" -o Dir::Etc::sourceparts=- \
    install -y --no-install-recommends "$@"
rm -rf /var/lib/apt/lists/*
