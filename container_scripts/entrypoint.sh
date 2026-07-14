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

# Replace resolv.conf
if [ -f "/etc/resolv.conf.override" ]; then
    echo "Replacing resolv.conf"
    [ ! -f "/etc/resolv.conf.old" ] && cp /etc/resolv.conf /etc/resolv.conf.old
    cp /etc/resolv.conf.override /etc/resolv.conf
fi

# Start dnscrypt-proxy
ln -sf "$_DNSCRYPT_LOG_FILE" /var/log/dnscrypt-proxy.err
"$_DNSCRYPT_DIR_INT/dnscrypt-proxy" -logfile "$_DNSCRYPT_LOG_FILE" -service start && sleep 5

# Starts zapret and saves nfqws PID
#   NOTE: executed by zapret_start_watchdog()
_zapret_start() {
    "$_ZAPRET_DIR_INT/init.d/sysv/zapret" start | tee -a "$_ZAPRET_LOG_FILE"
    nfqws_pid=$(pidof nfqws)
    if [[ -n "${nfqws_pid}" ]]; then
        echo "nfqws pid: $nfqws_pid" | tee -a "$_ZAPRET_LOG_FILE"
    else
        echo "nfqws was unable to start!" | tee -a "$_ZAPRET_LOG_FILE"
        nfqws_pid=""
    fi
}

# Stops zapret and clears nfqws_pid variable
#   NOTE: executed by zapret_start_watchdog() and cleanup()
_zapret_stop() {
    "$_ZAPRET_DIR_INT/init.d/sysv/zapret" stop | tee -a "$_ZAPRET_LOG_FILE"
    nfqws_pid=""
}

# Starts zapret and constantly checks if nfqws is running and restarts zapret if not and no /blockcheck file is present
# (see blockcheck.sh for more info)
# (blocking until killed or /stop file is present)
zapret_start_watchdog() {
    while true; do
        # Check for /stop file
        if [ -f "/stop" ]; then
            echo "/stop file is present. Stopping zapret..." | tee -a "$_ZAPRET_LOG_FILE"
            _zapret_stop
            break
        fi

        # Ignore if /blockcheck file is present
        if [[ -f "/blockcheck" ]]; then
            echo "zapret watchdog is paused due to /blockcheck file present" | tee -a "$_ZAPRET_LOG_FILE"
            sleep 1
            continue
        fi

        # Not started yet
        if [[ ! -n "${nfqws_pid:-}" ]]; then
            echo "No nfqws. Starting zapret..." | tee -a "$_ZAPRET_LOG_FILE"
            _zapret_start

        # Started -> check nfqws
        elif ! kill -0 "$nfqws_pid" 2>/dev/null; then
            echo "nfqws died! Restarting zapret..." | tee -a "$_ZAPRET_LOG_FILE"
            _zapret_start
        fi
        sleep 1
    done
}

# Stops zapret and it's watchdog and removes /stop file if exists
cleanup() {
    echo "Cleaning up..."

    # Stop watchdog first
    if [[ -n "${zapret_start_watchdog_pid:-}" ]] && kill -0 "$zapret_start_watchdog_pid" 2>/dev/null; then
        echo "Stopping zapret watchdog"
        kill "$zapret_start_watchdog_pid" 2>/dev/null
        wait "$zapret_start_watchdog_pid" 2>/dev/null
    fi

    # Stop zapret
    if [[ -n "${nfqws_pid:-}" ]]; then
        echo "Stopping zapret" | tee -a "$_ZAPRET_LOG_FILE"
        _zapret_stop
    fi

    if [ -f "/stop" ]; then rm /stop; fi
    exit 0
}

# Start zapret and nfqws watchdog
zapret_start_watchdog &
zapret_start_watchdog_pid=$!
echo "zapret watchdog PID: $zapret_start_watchdog_pid"

# Start sing-box and restart it in case of kill / error (blocking) (or exit if /stop file exists)
while true; do
    "$_SING_BOX_DIR_INT/sing-box" run --config "$_SING_BOX_CONFIG_FILE_INT" 2>&1 | tee -a "$_SING_BOX_LOG_FILE"
    if [ -f "/stop" ]; then
        cleanup
        break
    fi
    echo "WARNING! sing-box stopped! Restarting after 3s..." | tee -a "$_SING_BOX_LOG_FILE"
    sleep 3
done
