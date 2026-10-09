FROM ubuntu:24.04

ARG TARGETARCH

RUN apt-get update && apt-get install -y \
    python3 python3-pip python3.12-venv git bash jq build-essential binutils file xxd wget zip curl unzip libicu-dev \
    cmake libgl1-mesa-dev libglu1-mesa-dev libgl1-mesa-dri libsdl2-dev libsdl2-mixer-dev libsdl2-ttf-dev libfontconfig1-dev libvulkan-dev libglew-dev \
    clang ffmpeg pandoc valgrind xauth xvfb pkg-config

RUN if [ "$TARGETARCH" = amd64 ]; then \
      dpkg --add-architecture i386; \
      dpkg --add-architecture arm64; \
      dpkg --add-architecture armhf; \
      sed -i '/^Types: deb$/a Architectures: amd64 i386' /etc/apt/sources.list.d/ubuntu.sources; \
      printf '%s\n' \
        'Types: deb' \
        'URIs: http://ports.ubuntu.com/ubuntu-ports' \
        'Suites: noble noble-updates noble-backports noble-security' \
        'Components: main restricted universe multiverse' \
        'Architectures: arm64 armhf' \
        'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg' \
        > /etc/apt/sources.list.d/ubuntu-ports.sources; \
      apt-get update; \
      apt-get install -y gcc-i686-linux-gnu gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf \
        libsdl2-dev:i386 libsdl2-mixer-dev:i386 libgl-dev:i386 libglu1-mesa-dev:i386 \
        libsdl2-dev:arm64 libsdl2-mixer-dev:arm64 libgl-dev:arm64 libglu1-mesa-dev:arm64 \
        libsdl2-dev:armhf libsdl2-mixer-dev:armhf libgl-dev:armhf libglu1-mesa-dev:armhf \
        libgl1:i386 libgl1-mesa-dri:i386 libsdl2-2.0-0:i386 libsdl2-mixer-2.0-0:i386; \
    elif [ "$TARGETARCH" = arm64 ]; then \
      dpkg --add-architecture armhf; \
      sed -i '/^Types: deb$/a Architectures: arm64 armhf' /etc/apt/sources.list.d/ubuntu.sources; \
      apt-get update; \
      apt-get install -y gcc-arm-linux-gnueabihf \
        libsdl2-dev:armhf libsdl2-mixer-dev:armhf libgl-dev:armhf libglu1-mesa-dev:armhf \
        libgl1:armhf libgl1-mesa-dri:armhf libsdl2-2.0-0:armhf libsdl2-mixer-2.0-0:armhf; \
    else exit 1; fi

RUN python3 -m pip install textual==7.5.0 --ignore-installed --break-system-packages

COPY scripts/ /opt/scripts/
COPY config/ /workspace/config/
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /opt/scripts/*.sh

ENTRYPOINT ["/entrypoint.sh"]
