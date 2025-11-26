FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    python3 python3-pip python3.12-venv git bash jq build-essential wget zip unzip libicu-dev

COPY scripts/ /opt/scripts/
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /opt/scripts/*.sh

ENTRYPOINT ["/entrypoint.sh"]