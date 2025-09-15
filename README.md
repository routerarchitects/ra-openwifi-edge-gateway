# OpenWiFi (x86) — Build → Push to Docker Hub → Run with systemd
---

##  Prerequisites

```bash
sudo apt update
sudo apt install -y \
  build-essential libncurses5-dev gawk git libssl-dev gettext zlib1g-dev \
  swig unzip time rsync python3 python3-setuptools python3-yaml \
  docker.io docker-compose tree curl

sudo usermod -aG docker $USER
# Re-login (or reboot) so your user can run docker without sudo
```

---

##  Build OpenWiFi x86 rootfs and create Docker image

```bash
mkdir -p ~/OPENWIFI_WLANAP && cd ~/OPENWIFI_WLANAP
git clone https://github.com/routerarchitects/ra-openwifi-wlan-ap.git
cd ra-openwifi-wlan-ap
```

Checkout the required branch:

```bash
git checkout release/v3.1.0
```

Build the image:

```bash
./build.sh x64_vm
```

## Clone this repository

```bash
mkdir -p ~/WORKSPACE && cd ~/WORKSPACE
git clone <this-repo-url> OPENWIFI-X86
```

##  Build the image
After build completes, create a Docker image from the produced rootfs:

```bash
cd ~/OPENWIFI_WLANAP/ra-openwifi-wlan-ap/openwrt/build_dir/target-x86_64_musl/root-x86/
cp ~/WORKSPACE/OPENWIFI-X86/Dockerfile .
sudo docker build --network host -t openwifi-x86:latest .
```

---

##  Push image to public Docker Hub

```bash
docker login
# If you built with a different local name, retag:
# docker tag openwifi-x86:latest <your-dockerhub-username>/openwifi-x86:latest
docker push <your-dockerhub-username>/openwifi-x86:latest
```

Verify on [https://hub.docker.com/](https://hub.docker.com/) that your repository is **public**.

---

## Prepare host: persistent NIC names

Create two `.link` files with your **physical NIC MAC addresses**:

```bash
sudo tee /etc/systemd/network/10-usb-ether.link >/dev/null <<'EOF'
[Match]
Type=ether
MACAddress=<USB-ETHERNET-MAC>

[Link]
Name=eth1
EOF

sudo tee /etc/systemd/network/20-ether-pci.link >/dev/null <<'EOF'
[Match]
Type=ether
MACAddress=<ONBOARD-ETHERNET-MAC>

[Link]
Name=eth0
EOF
```

**Important:** Replace `<USB-ETHERNET-MAC>` and `<ONBOARD-ETHERNET-MAC>` with the actual MAC addresses of your physical interfaces.  

Find the MAC addresses using:

```bash
ip link show
```

Edit MAC addresses:

```bash
sudo vi /etc/systemd/network/10-usb-ether.link
sudo vi /etc/systemd/network/20-ether-pci.link
```

---

Create Docker daemon config to avoid iptables conflicts:

```bash
sudo vim /etc/docker/daemon.json
```

Paste the following:

```json
{
  "iptables": false
}
```

Reboot to apply:

```bash
sudo reboot
```

---

##Copy your certificate and gateway files into the `~/WORKSPACE/OPENWIFI-X86/certs/` directory:

**Important:** certificate COMMON NAME should be same as mac address of eth0 interface.

```bash
cd ~/WORKSPACE/OPENWIFI-X86
cp ~/Path_to_certificate/cert.pem certs/
cp ~/Path_to_certificate/key.pem certs/
cp ~/Path_to_certificate/cas.pem certs/
cp ~/Path_to_certificate/gateway.json certs/
```

Edit `docker-compose/docker-compose.yml` and update the Docker Hub username:

```bash
vim docker-compose/docker-compose.yml
# Replace the image line with your Docker Hub username:
# image: <your-dockerhub-username>/openwifi-x86:latest
# Replace the name of username in /home/<username>/WORKSPACE/OPENWIFI-X86/ with username of your hostmachine.
```

(Optional) Verify `gateway.json` example format:

```json
{"server":"openwifi1.routerarchitects.com","port":15002}
```

---

## Install systemd service (Step 5)

Copy the systemd service into place:

```bash
sudo cp scripts/openwifi-compose.service /etc/systemd/system/openwifi-compose.service
```

**Important:** Open the service file with `sudo` and change the absolute path to match your host username and home directory.

```bash
sudo vim /etc/systemd/system/openwifi-compose.service
```

Update these lines (replace `<your-username>` with your ubuntu's username and `<dockerhub-username>` with your docker-username):

```
ConditionPathExists=/home/<your-username>/WORKSPACE/OPENWIFI-X86/docker-compose/docker-compose.yml
WorkingDirectory=/home/<your-username>/WORKSPACE/OPENWIFI-X86/docker-compose
```

> Note: If your system only has the Docker **Compose v2 plugin** (`docker compose`), edit the Exec lines in the service to use `docker compose` instead of `docker-compose`.

Reload and enable the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable openwifi-compose.service #enable for starting at boot
sudo systemctl start openwifi-compose.service
systemctl status openwifi-compose.service
```

The unit will:

* Start the container with Docker Compose  
* Set `/etc/resolv.conf` → `127.0.0.1` while running  
* Restore `/etc/resolv.conf` → `127.0.0.53` when stopped  

---

##  Repo Layout

```
OPENWIFI-X86/
├── certs/
│   ├── cas.pem
│   ├── cert.pem
│   ├── key.pem
│   └── gateway.json
├── docker-compose/
│   └── docker-compose.yml
├── Dockerfile
├── README.md
└── scripts/
    ├── openwifi-compose.service
    └── openwifi-health.sh
```

