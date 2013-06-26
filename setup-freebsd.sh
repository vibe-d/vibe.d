#!/bin/sh

set -e

# root privileges required
[ "root" != "$USER" ] && echo "root privileges required..." && exec sudo $0 "$@"

# set variables
USER_NAME="www-vibe"
GROUP_NAME="www-vibe"
USER_COMMENT="Vibe user"
CONFIG_FILE="/usr/local/etc/vibe/vibe.conf"
LOG_FILE="/var/spool/vibe/install.log"

# remove user, group, log file and configuration file
if [ "$1" = "-r" ]
then

	# remove obsolete "vibe" user/group
	/usr/sbin/pw userdel vibe 2>/dev/null || true
	/usr/sbin/pw groupdel vibe 2>/dev/null || true

	# remove user if present in log file
	if grep "^user: $USER_NAME$" $LOG_FILE >/dev/null 2>&1
	then
		/usr/sbin/pw userdel $USER_NAME >/dev/null 2>&1 && echo "'$USER_NAME' user removed."
		sed -i "/^user: $USER_NAME$/d" $LOG_FILE >/dev/null 2>&1
	fi

	# remove group if present in log file
	if grep "^group: $GROUP_NAME$" $LOG_FILE >/dev/null 2>&1
	then
		/usr/sbin/pw groupdel $GROUP_NAME >/dev/null 2>&1 && echo "'$GROUP_NAME' group removed."
		sed -i "/^group: $GROUP_NAME$/d" $LOG_FILE >/dev/null 2>&1
	fi

	# remove log file if no data
	if [ -f $LOG_FILE ] && [ -z $(tr -d '[ \t\r\n]' 2>/dev/null <$LOG_FILE) ]
	then
		rm -f $LOG_FILE
		rmdir $(dirname $LOG_FILE) >/dev/null 2>&1 || true
	fi

	# remove config file
	echo "Removing configuration file $CONFIG_FILE..."
	rm -f $CONFIG_FILE
	rmdir $(dirname $CONFIG_FILE) >/dev/null 2>&1 || true

	exit
fi

# creating group if he isn't already there
if ! getent group $GROUP_NAME >/dev/null; then
	echo "Creating group $GROUP_NAME..."
	/usr/sbin/pw groupadd $GROUP_NAME >/dev/null
	mkdir -p $(dirname $LOG_FILE)
	echo "group: $GROUP_NAME" >>$LOG_FILE
fi

# creating user if he isn't already there
if ! getent passwd $USER_NAME >/dev/null; then
	echo "Creating user $USER_NAME..."
	/usr/sbin/pw useradd $USER_NAME -g $GROUP_NAME -c "$USER_COMMENT" >/dev/null
	mkdir -p $(dirname $LOG_FILE)
	echo "user: $USER_NAME" >>$LOG_FILE
fi

# create config dir if not there
mkdir -p $(dirname $CONFIG_FILE)

# create/update config file
echo "Creating new config file in $CONFIG_FILE..."
USER_ID=$(getent passwd $USER_NAME | cut -d: -f3)
GROUP_ID=$(getent group $GROUP_NAME | cut -d: -f3)
echo '{
	"uid": '$USER_ID',
	"gid": '$GROUP_ID'
}' >$CONFIG_FILE

# if everything went fine
echo "Setup finished successfully."
