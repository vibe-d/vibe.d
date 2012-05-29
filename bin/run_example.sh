#!/bin/sh
if [ "$1" = "" ]; then
	echo "Usage: run_example (example name)"
	echo ""
	echo "Possible examples:"
	for i in ../source/examples/*.d; do echo $i | sed "s/^[a-zA-Z._\/]*\//  /g; s/.d$//g"; done
else
	#use pkg-config or fallback to default flags
	LIBS=$(pkg-config --libs libevent libevent_openssl 2>/dev/null || echo "-levent_openssl -levent")
	LIBS=$(echo "$LIBS" | sed 's/^-L/-L-L/; s/ -L/ -L-L/g; s/^-l/-L-l/; s/ -l/ -L-l/g')
	rdmd -debug -g -gs -property -w -Jviews -I../source $LIBS ../source/examples/$1.d
fi
