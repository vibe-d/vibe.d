#!/bin/sh
if [ "$1" = "" ]; then
	echo "Usage: run_example (example name)"
	echo ""
	echo "Possible examples:"
	for i in ../source/examples/*.d; do echo $i | sed "s/^[a-zA-Z._\/]*\//  /g; s/.d$//g"; done
else
	LIBS="-L-levent -L-levent_openssl -L-lssl -L-lcrypto"
	rdmd -debug -g -gs -property -w -Jviews -I../source $LIBS ../source/examples/$1.d
fi
