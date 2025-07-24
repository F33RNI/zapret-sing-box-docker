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

# This script executes blockcheck.sh from _ZAPRET_DIR_INT directory
# NOTE: This script must ONLY be executed inside the container

# Check if we're inside the container
if [[ "$container" != "docker" ]]; then
    echo "ERROR: This script can ONLY be executed INSIDE the container"
    exit 126
fi

# Domains to check (space separated)
DOMAINS=${DOMAINS:-${DOMAINS_DEFAULT:-youtube.com}}
export DOMAINS

# Output file
log_file="${_LOGS_DIR_INT}/blockcheck.log"

cd $_ZAPRET_DIR_INT

# Stop zapret first
echo "Stopping zapret"
"$_ZAPRET_DIR_INT/init.d/sysv/zapret" stop | tee -a "$_ZAPRET_LOG_FILE"

# Run blockcheck.sh in BATCH mode
echo -e "\nStarting blockcheck in batch mode on domains: $DOMAINS"
BATCH=1 \
    DOMAINS="$DOMAINS" \
    IPVS=4 \
    ENABLE_HTTP=0 \
    ENABLE_HTTPS_TLS12=0 \
    ENABLE_HTTPS_TLS13=1 \
    ENABLE_HTTP3=0 \
    REPEATS=3 \
    PARALLEL=1 \
    SCANLEVEL=standard \
    SKIP_IPBLOCK=1 \
    SKIP_TPWS=1 \
    SECURE_DNS=0 \
    ./blockcheck.sh | tee "$log_file"

echo -e "\nBlockcheck done! Saved into $log_file"

# Start zapret back
echo -e "\nStarting zapret back"
"$_ZAPRET_DIR_INT/init.d/sysv/zapret" start | tee -a "$_ZAPRET_LOG_FILE"
