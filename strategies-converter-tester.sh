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

# This script downloads and parses .bat strategies from strategies-converter-tester_strategies.txt,
# converts them and tests if requested (see below)
# ----> SPECIFY test ARGUMENT TO THIS SCRIPT TO TEST EACH OPTION <----
if [ "$1" = "test" ]; then _test=true; fi

STRATEGIES_FILE=${STRATEGIES_FILE:-"strategies-converter-tester_strategies.txt"}
LISTS_FILE=${LISTS_FILE:-"strategies-converter-tester_lists.txt"}

TEMP_DIR=${TEMP_DIR:-"./strategies-converter-tester_tmp"}
STRATEGIES_DIR=${STRATEGIES_DIR:-"$TEMP_DIR/strategies"}
LISTS_DIR=${LISTS_DIR:-"$TEMP_DIR/lists"}

TEST_URL=${TEST_URL:-"https://youtube.com"}

LOG_FILE="strategies-converter-tester.log"

ZAPRET_DIR_INT="/opt/zapret"
ZAPRET_CONFIG=${ZAPRET_CONFIG:-"configs/zapret.conf"}
TEST_CONFIG=${TEST_CONFIG:-"configs/zapret.conf.test"}
RELOAD_SCRIPT=${RELOAD_SCRIPT:-"reload.sh"}

# Reads lists file and converts into value for --hostlist-domains= / --ipset-ip= arguments
# Args:
#   1: Path to list file inside $LISTS_DIR
expand_list_file() {
    local _file="$1"

    # Remove %LISTS% prefix
    _file="${_file//%LISTS%/}"

    # Read file safely
    if [[ ! -f "$LISTS_DIR/$_file" ]]; then
        echo ""
        return
    fi

    # Convert _lines into comma-separated + ignore empty / comments + trim empty _lines
    # paste -sd"," "$LISTS_DIR/$_file" | grep -v "^\s*$" | grep -v "^\s*#" | sed 's/,,*/,/g; s/^,//; s/,$//'
    grep -vE '^\s*(#|$)' "$LISTS_DIR/$_file" | sed -z 's/\r//g' | paste -sd "," -
}

# Parses NFQWS_OPT from .bat file
# Args:
#   1: Path to .bat file
parse_bat() {
    local bat_path="$1"

    # Remove ending ^
    local _cleaned=$(sed ':a;N;$!ba;s/\^/ /g' "$bat_path")

    # Extract lines with --filter-
    local _lines=$(echo "$_cleaned" | grep -oP -- '--filter-[^\n]+')

    # Exit if no strategy found
    if [ -z "$_lines" ]; then exit 0; fi

    # Replace %GameFilter%
    _lines=$(echo "$_lines" | sed "s|=%GameFilter%|=1024-65535|g" | sed "s|,%GameFilter%|,1024-65535|g")
    _lines=$(echo "$_lines" | sed "s|=%GameFilterTCP%|=1024-65535|g" | sed "s|,%GameFilterTCP%|,1024-65535|g")
    _lines=$(echo "$_lines" | sed "s|=%GameFilterUDP%|=1024-65535|g" | sed "s|,%GameFilterUDP%|,1024-65535|g")

    # Replace --ipset="%LISTS%ipset-all.txt" with <HOSTLIST>
    _lines=$(echo "$_lines" | sed "s|--ipset=\"%LISTS%ipset-all.txt\"|<HOSTLIST>|g")

    # Replace --ipset="%LISTS%list-general.txt" with <HOSTLIST>
    #_lines=$(echo "$_lines" | sed "s|--ipset=\"%LISTS%list-general.txt\"|<HOSTLIST>|g")

    # Proper lists replacement with expanding
    # 1. Read each line -> loop through arguments
    # 2. If arguments contains list -> check if file exists -> expand it, if not, remove argument entirely
    # 3. Keep other arguments intact
    local _lines_lists_replaced=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

        local _line_rebuilt=""

        for _arg in $_line; do
            # hostlist
            if [[ "$_arg" =~ ^--hostlist=\"%LISTS%([^\"]+)\"$ ]]; then
                _file="${BASH_REMATCH[1]}"
                _list="$(expand_list_file "$_file")"
                if [[ -n "$_list" ]]; then
                    _line_rebuilt+=" --hostlist-domains=$_list"
                fi
                continue
            fi

            # hostlist-exclude
            if [[ "$_arg" =~ ^--hostlist-exclude=\"%LISTS%([^\"]+)\"$ ]]; then
                _file="${BASH_REMATCH[1]}"
                _list="$(expand_list_file "$_file")"
                if [[ -n "$_list" ]]; then
                    _line_rebuilt+=" --hostlist-exclude-domains=$_list"
                fi
                continue
            fi

            # ipset
            if [[ "$_arg" =~ ^--ipset=\"%LISTS%([^\"]+)\"$ ]]; then
                _file="${BASH_REMATCH[1]}"
                _list="$(expand_list_file "$_file")"
                if [[ -n "$_list" ]]; then
                    _line_rebuilt+=" --ipset-ip=$_list"
                fi
                continue
            fi

            # ipset-exclude
            if [[ "$_arg" =~ ^--ipset-exclude=\"%LISTS%([^\"]+)\"$ ]]; then
                _file="${BASH_REMATCH[1]}"
                _list="$(expand_list_file "$_file")"
                if [[ -n "$_list" ]]; then
                    _line_rebuilt+=" --ipset-exclude-ip=$_list"
                fi
                continue
            fi

            # Unchanged
            _line_rebuilt+=" $_arg"

        done

        # Append without leading space + keep new line
        _lines_lists_replaced+="${_line_rebuilt# }"$'\n'

    done <<<"$_lines"
    _lines="$_lines_lists_replaced"

    # Replace %BIN%
    _lines=$(echo "$_lines" | sed "s|%BIN%|$ZAPRET_DIR_INT/files/fake/|g")

    # Trim trailing spaces from all _lines
    _lines=$(echo "$_lines" | sed 's/[[:space:]]\+$//')

    # Replace double spaces
    _lines=$(echo "$_lines" | sed 's/  */ /g')

    # If last line ends with --new, remove it
    _lines=$(echo "$_lines" | sed '$s/ --new$//')

    # Output final result
    if [ "$_test" == true ]; then
        echo "${_lines}"
    else
        echo "# Parsed from $(basename "$bat_path")"
        echo -e "NFQWS_OPT='\n${_lines}\n'\n"
    fi
}

# Parses NFQWS_OPT from .bat file and test it
# Args:
#   1: Path to .bat file
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
    echo -e "\n\nParsing and testing $(basename "$bat_path")..."
    #echo -e "NFQWS_OPT='\n${nfqws_opt}\n'"

    # Rewrite NFQWS_OPT without new _lines
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

# Downloads (if file starts with http) or copies strategy file
# Args:
#   1: URL or path to file
get_strategy_file() {
    local _strategy_path="$1"
    local _filename=$(basename "$_strategy_path")
    if [[ "$_strategy_path" =~ ^https?:// ]]; then
        echo "Downloading $_strategy_path -> ${STRATEGIES_DIR}/${_filename}..."
        curl -o "${STRATEGIES_DIR}/${_filename}" -L "$_strategy_path"
    elif [ -f "$_strategy_path" ]; then
        echo "Copying $_strategy_path -> ${STRATEGIES_DIR}/${_filename}..."
        cp "$_strategy_path" "${STRATEGIES_DIR}"
    else
        echo "WARNING: Unknown file: $_strategy_path. Ignoring it"
    fi
}

# Downloads (if file starts with http) or copies list file
# Args:
#   1: URL or path to file
get_list_file() {
    local _list_path="$1"
    local _filename=$(basename "$_list_path")
    if [[ "$_list_path" =~ ^https?:// ]]; then
        echo "Downloading $_list_path -> ${LISTS_DIR}/${_filename}..."
        curl -o "${LISTS_DIR}/${_filename}" -L "$_list_path"
    elif [ -f "$_list_path" ]; then
        echo "Copying $_list_path -> ${LISTS_DIR}/${_filename}..."
        cp "$_list_path" "${LISTS_DIR}"
    else
        echo "WARNING: Unknown file: $_list_path. Ignoring it"
    fi
}

######################
# SCRIPT ENTRY POINT #
######################

# Clear temp dir
rm -rf "$TEMP_DIR"

# Make dirs
mkdir -p "$TEMP_DIR"
mkdir -p "$STRATEGIES_DIR"
mkdir -p "$LISTS_DIR"

# Download strategies
if [ -f "$STRATEGIES_FILE" ]; then
    # Skip empty / commented lines
    grep -vE '^\s*#|^\s*$' "$STRATEGIES_FILE" | while IFS= read -r _url_or_file; do
        get_strategy_file "$_url_or_file"
    done
else
    echo "ERROR: No $STRATEGIES_FILE file"
    exit 1
fi

# Download lists
if [ -f "$LISTS_FILE" ]; then
    # Skip empty / commented lines
    grep -vE '^\s*#|^\s*$' "$LISTS_FILE" | while IFS= read -r _url_or_file; do
        get_list_file "$_url_or_file"
    done
fi

# Parse and test strategies
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

        # Clear temp dir
        rm -rf "$TEMP_DIR"

        exit 0
    }

    echo -e "\nParsing and testing strategies from $STRATEGIES_DIR..."
    export LOG_FILE LISTS_DIR ZAPRET_DIR_INT ZAPRET_CONFIG TEST_CONFIG RELOAD_SCRIPT TEST_URL
    export _test=true
    export -f expand_list_file
    export -f parse_bat
    export -f parse_test_bat
    trap cleanup SIGINT
    #find "$STRATEGIES_DIR" -type f -name "*.bat" -exec bash -c 'parse_test_bat "$0"' {} \; | tee "$LOG_FILE"
    find "$STRATEGIES_DIR" -type f -name "*.bat" -print0 | sort -Vz |
        xargs -0 -I {} bash -c 'parse_test_bat "$0"' {} | tee "$LOG_FILE"
    cleanup

# Just parse strategies
else
    echo -e "\nParsing strategies from $STRATEGIES_DIR..."
    echo "1. Please set \`NFQWS_ENABLE\` in zapret.conf to \`1\`"
    echo "2. Please set \`NFQWS_PORTS_TCP\` in zapret.conf to \`80,443,2053,2083,2087,2096,8443,1024-65535\`"
    echo "3. Please set \`NFQWS_PORTS_UDP\` in zapret.conf to \`443,1024-65535,19294-19344,50000-50100\`"
    echo "4. Copy parsed value of \`NFQWS_OPT\` from some script below into \`NFQWS_OPT\` in zapret.conf"
    echo -e "--------------------------------------------------------------------------------\n"
    export LISTS_DIR ZAPRET_DIR_INT
    export -f expand_list_file
    export -f parse_bat
    find "$STRATEGIES_DIR" -type f -name "*.bat" -exec bash -c 'parse_bat "$0"' {} \; | tee "$LOG_FILE"
    echo "--------------------------------------------------------------------------------"

    # Clear temp dir
    rm -rf "$TEMP_DIR"
fi
