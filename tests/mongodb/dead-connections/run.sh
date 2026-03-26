#!/bin/bash
set -e

MONGOPORT=22840
MONGOPID=0
APP_PID=0

cleanup() {
	echo "[INFO] Cleaning up..."
	if [ "$APP_PID" != "0" ] && kill -0 "$APP_PID" 2>/dev/null; then
		kill "$APP_PID" 2>/dev/null || true
		wait "$APP_PID" 2>/dev/null || true
	fi
	if [ "$MONGOPID" != "0" ] && kill -0 "$MONGOPID" 2>/dev/null; then
		kill "$MONGOPID" 2>/dev/null || true
		while kill -0 "$MONGOPID" 2>/dev/null; do sleep 1; done
	fi
	rm -rf db ready restarted log*.txt
}

trap cleanup EXIT
rm -f ready restarted log*.txt
rm -rf db
mkdir -p db

echo "========================================================"
echo "  Dead connection eviction test"
echo "========================================================"

# Start mongod
MONGOPID=$(mongod --logpath log.txt --bind_ip 127.0.0.1 --port $MONGOPORT --noauth --dbpath db --fork | grep -Po 'forked process: \K\d+')
echo "[INFO] Started mongod on port $MONGOPORT (PID: $MONGOPID)"

# Start the test app in the background
eval $DUB_INVOKE -- $MONGOPORT &
APP_PID=$!

# Wait for the app to signal it's ready (pool is populated)
echo "[INFO] Waiting for app to populate connection pool..."
for i in $(seq 1 30); do
	if [ -f ready ]; then
		break
	fi
	sleep 1
done

if [ ! -f ready ]; then
	echo "[FAIL] App never signaled ready"
	kill $APP_PID 2>/dev/null || true
	exit 1
fi

echo "[INFO] App is ready, killing mongod to simulate dead connections..."
kill $MONGOPID
while kill -0 "$MONGOPID" 2>/dev/null; do sleep 1; done
MONGOPID=0

sleep 2

echo "[INFO] Restarting mongod..."
MONGOPID=$(mongod --logpath log2.txt --bind_ip 127.0.0.1 --port $MONGOPORT --noauth --dbpath db --fork | grep -Po 'forked process: \K\d+')
echo "[INFO] Restarted mongod (PID: $MONGOPID)"

# Signal the app that the server is back
touch restarted

# Wait for the app to finish
echo "[INFO] Waiting for app to complete post-restart tests..."
wait $APP_PID
RESULT=$?

if [ $RESULT -eq 0 ]; then
	echo ""
	echo "============================================"
	echo "Dead connection eviction test PASSED"
	echo "============================================"
else
	echo ""
	echo "[FAIL] Dead connection eviction test failed (exit code $RESULT)"
	exit 1
fi
