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

# This script downloads and parses .bat strategies from strategies-converter-tester_strategies.txt,
# converts them and tests if requested (see below)

_arg_1="${1#-}"
_arg_1="${_arg_1#-}"
if [[ "$_arg_1" == "test" ]]; then _test=true; else _test=false; fi

STRATEGIES_FILE=${STRATEGIES_FILE:-"strategies.txt"}
LISTS_FILE=${LISTS_FILE:-"lists.txt"}

BASE_DIR=${BASE_DIR:-"./strategies-converter-tester"}
STRATEGIES_DIR=${STRATEGIES_DIR:-"$BASE_DIR/strategies"}
LISTS_DIR=${LISTS_DIR:-"$BASE_DIR/lists"}

TEST_URL=${TEST_URL:-"https://youtube.com"}

LOG_FILE="strategies-converter-tester.log"

ZAPRET_DIR_INT="/opt/zapret"
ZAPRET_CONFIG=${ZAPRET_CONFIG:-"configs/zapret.conf"}
TEST_CONFIG=${TEST_CONFIG:-"configs/zapret.conf.test"}
RELOAD_SCRIPT=${RELOAD_SCRIPT:-"reload.sh"}

if [[ "$_arg_1" == "help" ]] || [[ $_test == false ]]; then
    echo "You can specify optional [test] argument to this script."
    echo "Usage: $(basename $0) [test]"
    echo -e "  test, -test, --test\ttest each strategy after parsing. Test URL can be specified"
    echo -e "\t\t\tusing TEST_URL environment variable"
    echo ""
fi
echo "Environment variables:"
echo "  \$STRATEGIES_FILE=$STRATEGIES_FILE"
echo "  \$LISTS_FILE=$LISTS_FILE"
echo ""
echo "  \$BASE_DIR=$BASE_DIR"
echo "  \$STRATEGIES_DIR=$STRATEGIES_DIR"
echo "  \$LISTS_DIR=$LISTS_DIR"
echo ""
echo "  \$TEST_URL=$TEST_URL"
echo ""
echo "  \$LOG_FILE=$LOG_FILE"
echo ""
echo "  \$ZAPRET_DIR_INT=$ZAPRET_DIR_INT"
echo "  \$ZAPRET_CONFIG=$ZAPRET_CONFIG"
echo "  \$TEST_CONFIG=$TEST_CONFIG"
echo "  \$RELOAD_SCRIPT=$RELOAD_SCRIPT"
if [[ "$_arg_1" == "help" ]]; then exit 0; fi
echo ""

# Reads lists file and converts into value for --hostlist-domains= / --ipset-ip= arguments
# Args:
#   1: Path to list file inside $LISTS_DIR
expand_list_file() {
    local file="$1"

    # Remove %LISTS% prefix
    file="${file//%LISTS%/}"

    # Read file safely
    if [[ ! -f "$LISTS_DIR/$file" ]]; then
        echo ""
        return
    fi

    # Convert lines into comma-separated + ignore empty / comments + trim empty lines
    # paste -sd"," "$LISTS_DIR/$file" | grep -v "^\s*$" | grep -v "^\s*#" | sed 's/,,*/,/g; s/^,//; s/,$//'
    grep -vE '^\s*(#|$)' "$LISTS_DIR/$file" | sed -z 's/\r//g' | paste -sd "," -
}

# Parses NFQWS_OPT from .bat file
# Args:
#   1: Path to .bat file
parse_bat() {
    local bat_path="$1"

    # Remove ending ^
    local cleaned=$(sed ':a;N;$!ba;s/\^/ /g' "$bat_path")

    # Extract lines with --filter-
    local lines=$(echo "$cleaned" | grep -oP -- '--filter-[^\n]+')

    # Exit if no strategy found
    if [ -z "$lines" ]; then exit 0; fi

    # Replace %GameFilter%
    lines=$(echo "$lines" | sed "s|=%GameFilter%|=1024-65535|g" | sed "s|,%GameFilter%|,1024-65535|g")
    lines=$(echo "$lines" | sed "s|=%GameFilterTCP%|=1024-65535|g" | sed "s|,%GameFilterTCP%|,1024-65535|g")
    lines=$(echo "$lines" | sed "s|=%GameFilterUDP%|=1024-65535|g" | sed "s|,%GameFilterUDP%|,1024-65535|g")

    # # Replace --ipset="%LISTS%ipset-all.txt" with <HOSTLIST>
    # lines=$(echo "$lines" | sed "s|--ipset=\"%LISTS%ipset-all.txt\"|<HOSTLIST>|g")

    # # Replace --ipset="%LISTS%list-general.txt" with <HOSTLIST>
    # lines=$(echo "$lines" | sed "s|--ipset=\"%LISTS%list-general.txt\"|<HOSTLIST>|g")

    # # Replace --hostlist="%LISTS%list-general.txt" with <HOSTLIST>
    # lines=$(echo "$lines" | sed "s|--hostlist=\"%LISTS%list-general.txt\"|<HOSTLIST>|g")

    # Replace --hostlist-auto="%LISTS%hostlist-auto.txt" with <HOSTLIST>
    lines=$(echo "$lines" | sed "s|--hostlist-auto=\"%LISTS%hostlist-auto.txt\"|<HOSTLIST>|g")

    # Proper lists replacement with expanding
    # 1. Read each line -> loop through arguments
    # 2. If arguments contains list -> check if file exists -> expand it, if not, remove argument entirely, except for
    # --hostlist and --ipset, replace then with <HOSTLIST> placeholder
    # 3. Keep other arguments intact
    local lines_lists_replaced=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local line_rebuilt=""

        for arg in $line; do
            # hostlist
            if [[ "$arg" =~ ^--hostlist=\"%LISTS%([^\"]+)\"$ ]]; then
                file="${BASH_REMATCH[1]}"
                list="$(expand_list_file "$file")"
                if [[ -n "$list" ]]; then
                    line_rebuilt+=" --hostlist-domains=$list"
                elif [[ "$line_rebuilt" != *"<HOSTLIST>"* ]]; then
                    line_rebuilt+=" <HOSTLIST>"
                fi
                continue
            fi

            # hostlist-exclude
            if [[ "$arg" =~ ^--hostlist-exclude=\"%LISTS%([^\"]+)\"$ ]]; then
                file="${BASH_REMATCH[1]}"
                list="$(expand_list_file "$file")"
                if [[ -n "$list" ]]; then
                    line_rebuilt+=" --hostlist-exclude-domains=$list"
                fi
                continue
            fi

            # ipset
            if [[ "$arg" =~ ^--ipset=\"%LISTS%([^\"]+)\"$ ]]; then
                file="${BASH_REMATCH[1]}"
                list="$(expand_list_file "$file")"
                if [[ -n "$list" ]]; then
                    line_rebuilt+=" --ipset-ip=$list"
                elif [[ "$line_rebuilt" != *"<HOSTLIST>"* ]]; then
                    line_rebuilt+=" <HOSTLIST>"
                fi
                continue
            fi

            # ipset-exclude
            if [[ "$arg" =~ ^--ipset-exclude=\"%LISTS%([^\"]+)\"$ ]]; then
                file="${BASH_REMATCH[1]}"
                list="$(expand_list_file "$file")"
                if [[ -n "$list" ]]; then
                    line_rebuilt+=" --ipset-exclude-ip=$list"
                fi
                continue
            fi

            # Unchanged
            line_rebuilt+=" $arg"

        done

        # Append without leading space + keep new line
        lines_lists_replaced+="${line_rebuilt# }"$'\n'

    done <<<"$lines"
    lines="$lines_lists_replaced"

    # Replace %BIN%
    lines=$(echo "$lines" | sed "s|%BIN%|$ZAPRET_DIR_INT/files/fake/|g")

    # Trim trailing spaces from all lines
    lines=$(echo "$lines" | sed 's/[[:space:]]\+$//')

    # Replace double spaces
    lines=$(echo "$lines" | sed 's/  */ /g')

    # If last line ends with --new, remove it
    lines=$(echo "$lines" | sed '$s/ --new$//')

    # Output final result
    if [ "$_test" == true ]; then
        echo "${lines}"
    else
        echo "# Parsed from $(basename "$bat_path") @ $(date +"%Y-%m-%d %H:%M")"
        echo -e "NFQWS_OPT='\n${lines}\n'\n"
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

    # Rewrite NFQWS_OPT without new $lines
    nfqws_opt="${nfqws_opt//$'\n'/$' '}"

    # Write test config
    echo "Writing test config -> $ZAPRET_CONFIG"
    config=$(sed 's|{NFQWS_OPT_PLACEHOLDER}|'"${nfqws_opt}"'|' "$TEST_CONFIG")
    echo "$config" | tee "$ZAPRET_CONFIG" >/dev/null

    # Reload and wait
    echo "Calling reload script..."
    bash "$RELOAD_SCRIPT" >/dev/null

    # Wait for zapret (nfqws) to start in 5 seconds
    for i in {1..10}; do
        nfqws_pid=$(docker exec -t zapret-sing-box-docker /usr/bin/pidof nfqws)
        if [[ -n "${nfqws_pid:-}" ]]; then
            echo "zapret started. nfqws PID: $nfqws_pid"
            break
        fi
        sleep 0.5
    done
    if [[ ! -n "${nfqws_pid:-}" ]]; then
        echo "zapret was unable to start (⊙_⊙ ) in 5s. Check strategy"
        return
    fi

    # Test
    echo "Testing $TEST_URL"
    docker exec -t zapret-sing-box-docker curl --connect-timeout 1 --max-time 3 -L "$TEST_URL" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "^^ WORKING! WORKING! WORKING! ^^"
    else
        echo "Not working ˙◠˙"
    fi
}

# Decodes URL string <https://stackoverflow.com/a/37840948>
# @guest <https://stackoverflow.com/users/6470696/guest>
# @netdesign8 <https://stackoverflow.com/users/1988310/netdesign8>
function urldecode() {
    : "${*//+/ }"
    echo -e "${_//%/\\x}"
}

# Downloads (if file starts with http) or copies strategy/list file if it not exists.
# NOTE: will call exit 1 on download error
# Args:
#   1: URL or path to file
#   2: Directory where to copy / download file
get_file() {
    local path="$1"
    local filename=$(urldecode "$path")
    filename=$(basename "$filename")
    local base_dir="$2"

    # File exists
    if [[ -f "${base_dir}/${filename}" ]]; then
        echo "${base_dir}/${filename} exists"

    # Download remote
    elif [[ "$path" =~ ^https?:// ]]; then
        echo "Downloading $path -> ${base_dir}/${filename}..."
        if ! curl --retry 3 --retry-delay 2 --retry-all-errors -f -o "${base_dir}/${filename}" -L "$path"; then
            echo "ERROR: Unable to download $path -> ${base_dir}/${filename}"
            exit 1
        fi

    # Copy local
    elif [ -f "$path" ]; then
        echo "Copying $path -> ${base_dir}/${filename} ..."
        cp "$path" "${base_dir}/${filename}"

    # Not exists or wrong path
    else
        echo "WARNING: Unknown file: $path. Ignoring it"
    fi
}

######################
# SCRIPT ENTRY POINT #
######################

# Ask to delete base directory
if [[ -e "$BASE_DIR" ]]; then
    while true; do
        read -rp "Directory $BASE_DIR exists. Delete it? [y/N] " answer </dev/tty || answer=""

        case "${answer,,}" in
        y | yes)
            echo "Deleting $BASE_DIR"
            rm -rf "$BASE_DIR"
            break
            ;;

        n | no | "")
            break
            ;;

        *)
            echo "Please answer y or n"
            ;;
        esac
    done
    echo ""
fi

# Make dirs
mkdir -p "$BASE_DIR"
mkdir -p "$STRATEGIES_DIR"
mkdir -p "$LISTS_DIR"

# Download strategies
if [ -f "$STRATEGIES_FILE" ]; then
    # Skip empty / commented lines
    grep -vE '^\s*#|^\s*$' "$STRATEGIES_FILE" | while IFS= read -r url_or_file; do
        get_file "$url_or_file" "$STRATEGIES_DIR"
    done || exit 1
else
    echo "ERROR: No $STRATEGIES_FILE file"
    exit 1
fi

# Download lists
if [ -f "$LISTS_FILE" ]; then
    # Skip empty / commented lines
    grep -vE '^\s*#|^\s*$' "$LISTS_FILE" | while IFS= read -r url_or_file; do
        get_file "$url_or_file" "$LISTS_DIR"
    done || exit 1
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
    echo "1. Set \`NFQWS_ENABLE\` in zapret.conf to \`1\`"
    echo "2. Set \`NFQWS_PORTS_TCP\` in zapret.conf to \`80,443,2053,2083,2087,2096,8443,1024-65535\`"
    echo "3. Set \`NFQWS_PORTS_UDP\` in zapret.conf to \`443,500,1701,4500,8095,2408,1024-65535,19294-19344,50000-50100\`"
    echo "4. Copy parsed value of \`NFQWS_OPT\` from some script below into \`NFQWS_OPT\` in zapret.conf"
    echo -e "--------------------------------------------------------------------------------\n"
    export LISTS_DIR ZAPRET_DIR_INT
    export _keep
    export -f expand_list_file
    export -f parse_bat
    find "$STRATEGIES_DIR" -type f -name "*.bat" -exec bash -c 'parse_bat "$0"' {} \; | tee "$LOG_FILE"
    echo "--------------------------------------------------------------------------------"
fi
