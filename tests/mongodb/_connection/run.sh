#!/bin/bash

# This test file uses run.sh to manually start the mongod server with different authentication schemes and run dub multiple times with different expected test results.

MONGOPORT=22824
rm -f log.txt*
rm -rf db
mkdir -p db/noauth
mkdir -p db/wcert
mkdir -p db/auth

if ! eval $DUB_INVOKE -- $MONGOPORT failconnect ; then
	exit 1
fi

# We use --fork in all mongod calls because it waits until the database is fully up-and-running for all queries.

# Unauthenticated Test

MONGOPID=$(mongod --logpath log.txt --bind_ip 127.0.0.1 --port $MONGOPORT --noauth --dbpath db/noauth --fork | grep -Po 'forked process: \K\d+')

if ! eval $DUB_INVOKE -- $MONGOPORT ; then
	kill $MONGOPID
	exit 1
else
	kill $MONGOPID
fi
((MONGOPORT++))

# TODO: Certificate Auth Test

# Authenticated Test

MONGOPID=$(mongod --logpath log.txt --bind_ip 127.0.0.1 --port $MONGOPORT --noauth --dbpath db/auth --fork | grep -Po 'forked process: \K\d+')
echo "db.createUser({user:'admin',pwd:'123456',roles:[{role:'readWrite',db:'unittest'},'dbAdmin'],passwordDigestor:'server'})" | $MONGO "mongodb://127.0.0.1:$MONGOPORT/admin"
kill $MONGOPID

while kill -0 $MONGOPID &>/dev/null; do
	sleep 1
done

MONGOPID=$(mongod --logpath log.txt --bind_ip 127.0.0.1 --port $MONGOPORT --auth --dbpath db/auth --fork | grep -Po 'forked process: \K\d+')
sleep 1

echo Trying unauthenticated operations on a protected database
if ! eval $DUB_INVOKE -- $MONGOPORT faildb ; then
	kill $MONGOPID
	exit 1
fi

echo Trying wrongly authenticated operations on a protected database
if ! eval $DUB_INVOKE -- $MONGOPORT failauth auth admin 1234567 ; then
	kill $MONGOPID
	exit 1
fi

echo Trying authenticated operations on a protected database
if ! eval $DUB_INVOKE -- $MONGOPORT auth admin 123456 ; then
	kill $MONGOPID
	exit 1
fi

kill $MONGOPID
((MONGOPORT++))
