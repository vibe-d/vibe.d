#!/bin/bash
set -e

PORT1=22830
PORT2=22831
PORT3=22832

PIDS=()

cleanup() {
	echo "[INFO] Cleaning up mongod instances..."
	for pid in "${PIDS[@]}"; do
		if [ "$pid" != "0" ] && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null || true
		fi
	done
	for pid in "${PIDS[@]}"; do
		if [ "$pid" != "0" ] && [ -n "$pid" ]; then
			while kill -0 "$pid" 2>/dev/null; do
				sleep 1
			done
		fi
	done
	rm -rf db
	rm -f log*.txt
}

trap cleanup EXIT

wait_for_pid_exit() {
	local pid=$1
	while kill -0 "$pid" 2>/dev/null; do
		sleep 1
	done
}

start_mongod() {
	local idx=$1
	local port=$2
	local logfile="log${idx}.txt"
	local dbpath="db/rs${idx}"
	mkdir -p "$dbpath"
	PIDS[$idx]=$(mongod --logpath "$logfile" --bind_ip 127.0.0.1 --port "$port" --replSet rs0 --dbpath "$dbpath" --fork | grep -Po 'forked process: \K\d+')
	echo "[INFO] Started mongod on port $port (PID: ${PIDS[$idx]})"
}

kill_mongod() {
	local idx=$1
	local pid=${PIDS[$idx]}
	if [ "$pid" != "0" ] && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
		echo "[INFO] Killing mongod PID $pid"
		kill "$pid" 2>/dev/null || true
		wait_for_pid_exit "$pid"
	fi
	PIDS[$idx]=0
}

run_test() {
	local num=$1
	local desc=$2
	shift 2
	echo ""
	echo "============================================"
	echo "Test $num: $desc"
	echo "============================================"
	if ! eval $DUB_INVOKE -- "$@" ; then
		echo "[FAIL] Test $num failed"
		exit 1
	fi
	echo "[PASS] Test $num passed"
}

wait_for_primary() {
	local port=$1
	echo "[INFO] Waiting for primary election..."
	for i in $(seq 1 30); do
		PRIMARY=$($MONGO --quiet "mongodb://127.0.0.1:$port" --eval "
			var status = rs.status();
			var primary = status.members.filter(function(m) { return m.stateStr === 'PRIMARY'; });
			if (primary.length > 0) { print(primary[0].name); } else { print(''); }
		" 2>/dev/null || echo "")

		if [ -n "$PRIMARY" ]; then
			echo "[INFO] Primary elected: $PRIMARY"
			return 0
		fi
		echo "[INFO] Waiting... ($i/30)"
		sleep 2
	done

	echo "[ERROR] No primary elected after 60 seconds"
	return 1
}

detect_roles() {
	PRIMARY_PORT=$(echo "$PRIMARY" | grep -Po ':\K\d+')
	SECONDARY_PORTS=()
	for port in $PORT1 $PORT2 $PORT3; do
		if [ "$port" != "$PRIMARY_PORT" ]; then
			SECONDARY_PORTS+=("$port")
		fi
	done
	echo "[INFO] Primary port: $PRIMARY_PORT"
	echo "[INFO] Secondary ports: ${SECONDARY_PORTS[*]}"
}

rm -f log*.txt
rm -rf db

echo "========================================================"
echo "  Phase 1: Basic replica set connection tests"
echo "========================================================"

start_mongod 0 $PORT1
start_mongod 1 $PORT2
start_mongod 2 $PORT3
sleep 2

echo "[INFO] Initiating replica set..."
for attempt in $(seq 1 5); do
	if $MONGO --quiet "mongodb://127.0.0.1:$PORT1" --eval "
		rs.initiate({
			_id: 'rs0',
			members: [
				{_id: 0, host: '127.0.0.1:$PORT1'},
				{_id: 1, host: '127.0.0.1:$PORT2'},
				{_id: 2, host: '127.0.0.1:$PORT3'}
			]
		})
	" 2>/dev/null; then
		echo "[INFO] Replica set initiated"
		break
	fi
	echo "[INFO] rs.initiate attempt $attempt failed, retrying in 2s..."
	sleep 2
done

wait_for_primary $PORT1
detect_roles

run_test 1 "Connect directly to primary" \
	$PRIMARY_PORT

run_test 2 "Connect to secondary, chase primary" \
	${SECONDARY_PORTS[0]}

run_test 3 "Connect with all 3 hosts" \
	"$PORT1,$PORT2,$PORT3"

run_test 4 "Connect with secondaries first in host list" \
	"${SECONDARY_PORTS[0]},${SECONDARY_PORTS[1]},$PRIMARY_PORT"

run_test 5 "Wrong replica set name (expect fail)" \
	"$PORT1,$PORT2,$PORT3" --replicaSet wrongname --expectFail

run_test 6 "Correct replica set name" \
	"$PORT1,$PORT2,$PORT3" --replicaSet rs0

run_test 7 "Unreachable host + live secondary" \
	"22899,${SECONDARY_PORTS[0]}"

echo ""
echo "========================================================"
echo "  Phase 2: Read preference tests"
echo "========================================================"

run_test 8 "readPreference=secondary connects to secondary" \
	"$PORT1,$PORT2,$PORT3" --replicaSet rs0 --readPreference secondary --expectSecondary

run_test 9 "readPreference=secondaryPreferred connects to secondary" \
	"$PORT1,$PORT2,$PORT3" --replicaSet rs0 --readPreference secondaryPreferred --expectSecondary

run_test 10 "readPreference=primary connects to primary (CRUD)" \
	"$PORT1,$PORT2,$PORT3" --replicaSet rs0 --readPreference primary

echo ""
echo "========================================================"
echo "  Phase 3: Dead secondary tests"
echo "========================================================"

echo "[INFO] Killing one secondary (port ${SECONDARY_PORTS[0]})..."
# Find which PIDS index corresponds to the secondary port
for idx in 0 1 2; do
	case $idx in
		0) p=$PORT1 ;;
		1) p=$PORT2 ;;
		2) p=$PORT3 ;;
	esac
	if [ "$p" = "${SECONDARY_PORTS[0]}" ]; then
		kill_mongod $idx
		KILLED_SEC_IDX=$idx
		break
	fi
done

run_test 11 "Dead secondary in host list, primary still reachable" \
	"${SECONDARY_PORTS[0]},$PRIMARY_PORT"

run_test 12 "All hosts listed, one secondary dead" \
	"$PORT1,$PORT2,$PORT3"

run_test 13 "readPreference=secondary with one dead secondary" \
	"$PORT1,$PORT2,$PORT3" --replicaSet rs0 --readPreference secondary --expectSecondary

echo ""
echo "========================================================"
echo "  Phase 4: Dead primary tests"
echo "========================================================"

# Restart the killed secondary first
echo "[INFO] Restarting killed secondary on port ${SECONDARY_PORTS[0]}..."
start_mongod $KILLED_SEC_IDX ${SECONDARY_PORTS[0]}
sleep 3

echo "[INFO] Killing primary (port $PRIMARY_PORT)..."
for idx in 0 1 2; do
	case $idx in
		0) p=$PORT1 ;;
		1) p=$PORT2 ;;
		2) p=$PORT3 ;;
	esac
	if [ "$p" = "$PRIMARY_PORT" ]; then
		kill_mongod $idx
		KILLED_PRI_IDX=$idx
		break
	fi
done

echo "[INFO] Waiting for new primary election after killing old primary..."
# Find a live port to query
LIVE_PORT=${SECONDARY_PORTS[0]}
wait_for_primary $LIVE_PORT
detect_roles

run_test 14 "New primary after old primary killed" \
	"$PORT1,$PORT2,$PORT3"

run_test 15 "readPreference=secondary after primary failover" \
	"$PORT1,$PORT2,$PORT3" --replicaSet rs0 --readPreference secondary --expectSecondary

echo ""
echo "========================================================"
echo "  Phase 5: All hosts unreachable"
echo "========================================================"

echo "[INFO] Killing all remaining mongod instances..."
for idx in 0 1 2; do
	kill_mongod $idx
done

run_test 16 "All hosts dead (expect fail)" \
	"$PORT1,$PORT2,$PORT3" --expectFail

echo ""
echo "========================================================"
echo "  Phase 6: Restart from dead state"
echo "========================================================"

echo "[INFO] Restarting all mongod instances..."
start_mongod 0 $PORT1
start_mongod 1 $PORT2
start_mongod 2 $PORT3
sleep 2

wait_for_primary $PORT1
detect_roles

run_test 17 "Connect after full cluster restart" \
	"$PORT1,$PORT2,$PORT3" --replicaSet rs0

echo ""
echo "============================================"
echo "All $((17)) replica set tests passed!"
echo "============================================"
