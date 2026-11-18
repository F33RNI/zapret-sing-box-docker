#!/usr/bin/env bash

# This file is part of the zapret-sing-box-docker distribution.
# See <https://github.com/F33RNI/zapret-sing-box-docker> for more info.
#
# Copyright (c) 2025-2026 Fern Lane.
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
    local log_file=$1
    if [ -f "$log_file" ]; then
        echo "Deleting existing log file: $log_file"
        rm $log_file
    fi
}

# Monitors if PID of process exists and calls f_start() if not. Also calls f_stop() if "/stop" file is present
# NOTE: Blocking until interrupted / killed or "/stop" file is present
# Args:
#   1: Process name (e.g. nfqws)
#   2: Non-blocking function to (re)start the process
#   3: Function to stop the process
#   4: Path to log file
#   5: true to pause if /blockcheck is present
watchdog() {
    local proc_name=$1
    local f_start=$2
    local f_stop=$3
    local log_file=$4
    local pause_on_blockcheck=${5:-false}
    local proc_pid
    local start_exit_code

    while true; do
        # Check for /stop file
        if [ -f "/stop" ]; then
            echo "[$proc_name watchdog] /stop file is present. Stopping ${proc_name}..." | tee -a "$log_file"

            # Try to run stop function
            if "$f_stop" > >(tee -a "$log_file") 2>&1; then
                return 0
            else
                local stop_exit_code=$?
                echo "[$proc_name watchdog] Stop function failed (exit code: $stop_exit_code)!" | tee -a "$log_file"
                return "$stop_exit_code"
            fi
        fi

        # Ignore if /blockcheck file is present
        if [[ "$pause_on_blockcheck" == "true" && -f "/blockcheck" ]]; then
            echo "[$proc_name watchdog] Paused due to /blockcheck file present" | tee -a "$log_file"
            sleep 1s
            continue
        fi

        # Check if process is running
        proc_pid=$(pidof "$proc_name" 2>/dev/null) || proc_pid=
        if [[ -z "$proc_pid" ]]; then
            echo "[$proc_name watchdog] No $proc_name or it died. (Re)starting ${proc_name}..." | tee -a "$log_file"

            # Try to start it
            if "$f_start" > >(tee -a "$log_file") 2>&1; then
                :
            else
                start_exit_code=$?
                echo "[$proc_name watchdog] Start function failed (exit code: $start_exit_code)!" | tee -a "$log_file"
            fi

            # Check if process started
            proc_pid=$(pidof "$proc_name" 2>/dev/null) || proc_pid=
            if [[ -n "$proc_pid" ]]; then
                echo "[$proc_name watchdog] $proc_name PID: $proc_pid" | tee -a "$log_file"
            else
                echo "[$proc_name watchdog] $proc_name was unable to start!" | tee -a "$log_file"
            fi
        fi

        sleep 1s
    done
}

# Functions to start / stop zapret
zapret_start() { "$_ZAPRET_DIR_INT/init.d/sysv/zapret" start; }
zapret_stop() { "$_ZAPRET_DIR_INT/init.d/sysv/zapret" stop; }

# Stops zapret, it's watchdog, removes /stop file if exists and exists with 0
cleanup() {
    echo "Cleaning up..."

    # Stop watchdog first
    if [[ -n "${zapret_watchdog_pid:-}" ]] && kill -0 "$zapret_watchdog_pid" 2>/dev/null; then
        echo "Stopping zapret watchdog..." | tee -a "$_ZAPRET_LOG_FILE"
        kill "$zapret_watchdog_pid" 2>/dev/null
        wait "$zapret_watchdog_pid" 2>/dev/null
    fi

    # Stop zapret
    local nfqws_pid=$(pidof nfqws 2>/dev/null) || nfqws_pid=
    if [[ -n "$nfqws_pid" ]]; then
        echo "Stopping zapret..." | tee -a "$_ZAPRET_LOG_FILE"
        zapret_stop | tee -a "$_ZAPRET_LOG_FILE"
    fi

    # Remove /stop file and exit from script
    if [ -f "/stop" ]; then rm /stop; fi
    exit 0
}

# Delete previous stop file (just in case)
if [ -f "/stop" ]; then rm /stop; fi

# Set timezone
echo "Setting timezone to $TZ"
echo "$TZ" >/etc/timezone
dpkg-reconfigure -f noninteractive tzdata

# Remove old log files
delete_old_log "$_DNSCRYPT_LOG_FILE"
delete_old_log "$_SING_BOX_LOG_FILE"
delete_old_log "$_ZAPRET_LOG_FILE"
delete_old_log "$_USQUE_LOG_FILE"

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

# Start zapret and nfqws watchdog
watchdog "nfqws" zapret_start zapret_stop "$_ZAPRET_LOG_FILE" true &
zapret_watchdog_pid=$!
echo "zapret watchdog PID: $zapret_watchdog_pid" | tee -a "$_ZAPRET_LOG_FILE"

# Wait a bit before starting usque to make sure zapret is running
sleep 1s

# Register usque if not registered yet
if [ ! -f "$_USQUE_CONFIG_FILE_INT" ] ||
    [ ! -s "$_USQUE_CONFIG_FILE_INT" ] ||
    [ "$(tr -d '[:space:]' <"$_USQUE_CONFIG_FILE_INT")" = "{}" ]; then
    echo "y" | "$_USQUE_DIR_INT/usque" -c "$_USQUE_CONFIG_FILE_INT" register -a 2>&1 | tee -a "$_USQUE_LOG_FILE"
fi

# Start usque
echo "Starting usque..." | tee -a "$_USQUE_LOG_FILE"
"$_USQUE_DIR_INT/usque" -c "$_USQUE_CONFIG_FILE_INT" socks --always-reconnect \
    -b "$USQUE_SOCKS_IP" -p "$USQUE_SOCKS_PORT" 2>&1 | tee -a "$_USQUE_LOG_FILE" &
echo "usque PID: $(pidof usque)" | tee -a "$_USQUE_LOG_FILE"

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
