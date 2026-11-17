# 📦 zapret-sing-box-docker [warp branch]

## Docker image with zapret, dnscrypt-proxy, sing-box and usque (Cloudflare WARP implementation)

Allows you to dockerize zapret + usque + dnscrypt-proxy and access them via any proxy protocol supported by sing-box

---

## 🏗️ Installation

### 1. Install Docker

<https://docs.docker.com/engine/install/>

### 2. Clone repo

```shell
git clone -b warp https://github.com/F33RNI/zapret-sing-box-docker.git
cd zapret-sing-box-docker
```

### 3. Build image

```shell
./build.sh
```

> Edit `.env` file if needed

### 4. Edit config files

All configs are located in `configs/` dir

- sing-box official documentation: <https://sing-box.sagernet.org/configuration/>
- dnscrypt-proxy official documentation: <https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Configuration>
- zapret official documentation: <https://github.com/bol-van/zapret?tab=readme-ov-file#nfqws>
- usque official documentation: <https://github.com/Diniboy1123/usque?tab=readme-ov-file#usage>

Use provided `strategies-converter-tester.sh` script to fetch and parse windows .bat strategies from `strategies.txt`
and edit `configs/zapret.conf` accordingly

**Or you can start the container (by calling `start.sh`) and use `strategies-converter-tester.sh` with `test`**
**argument to test parsed strategies:**

```shell
# Start the container
TZ="Etc/UTC" ./start.sh

# Parse and test ALL strategies from strategies.txt using custom URL
TEST_URL="https://cp.cloudflare.com" ./strategies-converter-tester.sh test
```

> You can specify custom URLs or local filepaths to windows .bat strategies inside strategies.txt and custom lists
> (URLs or local file paths) used by them inside lists.txt

### 5. Provide ports and start the container

```shell
PORTS="127.0.0.1:2080:2080 127.0.0.1:2090:2090" TZ="Etc/UTC" ./start.sh
```

> Please see comments in the `.env` file for more info.
> NOTE: Default internal port for usque socks proxy is 2090
>
> NOTE: To start without -d / --detach arg, use  `./start.sh nd` / `./start.sh nodetach` instead

```shell
# Check zapret logs
tail -f logs/zapret.log

# Check dnscrypt-proxy logs
tail -f logs/dnscrypt-proxy.log

# Check sing-box logs
tail -f logs/sing-box.log

# Check usque logs
tail -f logs/usque.log
```

### 6. Wait a bit and test

```shell
curl --proxy "127.0.0.1:2080" --head -L https://youtube.com
```

OR

```shell
curl --proxy "127.0.0.1:2090" --head -L https://youtube.com
```

---

## ⏹️ Stopping the container

Simply run

```shell
./stop.sh rm
```

> Specify `rm` argument to this script to remove the container

---

## 🔃 Reloading configs

You can apply new config files without restarting the container. For that, simply run

```shell
./reload.sh
```

> Optionally, to see logs after reload you can run
>
> ```shell
> ./reload.sh && tail -f logs/sing-box.log
> ```

---

## 🧱 Blockcheck

Simply start the container and run

```shell
./blockcheck.sh
```

So

```shell
./start.sh
# Wait a few seconds
./blockcheck.sh
```

Output will be written into `logs/blockcheck.log`

To edit domains, use `DOMAINS` environment variable:

```shell
DOMAINS="cloudflare.com" ./blockcheck.sh
```

---

## ⛺ Local dnscrypt-proxy resolvers and relays

If you want to store cached dnscrypt-proxy resolvers and relays outside the container (e.g. if github is blocked)

1. Provide absolute local paths to `public-resolvers.md`, `relays.md`, `public-resolvers.minisig` and
    `relays.md.minisig` in `dnscrypt-proxy_local_sources.patch`

2. Apply patch:

    ```shell
    git apply dnscrypt-proxy_local_sources.patch
    ```

---

## 🐧 Linux service **(example)**

`/lib/systemd/system/zapret-sing-box-docker.service`

```ini
[Unit]
Description=zapret-sing-box-docker service
After=docker.service network-online.target
Requires=docker.service network-online.target multi-user.target

[Service]
Type=simple
WorkingDirectory=/path/to/zapret-sing-box-docker
Environment=PORTS="0.0.0.0:2080:2080" TZ="Etc/UTC"
ExecStartPre=/usr/bin/sleep 5
ExecStart=/path/to/zapret-sing-box-docker/start.sh nd
ExecStop=/path/to/zapret-sing-box-docker/stop.sh rm
ExecReload=/path/to/zapret-sing-box-docker/reload.sh
Restart=no
User=your-user-name
Group=your-user-name

[Install]
WantedBy=multi-user.target
```

```shell
sudo systemctl daemon-reload
sudo systemctl enable --now zapret-sing-box-docker.service
```

> With that service you can reload container by typing `sudo systemctl reload zapret-sing-box-docker.service`

---

## 🌲 Dependencies and credits

- <https://github.com/bol-van/zapret> 💜
- <https://github.com/DNSCrypt/dnscrypt-proxy> 💜
- <https://github.com/SagerNet/sing-box> 💜
- <https://github.com/Flowseal/zapret-discord-youtube> 💜
- <https://github.com/Sergeydigl3/flowseal-strategies-backup> 💜
- <https://github.com/MAKAKAIglitch/zapret-discord-youtube-warp/> 💜
- <https://github.com/Diniboy1123/usque/> 💜
