#!/bin/bash
set -e

PORT1=22840
PORT2=22841
PORT3=22842

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

start_mongod() {
	local idx=$1
	local port=$2
	local logfile="log${idx}.txt"
	local dbpath="db/rs${idx}"
	mkdir -p "$dbpath"
	PIDS[$idx]=$(mongod --logpath "$logfile" --bind_ip 127.0.0.1 --port "$port" --replSet rs0 --dbpath "$dbpath" --fork | grep -Po 'forked process: \K\d+')
	echo "[INFO] Started mongod on port $port (PID: ${PIDS[$idx]})"
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

rm -f log*.txt
rm -rf db

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

echo ""
echo "============================================"
echo "Health monitor failover test"
echo "============================================"
if ! eval $DUB_INVOKE -- "$PORT1,$PORT2,$PORT3"; then
	echo "[FAIL] Health monitor failover test failed"
	exit 1
fi
echo "[PASS] Health monitor failover test passed"
