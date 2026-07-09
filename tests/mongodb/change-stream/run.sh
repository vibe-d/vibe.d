#!/bin/bash
# Change-stream integration test. The app adapts to the deployment it is pointed at,
# so this harness runs it against both:
#   Phase 1 (standalone): every watch() must be rejected with the replica-set topology
#            error, proving the driver builds a well-formed $changeStream command.
#   Phase 2 (single-node replica set): a real insert must be observed as an `insert`
#            change event carrying a resume token. This positive path is dead on a
#            standalone (the default CI harness), which is what this script fixes.
set -e

STANDALONE_PORT=22840
RS_PORT=22841

PIDS=()

cleanup() {
	echo "[INFO] Cleaning up mongod instances..."
	for pid in "${PIDS[@]}"; do
		if [ -n "$pid" ] && [ "$pid" != "0" ] && kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null || true
		fi
	done
	for pid in "${PIDS[@]}"; do
		if [ -n "$pid" ] && [ "$pid" != "0" ]; then
			while kill -0 "$pid" 2>/dev/null; do sleep 1; done
		fi
	done
	rm -rf db
	rm -f log*.txt
}
trap cleanup EXIT

wait_for_primary() {
	local port=$1
	for i in $(seq 1 30); do
		local ok
		ok=$($MONGO --quiet "mongodb://127.0.0.1:$port" \
			--eval "try { db.hello().isWritablePrimary } catch (e) { false }" 2>/dev/null || echo false)
		if [ "$ok" = "true" ]; then
			echo "[INFO] Primary ready on port $port"
			return 0
		fi
		sleep 2
	done
	echo "[ERROR] No primary elected on port $port after 60s"
	return 1
}

rm -f log*.txt
rm -rf db

echo "========================================================"
echo "  Phase 1: Standalone — every watch() rejected"
echo "========================================================"
mkdir -p db/standalone
PIDS[0]=$(mongod --logpath log0.txt --bind_ip 127.0.0.1 --port $STANDALONE_PORT \
	--dbpath db/standalone --fork | grep -Po 'forked process: \K\d+')
echo "[INFO] Started standalone mongod on $STANDALONE_PORT (PID ${PIDS[0]})"

if ! eval $DUB_INVOKE -- $STANDALONE_PORT ; then
	echo "[FAIL] Standalone change-stream test failed"
	exit 1
fi
echo "[PASS] Standalone change-stream test passed"

echo "========================================================"
echo "  Phase 2: Replica set — insert observed with resume token"
echo "========================================================"
mkdir -p db/rs
PIDS[1]=$(mongod --logpath log1.txt --bind_ip 127.0.0.1 --port $RS_PORT \
	--dbpath db/rs --replSet csrs0 --fork | grep -Po 'forked process: \K\d+')
echo "[INFO] Started replica-set mongod on $RS_PORT (PID ${PIDS[1]})"

for attempt in $(seq 1 5); do
	if $MONGO --quiet "mongodb://127.0.0.1:$RS_PORT" \
		--eval "rs.initiate({_id:'csrs0', members:[{_id:0, host:'127.0.0.1:$RS_PORT'}]})" 2>/dev/null; then
		echo "[INFO] Replica set initiated"
		break
	fi
	echo "[INFO] rs.initiate attempt $attempt failed, retrying in 2s..."
	sleep 2
done

wait_for_primary $RS_PORT

if ! eval $DUB_INVOKE -- $RS_PORT ; then
	echo "[FAIL] Replica-set change-stream test failed"
	exit 1
fi
echo "[PASS] Replica-set change-stream test passed"

echo "============================================"
echo "All change-stream tests passed!"
echo "============================================"
