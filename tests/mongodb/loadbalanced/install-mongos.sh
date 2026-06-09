#!/usr/bin/env bash
#
# Installs the tooling run.sh needs to stand up a load-balanced cluster.
#   - `mongos` (sharding router) matching the installed `mongod`, since load-balancer
#     mode is a mongos feature; a standalone mongod never returns a serviceId.
#   - `haproxy`, the load-balancer front. mongos's loadBalancerPort requires the
#     PROXY protocol header on every connection (a plain TCP forward like socat is
#     rejected), and haproxy's send-proxy-v2 emits it.
#
# Run as   sudo ./install-mongos.sh
#
# Targets the el9 MongoDB packages (what mongodb-org-server is built from on this host).

set -euo pipefail

if command -v mongod >/dev/null 2>&1; then
	if command -v mongos >/dev/null 2>&1; then
		echo "mongos already installed: $(mongos --version | head -1)"
	else
		# match mongos to the installed mongod version exactly (they must agree)
		ver="$(mongod --version | sed -n 's/.*v\([0-9][0-9.]*\).*/\1/p' | head -1)"
		[ -n "$ver" ] || { echo "could not determine mongod version" >&2; exit 1; }
		series="$(echo "$ver" | cut -d. -f1-2)"   # e.g. 7.0
		rpm="https://repo.mongodb.org/yum/redhat/9/mongodb-org/${series}/x86_64/RPMS/mongodb-org-mongos-${ver}-1.el9.x86_64.rpm"
		echo "Installing mongos ${ver} (to match mongod ${ver}):"
		echo "  ${rpm}"
		dnf install -y "$rpm"
		mongos --version | head -1
	fi
else
	echo "mongod is not installed — install mongodb-org-server first." >&2
	exit 1
fi

if command -v haproxy >/dev/null 2>&1; then
	echo "haproxy already installed: $(haproxy -v | head -1)"
else
	echo "Installing haproxy (load-balancer front, emits the PROXY protocol header):"
	dnf install -y haproxy
	haproxy -v | head -1
fi

echo
echo "Done. Now run:  ./run.sh start"
