FROM agent3d-validation:ubuntu-24.04-base-20261119 AS base

ENV LANG=C.UTF-8 TZ=UTC
RUN --mount=type=bind,from=apt-repo,target=/apt-repo \
    --mount=type=bind,source=install-apt.sh,target=/tmp/install-apt.sh \
    sh /tmp/install-apt.sh ca-certificates curl file git jq python3 python3-venv ripgrep unzip zip \
    && install -d -o 1000 -g 1000 /home/agent /workspace /out

FROM base AS blender-files
RUN --mount=type=bind,from=apt-repo,target=/apt-repo \
    --mount=type=bind,source=install-apt.sh,target=/tmp/install-apt.sh \
    sh /tmp/install-apt.sh xz-utils
RUN --mount=type=bind,from=releases,source=blender.tar.xz,target=/tmp/blender.tar.xz \
    mkdir -p /opt/blender \
    && tar -xJf /tmp/blender.tar.xz --strip-components=1 -C /opt/blender

FROM base AS godot-files
RUN --mount=type=bind,from=releases,source=godot.zip,target=/tmp/godot.zip \
    unzip -q /tmp/godot.zip -d /tmp/godot \
    && install /tmp/godot/Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot \
    && rm -rf /tmp/godot

FROM base AS cadquery-env
COPY cadquery.lock /tmp/cadquery.lock
RUN --mount=type=bind,from=wheelhouse,target=/wheels \
    python3 -m venv /opt/cadquery \
    && /opt/cadquery/bin/pip --disable-pip-version-check install \
        --no-index --find-links=/wheels --only-binary=:all: --require-hashes \
        --no-cache-dir -r /tmp/cadquery.lock \
    && /opt/cadquery/bin/pip check

FROM base AS core
RUN --mount=type=bind,from=releases,source=opencode-npm.tar.gz,target=/tmp/opencode.tar.gz \
    tar -xzf /tmp/opencode.tar.gz -C /tmp package/bin/opencode \
    && install /tmp/package/bin/opencode /usr/local/bin/opencode \
    && rm -rf /tmp/package
ENV HOME=/home/agent
WORKDIR /workspace

FROM core AS graphics-libs
RUN --mount=type=bind,from=apt-repo,target=/apt-repo \
    --mount=type=bind,source=install-apt.sh,target=/tmp/install-apt.sh \
    sh /tmp/install-apt.sh \
        libegl1 libgl1 libgomp1 libx11-6 libxext6 libxfixes3 libxi6 libxrender1 libxxf86vm1

FROM graphics-libs AS blender
COPY --from=blender-files /opt/blender /opt/blender
RUN ln -s /opt/blender/blender /usr/local/bin/blender
RUN --mount=type=bind,from=apt-repo,target=/apt-repo \
    --mount=type=bind,source=install-apt.sh,target=/tmp/install-apt.sh \
    sh /tmp/install-apt.sh libfontconfig1 libsm6 libice6 libxkbcommon0
USER 1000:1000

FROM graphics-libs AS cad
COPY --from=cadquery-env /opt/cadquery /opt/cadquery
USER 1000:1000

FROM core AS godot-core
COPY --from=godot-files /usr/local/bin/godot /usr/local/bin/godot
USER 1000:1000

FROM godot-core AS godot
USER 0:0
RUN --mount=type=bind,from=apt-repo,target=/apt-repo \
    --mount=type=bind,source=install-apt.sh,target=/tmp/install-apt.sh \
    sh /tmp/install-apt.sh libfontconfig1
USER 1000:1000

FROM godot-core AS godot-preview
USER 0:0
RUN --mount=type=bind,from=apt-repo,target=/apt-repo \
    --mount=type=bind,source=install-apt.sh,target=/tmp/install-apt.sh \
    sh /tmp/install-apt.sh \
        libegl1 libfontconfig1 libgl1 libgl1-mesa-dri libglx-mesa0 \
        libx11-6 libxcursor1 libxext6 libxi6 libxinerama1 libxkbcommon0 libxrandr2 libxrender1 \
        xauth xvfb
USER 1000:1000

FROM blender AS all
COPY --from=cadquery-env /opt/cadquery /opt/cadquery
COPY --from=godot-files /usr/local/bin/godot /usr/local/bin/godot
