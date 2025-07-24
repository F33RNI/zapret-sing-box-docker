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

# This script downloads sing-box, zapret and dnscrypt-proxy, builds image and starts container (provide start argument)
# NOTE: This script must ONLY be executed OUTSIDE the container

_VERSION="1.0.dev"

# Print some cool looking ascii art :)
echo "                ,                     .               .      .        "
echo "__. _.._ ._. _ -+- ___  __*._  _  ___ |_  _ \\./ ___  _| _  _.;_/ _ ._."
echo " /_(_][_)[  (/, |      _) |[ )(_]     [_)(_)/'\\     (_](_)(_.| \\(/,[  "
echo "      |                       ._|                                     "
echo -e "\nVersion: $_VERSION\n"

# Specify start argument to this script to start the container after build
if [ "$1" = "start" ]; then _start=true; fi

# Checks if command exists and exists it not
# Args:
#   1: Command to check
check_command() {
    echo "Checking $1"
    if ! command -v $1 2>&1 >/dev/null; then
        echo "ERROR: $1 could not be found"
        exit 1
    fi
}

# Check requirements
check_command source
check_command uname
check_command readlink
check_command curl
check_command tar
check_command unzip
check_command docker
#check_command docker-compose

# Load environment variables and perform basic check
source .env
if [ -z "$DOCKERFILE" ] ||
    [ -z "$TAG_NAME" ] ||
    [ -z "$PORTS" ] ||
    [ -z "$LOGS_DIR" ] ||
    [ -z "$DNSCRYPT_CONFIG_FILE" ] ||
    [ -z "$SING_BOX_CONFIG_FILE" ] ||
    [ -z "$ZAPRET_CONFIG_FILE" ] ||
    [ -z "$LISTS_DIR" ] ||
    [ -z "$DNSCRYPT_DIR" ] ||
    [ -z "$SING_BOX_DIR" ] ||
    [ -z "$ZAPRET_DIR" ] ||
    [ -z "$_CONFIGS_DIR_INT" ] ||
    [ -z "$_LISTS_DIR_INT" ] ||
    [ -z "$_LOGS_DIR_INT" ]; then
    echo "ERROR: Some environment variables are empty / not specified"
    exit 1
fi

# Platform and architecture for programs
# See <https://github.com/DNSCrypt/dnscrypt-proxy/releases/latest>
# and <https://github.com/SagerNet/sing-box/releases/latest> for more info
#
# You can specify them as environment variables PLATFORM, DNSCRYPT_ARCH, SING_BOX_ARCH
if [ -z "$PLATFORM" ]; then PLATFORM="linux"; fi
if [ -z "$DNSCRYPT_ARCH" ] || [ -z "$SING_BOX_ARCH" ]; then
    arch_=$(uname -m)
    case "$arch_" in
    x86_64)
        _dnscrypt_arch="x86_64"
        _sing_box_arch="amd64"
        ;;
    i686 | i386)
        _dnscrypt_arch="x86"
        _sing_box_arch="386"
        ;;
    aarch64 | arm64 | armv8*)
        _dnscrypt_arch="arm64"
        _sing_box_arch="arm64"
        ;;
    arm* | sa110*)
        _dnscrypt_arch="arm"
        _sing_box_arch="armv7"
        ;;
    *)
        echo "Unknown architecture: $arch_"
        exit 1
        ;;
    esac
    if [ -z "$DNSCRYPT_ARCH" ]; then DNSCRYPT_ARCH="$_dnscrypt_arch"; fi
    if [ -z "$SING_BOX_ARCH" ]; then SING_BOX_ARCH="$_sing_box_arch"; fi
fi
echo "Working on $PLATFORM platform. dnscrypt-proxy target architecture: $DNSCRYPT_ARCH, sing-box: $SING_BOX_ARCH"

# Checks if config file doesn't exist and tries to copy .example config / downloaded config file. Note: existing
#  .example file will be prioritized
# Args:
#   1: Path to existing config file (in download asset) or empty to ignore it
#   2: Path to expected config file
check_copy_config_file() {
    local built_in_config="$1"
    local config_file="$2"

    if [ ! -f "$config_file" ] && [ ! -f "${config_file}.example" ] && [[ -z "$built_in_config" || ! -f "$built_in_config" ]]; then
        echo "ERROR: No config file $config_file or ${config_file}.example"
        exit 1
    elif [ ! -f "$config_file" ]; then
        if [ -f "${config_file}.example" ]; then
            echo "WARNING: File $config_file doesn't exist. Copying example one (${config_file}.example)"
            cp "${config_file}.example" "$config_file"
        else
            echo "WARNING: File $config_file doesn't exist. Copying $built_in_config"
            cp "$built_in_config" "$config_file"
        fi

    fi
}

# Wrapper that checks and downloads program
# Args:
#   1: Path to target directory (asset will be unpacked into it)
#   2: Link to asset (.tar.gz or .zip)
#   3: Latest tag name for simple version checking (grep -oP '"tag_name": "\K.*?(?=")')
check_download() {
    local target_dir="$1"
    local download_url="$2"
    local latest_tag_name="$3"

    # Debug arguments
    echo "$download_url @ $latest_tag_name -> $target_dir"

    # Directory and version file exist, and it's the latest version
    if [ -d "$target_dir" ] && [ -f "$target_dir/tag_name.txt" ] && grep -q "$latest_tag_name" "$target_dir/tag_name.txt"; then
        echo "Skipping $target_dir ($latest_tag_name already exists)"
        return
    fi

    # Check download link
    if [ -z "$download_url" ]; then
        echo "ERROR: No download URL for $target_dir (check platform and architecture)"
        exit 1
    fi

    # Delete existing dir
    if [ -d "$target_dir" ]; then
        echo "The downloaded $target_dir is either not the latest version or doesn't contain a version tag. Deleting"
        rm -rf "$target_dir"
    fi

    # Download and check
    local download_filename=$(basename "$download_url")
    echo -e "\nDownloading $download_url"
    curl --output "$download_filename" --location "$download_url"
    if [ ! -f "$download_filename" ]; then
        echo "ERROR: Unable to download $download_filename"
        exit 1
    fi

    # Extract and check
    if [[ "$download_filename" == *.zip ]]; then
        echo "Unzipping into $target_dir using unzip command"
        unzip "$download_filename" -d "$target_dir"
    else
        echo "Extracting into $target_dir using tar command"
        mkdir -p "$target_dir"
        if ! tar -xvzf "$download_filename" -C "$target_dir" --strip-components 1; then
            tar xvzf "$download_filename" -C "$target_dir" --strip-components 1
        fi
    fi
    if [ -z "$(ls -A $target_dir)" ]; then
        echo "ERROR: Unable to extract $download_filename"
        exit 1
    fi

    # Delete archive
    echo "Deleting archive $download_filename"
    rm "$download_filename"

    # Write latest tag name
    echo "$latest_tag_name" >"$target_dir/tag_name.txt"

    echo "$target_dir downloaded successfully"
}

# ################# #
# Download programs #
# ################# #

# Download dnscrypt-proxy
release_json=$(curl -s https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest)
download_url=$(echo "$release_json" | grep -oP '"browser_download_url": "\K.*?\.tar\.gz(?=")' | grep -oE ".*dnscrypt-proxy-${PLATFORM}_${DNSCRYPT_ARCH}-.*\.tar\.gz")
latest_tag_name=$(echo "$release_json" | grep -oP '"tag_name": "\K.*?(?=")')
check_download "$DNSCRYPT_DIR" "$download_url" "$latest_tag_name"

# Download sing-box
release_json=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest)
download_url=$(echo "$release_json" | grep -oP '"browser_download_url": "\K.*?\.tar\.gz(?=")' | grep -oE ".*sing-box-.*-${PLATFORM}-${SING_BOX_ARCH}\.tar\.gz")
latest_tag_name=$(echo "$release_json" | grep -oP '"tag_name": "\K.*?(?=")')
check_download "$SING_BOX_DIR" "$download_url" "$latest_tag_name"

# Download zapret
release_json=$(curl -s https://api.github.com/repos/bol-van/zapret/releases/latest)
download_url=$(echo "$release_json" | grep -oP '"browser_download_url": "\K.*?\.tar\.gz(?=")' | grep -v "openwrt")
latest_tag_name=$(echo "$release_json" | grep -oP '"tag_name": "\K.*?(?=")')
check_download "$ZAPRET_DIR" "$download_url" "$latest_tag_name"

# ########### #
# Build image #
# ########### #

# Make sure container is stopped
echo "Stopping and removing old containers"
./stop.sh rm

# Check config files and copy .example if not exists
check_copy_config_file "$DNSCRYPT_DIR/example-dnscrypt-proxy.toml" "$DNSCRYPT_CONFIG_FILE"
check_copy_config_file "" "$SING_BOX_CONFIG_FILE"
check_copy_config_file "$ZAPRET_DIR/config.default" "$ZAPRET_CONFIG_FILE"

# Build the image
echo -e "\nBuilding image"
if ! docker build \
    --force-rm --progress=plain \
    --build-arg DNSCRYPT_DIR="$DNSCRYPT_DIR" \
    --build-arg SING_BOX_DIR="$SING_BOX_DIR" \
    --build-arg ZAPRET_DIR="$ZAPRET_DIR" \
    --build-arg _CONFIGS_DIR_INT="$_CONFIGS_DIR_INT" \
    --build-arg _LOGS_DIR_INT="$_LOGS_DIR_INT" \
    --tag="f33rni/zapret-sing-box-docker:$TAG_NAME" \
    --file "$DOCKERFILE" .; then
    echo -e "\nERROR: Build finished with error"
    exit 1
fi

# Exit it user not asked to start the container
if [ "$_start" != true ]; then
    echo -e "\nDone! Run ./start.sh script to start the container"
    exit 0
fi

# Start it
./start.sh
