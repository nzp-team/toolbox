FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    python3 python3-pip python3.12-venv git bash jq build-essential wget zip unzip libicu-dev

COPY scripts/ /opt/scripts/
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /opt/scripts/*.sh
RUN mkdir /workspace
# set read,write,execute permissions for everyone, in case we don't wnat to run as root later.
RUN chmod -R 777 /workspace /entrypoint.sh /opt/scripts

ENTRYPOINT ["/entrypoint.sh"]
