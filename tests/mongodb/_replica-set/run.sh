#!/bin/bash
set -e

PORT1=22830
PORT2=22831
PORT3=22832

PIDS=()

cleanup() {
	echo "[INFO] Cleaning up mongod instances..."
	for pid in "${PIDS[@]}"; do
		if kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null || true
		fi
	done
	for pid in "${PIDS[@]}"; do
		while kill -0 "$pid" 2>/dev/null; do
			sleep 1
		done
	done
	rm -rf db
	rm -f log*.txt
}

trap cleanup EXIT

rm -f log*.txt
rm -rf db
mkdir -p db/rs0 db/rs1 db/rs2

echo "[INFO] Starting 3 mongod instances for replica set rs0..."

PIDS[0]=$(mongod --logpath log1.txt --bind_ip 127.0.0.1 --port $PORT1 --replSet rs0 --dbpath db/rs0 --fork | grep -Po 'forked process: \K\d+')
PIDS[1]=$(mongod --logpath log2.txt --bind_ip 127.0.0.1 --port $PORT2 --replSet rs0 --dbpath db/rs1 --fork | grep -Po 'forked process: \K\d+')
PIDS[2]=$(mongod --logpath log3.txt --bind_ip 127.0.0.1 --port $PORT3 --replSet rs0 --dbpath db/rs2 --fork | grep -Po 'forked process: \K\d+')

echo "[INFO] mongod PIDs: ${PIDS[*]}"

echo "[INFO] Initiating replica set..."
$MONGO --quiet "mongodb://127.0.0.1:$PORT1" --eval "
rs.initiate({
	_id: 'rs0',
	members: [
		{_id: 0, host: '127.0.0.1:$PORT1'},
		{_id: 1, host: '127.0.0.1:$PORT2'},
		{_id: 2, host: '127.0.0.1:$PORT3'}
	]
})
"

echo "[INFO] Waiting for replica set to elect a primary..."
for i in $(seq 1 30); do
	PRIMARY=$($MONGO --quiet "mongodb://127.0.0.1:$PORT1" --eval "
		var status = rs.status();
		var primary = status.members.filter(function(m) { return m.stateStr === 'PRIMARY'; });
		if (primary.length > 0) { print(primary[0].name); } else { print(''); }
	" 2>/dev/null || echo "")

	if [ -n "$PRIMARY" ]; then
		echo "[INFO] Primary elected: $PRIMARY"
		break
	fi
	echo "[INFO] Waiting... ($i/30)"
	sleep 2
done

if [ -z "$PRIMARY" ]; then
	echo "[ERROR] No primary elected after 60 seconds"
	exit 1
fi

PRIMARY_PORT=$(echo "$PRIMARY" | grep -Po ':\K\d+')

SECONDARY_PORTS=()
for port in $PORT1 $PORT2 $PORT3; do
	if [ "$port" != "$PRIMARY_PORT" ]; then
		SECONDARY_PORTS+=("$port")
	fi
done

echo "[INFO] Primary port: $PRIMARY_PORT"
echo "[INFO] Secondary ports: ${SECONDARY_PORTS[*]}"

echo ""
echo "============================================"
echo "Test 1: Connect directly to primary"
echo "============================================"
if ! eval $DUB_INVOKE -- $PRIMARY_PORT ; then
	echo "[FAIL] Test 1 failed"
	exit 1
fi
echo "[PASS] Test 1 passed"

echo ""
echo "============================================"
echo "Test 2: Connect to secondary, chase primary"
echo "============================================"
if ! eval $DUB_INVOKE -- ${SECONDARY_PORTS[0]} ; then
	echo "[FAIL] Test 2 failed"
	exit 1
fi
echo "[PASS] Test 2 passed"

echo ""
echo "============================================"
echo "Test 3: Connect with all 3 hosts"
echo "============================================"
if ! eval $DUB_INVOKE -- "$PORT1,$PORT2,$PORT3" ; then
	echo "[FAIL] Test 3 failed"
	exit 1
fi
echo "[PASS] Test 3 passed"

echo ""
echo "============================================"
echo "Test 4: Connect with secondaries first"
echo "============================================"
if ! eval $DUB_INVOKE -- "${SECONDARY_PORTS[0]},${SECONDARY_PORTS[1]},$PRIMARY_PORT" ; then
	echo "[FAIL] Test 4 failed"
	exit 1
fi
echo "[PASS] Test 4 passed"

echo ""
echo "============================================"
echo "Test 5: Wrong replica set name (expect fail)"
echo "============================================"
if ! eval $DUB_INVOKE -- "$PORT1,$PORT2,$PORT3" --replicaSet wrongname --expectFail ; then
	echo "[FAIL] Test 5 failed"
	exit 1
fi
echo "[PASS] Test 5 passed"

echo ""
echo "============================================"
echo "Test 6: Correct replica set name"
echo "============================================"
if ! eval $DUB_INVOKE -- "$PORT1,$PORT2,$PORT3" --replicaSet rs0 ; then
	echo "[FAIL] Test 6 failed"
	exit 1
fi
echo "[PASS] Test 6 passed"

echo ""
echo "============================================"
echo "Test 7: Unreachable host + secondary"
echo "============================================"
if ! eval $DUB_INVOKE -- "22899,${SECONDARY_PORTS[0]}" ; then
	echo "[FAIL] Test 7 failed"
	exit 1
fi
echo "[PASS] Test 7 passed"

echo ""
echo "============================================"
echo "All replica set tests passed!"
echo "============================================"
