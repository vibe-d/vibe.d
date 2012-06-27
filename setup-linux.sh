#!/bin/bash

set -e

echo "Checking for root priviledges..."
# root privileges required
[ "root" != "$USER" ] && exec sudo $0 "$@"

# set variables
USER_NAME="vibe"
GROUP_NAME=$USER_NAME
USER_COMMENT="Vibe user"
CONFIG_FILE="/etc/vibe/vibe.conf"
SYMLINK_FILE="/usr/bin/vibe"

# remove user, group and configuration file
if [ "$1" = "-r" ] ;then
	echo "Removing user '$SUER_NAME'..."
	/usr/sbin/userdel $USER_NAME 2>/dev/null || true
	echo "Removing group '$SUER_NAME'..."
	/usr/sbin/groupdel $GROUP_NAME 2>/dev/null || true
	echo "Removing configuration file $CONFIG_FILE..."
	rm -f $CONFIG_FILE
	rmdir -p $(dirname $CONFIG_FILE) 2>/dev/null || true
	echo "Removing symlink $SYMLINK_FILE..."
	rm -f $SYMLINK_FILE
	exit
fi

# create a symlink to the vibe script
echo "Creating symlink in $SYMLINK_FILE..."
ln -sf $(pwd)/bin/vibe $SYMLINK_FILE

# creating group if he isn't already there
if ! getent group $GROUP_NAME >/dev/null; then
	echo "Creating group $GROUP_NAME..."
	/usr/sbin/groupadd -r $GROUP_NAME >/dev/null
fi

# creating user if he isn't already there
if ! getent passwd $USER_NAME >/dev/null; then
	echo "Creating user $GROUP_NAME..."
	/usr/sbin/useradd -r -g $GROUP_NAME -c "$USER_COMMENT" $USER_NAME >/dev/null
fi

# create/overwrite configuration file
echo "Creating new config file in $CONFIG_FILE..."
USER_ID=$(getent passwd $USER_NAME | cut -d: -f3)
GROUP_ID=$(getent group $USER_NAME | cut -d: -f3)
mkdir -p $(dirname $CONFIG_FILE)
echo -e '{
	"uid": '$USER_ID',
	"gid": '$GROUP_ID'
}' >$CONFIG_FILE

# if everything went fine
echo "Setup finished successfully."
echo "You can now run 'vibe' from any vibe.d application directory to run an app (e.g. in examples/simple_http/)."