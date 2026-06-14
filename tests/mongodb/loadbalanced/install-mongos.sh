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
# Installs from the GPG-checked MongoDB yum repo, detecting the RHEL major version and arch.

set -euo pipefail

if command -v mongod >/dev/null 2>&1; then
	if command -v mongos >/dev/null 2>&1; then
		echo "mongos already installed: $(mongos --version | head -1)"
	else
		# match mongos to the installed mongod version exactly (they must agree)
		ver="$(mongod --version | sed -n 's/.*v\([0-9][0-9.]*\).*/\1/p' | head -1)"
		[ -n "$ver" ] || { echo "could not determine mongod version" >&2; exit 1; }
		series="$(echo "$ver" | cut -d. -f1-2)"   # e.g. 7.0

		# Detect arch and the RHEL major version rather than hardcoding x86_64/el9.
		arch="$(uname -m)"
		case "$arch" in x86_64|aarch64) ;; *) echo "unsupported arch: $arch" >&2; exit 1;; esac
		elver="$( . /etc/os-release 2>/dev/null; echo "${VERSION_ID%%.*}" )"
		[ -n "$elver" ] || elver=9

		# Install from the MongoDB yum repo with gpgcheck=1 so dnf verifies the package
		# signature, instead of fetching an unverified URL RPM (dnf does not GPG-check a
		# package passed by URL).
		echo "Installing mongos ${ver} (to match mongod ${ver}) from the GPG-checked MongoDB repo:"
		cat > "/etc/yum.repos.d/mongodb-org-${series}.repo" <<EOF
[mongodb-org-${series}]
name=MongoDB ${series} Repository
baseurl=https://repo.mongodb.org/yum/redhat/${elver}/mongodb-org/${series}/${arch}/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-${series}.asc
EOF
		dnf install -y "mongodb-org-mongos-${ver}"
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
