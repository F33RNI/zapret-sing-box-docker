# 📦 zapret-sing-box-docker

## Docker image with zapret, dnscrypt-proxy and sing-box

Allows you to dockerize zapret + dnscrypt-proxy and access them via any proxy protocol supported by sing-box

> Based on <https://github.com/F33RNI/zapret-v2ray-docker> [deprecated]

---

### 🏗️ Installation

#### 1. Install Docker

<https://docs.docker.com/engine/install/>

#### 2. Clone repo

```shell
git clone https://github.com/F33RNI/zapret-sing-box-docker.git
cd zapret-sing-box-docker
```

#### 3. Build image

```shell
./build.sh
```

> Edit `.env` file if needed

#### 4. Edit config files

All configs are located in `configs/` dir

Use provided `zapret-discord-youtube-rules-converter.sh` script to fetch and parse rules from
<https://github.com/Flowseal/zapret-discord-youtube> and edit `configs/zapret.conf` accordingly

#### 5. Provide ports and start the container

```shell
PORTS="127.0.0.1:2080:2080" TZ="Etc/UTC" ./start.sh
```

> Please see comments in the `.env` file for more info
>
> NOTE: To start without -d / --detach arg, use  `./start.sh nd` / `./start.sh nodetach` instead

```shell
# Check zapret logs
tail -f logs/zapret.log

# Check dnscrypt-proxy logs
tail -f logs/dnscrypt-proxy.log

# Check sing-box logs
tail -f logs/sing-box.log
```

#### 6. Wait a bit and test

```shell
curl --proxy "127.0.0.1:2080" --head -L https://youtube.com
```

---

### ⏹️ Stop the container

Simply run

```shell
./stop.sh rm
```

> Specify `rm` argument to this script to remove the container

---

### 🔃 Reload configs

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

### 🧱 Blockcheck

Simply start the container and run

```shell
`./blockcheck.sh`
```

So

```shell
./start.sh
# Wait a few seconds
./blockcheck.sh
```

Output will be written into `logs/blockcheck.log`

To edit domains, add `DOMAINS` variable to the `.env` file and run `./build.sh` script again

---

### 🐧 Linux service (example)

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
Restart=on-failure
RestartSec=5
User=your-user-name
Group=your-user-name

[Install]
WantedBy=multi-user.target
```

```shell
sudo systemctl daemon-reload
sudo systemctl enable --now zapret-sing-box-docker.service
```

---

### 🌲 Dependencies

- <https://github.com/bol-van/zapret>
- <https://github.com/DNSCrypt/dnscrypt-proxy>
- <https://github.com/SagerNet/sing-box>
- <https://github.com/Flowseal/zapret-discord-youtube>
