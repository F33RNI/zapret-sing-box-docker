# This file is part of the zapret-sing-box-docker distribution.
# See <https://github.com/F33RNI/zapret-sing-box-docker> for more info.
#
# Copyright (c) 2025 Fern Lane.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

FROM debian:stable-slim
LABEL maintainer="Fern Lane"

# Internal paths to programs (where they will be installed) inside the image (copied from host)
ENV _DNSCRYPT_DIR_INT="/opt/dnscrypt-proxy"
ENV _SING_BOX_DIR_INT="/opt/sing-box"
ENV _ZAPRET_DIR_INT="/opt/zapret"

# Internal paths to symbolic links of config files inside the container
ENV _DNSCRYPT_CONFIG_FILE_INT="${_DNSCRYPT_DIR_INT}/dnscrypt-proxy.toml"
ENV _SING_BOX_CONFIG_FILE_INT="${_SING_BOX_DIR_INT}/config.json"
ENV _ZAPRET_CONFIG_FILE_INT="${_ZAPRET_DIR_INT}/config"

# Arguments from build script or docker-compose.yml
ARG DNSCRYPT_DIR
RUN test -n "$DNSCRYPT_DIR"
ENV DNSCRYPT_DIR=${DNSCRYPT_DIR}
ARG SING_BOX_DIR
RUN test -n "$SING_BOX_DIR"
ENV SING_BOX_DIR=${SING_BOX_DIR}
ARG ZAPRET_DIR
RUN test -n "$ZAPRET_DIR"
ENV ZAPRET_DIR=${ZAPRET_DIR}
ARG _CONFIGS_DIR_INT
RUN test -n "$_CONFIGS_DIR_INT"
ENV _CONFIGS_DIR_INT=${_CONFIGS_DIR_INT}
ARG _LOGS_DIR_INT
RUN test -n "$_LOGS_DIR_INT"
ENV _LOGS_DIR_INT=${_LOGS_DIR_INT}

# Config and log files in mounted volume inside the container
ENV _DNSCRYPT_CONFIG_FILE="${_CONFIGS_DIR_INT}/dnscrypt-proxy.toml"
ENV _SING_BOX_CONFIG_FILE="${_CONFIGS_DIR_INT}/sing-box.json"
ENV _ZAPRET_CONFIG_FILE="${_CONFIGS_DIR_INT}/zapret.conf"
ENV _DNSCRYPT_LOG_FILE="${_LOGS_DIR_INT}/dnscrypt-proxy.log"
ENV _SING_BOX_LOG_FILE="${_LOGS_DIR_INT}/sing-box.log"
ENV _ZAPRET_LOG_FILE="${_LOGS_DIR_INT}/zapret.log"

ENV container="docker"
WORKDIR /root

# Upgrade everything and install essentials
RUN DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get -y update && \
    apt-get -y dist-upgrade && \
    apt-get -y install ca-certificates tzdata && \
    apt-get -y autoremove && \
    apt-get -y autoclean && \
    apt-get clean all

# Install dnscrypt-proxy
COPY ${DNSCRYPT_DIR} ${_DNSCRYPT_DIR_INT}
WORKDIR ${_DNSCRYPT_DIR_INT}
#RUN /usr/bin/env bash -c 'echo -e "nameserver 127.0.0.1\nnameserver ::1\noptions edns0" >/etc/resolv.conf.override'
RUN mkdir -p $(dirname "$_DNSCRYPT_CONFIG_FILE_INT")
RUN ln -sf "$_DNSCRYPT_CONFIG_FILE" "$_DNSCRYPT_CONFIG_FILE_INT"
RUN mkdir -p "/etc/init.d"
RUN "./dnscrypt-proxy" -config "$_DNSCRYPT_CONFIG_FILE_INT" -service install

# Install sing-box
COPY ${SING_BOX_DIR} ${_SING_BOX_DIR_INT}
WORKDIR ${_SING_BOX_DIR_INT}
RUN mkdir -p $(dirname "$_SING_BOX_CONFIG_FILE_INT")
RUN ln -sf "$_SING_BOX_CONFIG_FILE" "$_SING_BOX_CONFIG_FILE_INT"

# Install zapret
COPY ${ZAPRET_DIR} ${_ZAPRET_DIR_INT}
WORKDIR ${_ZAPRET_DIR_INT}
RUN ./install_bin.sh
RUN echo "1" | ./install_prereq.sh
RUN echo "Y" | ./install_easy.sh
RUN mkdir -p $(dirname "$_ZAPRET_CONFIG_FILE_INT")
RUN ln -sf "$_ZAPRET_CONFIG_FILE" "$_ZAPRET_CONFIG_FILE_INT"

WORKDIR /root

# Copy scripts
COPY container_scripts/*.sh ./
RUN chmod +x ./*.sh

# Start everything
ENTRYPOINT ["/usr/bin/env", "bash"]
CMD ["./entrypoint.sh"]
