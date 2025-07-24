#!/usr/bin/env bash

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

# This script executes at the start of the container. It sets DNS server, installs zapret and restarts services
# NOTE: This script must ONLY be executed inside the container

# Check if we're inside the container
if [[ "$container" != "docker" ]]; then
    echo "ERROR: This script can ONLY be executed INSIDE the container"
    exit 126
fi

# Deletes log file if it exists
# Args:
#   1: Path to log file
delete_old_log() {
    _config_file=$1
    if [ -f "$_config_file" ]; then
        echo "Deleting existing log file: $_config_file"
        rm $_config_file
    fi
}

# Delete previous stop file (just in case)
if [ -f "/stop" ]; then rm /stop; fi

# Set timezone
echo "Setting timezone to $TZ"
echo "$TZ" >/etc/timezone
dpkg-reconfigure -f noninteractive tzdata

# Remove old config files
delete_old_log "$_DNSCRYPT_LOG_FILE"
delete_old_log "$_SING_BOX_LOG_FILE"
delete_old_log "$_ZAPRET_LOG_FILE"

# Create log dir
mkdir -p "$_LOGS_DIR_INT"
chmod 777 "$_LOGS_DIR_INT"

# Start dnscrypt-proxy
#cp /etc/resolv.conf /etc/resolv.conf.old
#cp /etc/resolv.conf.override /etc/resolv.conf
ln -sf "$_DNSCRYPT_LOG_FILE" /var/log/dnscrypt-proxy.err
"$_DNSCRYPT_DIR_INT/dnscrypt-proxy" -logfile "$_DNSCRYPT_LOG_FILE" -service start && sleep 3

# Start zapret
"$_ZAPRET_DIR_INT/init.d/sysv/zapret" start | tee -a "$_ZAPRET_LOG_FILE"

# Start sing-box and restart it in case of kill / error (blocking) (or exit if /stop file exists)
while true; do
    "$_SING_BOX_DIR_INT/sing-box" run --config "$_SING_BOX_CONFIG_FILE_INT" 2>&1 | tee -a "$_SING_BOX_LOG_FILE"
    if [ -f "/stop" ]; then
        echo "Exiting"
        rm /stop
        break
    fi
    echo "WARNING! sing-box stopped! Restarting after 3s..." | tee -a "$_SING_BOX_LOG_FILE"
    sleep 3
done
