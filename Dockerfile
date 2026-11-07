FROM ubuntu:24.04 AS native

ARG TARGETARCH

RUN apt-get update && apt-get install -y \
    python3 python3-pip python3.12-venv git bash jq build-essential binutils file xxd wget zip curl unzip libicu-dev \
    cmake libgl1-mesa-dev libglu1-mesa-dev libgl1-mesa-dri libsdl2-dev libsdl2-mixer-dev libsdl2-ttf-dev libfontconfig1-dev libvulkan-dev libglew-dev \
    clang clang-tools lld glslang-tools cppcheck ffmpeg pandoc valgrind xauth xvfb pkg-config squashfs-tools \
    ca-certificates libegl1 libgtk-3-0 libxcb-cursor0 libxkbcommon-x11-0 \
    mesa-vulkan-drivers vulkan-tools libvulkan1 libasound2t64 libpulse0 libudev1 \
    libx11-6 libxext6 libxrandr2 libxcursor1 libxi6 libxss1 libxtst6 libxkbcommon0 \
    libwayland-client0 libwayland-cursor0 libwayland-egl1 libdecor-0-0

RUN python3 -m pip install textual==7.5.0 --ignore-installed --break-system-packages

FROM --platform=$BUILDPLATFORM ubuntu:24.04 AS ps4-shaders

ARG BUILDARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git xz-utils && rm -rf /var/lib/apt/lists/*

RUN case "$BUILDARCH" in \
      amd64) zigarch=x86_64; digest=1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026;; \
      arm64) zigarch=aarch64; digest=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8;; \
      *) exit 1;; esac && \
    curl -fL --retry 3 -o /tmp/zig.tar.xz "https://ziglang.org/download/0.17.0/zig-$zigarch-linux-0.17.0.tar.xz" && \
    echo "$digest  /tmp/zig.tar.xz" | sha256sum -c - && \
    mkdir /tmp/zig && tar -xJf /tmp/zig.tar.xz -C /tmp/zig --strip-components=1 && \
    git clone https://github.com/lateleite/psbc.git /tmp/psbc && \
    cd /tmp/psbc && git checkout 3b1ea85bc25315d6e611f58f51a8639003a291e8 && \
    /tmp/zig/zig build --release=fast -Dtarget=x86_64-linux-musl -j2 && \
    git diff --exit-code HEAD -- && \
    mkdir -p /out && cp zig-out/bin/psbc /out/ && \
    cp LICENSE /out/ && \
    rm -rf /tmp/zig /tmp/zig.tar.xz /tmp/psbc /root/.cache/zig

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS ps4-pkgtool

ARG TARGETARCH

RUN git clone https://github.com/OpenOrbis/LibOrbisPkg.git /tmp/LibOrbisPkg && \
    cd /tmp/LibOrbisPkg && \
    git checkout 92a4e7f8e5914cb06b52ba3ae6b0675da438a051 && \
    case "$TARGETARCH" in amd64) runtime=linux-x64;; arm64) runtime=linux-arm64;; *) exit 1;; esac && \
    dotnet publish PkgTool.Core/PkgTool.Core.csproj -c Release -r "$runtime" \
      --self-contained true -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true \
      -o /out && \
    cp LICENSE.txt /out/

FROM ubuntu:24.04 AS ps4

ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git build-essential clang lld glslang-tools python3 \
    xz-utils bzip2 golang-go libicu74 libssl3t64 zlib1g && \
    if [ "$TARGETARCH" = arm64 ]; then apt-get install -y --no-install-recommends qemu-user; fi && \
    rm -rf /var/lib/apt/lists/*

ENV OO_PS4_TOOLCHAIN=/opt/ps4/sdk
ENV PS4_DEPS=/opt/ps4/portlibs
ENV FREEGNM_EXAMPLES=/opt/ps4/share/freegnm-examples
ENV PSBC=/opt/ps4/bin/psbc
ENV PATH="/opt/ps4/bin:${PATH}"

RUN curl -fL --retry 3 -o /tmp/openorbis.tar.gz \
      https://github.com/OpenOrbis/OpenOrbis-PS4-Toolchain/releases/download/v0.5.4/toolchain-llvm-18.tar.gz && \
    echo '3c7cd5bb593ca74fa1c13fd59f3938dc0fc07985167f7275063019e63abe4526  /tmp/openorbis.tar.gz' | sha256sum -c - && \
    mkdir -p "$OO_PS4_TOOLCHAIN" && \
    tar -xzf /tmp/openorbis.tar.gz -C "$OO_PS4_TOOLCHAIN" --strip-components=2 \
      OpenOrbis/PS4Toolchain/include OpenOrbis/PS4Toolchain/lib \
      OpenOrbis/PS4Toolchain/link.x OpenOrbis/PS4Toolchain/LICENSE \
      OpenOrbis/PS4Toolchain/samples/graphics/sce_module \
      OpenOrbis/PS4Toolchain/samples/graphics/sce_sys/about && \
    rm /tmp/openorbis.tar.gz

RUN mkdir -p "$OO_PS4_TOOLCHAIN/bin/linux" && \
    git clone https://github.com/OpenOrbis/create-fself.git /tmp/create-fself && \
    cd /tmp/create-fself && git checkout f2da6229684ce320f673c06fceac9c218f621788 && \
    cd cmd/create-fself && go build -modfile=go-linux.mod -o "$OO_PS4_TOOLCHAIN/bin/linux/create-fself" . && \
    git clone https://github.com/OpenOrbis/create-gp4.git /tmp/create-gp4 && \
    cd /tmp/create-gp4 && git checkout bf8e66e9e9bdd92e41e1697893bc8098a151fa24 && \
    GO111MODULE=off go build -o "$OO_PS4_TOOLCHAIN/bin/linux/create-gp4" ./cmd/create-gp4/main.go && \
    rm -rf /tmp/create-fself /tmp/create-gp4 /root/go

COPY --from=ps4-pkgtool /out/ /opt/ps4/sdk/bin/linux/

RUN git clone https://github.com/PS4-OpenGNM/opengnm.git /tmp/opengnm && \
    cd /tmp/opengnm && git checkout c51243f333a1a964894903da080a508f7af4d91f && \
    cp config.orbis.mak config.mak && \
    make -j2 lib CC=clang AR=ar && \
    make install-headers install-lib CC=clang AR=ar DESTDIR="$PS4_DEPS" INCDIR=/include LIBDIR=/lib && \
    mkdir -p /opt/ps4/licenses && cp LICENSE /opt/ps4/licenses/opengnm && \
    git clone https://github.com/PS4-OpenGNM/freegnm-examples.git /tmp/freegnm-examples && \
    cd /tmp/freegnm-examples && git checkout ffd055563e5b849ebef1b276ba29e730199670f8 && \
    mkdir -p "$FREEGNM_EXAMPLES/shared" && \
    cp -a shared/src "$FREEGNM_EXAMPLES/shared/" && \
    cp LICENSE "$FREEGNM_EXAMPLES/" && \
    rm -rf /tmp/opengnm /tmp/freegnm-examples

RUN curl -fL --retry 3 -o /tmp/mpg123.tar.bz2 \
      https://www.mpg123.de/download/mpg123-1.33.4.tar.bz2 && \
    echo '3ae8c9ff80a97bfc0e22e89fbcd74687eca4fc1db315b12607f27f01cb5a47d9  /tmp/mpg123.tar.bz2' | sha256sum -c - && \
    tar -xjf /tmp/mpg123.tar.bz2 -C /tmp && \
    cd /tmp/mpg123-1.33.4 && \
    CC="clang --target=x86_64-pc-freebsd12-elf -isysroot $OO_PS4_TOOLCHAIN -isystem $OO_PS4_TOOLCHAIN/include" \
    CFLAGS='-O2 -fPIC' AR=ar RANLIB=ranlib \
    LDFLAGS="-fuse-ld=lld -nostdlib -Wl,-m,elf_x86_64,-pie,--script=$OO_PS4_TOOLCHAIN/link.x,--eh-frame-hdr -L$OO_PS4_TOOLCHAIN/lib $OO_PS4_TOOLCHAIN/lib/crt1.o" \
    LIBS='-lm -lc -lkernel' \
    ./configure --host=x86_64-unknown-freebsd --prefix="$PS4_DEPS" \
      --disable-shared --enable-static --with-cpu=generic --disable-network \
      --disable-ipv6 --disable-components --enable-libmpg123 && \
    make -j2 && make install && \
    cp COPYING /opt/ps4/licenses/mpg123 && \
    rm -rf /tmp/mpg123-1.33.4 /tmp/mpg123.tar.bz2

COPY --from=ps4-shaders /out/psbc /opt/ps4/libexec/psbc
COPY --from=ps4-shaders /out/LICENSE /opt/ps4/licenses/psbc
RUN mkdir -p /opt/ps4/bin && \
    if [ "$TARGETARCH" = arm64 ]; then \
      printf '#!/bin/sh\nexec qemu-x86_64 /opt/ps4/libexec/psbc "$@"\n' > /opt/ps4/bin/psbc; \
      chmod +x /opt/ps4/bin/psbc; \
    else ln -s ../libexec/psbc /opt/ps4/bin/psbc; fi

RUN clang --version && ld.lld --version && glslangValidator --version && \
    test -x "$PSBC" && \
    test -x "$OO_PS4_TOOLCHAIN/bin/linux/create-fself" && \
    test -x "$OO_PS4_TOOLCHAIN/bin/linux/create-gp4" && \
    test -x "$OO_PS4_TOOLCHAIN/bin/linux/PkgTool.Core" && \
    test -f "$PS4_DEPS/lib/libopengnm.a" && \
    test -f "$PS4_DEPS/lib/libmpg123.a"

# Package the examples' shared utilities once as an installed dependency.
RUN mkdir -p /tmp/freegnm-helpers "$PS4_DEPS/include/freegnm-helpers" && \
    for helper in u/fs u/utility displayctx memalloc misc; do \
      clang --target=x86_64-pc-freebsd12-elf -isysroot "$OO_PS4_TOOLCHAIN" \
        -isystem "$OO_PS4_TOOLCHAIN/include" -I"$PS4_DEPS/include/opengnm" \
        -I"$FREEGNM_EXAMPLES/shared/src" -DUSE_OPENGNM -DSTB_IMAGE_STATIC \
        -O2 -fPIC -ffunction-sections -fdata-sections \
        -c "$FREEGNM_EXAMPLES/shared/src/$helper.c" -o "/tmp/freegnm-helpers/${helper##*/}.o" || exit 1; \
    done && \
    ar rcs "$PS4_DEPS/lib/libfreegnm-helpers.a" /tmp/freegnm-helpers/*.o && \
    cd "$FREEGNM_EXAMPLES/shared/src" && \
    find . -name '*.h' -exec cp --parents '{}' "$PS4_DEPS/include/freegnm-helpers/" \; && \
    cp "$FREEGNM_EXAMPLES/LICENSE" /opt/ps4/licenses/freegnm-examples && \
    rm -rf /tmp/freegnm-helpers

RUN printf '#version 450\nvoid main() { gl_Position = vec4(0.0, 0.0, 0.0, 1.0); }\n' > /tmp/ps4-check.vert && \
    glslangValidator -V -S vert /tmp/ps4-check.vert -o /tmp/ps4-check.spv && \
    "$PSBC" -s vertex /tmp/ps4-check.spv /tmp/ps4-check.sb && \
    test -s /tmp/ps4-check.sb && \
    "$OO_PS4_TOOLCHAIN/bin/linux/PkgTool.Core" sfo_new /tmp/ps4-check.sfo && \
    rm /tmp/ps4-check.vert /tmp/ps4-check.spv /tmp/ps4-check.sb /tmp/ps4-check.sfo

FROM ubuntu:24.04 AS xbox

ARG TARGETARCH

ENV NXDK_DIR=/opt/nxdk
ENV GLES_DIR=/opt/nxdk-gles11
ENV MINIMP3_DIR=/opt/minimp3
ENV PATH="/opt/nxdk/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake clang lld llvm bison flex ninja-build python3 git curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/XboxDev/nxdk.git "$NXDK_DIR" && \
    cd "$NXDK_DIR" && git checkout 004fefbfe8fd93a5ea8ee9a95ff187b0f58ec8ed && \
    git submodule update --init --recursive --depth 1 && \
    make -j4 NXDK_ONLY=y NXDK_SDL= NXDK_CXX= && \
    make clean-pdclib clean-pbkit NXDK_SDL= NXDK_CXX= && \
    make -j4 "$NXDK_DIR/lib/libpdclib.lib" "$NXDK_DIR/lib/libpbkit.lib" NXDK_SDL= NXDK_CXX= \
      CFLAGS="-O2 -fno-strict-aliasing" && \
    make -j4 tools && \
    test -f lib/nxdk_usb.lib && test -f lib/libnxdk_net.lib

COPY config/nxdk-gles11.patch /tmp/nxdk-gles11.patch
COPY config/nxdk-gles11-performance.patch /tmp/nxdk-gles11-performance.patch
COPY config/nxdk-gles11-buffers.patch /tmp/nxdk-gles11-buffers.patch
COPY config/nxdk-gles11-state.patch /tmp/nxdk-gles11-state.patch
RUN git clone https://github.com/Ryzee119/nxdk-gles11.git "$GLES_DIR" && \
    cd "$GLES_DIR" && git checkout 5a726e61f1af5c3e9682af2c833c9703cab5022e && \
    git submodule update --init --recursive && git apply /tmp/nxdk-gles11.patch && \
    git apply /tmp/nxdk-gles11-performance.patch && \
    git apply /tmp/nxdk-gles11-buffers.patch && \
    git apply /tmp/nxdk-gles11-state.patch && \
    cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE="$NXDK_DIR/share/toolchain-nxdk.cmake" \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS_RELEASE="-O2 -fno-strict-aliasing" \
      -DNXDK_GLES11_WITH_GL4ES=OFF && \
    cmake --build build -j4 && \
    grep -q -- "-O2" build/CMakeFiles/GLESv1_CM.dir/flags.make && \
    git clone https://github.com/lieff/minimp3.git "$MINIMP3_DIR" && \
    cd "$MINIMP3_DIR" && git checkout ea99364f61c14656440e8d77e9c233ccf3124633

FROM ubuntu:24.04 AS xemu

ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates python3 squashfs-tools && rm -rf /var/lib/apt/lists/*

RUN case "$TARGETARCH" in \
      amd64) arch=x86_64; digest=ac77363a599109194ba2af3caa695348d199f515cf1d0fde091beb629e0c3103;; \
      arm64) arch=aarch64; digest=8d2598bab0680ddd36c2d15ecccb70523e29adb852cd75e35bc5943dc0eb4816;; \
      *) exit 1;; esac && \
    curl -fL --retry 3 -o /tmp/xemu.AppImage \
      "https://github.com/xemu-project/xemu/releases/download/v0.8.136/xemu-0.8.136-$arch.AppImage" && \
    echo "$digest  /tmp/xemu.AppImage" | sha256sum -c - && \
    image_offset="$(python3 -c 'import struct; h=open("/tmp/xemu.AppImage","rb").read(64); assert h[:6] == b"\x7fELF\x02\x01"; print(struct.unpack_from("<Q",h,40)[0] + struct.unpack_from("<H",h,58)[0] * struct.unpack_from("<H",h,60)[0])')" && \
    unsquashfs -no-progress -offset "$image_offset" -d /opt/xemu /tmp/xemu.AppImage && \
    test -x /opt/xemu/AppRun && rm /tmp/xemu.AppImage

# A focused image for developing and validating the Xbox tools without other SDKs.
FROM xbox AS xbox-tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb xauth libgl1 libgl1-mesa-dri libegl1 libvulkan1 mesa-vulkan-drivers \
    libsdl2-2.0-0 libgtk-3-0 libpulse0 libasound2t64 libslirp0 libepoxy0 ffmpeg unzip && \
    rm -rf /var/lib/apt/lists/*
ENV XEMU_BIN=/opt/xemu/AppRun
COPY --from=xemu /opt/xemu/ /opt/xemu/
COPY scripts/ /opt/scripts/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /opt/scripts/*.sh
ENTRYPOINT ["/entrypoint.sh"]

FROM native AS ppsspp

COPY config/ppsspp.patch /tmp/ppsspp.patch

RUN git clone --depth 1 --branch v1.17.1 --recurse-submodules \
      https://github.com/hrydgard/ppsspp.git /opt/ppsspp && \
    cd /opt/ppsspp && \
    test "$(git rev-parse HEAD)" = d479b74ed9c3e321bc3735da29bc125a2ac3b9b2 && \
    git apply /tmp/ppsspp.patch && \
    ./b.sh --headless && \
    test -x build/PPSSPPHeadless && \
    test -d build/assets

FROM native AS shadps4

ARG TARGETARCH

RUN if [ "$TARGETARCH" = amd64 ]; then \
      curl -fL --retry 3 -o /tmp/shadps4.zip \
        https://github.com/shadps4-emu/shadPS4/releases/download/v.0.18.0/shadps4-linux-sdl-0.18.0.zip && \
      echo '3cf0f669c089411775a2434a41ca9c391fb7d24c1a1521ee45dd1d36f390c4a4  /tmp/shadps4.zip' | sha256sum -c - && \
      unzip -q /tmp/shadps4.zip -d /tmp && \
      image_offset="$(python3 -c 'import struct; h=open("/tmp/Shadps4-sdl.AppImage","rb").read(64); assert h[:6] == b"\x7fELF\x02\x01"; print(struct.unpack_from("<Q",h,40)[0] + struct.unpack_from("<H",h,58)[0] * struct.unpack_from("<H",h,60)[0])')" && \
      unsquashfs -no-progress -offset "$image_offset" -d /opt/shadps4 /tmp/Shadps4-sdl.AppImage && \
      test -x /opt/shadps4/AppRun && \
      python3 -c 'import struct; h=open("/opt/shadps4/usr/bin/shadps4","rb").read(64); assert h[:6] == b"\x7fELF\x02\x01" and struct.unpack_from("<H",h,18)[0] == 62' && \
      rm /tmp/shadps4.zip /tmp/Shadps4-sdl.AppImage; \
    else mkdir -p /opt/shadps4; fi

COPY config/shadps4.json /opt/shadps4/profile/config.json

RUN for user in 1000 1001 1002 1003; do \
      mkdir -p "/opt/shadps4/profile/home/$user/savedata" \
        "/opt/shadps4/profile/home/$user/trophy" \
        "/opt/shadps4/profile/home/$user/inputs"; \
    done

FROM native AS pcsx2

ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    mtools dosfstools libaio1t64 && rm -rf /var/lib/apt/lists/*

COPY config/pcsx2-usb-sync.c /tmp/pcsx2-usb-sync.c

RUN if [ "$TARGETARCH" = amd64 ]; then \
      curl -fL --retry 3 -o /tmp/pcsx2.AppImage \
        https://github.com/PCSX2/pcsx2/releases/download/v2.4.0/pcsx2-v2.4.0-linux-appimage-x64-Qt.AppImage && \
      echo '2d5061f4f2906f22befc719aac3acebd2699fb07c611bc90709780e28dea8c8e  /tmp/pcsx2.AppImage' | sha256sum -c - && \
      image_offset="$(python3 -c 'import struct; h=open("/tmp/pcsx2.AppImage","rb").read(64); assert h[:6] == b"\x7fELF\x02\x01"; print(struct.unpack_from("<Q",h,40)[0] + struct.unpack_from("<H",h,58)[0] * struct.unpack_from("<H",h,60)[0])')" && \
      unsquashfs -no-progress -offset "$image_offset" -d /opt/pcsx2 /tmp/pcsx2.AppImage && \
      cc -shared -fPIC -O2 -Wall -Wextra -Werror /tmp/pcsx2-usb-sync.c -ldl -o /opt/pcsx2/usb-sync.so && \
      test -x /opt/pcsx2/AppRun && \
      rm /tmp/pcsx2.AppImage; \
    else mkdir -p /opt/pcsx2; fi && \
    rm /tmp/pcsx2-usb-sync.c

FROM devkitpro/devkitarm AS devkitarm

FROM devkitpro/devkita64 AS devkita64

RUN dkp-pacman -S --needed --noconfirm switch-sdl2_mixer && \
    test -f /opt/devkitpro/libnx/switch_rules && \
    test -f /opt/devkitpro/portlibs/switch/lib/pkgconfig/SDL2_mixer.pc

FROM vitasdk/vitasdk:2026.08 AS vita

RUN git clone https://github.com/Rinnegatamante/vitaGL.git /tmp/vitaGL && \
    cd /tmp/vitaGL && \
    git checkout 6e7fe40 && \
    make MATH_SPEEDHACK=1 PRIMITIVES_SPEEDHACK=1 HAVE_FFP_SHADER_SUPPORT=1 DISABLE_FFP_MULTITEXTURE=1 HAVE_WVP_ON_GPU=1 NO_TILE_CLIPPER=1 NO_SPLASHSCREEN=1 -j"$(nproc)" && \
    make install && \
    rm -rf /tmp/vitaGL

FROM ubuntu:24.04 AS psp

ARG TARGETARCH
ENV PSPDEV=/opt/pspdev
ENV PATH="/opt/pspdev/bin:${PATH}"
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN if [ "$TARGETARCH" = amd64 ]; then \
      archive=pspdev-ubuntu-latest-x86_64.tar.gz; \
      digest=a86efe624e770005290919617859e9df24bd8fcd3e364f4587f23ec7364b0acd; \
    else \
      archive=pspdev-ubuntu-24.04-arm-arm64.tar.gz; \
      digest=0638f5f32fe4354c70040f8ee987b2e7111a981e93499d3986d30b15d1fb8e61; \
    fi && \
    curl -fL --retry 3 -o /tmp/pspdev.tar.gz \
      "https://github.com/pspdev/pspdev/releases/download/v20261001/$archive" && \
    echo "$digest  /tmp/pspdev.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/pspdev.tar.gz -C /opt && \
    rm /tmp/pspdev.tar.gz && \
    test -x /opt/pspdev/bin/psp-config && \
    test -f /opt/pspdev/psp/sdk/lib/libpspmath.a


FROM ubuntu:24.04 AS ps2

ARG TARGETARCH

ENV PS2DEV=/usr/local/ps2dev
ENV PS2SDK=/usr/local/ps2dev/ps2sdk
ENV GSKIT=/usr/local/ps2dev/gsKit
ENV PATH="${PS2DEV}/bin:${PS2DEV}/ee/bin:${PS2DEV}/iop/bin:${PS2DEV}/dvp/bin:${PS2SDK}/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN case "$TARGETARCH" in \
      amd64) archive=ps2dev-ubuntu-latest.tar.gz; \
        digest=c8e5dedccf62084d476894e88cd0451b57f1ed288e741eb3c1263010aaffc028;; \
      arm64) archive=ps2dev-ubuntu-24.04-arm.tar.gz; \
        digest=ed69330f235d421754196acf866f8590e5f92e8b92571f1c7e05e853900e7622;; \
      *) exit 1;; \
    esac && \
    curl -fL --retry 3 -o /tmp/ps2dev.tar.gz \
      "https://github.com/ps2dev/ps2dev/releases/download/v2.0.0/$archive" && \
    echo "$digest  /tmp/ps2dev.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/ps2dev.tar.gz -C /usr/local && \
    rm /tmp/ps2dev.tar.gz && \
    mips64r5900el-ps2-elf-gcc --version && \
    dvp-as --version && \
    test -f "$GSKIT/lib/libgskit.a" && \
    test -f "$GSKIT/lib/libdmakit.a" && \
    test -f "$PS2SDK/ee/lib/libpacket2.a" && \
    test -f "$PS2SDK/ports/include/mpg123.h" && \
    test -f "$PS2SDK/ports/lib/libmpg123.a"

RUN curl -fL --retry 3 -o /tmp/mmceman.tar.gz \
      https://codeload.github.com/ps2-mmce/mmceman/tar.gz/de28936fdf45fe445554cfa0b8f058b05fa8212f && \
    echo 'dcf41e87681a7b5c9df0a1f3aee6e689a9ab7805faaa92841214671f28223b2c  /tmp/mmceman.tar.gz' | sha256sum -c - && \
    mkdir /tmp/mmceman && \
    tar -xzf /tmp/mmceman.tar.gz -C /tmp/mmceman --strip-components=1 && \
    make -C /tmp/mmceman/mmceman && \
    cp /tmp/mmceman/mmceman/irx/mmceman.irx "$PS2SDK/iop/irx/" && \
    mkdir -p "$PS2SDK/share/licenses" && \
    cp /tmp/mmceman/LICENSE "$PS2SDK/share/licenses/mmceman.txt" && \
    rm -rf /tmp/mmceman /tmp/mmceman.tar.gz

FROM ubuntu:24.04 AS ndless

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ git make wget texinfo python3-dev ca-certificates \
    libgmp-dev libmpfr-dev libmpc-dev zlib1g-dev lbzip2 xz-utils \
    libboost-program-options-dev php file

RUN git clone --recursive --depth 1 --branch r2020 \
    https://github.com/ndless-nspire/Ndless.git /opt/ndless

WORKDIR /opt/ndless/ndless-sdk/toolchain
RUN PARALLEL="-j$(nproc)" ./build_toolchain.sh

ENV PATH="/opt/ndless/ndless-sdk/toolchain/install/bin:/opt/ndless/ndless-sdk/bin:${PATH}"
WORKDIR /opt/ndless
RUN make all -j"$(nproc)" && \
    rm -rf ndless-sdk/toolchain/build ndless-sdk/toolchain/download

# Focused cross-platform validation images share the standard Toolbox commands.
FROM xbox-tools AS psp-tools
ENV PSPDEV=/opt/pspdev
ENV PATH="/opt/pspdev/bin:${PATH}"
COPY --from=psp /opt/pspdev/ /opt/pspdev/

FROM xbox-tools AS ps2-tools
ENV PS2DEV=/usr/local/ps2dev
ENV PS2SDK=/usr/local/ps2dev/ps2sdk
ENV GSKIT=/usr/local/ps2dev/gsKit
ENV PATH="${PS2DEV}/bin:${PS2DEV}/ee/bin:${PS2DEV}/iop/bin:${PS2DEV}/dvp/bin:${PS2SDK}/bin:${PATH}"
COPY --from=ps2 /usr/local/ps2dev/ /usr/local/ps2dev/

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
      apt-get install -y --no-remove \
        python3:amd64 python3-minimal:amd64 python3.12-minimal:amd64 \
        libsdl2-dev:i386 libsdl2-mixer-dev:i386 libgl-dev:i386 libglu1-mesa-dev:i386 \
        libsdl2-dev:arm64 libsdl2-mixer-dev:arm64 libgl-dev:arm64 libglu1-mesa-dev:arm64 \
        libsdl2-dev:armhf libsdl2-mixer-dev:armhf libgl-dev:armhf libglu1-mesa-dev:armhf \
        libgl1:i386 libgl1-mesa-dri:i386 libsdl2-2.0-0:i386 libsdl2-mixer-2.0-0:i386; \
    elif [ "$TARGETARCH" = arm64 ]; then \
      dpkg --add-architecture armhf; \
      sed -i '/^Types: deb$/a Architectures: arm64 armhf' /etc/apt/sources.list.d/ubuntu.sources; \
      apt-get update; \
      apt-get install -y --no-remove \
        python3:arm64 python3-minimal:arm64 python3.12-minimal:arm64 \
        libsdl2-dev:armhf libsdl2-mixer-dev:armhf libgl-dev:armhf libglu1-mesa-dev:armhf \
        libgl1:armhf libgl1-mesa-dri:armhf libsdl2-2.0-0:armhf libsdl2-mixer-2.0-0:armhf; \
    else exit 1; fi

RUN mkdir -p /opt/foreign/usr/lib /opt/foreign/usr/include /opt/foreign/lib && \
    if [ "$TARGETARCH" = amd64 ]; then \
      triplets='i386-linux-gnu aarch64-linux-gnu arm-linux-gnueabihf'; \
      cp -a /lib/ld-linux.so.2 /opt/foreign/lib/; \
      cp -a /lib/ld-linux-aarch64.so.1 /opt/foreign/lib/; \
      cp -a /lib/ld-linux-armhf.so.3 /opt/foreign/lib/; \
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

ENV NXDK_DIR=/opt/nxdk
ENV GLES_DIR=/opt/nxdk-gles11
ENV MINIMP3_DIR=/opt/minimp3
ENV XEMU_BIN=/opt/xemu/AppRun
ENV PATH="/opt/nxdk/bin:${PATH}"
COPY --from=xbox /opt/nxdk/ /opt/nxdk/
COPY --from=xbox /opt/nxdk-gles11/ /opt/nxdk-gles11/
COPY --from=xbox /opt/minimp3/ /opt/minimp3/
COPY --from=xemu /opt/xemu/ /opt/xemu/
RUN apt-get update && apt-get install -y --no-install-recommends llvm bison flex && \
    rm -rf /var/lib/apt/lists/*


ENV OO_PS4_TOOLCHAIN=/opt/ps4/sdk
ENV PS4_DEPS=/opt/ps4/portlibs
ENV PSBC=/opt/ps4/bin/psbc
ENV PATH="/opt/ps4/bin:${PATH}"

COPY --from=ps4 /opt/ps4/ /opt/ps4/

RUN if [ "$TARGETARCH" = arm64 ]; then apt-get update && apt-get install -y qemu-user; fi

ENV PS2DEV=/usr/local/ps2dev
ENV PS2SDK=/usr/local/ps2dev/ps2sdk
ENV GSKIT=/usr/local/ps2dev/gsKit
ENV PATH="${PS2DEV}/bin:${PS2DEV}/ee/bin:${PS2DEV}/iop/bin:${PS2DEV}/dvp/bin:${PS2SDK}/bin:${PATH}"
ENV PSPDEV=/opt/pspdev
ENV PATH="/opt/pspdev/bin:${PATH}"
ENV DEVKITPRO=/opt/devkitpro
ENV DEVKITARM=/opt/devkitpro/devkitARM
ENV DEVKITA64=/opt/devkitpro/devkitA64
ENV PATH="/opt/devkitpro/tools/bin:${PATH}"
ENV VITASDK=/usr/local/vitasdk
ENV PATH="/usr/local/vitasdk/bin:${PATH}"
ENV PATH="/opt/ndless/ndless-sdk/toolchain/install/bin:/opt/ndless/ndless-sdk/bin:${PATH}"

RUN if [ "$TARGETARCH" = amd64 ]; then \
      dpkg --add-architecture i386; \
      sed -i '/^Types: deb$/a Architectures: amd64 i386' /etc/apt/sources.list.d/ubuntu.sources; \
      apt-get update; \
      apt-get install -y gcc-i686-linux-gnu gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf \
        gcc-mingw-w64-i686 gcc-mingw-w64-x86-64 mingw-w64-tools wine wine64 wine32:i386; \
    elif [ "$TARGETARCH" = arm64 ]; then \
      apt-get install -y gcc-arm-linux-gnueabihf \
        gcc-mingw-w64-i686 gcc-mingw-w64-x86-64 mingw-w64-tools; \
    else exit 1; fi

COPY --from=cross-deps /opt/foreign/ /opt/foreign/

RUN apt-get update && apt-get install -y libboost-program-options1.83.0

RUN cp -a /opt/foreign/usr/lib/. /usr/lib/ && \
    cp -a /opt/foreign/usr/include/. /usr/include/ && \
    cp -a /opt/foreign/lib/. /lib/

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

RUN mkdir -p /opt/mingw-deps && \
    curl -fL --retry 3 -o /tmp/SDL2-mingw.tar.gz \
      https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-devel-2.32.10-mingw.tar.gz && \
    curl -fL --retry 3 -o /tmp/SDL2_mixer-mingw.tar.gz \
      https://github.com/libsdl-org/SDL_mixer/releases/download/release-2.8.2/SDL2_mixer-devel-2.8.2-mingw.tar.gz && \
    tar -xzf /tmp/SDL2-mingw.tar.gz -C /tmp && \
    tar -xzf /tmp/SDL2_mixer-mingw.tar.gz -C /tmp && \
    for triplet in i686-w64-mingw32 x86_64-w64-mingw32; do \
      dest="/opt/mingw-deps/$triplet"; \
      mkdir -p "$dest"; \
      cp -a "/tmp/SDL2-2.32.10/$triplet/." "$dest/"; \
      cp -a "/tmp/SDL2_mixer-2.8.2/$triplet/." "$dest/"; \
      sed -i "s|^prefix=.*|prefix=$dest|" "$dest"/lib/pkgconfig/*.pc; \
      PKG_CONFIG_LIBDIR="$dest/lib/pkgconfig" pkg-config --exists sdl2; \
      test -f "$dest/lib/libSDL2.a"; \
      test -f "$dest/lib/libSDL2_mixer.a"; \
      printf 'int main(void) { return 0; }\n' | "$triplet-gcc" -x c - -o "/tmp/check-$triplet.exe" \
        -L"$dest/lib" -lSDL2_mixer -lSDL2; \
    done && \
    rm -rf /tmp/SDL2-2.32.10 /tmp/SDL2_mixer-2.8.2 \
      /tmp/SDL2-mingw.tar.gz /tmp/SDL2_mixer-mingw.tar.gz

COPY --from=psp /opt/pspdev/ /opt/pspdev/

ENV PCSX2_BIN=/opt/pcsx2/AppRun
COPY --from=pcsx2 /opt/pcsx2/ /opt/pcsx2/

RUN apt-get update && apt-get install -y --no-install-recommends \
    mtools dosfstools libaio1t64 && rm -rf /var/lib/apt/lists/*

ENV SHADPS4_BIN=/opt/shadps4/AppRun
COPY --from=shadps4 /opt/shadps4/ /opt/shadps4/

COPY --from=ppsspp /opt/ppsspp/build/PPSSPPHeadless /opt/ppsspp/PPSSPPHeadless
COPY --from=ppsspp /opt/ppsspp/build/assets/ /opt/ppsspp/assets/
COPY --from=devkitarm /opt/devkitpro/ /opt/devkitpro/
COPY --from=devkita64 /opt/devkitpro/ /opt/devkitpro/
COPY --from=vita /usr/local/vitasdk/ /usr/local/vitasdk/
COPY --from=ndless /opt/ndless/ /opt/ndless/
COPY --from=ps2 /usr/local/ps2dev/ /usr/local/ps2dev/

RUN mips64r5900el-ps2-elf-gcc --version && dvp-as --version

RUN nspire-gcc -v && command -v genzehn

RUN psp-config --pspsdk-path && \
    /opt/ppsspp/PPSSPPHeadless --help 2>&1 | grep -q -- '--system='

RUN test -f "$DEVKITARM/3ds_rules" && \
    test -x "$DEVKITARM/bin/arm-none-eabi-gcc" && \
    test -f "$DEVKITPRO/libnx/switch_rules" && \
    test -x "$DEVKITA64/bin/aarch64-none-elf-gcc" && \
    test -f "$DEVKITPRO/portlibs/switch/lib/pkgconfig/SDL2_mixer.pc"

RUN git clone --depth 1 --branch revamp https://github.com/masterfeizz/picaGL.git /tmp/picaGL && \
    mkdir -p /tmp/picaGL/clean && \
    make -C /tmp/picaGL install && \
    rm -rf /tmp/picaGL

RUN curl -fL --retry 3 -o /tmp/mpg123.tar.bz2 \
      https://downloads.sourceforge.net/project/mpg123/mpg123/1.32.3/mpg123-1.32.3.tar.bz2 && \
    tar -xf /tmp/mpg123.tar.bz2 -C /tmp && \
    cd /tmp/mpg123-1.32.3 && \
    ./configure --host=arm-none-eabi --prefix="$DEVKITPRO/portlibs/3ds" \
      --disable-shared --enable-static --with-cpu=generic_fpu \
      CC="$DEVKITARM/bin/arm-none-eabi-gcc" \
      CFLAGS='-march=armv6k -mtune=mpcore -mfloat-abi=hard -mtp=soft -D_3DS' && \
    (make -k -j"$(nproc)" || true) && \
    (make -k install || true) && \
    cp src/libmpg123/mpg123.h "$DEVKITPRO/portlibs/3ds/include/" && \
    test -f "$DEVKITPRO/portlibs/3ds/lib/libmpg123.a" && \
    rm -rf /tmp/mpg123-1.32.3 /tmp/mpg123.tar.bz2

RUN curl -fL --retry 3 -o /tmp/azahar.AppImage \
      https://github.com/azahar-emu/azahar/releases/download/2126.0/azahar.AppImage && \
    image_offset="$(python3 -c 'import struct; p="/tmp/azahar.AppImage"; h=open(p,"rb").read(64); assert h[:6] == b"\x7fELF\x02\x01"; print(struct.unpack_from("<Q",h,40)[0] + struct.unpack_from("<H",h,58)[0] * struct.unpack_from("<H",h,60)[0])')" && \
    unsquashfs -no-progress -offset "$image_offset" -d /opt/azahar /tmp/azahar.AppImage && \
    test -x /opt/azahar/AppRun && \
    rm /tmp/azahar.AppImage

COPY scripts/ /opt/scripts/
COPY config/ /workspace/config/
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /opt/scripts/*.sh

ENTRYPOINT ["/entrypoint.sh"]
