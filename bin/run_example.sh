#!/bin/sh
if [ "$1" = "" ]; then
	echo "Usage: run_example (example name)"
	echo ""
	echo "Possible examples:"
	for i in ../examples/*; do echo $i | sed "s/^[a-zA-Z._\/]*\//  /g"; done
else
	cd ../examples/$1
	vibe
	cd ../../bin
fi
