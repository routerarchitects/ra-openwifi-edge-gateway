#!/bin/sh
# Healthcheck for host-networked, privileged container
# Checks: default route, ping to Internet, HTTPS fetch, DNS, free disk space

MIN_FREE_MB="${MIN_FREE_MB:-500}"   # set via env if you want (default 500 MB)
CHECK_PATH="${CHECK_PATH:-/}"       # path to check disk space (usually /)

fail() { echo "[health] $1" >&2; exit 1; }

# 1) Default route present (gateway can be anything)
ip route show default | grep -q "^default " || fail "no default route"

# 2) Raw Internet reachability (no DNS)
ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || \
ping -c1 -W2 8.8.8.8  >/dev/null 2>&1 || \
fail "no ICMP reachability to Internet"

# 3) DNS works (resolve a common domain)
getent hosts google.com >/dev/null 2>&1 || \
nslookup google.com >/dev/null 2>&1 || \
fail "DNS resolution failed"

# 4) HTTPS reachability (204 page; very lightweight)
# Requires curl in the image. If not present, install it or switch to wget --spider
curl -fsS --max-time 5 "https://connectivitycheck.gstatic.com/generate_204" >/dev/null 2>&1 || \
curl -fsS --max-time 5 "https://www.google.com/generate_204" >/dev/null 2>&1 || \
fail "HTTPS reachability failed"

# 5) Free disk space check on CHECK_PATH
FREE_MB="$(df -Pk "$CHECK_PATH" | awk 'NR==2 {print $4}')"
# df -Pk prints KB in column 4; convert to MB (round down)
FREE_MB=$(( FREE_MB / 1024 ))
[ "$FREE_MB" -ge "$MIN_FREE_MB" ] || fail "low disk: ${FREE_MB}MB < ${MIN_FREE_MB}MB on $CHECK_PATH"

echo "[health] ok: route+icmp+dns+https+disk(${FREE_MB}MB free)"
exit 0

