# OpenWiFi (x86) — Build Openwifi image for edge gateway router → Push to Docker Hub → Run with systemd
---

##  Prerequisites to Build the Edge Gateway Router Image on Ubuntu (Tested on 22.04) 

```bash
sudo apt update
sudo apt install build-essential libncurses5-dev gawk git libssl-dev gettext zlib1g-dev swig unzip time rsync python3 python3-setuptools python3-yaml

```

---

## Building OpenWiFi x86 RootFS for Edge Gateway Router, Creating Docker Image, and Uploading to Docker Hub

```bash
mkdir -p ~/OPENWIFI_WLANAP && cd ~/OPENWIFI_WLANAP
git clone https://github.com/routerarchitects/ra-openwifi-wlan-ap.git
cd ra-openwifi-wlan-ap
```

Checkout the required branch:

```bash
git checkout release/v3.1.0
```

Make some adjustments to the ucentral-tools before starting the image build:

```bash
vi feeds/ucentral/ucentral-tools/Makefile
```
Update the variables with the following values:

```bash
PKG_SOURCE_URL=https://github.com/routerarchitects/ucentral-tools.git
PKG_MIRROR_HASH:=6b69ac0378d879e1a78606bc837e8f8a3d6ba8a6c53817acbcce987a639ad04d
PKG_SOURCE_PROTO:=git
PKG_SOURCE_DATE:=2025-09-29
PKG_SOURCE_VERSION:=17bd7d5574a0f62b972c40898710f04509b7cf64
```

Build the image:

```bash
./build.sh x64_vm
```

###  Build the docker image using Dockerfile 
After build completes, create a Docker image from the produced rootfs:

```bash
cd openwrt/build_dir/target-x86_64_musl/root-x86/
```
Create a Dockerfile
 
```bash
vi Dockerfile
```
Save the following data inside Dockerfile

```bash
FROM scratch
ADD . /
CMD ["/sbin/init"]
```
Build the docker image

```bash
sudo docker build --network host -t openwifi-x86:latest .
```

---

###  Push image to Docker Hub

```bash
docker login

#please change the <your-dockerhub-username> with your dockerhub username

docker tag openwifi-x86:latest <your-dockerhub-username>/openwifi-x86:latest

#example: docker tag openwifi-x86 routerarchitect123/openwifi-x86:latest

docker push <your-dockerhub-username>/openwifi-x86:latest

#example: docker push routerarchitect123/openwifi-x86:latest

```

Verify on [https://hub.docker.com/](https://hub.docker.com/) that your repository is **public**.

---

## Steps to Prepare the Host Machine for Running the Edge Gateway Docker Container

### Prerequisite: Install Docker & Docker Compose

```bash
# Update package index and install from Ubuntu repositories
sudo apt update && sudo apt install -y docker.io docker-compose
```
**Important:** If above does not work then please follow the official Docker installation guide here: https://docs.docker.com/engine/install/ubuntu/

### Prepare host: persistent NIC names

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

###  Create Docker daemon config to avoid iptables conflicts:

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

## Steps to Generate Certificates and Replace Default Files

### 1. Generate New Certificates
The process of generating certificates is identical to the method used for the Banana Pi Router.  

⚠️ **Important:**  
When creating the certificate, ensure that the **Common Name (CN)** is set to the **MAC address of the `eth0` interface** on the Edge Gateway host machine.


### 2. Replace the Default Certificate and Files

```bash
mkdir -p ~/WORKSPACE && cd ~/WORKSPACE
git clone https://github.com/routerarchitects/ra-openwifi-edge-gateway.git OPENWIFI-X86
cd ~/WORKSPACE/OPENWIFI-X86
cp ~/Path_to_certificate/cert.pem certs/
cp ~/Path_to_certificate/key.pem certs/
cp ~/Path_to_certificate/cas.pem certs/
cp ~/Path_to_certificate/gateway.json certs/
```

Verify `gateway.json` example format:

```json
{"server":"openwifi1.routerarchitects.com","port":15002}
```
⚠️ **Note:**  
The configuration must include the **OpenWiFi Controller’s hostname and port number** in order to connect.

Edit `docker-compose/docker-compose.yml` and update the Docker Hub username:

```bash
vim docker-compose/docker-compose.yml

# Update the image line with your Docker Hub username:
# image: <your-dockerhub-username>/openwifi-x86:latest
# Example:
# image: routerarchitect123/openwifi-x86:latest

# Also update the path by replacing <username> with your host machine's username:
# /home/<username>/WORKSPACE/OPENWIFI-X86/
# Example:
# /home/ubuntu/WORKSPACE/OPENWIFI-X86/

```

---

## Install systemd service on Edge Gateway Router

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
# Replace <your-username> with your Ubuntu username
# Replace <dockerhub-username> with your Docker Hub username

ConditionPathExists=/home/<your-username>/WORKSPACE/OPENWIFI-X86/docker-compose/docker-compose.yml
WorkingDirectory=/home/<your-username>/WORKSPACE/OPENWIFI-X86/docker-compose
ExecStartPre=docker pull <dockerhub-username>/openwifi-x86:latest

# Example (Ubuntu username: 'ubuntu', Docker Hub username: 'routerarchitect123')
ConditionPathExists=/home/ubuntu/WORKSPACE/OPENWIFI-X86/docker-compose/docker-compose.yml
WorkingDirectory=/home/ubuntu/WORKSPACE/OPENWIFI-X86/docker-compose
ExecStartPre=docker pull routerarchitect123/openwifi-x86:latest 
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
├── README.md
└── scripts/
    ├── openwifi-compose.service
    └── openwifi-health.sh
```
