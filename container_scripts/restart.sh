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

# This script executes inside the container and reload all services
# NOTE: This script must ONLY be executed inside the container

# Check if we're inside the container
if [[ "$container" != "docker" ]]; then
    echo "ERROR: This script can ONLY be executed INSIDE the container"
    exit 126
fi

# Restart zapret by stopping it (will be restarted by watchdog. See entrypoint.sh for more info)
echo "Restarting zapret"
"$_ZAPRET_DIR_INT/init.d/sysv/zapret" stop | tee -a "$_ZAPRET_LOG_FILE"

# Wait for zapret (nfqws) to start in 5 seconds
for i in {1..10}; do
    nfqws_pid=$(pidof nfqws)
    [[ -n "${nfqws_pid:-}" ]] && break
    sleep 0.5
done
if [[ ! -n "${nfqws_pid:-}" ]]; then
    echo "WARNING: zapret was unable to start in 5s" | tee -a "$_ZAPRET_LOG_FILE"
    return
fi

# Restart dnscrypt-proxy and wait a bit to make sure it's started
echo "Restarting dnscrypt-proxy"
#cp /etc/resolv.conf.override /etc/resolv.conf
"$_DNSCRYPT_DIR_INT/dnscrypt-proxy" -logfile "$_DNSCRYPT_LOG_FILE" -service restart
sleep 3

# Send SIGTERM to sing-box to restart it
sing_box_pid=$(pidof "sing-box")
if [[ $sing_box_pid ]]; then
    echo "Restarting sing-box"
    kill -15 "$sing_box_pid"
else
    echo "sing-box not running! Wait for it to start or see log file for errors"
fi
