FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    python3 python3-pip python3.12-venv git bash jq build-essential wget zip curl unzip libicu-dev \
    cmake libgl1-mesa-dev libsdl2-dev libsdl2-ttf-dev libfontconfig1-dev libvulkan-dev libglew-dev \
    clang ffmpeg pandoc

RUN python3 -m pip install textual==7.5.0 --ignore-installed --break-system-packages

COPY scripts/ /opt/scripts/
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /opt/scripts/*.sh

ENTRYPOINT ["/entrypoint.sh"]