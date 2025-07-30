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

REPO_URL="https://github.com/Flowseal/zapret-discord-youtube.git"
TEMP_DIR="zapret-discord-youtube_temp"
ZAPRET_DIR_INT="/opt/zapret"

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
    echo "# Parsed from $(basename "$bat_path") (Flowseal/zapret-discord-youtube @ $git_head)"
    echo -e "NFQWS_OPT='\n${filtered_lines}\n'\n"
}

# Clone repo
if [ -d "$TEMP_DIR" ]; then
    echo "$TEMP_DIR already exists! Deleting..."
    rm -rf "$TEMP_DIR"
fi
git clone "$REPO_URL" "$TEMP_DIR"

# Save repo version for comments
git_head=$(git -C "$TEMP_DIR" rev-parse --short HEAD)

# Parse rules
echo -e "\nParsing rules..."
echo "1. Please set \`NFQWS_ENABLE\` in zapret.conf to \`1\`"
echo "2. Please set \`NFQWS_PORTS_TCP\` in zapret.conf to \`80,443\`"
echo "3. Please set \`NFQWS_PORTS_UDP\` in zapret.conf to \`443,50000-50100\`"
echo "4. Copy parsed value of \`NFQWS_OPT\` from some script below into \`NFQWS_OPT\` in zapret.conf"
echo -e "--------------------------------------------------------------------------------\n"
export ZAPRET_DIR_INT="$ZAPRET_DIR_INT"
export git_head="$git_head"
export -f parse_bat
find "$TEMP_DIR" -type f -name "*.bat" -exec bash -c 'parse_bat "$0"' {} \; | tee "$LOG_FILE"
echo "--------------------------------------------------------------------------------"

# Delete repo
rm -rf "$TEMP_DIR"
