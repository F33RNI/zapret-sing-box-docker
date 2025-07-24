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

# This script executes inside the container to gracefully stop it
# NOTE: This script must ONLY be executed inside the container

# Check if we're inside the container
if [[ "$container" != "docker" ]]; then
    echo "ERROR: This script can ONLY be executed INSIDE the container"
    exit 126
fi

# Create stop file for sing-box wrapper
touch /stop

# Stop zapret
echo "Stopping zapret"
"$_ZAPRET_DIR_INT/init.d/sysv/zapret" stop | tee -a "$_ZAPRET_LOG_FILE"

# Stop dnscrypt-proxy and restore default DNS
echo "Stopping dnscrypt-proxy service and restoring original DNS servers"
"$_DNSCRYPT_DIR_INT/dnscrypt-proxy" -logfile "$_DNSCRYPT_LOG_FILE" -service stop
if [ -f "/etc/resolv.conf.old" ]; then
    cp /etc/resolv.conf.old /etc/resolv.conf
    rm /etc/resolv.conf.old
fi

# Finally send SIGTERM to sing-box (because it's the only "blocking" process in entrypoint)
sing_box_pid=$(pidof "sing-box")
if [[ $sing_box_pid ]]; then
    echo "Stopping sing-box"
    kill -15 "$sing_box_pid"
else
    echo "sing-box already stopped"
fi
