#!/bin/bash

set -e

echo "Checking for root privileges..."
# root privileges required
[ "root" != "$USER" ] && exec sudo $0 "$@"

# set variables
USER_NAME="_www"
GROUP_NAME=$USER_NAME
USER_COMMENT="Vibe user"
CONFIG_FILE="/etc/vibe/vibe.conf"

# remove user, group and configuration file
if [ "$1" = "-r" ] ;then
	echo "Removing configuration file $CONFIG_FILE..."
	rm -f $CONFIG_FILE
	rmdir -p $(dirname $CONFIG_FILE) 2>/dev/null || true
	exit
fi

# create/overwrite configuration file
echo "Creating new config file in $CONFIG_FILE..."
USER_ID=$(dscl . -read /Users/_www UniqueID | sed "s/[^:]*: //")
GROUP_ID=$(dscl . -read /Groups/_www PrimaryGroupID | sed "s/[^:]*: //")
mkdir -p $(dirname $CONFIG_FILE)
echo -e '{
	"uid": '$USER_ID',
	"gid": '$GROUP_ID'
}' >$CONFIG_FILE

# if everything went fine
echo "Setup finished successfully."
echo "You can now run 'vibe' from any vibe.d application directory to run an app (e.g. in examples/http_server/)."
