FROM ubuntu:24.04 AS native

ARG TARGETARCH

RUN apt-get update && apt-get install -y \
    python3 python3-pip python3.12-venv git bash jq build-essential binutils file xxd wget zip curl unzip libicu-dev \
    cmake libgl1-mesa-dev libglu1-mesa-dev libgl1-mesa-dri libsdl2-dev libsdl2-mixer-dev libsdl2-ttf-dev libfontconfig1-dev libvulkan-dev libglew-dev \
    clang ffmpeg pandoc valgrind xauth xvfb pkg-config

RUN python3 -m pip install textual==7.5.0 --ignore-installed --break-system-packages

FROM native AS cross-deps

ARG TARGETARCH

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
      apt-get install -y \
        libsdl2-dev:i386 libsdl2-mixer-dev:i386 libgl-dev:i386 libglu1-mesa-dev:i386 \
        libsdl2-dev:arm64 libsdl2-mixer-dev:arm64 libgl-dev:arm64 libglu1-mesa-dev:arm64 \
        libsdl2-dev:armhf libsdl2-mixer-dev:armhf libgl-dev:armhf libglu1-mesa-dev:armhf \
        libgl1:i386 libgl1-mesa-dri:i386 libsdl2-2.0-0:i386 libsdl2-mixer-2.0-0:i386; \
    elif [ "$TARGETARCH" = arm64 ]; then \
      dpkg --add-architecture armhf; \
      sed -i '/^Types: deb$/a Architectures: arm64 armhf' /etc/apt/sources.list.d/ubuntu.sources; \
      apt-get update; \
      apt-get install -y \
        libsdl2-dev:armhf libsdl2-mixer-dev:armhf libgl-dev:armhf libglu1-mesa-dev:armhf \
        libgl1:armhf libgl1-mesa-dri:armhf libsdl2-2.0-0:armhf libsdl2-mixer-2.0-0:armhf; \
    else exit 1; fi

RUN mkdir -p /opt/foreign/usr/lib /opt/foreign/usr/include /opt/foreign/lib && \
    if [ "$TARGETARCH" = amd64 ]; then \
      triplets='i386-linux-gnu aarch64-linux-gnu arm-linux-gnueabihf'; \
      cp -a /lib/ld-linux.so.2 /opt/foreign/lib/; \
    else \
      triplets='arm-linux-gnueabihf'; \
      cp -a /lib/ld-linux-armhf.so.3 /opt/foreign/lib/; \
    fi && \
    for triplet in $triplets; do \
      cp -a "/usr/lib/$triplet" /opt/foreign/usr/lib/; \
      if [ -d "/usr/include/$triplet" ]; then \
        cp -a "/usr/include/$triplet" /opt/foreign/usr/include/; \
      fi; \
    done

FROM native

ARG TARGETARCH

RUN if [ "$TARGETARCH" = amd64 ]; then \
      apt-get install -y gcc-i686-linux-gnu gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf; \
    elif [ "$TARGETARCH" = arm64 ]; then \
      apt-get install -y gcc-arm-linux-gnueabihf; \
    else exit 1; fi

COPY --from=cross-deps /opt/foreign/ /

RUN test "$(dpkg-query -W -f='${Architecture}' python3.12-minimal)" = "$TARGETARCH" && \
    python3 -c 'import sys; print(sys.version)' && \
    if [ "$TARGETARCH" = amd64 ]; then \
      targets='i386-linux-gnu:i686-linux-gnu-gcc aarch64-linux-gnu:aarch64-linux-gnu-gcc arm-linux-gnueabihf:arm-linux-gnueabihf-gcc'; \
    else \
      targets='arm-linux-gnueabihf:arm-linux-gnueabihf-gcc'; \
    fi && \
    for target in $targets; do \
      triplet="${target%%:*}"; compiler="${target#*:}"; \
      PKG_CONFIG_LIBDIR="/usr/lib/$triplet/pkgconfig:/usr/share/pkgconfig" pkg-config --exists sdl2; \
      printf 'int main(void) { return 0; }\n' | "$compiler" -x c - -o "/tmp/check-$triplet" \
        -L"/usr/lib/$triplet" -lSDL2 -lSDL2_mixer -lGL -lGLU; \
    done

COPY scripts/ /opt/scripts/
COPY config/ /workspace/config/
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /opt/scripts/*.sh

ENTRYPOINT ["/entrypoint.sh"]
