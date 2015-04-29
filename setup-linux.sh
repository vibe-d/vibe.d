#!/bin/bash


set -e


# set variables
PREFIX="/usr/local"
BASE_DIR="$PREFIX/share/vibe"
SRC_DIR=$(dirname $0)
CONFIG_DIR="/etc/vibe"
CONFIG_FILE="$CONFIG_DIR/vibe.conf"
LOG_DIR="/var/spool/vibe"
LOG_FILE="$LOG_DIR/install.log"
MENU_DIR="$PREFIX/share/applications"
MENU_FILE="$MENU_DIR/vibe.desktop"

USER_NAME="www-vibe"
GROUP_NAME="www-vibe"
USER_COMMENT="Vibe user"
DEBIAN_USER="www-data"
DEBIAN_GROUP="www-data"


# throw error
ferror()
{
	for I in "$@"
	do
		echo "$I" >&2
	done
	exit 1
}


# script help
fhelp()
{
	echo "Script to install and remove 'vibe' on Linux."
	echo
	echo "Usage:"
	echo "  $0 [ -i | -r | -h ] "
	echo
	echo "Options:"
	echo "  -i     installs vibe"
	echo
	echo "  -r     removes vibe"
	echo
	echo "  -h     show this help"
}


# force to be root
froot()
{
	test "root" != "$USER" && echo "'root' privileges required..." && exec sudo "$@"
	echo -en "\033[0A                              \015"
}


fremove()
{
	# remove user if present in log file
	if grep "^user: $USER_NAME$" $LOG_FILE >/dev/null 2>&1
	then
		/usr/sbin/userdel $USER_NAME >/dev/null 2>&1 && echo "'$USER_NAME' user removed."
		sed -i "/^user: $USER_NAME$/d" $LOG_FILE >/dev/null 2>&1
	fi

	# remove group if present in log file
	if grep "^group: $GROUP_NAME$" $LOG_FILE >/dev/null 2>&1
	then
		/usr/sbin/groupdel $GROUP_NAME >/dev/null 2>&1 && echo "'$GROUP_NAME' group removed."
		sed -i "/^group: $GROUP_NAME$/d" $LOG_FILE >/dev/null 2>&1
	fi

	# remove log file if no data
	if [ -f $LOG_FILE ] && [ -z $(tr -d '[ \t\r\n]' 2>/dev/null <$LOG_FILE) ]
	then
		rm -f $LOG_FILE
	fi
	rmdir $LOG_DIR >/dev/null 2>&1 || :

	# remove config file
	echo "Removing configuration file $CONFIG_FILE..."
	rm -f $CONFIG_FILE
	rmdir $CONFIG_DIR >/dev/null 2>&1 || :

	# remove menu entry
	rm -f $MENU_FILE
	rmdir $MENU_DIR >/dev/null 2>&1 || :

	# remove files
	echo "Removing 'vibe' files in $BASE_DIR/..."
	rm -Rf $BASE_DIR/
}


finstall()
{
	# check if vibe sources
	if [ ! -f $SRC_DIR/source/vibe/vibe.d ]
	then
		ferror "$0: FATAL ERROR! missing 'vibe' sources!" "Try '$0 -h' for more information."
	fi

	# install files
	echo "Installing 'vibe' files in $BASE_DIR/..."
	cp -Rf $SRC_DIR/{source/,docs/,examples/} $BASE_DIR/

	# create menu entry
	if [ -f $BASE_DIR/docs/index.html ]
	then
		mkdir -p $MENU_DIR
		echo "[Desktop Entry]" >$MENU_FILE
		echo "Type=Application" >>$MENU_FILE
		echo "Name=Vibe Documentation" >>$MENU_FILE
		echo "Comment=Vibe web framework documentation" >>$MENU_FILE
		echo "Exec=xdg-open $BASE_DIR/docs/index.html" >>$MENU_FILE
		echo "Icon=html" >>$MENU_FILE
		echo "Categories=Development;" >>$MENU_FILE
	else
		unset MENU_DIR MENU_FILE
	fi

	# user/group administration
	if getent group $DEBIAN_GROUP >/dev/null && getent passwd $DEBIAN_USER >/dev/null
	then
		GROUP_NAME=$DEBIAN_GROUP
		USER_NAME=$DEBIAN_USER
	else
		# creating group if he isn't already there
		if ! getent group $GROUP_NAME >/dev/null
		then
			echo "Creating group $GROUP_NAME..."
			/usr/sbin/groupadd -r $GROUP_NAME
			mkdir -p $LOG_DIR
			echo "group: $GROUP_NAME" >>$LOG_FILE
		fi
		# creating user if he isn't already there
		if ! getent passwd $USER_NAME >/dev/null
		then
			echo "Creating user $USER_NAME..."
			/usr/sbin/useradd -r -g $GROUP_NAME -c "$USER_COMMENT" $USER_NAME
			mkdir -p $LOG_DIR
			echo "user: $USER_NAME" >>$LOG_FILE
		fi
	fi

	# create/update config file
	echo "Creating config file $CONFIG_FILE..."
	mkdir -p $CONFIG_DIR
	echo '{' >$CONFIG_FILE
	echo '	"user": "'$USER_NAME'",' >>$CONFIG_FILE
	echo '	"group": "'$GROUP_NAME'"' >>$CONFIG_FILE
	echo '}' >>$CONFIG_FILE

	# set files/folders permissions
	chmod 0755 $(find $BASE_DIR/ -type d) $CONFIG_DIR $MENU_DIR
	chmod 0644 $(find $BASE_DIR/ ! -type d) $CONFIG_FILE $MENU_FILE

	# if everything went fine
	echo -e "\n  \033[32;40;7;1mvibe.d installed successfully!\033[0m\n"
	echo "You need to have the following dependencies installed:"
	echo "  ·dmd 2.061 - http://dlang.org"
	echo "  ·libssl (development files) - http://www.openssl.org/"
	echo "  ·libevent 2.0.x (development files) - http://libevent.org/"
	echo -e "\ntake a look at examples on $BASE_DIR/examples/"
}


# check if more than one argument
if [ $# -gt 1 ]
then
	ferror "$0: too many arguments" "Try '$0 -h' for more information."
fi


# check first argument
case "$1" in
-h|-H)
    fhelp
    ;;
-i|-I)
    froot $0 "$@"
    finstall
    ;;
-r|-R)
    froot $0 "$@"
    fremove
    ;;
"")
    ferror "$0: missing argument" "Try '$0 -h' for more information."
    ;;
*)
    ferror "$0: unknown argument '$1'" "Try '$0 -h' for more information."
    ;;
esac
