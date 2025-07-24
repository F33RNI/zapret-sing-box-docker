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

# This script iterates through all containers, stops them using internal ./stop.sh script and removes if needed
# NOTE: This script must ONLY be executed OUTSIDE the container

# Specify rm argument to this script to remove the container
if [ "$1" = "rm" ]; then _rm=true; fi

# Get all container IDs (even of stopped ones)
while IFS= read -a container_id; do
    # Check if container is running and stop it
    if [ "$(docker container inspect -f '{{.State.Status}}' $container_id)" = "running" ]; then
        echo "Stopping container $container_id gracefully"
        docker exec "$container_id" ./stop.sh
        docker stop "$container_id"
    else
        echo "Container $container_id is not running"
    fi

    if [ "$_rm" != true ]; then
        echo "Launch with rm argument (./stop.sh rm) to remove it"
        continue
    fi

    echo "Removing container $container_id"
    docker rm "$container_id"
done < <(docker ps -a | grep zapret-sing-box-docker | awk '{print $1}')
unset container_id
