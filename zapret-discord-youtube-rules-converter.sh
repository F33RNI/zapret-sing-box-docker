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

# This script parses latest rules from <https://github.com/Flowseal/zapret-discord-youtube>
# And converts them into normal zapret NFQWS_OPT value

# Specify test argument to this script to test each option
if [ "$1" = "test" ]; then _test=true; fi

REPO_URL="https://github.com/Flowseal/zapret-discord-youtube.git"
TEMP_DIR="zapret-discord-youtube_temp"
ZAPRET_DIR_INT="/opt/zapret"
ZAPRET_CONFIG=${ZAPRET_CONFIG:-"configs/zapret.conf"}
TEST_CONFIG=${TEST_CONFIG:-"configs/zapret.conf.test"}
RELOAD_SCRIPT=${RELOAD_SCRIPT:-"reload.sh"}
TEST_URL=${TEST_URL:-"https://youtube.com"}

LOG_FILE="zapret-discord-youtube-rules-converter.log"

# Parses NFQWS_OPT from .bat files
parse_bat() {
    local bat_path="$1"

    # Remove ending ^
    cleaned=$(sed ':a;N;$!ba;s/\^/ /g' "$bat_path")

    # Extract lines with --filter-
    filtered_lines=$(echo "$cleaned" | grep -oP -- '--filter-[^\n]+')

    # Ignore lines with list-general.txt
    filtered_lines=$(echo "$filtered_lines" | grep -v 'list-general.txt')

    # Exit if no rules found
    if [ -z "$filtered_lines" ]; then exit 0; fi

    # Replace %GameFilter%
    filtered_lines=$(echo "$filtered_lines" | sed "s|=%GameFilter%|=1024-65535|g" | sed "s|,%GameFilter%|,1024-65535|g")

    # Replace --ipset="%LISTS%ipset-all.txt" with <HOSTLIST>
    filtered_lines=$(echo "$filtered_lines" | sed "s|--ipset=\"%LISTS%ipset-all.txt\"|<HOSTLIST>|g")

    # Replace --ipset="%LISTS%list-general.txt" with <HOSTLIST>
    #filtered_lines=$(echo "$filtered_lines" | sed "s|--ipset=\"%LISTS%list-general.txt\"|<HOSTLIST>|g")

    # Replace %BIN%
    filtered_lines=$(echo "$filtered_lines" | sed "s|%BIN%|$ZAPRET_DIR_INT/files/fake/|g")

    # Trim trailing spaces from all lines
    filtered_lines=$(echo "$filtered_lines" | sed 's/[[:space:]]\+$//')

    # If last line ends with --new, remove it
    filtered_lines=$(echo "$filtered_lines" | sed '$s/ --new$//')

    # Output final result
    if [ "$_test" == true ]; then
        echo "${filtered_lines}"
    else
        echo "# Parsed from $(basename "$bat_path") (Flowseal/zapret-discord-youtube @ $git_head)"
        echo -e "NFQWS_OPT='\n${filtered_lines}\n'\n"
    fi
}

# Parses NFQWS_OPT from .bat files and tests each file
parse_test_bat() {
    # Check test config file
    if [ ! -f $TEST_CONFIG ]; then
        echo "ERROR: No $TEST_CONFIG file!"
        exit 1
    fi

    # Parse .bat file
    local bat_path="$1"
    nfqws_opt=$(parse_bat "$bat_path")
    if [ -z "$nfqws_opt" ]; then exit 0; fi

    # Log
    echo -e "\n\nParsing and testing $(basename "$bat_path") (Flowseal/zapret-discord-youtube @ $git_head)..."
    echo -e "NFQWS_OPT='\n${nfqws_opt}\n'"

    # Rewrite NFQWS_OPT without new lines
    nfqws_opt="${nfqws_opt//$'\n'/$' '}"

    # Write test config
    echo "Writing test config -> $ZAPRET_CONFIG"
    config=$(sed 's|{NFQWS_OPT_PLACEHOLDER}|'"${nfqws_opt}"'|' "$TEST_CONFIG")
    echo "$config" | tee "$ZAPRET_CONFIG" >/dev/null

    # Reload and wait
    echo "Calling reload script..."
    bash "$RELOAD_SCRIPT" >/dev/null

    # Test
    echo "Testing $TEST_URL"
    docker exec -t zapret-sing-box-docker curl --connect-timeout 1 --max-time 3 -L "$TEST_URL" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "WORKING! WORKING! WORKING! ^^"
    else
        echo "Not working ˙◠˙"
    fi
}

# Clone repo
if [ -d "$TEMP_DIR" ]; then
    echo "$TEMP_DIR already exists! Deleting..."
    rm -rf "$TEMP_DIR"
fi
git clone "$REPO_URL" "$TEMP_DIR"

# Save repo version for comments
git_head=$(git -C "$TEMP_DIR" rev-parse --short HEAD)

# Parse and test rules
if [ "$_test" == true ]; then
    # Check if container is running
    container_id=$(docker ps | grep zapret-sing-box-docker | tail -n1 | awk '{print $1}')
    if [ -z "$container_id" ]; then
        echo "ERROR: Container not found! Please start it first!"
        exit 1
    fi

    # Check if reload script exists
    if [ ! -f "$RELOAD_SCRIPT" ]; then
        echo "ERROR: Reload script $RELOAD_SCRIPT doesn't exist"
        exit 1
    fi

    # Copy current config
    if [ -f "$ZAPRET_CONFIG" ]; then
        echo "Saving current config file $ZAPRET_CONFIG -> $ZAPRET_CONFIG.bak"
        cp "$ZAPRET_CONFIG" "${ZAPRET_CONFIG}.bak"
    fi

    cleanup() {
        # Restore original config file
        if [ -f "${ZAPRET_CONFIG}.bak" ]; then
            echo "Restoring config file $ZAPRET_CONFIG.bak -> $ZAPRET_CONFIG"
            cat "${ZAPRET_CONFIG}.bak" | tee "$ZAPRET_CONFIG" >/dev/null
            rm "${ZAPRET_CONFIG}.bak"
        fi

        # Reload
        echo "Calling reload script before exit... Please wait"
        bash "$RELOAD_SCRIPT" >/dev/null
        echo -e "\nFinished!"

        exit 0
    }

    echo -e "\nParsing and testing rules..."
    export LOG_FILE="$LOG_FILE"
    export ZAPRET_DIR_INT="$ZAPRET_DIR_INT"
    export git_head="$git_head"
    export ZAPRET_CONFIG="$ZAPRET_CONFIG"
    export TEST_CONFIG="$TEST_CONFIG"
    export RELOAD_SCRIPT="$RELOAD_SCRIPT"
    export TEST_URL="$TEST_URL"
    export _test=true
    export -f parse_bat
    export -f parse_test_bat
    trap cleanup SIGINT
    find "$TEMP_DIR" -type f -name "*.bat" -exec bash -c 'parse_test_bat "$0"' {} \; | tee "$LOG_FILE"
    cleanup

# Just parse rules
else
    echo -e "\nParsing rules..."
    echo "1. Please set \`NFQWS_ENABLE\` in zapret.conf to \`1\`"
    echo "2. Please set \`NFQWS_PORTS_TCP\` in zapret.conf to \`80,443,2053,2083,2087,2096,8443,1024-65535\`"
    echo "3. Please set \`NFQWS_PORTS_UDP\` in zapret.conf to \`443,1024-65535,19294-19344,50000-50100\`"
    echo "4. Copy parsed value of \`NFQWS_OPT\` from some script below into \`NFQWS_OPT\` in zapret.conf"
    echo -e "--------------------------------------------------------------------------------\n"
    export ZAPRET_DIR_INT="$ZAPRET_DIR_INT"
    export git_head="$git_head"
    export -f parse_bat
    find "$TEMP_DIR" -type f -name "*.bat" -exec bash -c 'parse_bat "$0"' {} \; | tee "$LOG_FILE"
    echo "--------------------------------------------------------------------------------"
fi

# Delete repo
rm -rf "$TEMP_DIR"
