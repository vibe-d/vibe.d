#!/usr/bin/env bash
#
# Manage a minimal load-balanced MongoDB deployment for the loadbalanced
# integration harness, so the cursor-pinning path actually executes instead of
# self-skipping.
#
# Usage
#   ./run.sh start   # bring the cluster up and leave it running; prints MONGODB_LB_URI
#   ./run.sh stop    # tear the cluster down and clean up
#   ./run.sh status  # show whether the cluster is up
#   ./run.sh         # full cycle (start -> build+run harness -> stop); used by run-ci.sh
#
# Load-balancer mode is a mongos feature: a mongos started with
# `--setParameter loadBalancerPort=<port>` returns a `serviceId` in its hello reply
# on that port (a plain mongod never does). So the cluster is:
#   - a single-node config-server replica set   (mongod --configsvr)
#   - a single-node shard replica set           (mongod --shardsvr)
#   - a mongos with a loadBalancerPort          (mongos --setParameter ...)
#   - a load balancer in front of the LB port   (haproxy, send-proxy-v2)
# The harness's positive path uses MONGODB_LB_URI (the load-balancer front); its
# negative path (loadBalanced against a non-LB server) uses a plain standalone mongod.
#
# The mongos loadBalancerPort REQUIRES the PROXY protocol header on every connection,
# so the front must be haproxy (send-proxy-v2), not a plain forwarder like socat.
#
# Requires mongod, mongos, mongosh, haproxy. If any is missing the cluster cannot be
# built and start/run SKIP cleanly (exit 0). Run 'sudo ./install-mongos.sh' to install.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
DUB="${DUB_INVOKE:-dub}"
work="$here/lb-cluster"          # persisted state: data, pidfiles, logs, lb.env
envfile="$work/lb.env"

# ports
STANDALONE_PORT=27040   # plain mongod, harness negative path (returns no serviceId)
CFG_PORT=27041          # config-server replica set
SHARD_PORT=27042        # shard replica set
MONGOS_PORT=27043       # mongos normal port
MONGOS_LB_PORT=27044    # mongos load-balancer port (returns serviceId)
LB_FRONT_PORT=27045     # load balancer front the client connects to

need() { command -v "$1" >/dev/null 2>&1; }

have_tooling() {
	local missing=()
	local t
	for t in mongod mongos mongosh haproxy; do need "$t" || missing+=("$t"); done
	if [ ${#missing[@]} -gt 0 ]; then
		echo "[loadbalanced] missing: ${missing[*]}"
		echo "[loadbalanced] load-balanced mode needs a sharded cluster (mongos) behind a"
		echo "[loadbalanced] PROXY-protocol load balancer (haproxy). Run 'sudo ./install-mongos.sh'."
		echo "[loadbalanced] Skipping."
		return 1
	fi
	return 0
}

wait_for() { # host port
	local h="$1" p="$2"
	for _ in $(seq 1 60); do
		# Prefer mongosh (6.0+); fall back to the legacy `mongo` shell (the 3.6-5.0 CI
		# images ship only that). With no shell at all, a TCP connect is enough — mongod
		# --fork only starts listening once it is ready to serve.
		if need mongosh; then
			mongosh --quiet --host "$h" --port "$p" --eval 'db.runCommand({ping:1})' >/dev/null 2>&1 && return 0
		elif need mongo; then
			mongo --quiet --host "$h" --port "$p" --eval 'db.runCommand({ping:1})' >/dev/null 2>&1 && return 0
		elif (exec 3<>"/dev/tcp/$h/$p") 2>/dev/null; then
			return 0
		fi
		sleep 1
	done
	echo "[loadbalanced] timed out waiting for $h:$p" >&2
	return 1
}

start_mongod() { # name dbpath port extra-args...
	local name="$1" dbpath="$2" port="$3"; shift 3
	mkdir -p "$dbpath"
	mongod --dbpath "$dbpath" --logpath "$work/logs/$name.log" --pidfilepath "$work/$name.pid" \
		--bind_ip 127.0.0.1 --port "$port" --fork "$@" >/dev/null
}

do_start() {
	# The negative path (loadBalanced against a non-LB server must be rejected) only
	# needs a plain standalone mongod, so it ALWAYS runs — including in CI where mongos
	# and haproxy are not installed. Only the cursor-pinning (positive) path needs the
	# full sharded cluster behind a PROXY-protocol load balancer; without that tooling it
	# self-skips (MONGODB_LB_URI is left unset and the harness skips path B).
	need mongod || { echo "[loadbalanced] mongod is required even for the negative path. Skipping."; exit 0; }
	if [ -f "$envfile" ]; then
		echo "[loadbalanced] cluster already started (see $envfile). Run './run.sh stop' first."
		return 0
	fi
	rm -rf "$work"; mkdir -p "$work/logs"

	echo "[loadbalanced] standalone mongod (negative path) :$STANDALONE_PORT"
	start_mongod standalone "$work/standalone" "$STANDALONE_PORT"
	wait_for 127.0.0.1 "$STANDALONE_PORT" || {
		echo "[loadbalanced] standalone mongod did not become ready; its log:" >&2
		[ -f "$work/logs/standalone.log" ] && tail -n 40 "$work/logs/standalone.log" >&2
		do_stop
		exit 1
	}

	if ! have_tooling; then
		echo "[loadbalanced] mongos/haproxy unavailable: running the negative path only (cursor-pinning path skipped)."
		echo "STANDALONE_PORT=$STANDALONE_PORT" > "$envfile"
		return 0
	fi

	echo "[loadbalanced] config-server RS :$CFG_PORT"
	start_mongod cfg "$work/cfg" "$CFG_PORT" --configsvr --replSet cfgrs
	wait_for 127.0.0.1 "$CFG_PORT" || { do_stop; exit 1; }
	mongosh --quiet --port "$CFG_PORT" --eval \
		"quit(rs.initiate({_id:'cfgrs', configsvr:true, members:[{_id:0, host:'127.0.0.1:$CFG_PORT'}]}).ok ? 0 : 1)" \
		|| { echo "[loadbalanced] config-server rs.initiate failed" >&2; do_stop; exit 1; }

	echo "[loadbalanced] shard RS :$SHARD_PORT"
	start_mongod shard "$work/shard" "$SHARD_PORT" --shardsvr --replSet shardrs
	wait_for 127.0.0.1 "$SHARD_PORT" || { do_stop; exit 1; }
	mongosh --quiet --port "$SHARD_PORT" --eval \
		"quit(rs.initiate({_id:'shardrs', members:[{_id:0, host:'127.0.0.1:$SHARD_PORT'}]}).ok ? 0 : 1)" \
		|| { echo "[loadbalanced] shard rs.initiate failed" >&2; do_stop; exit 1; }

	# wait for the single-node replica sets to elect their primary; fail loudly on timeout
	for p in "$CFG_PORT" "$SHARD_PORT"; do
		elected=
		for _ in $(seq 1 30); do
			mongosh --quiet --port "$p" --eval 'quit(db.hello().isWritablePrimary ? 0 : 1)' >/dev/null 2>&1 && { elected=1; break; }
			sleep 1
		done
		[ -n "$elected" ] || { echo "[loadbalanced] replica set on :$p never elected a primary" >&2; do_stop; exit 1; }
	done

	echo "[loadbalanced] mongos :$MONGOS_PORT (loadBalancerPort=$MONGOS_LB_PORT)"
	mongos --configdb "cfgrs/127.0.0.1:$CFG_PORT" --logpath "$work/logs/mongos.log" \
		--pidfilepath "$work/mongos.pid" --bind_ip 127.0.0.1 --port "$MONGOS_PORT" \
		--setParameter "loadBalancerPort=$MONGOS_LB_PORT" --fork >/dev/null
	wait_for 127.0.0.1 "$MONGOS_PORT" || { do_stop; exit 1; }
	mongosh --quiet --port "$MONGOS_PORT" --eval "quit(sh.addShard('shardrs/127.0.0.1:$SHARD_PORT').ok ? 0 : 1)" \
		|| { echo "[loadbalanced] sh.addShard failed" >&2; do_stop; exit 1; }

	# Load-balancer front. mongos's loadBalancerPort REQUIRES the PROXY protocol
	# header on every connection (it uses it to learn the real client address), so a
	# plain TCP forward (e.g. socat) is rejected with "Error while parsing proxy
	# protocol header". HAProxy with send-proxy-v2 emits the header mongos expects.
	cat > "$work/haproxy.cfg" <<EOF
defaults
  mode tcp
  timeout connect 5s
  timeout client 1m
  timeout server 1m
frontend mongos_lb
  bind 127.0.0.1:$LB_FRONT_PORT
  default_backend mongos
backend mongos
  server m1 127.0.0.1:$MONGOS_LB_PORT send-proxy-v2
EOF
	echo "[loadbalanced] haproxy LB front :$LB_FRONT_PORT -> mongos LB :$MONGOS_LB_PORT (send-proxy-v2)"
	haproxy -f "$work/haproxy.cfg" -D -p "$work/haproxy.pid" \
		|| { echo "[loadbalanced] haproxy failed to start" >&2; do_stop; exit 1; }
	sleep 1
	local lb_target="$LB_FRONT_PORT"

	{
		echo "MONGODB_LB_URI=mongodb://127.0.0.1:$lb_target/?loadBalanced=true"
		echo "STANDALONE_PORT=$STANDALONE_PORT"
	} > "$envfile"

	echo "[loadbalanced] cluster up."
	echo "  MONGODB_LB_URI=mongodb://127.0.0.1:$lb_target/?loadBalanced=true"
	echo "  run harness:  MONGODB_LB_URI=mongodb://127.0.0.1:$lb_target/?loadBalanced=true ./tests $STANDALONE_PORT"
	echo "  stop:         ./run.sh stop"
}

do_stop() {
	set +e
	[ -f "$work/haproxy.pid" ] && kill "$(cat "$work/haproxy.pid")" 2>/dev/null
	# graceful shutdown via the admin command (mongos first, then the mongods)
	mongosh --quiet --port "$MONGOS_PORT" --eval 'db.adminCommand({shutdown:1})' >/dev/null 2>&1
	for p in "$SHARD_PORT" "$CFG_PORT" "$STANDALONE_PORT"; do
		mongosh --quiet --port "$p" --eval 'db.adminCommand({shutdown:1, force:true})' >/dev/null 2>&1
	done
	sleep 1
	# backstop for any pidfiles still alive
	for f in "$work"/*.pid; do
		[ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null
	done
	rm -rf "$work"
	echo "[loadbalanced] cluster stopped."
}

do_status() {
	if [ -f "$envfile" ]; then
		echo "[loadbalanced] up:"; cat "$envfile"
	else
		echo "[loadbalanced] not running."
	fi
}

do_run() {   # full cycle for run-ci.sh: build -> start -> run harness -> stop
	# Build the harness BEFORE bringing up any servers, so the heavy compile doesn't
	# compete with the just-started cluster for resources (which can leave the
	# standalone briefly unreachable when the harness then connects).
	#
	# The `build` subcommand must come BEFORE the options: $DUB expands to
	# `dub --compiler=... <args>`, and the old `$DUB build` put `build` after the
	# options, where dub treats it as a package name. `${DUB#dub}` strips the leading
	# `dub` so we can re-prepend `dub build`, giving `dub build --compiler=... <args>`.
	eval "dub build${DUB#dub}" || exit 1

	# do_start always brings up at least the standalone (negative path); the LB cluster
	# and MONGODB_LB_URI come up only when mongos/haproxy exist.
	do_start
	trap do_stop EXIT
	# shellcheck disable=SC1090
	source "$envfile"
	export MONGODB_LB_URI="${MONGODB_LB_URI:-}"
	./tests "$STANDALONE_PORT"
	local rc=$?
	echo "[loadbalanced] harness exit: $rc"
	exit "$rc"
}

case "${1:-run}" in
	start)  do_start ;;
	stop)   do_stop ;;
	status) do_status ;;
	run|"") do_run ;;
	*) echo "usage: $0 {start|stop|status|run}" >&2; exit 2 ;;
esac
