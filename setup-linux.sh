#!/bin/bash


set -e


# set variables
PREFIX="/usr/local"
BASE_DIR="$PREFIX/share/vibe"
USER_NAME="www-vibe"
GROUP_NAME="www-vibe"
USER_COMMENT="Vibe user"
CONFIG_FILE="/etc/vibe/vibe.conf"
SYMLINK_FILE="$PREFIX/bin/vibe"
LOG_FILE="/var/spool/vibe/install.log"
MENU_FILE="$PREFIX/share/applications/vibe.desktop"
DEBIAN_USER="www-data"
DEBIAN_GROUP="www-data"


fhelp()
{
	# script help
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


froot()
{
	# force to be root
	test "root" != "$USER" && echo '"root" privileges required...' && exec sudo "$@"
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
		rmdir $(dirname $LOG_FILE) >/dev/null 2>&1 || :
	fi

	# remove config file
	echo "Removing configuration file $CONFIG_FILE..."
	rm -f $CONFIG_FILE
	rmdir $(dirname $CONFIG_FILE) >/dev/null 2>&1 || :

	# remove symlink
	echo "Removing symlink $SYMLINK_FILE..."
	rm -f $SYMLINK_FILE

	# remove menu entry
	rm -f $MENU_FILE
	rmdir $(dirname $MENU_FILE) >/dev/null 2>&1 || :

	# remove files
	echo "Removing files in $BASE_DIR/..."
	rm -Rf $BASE_DIR/
}


finstall()
{
	# install files
	echo "Installing files in $BASE_DIR/..."
	mkdir -p $BASE_DIR/bin/
	cp -Rf bin/{vibe,vpm.d} $BASE_DIR/bin/
	cp -Rf {source/,docs/,examples/} $BASE_DIR/

	# create menu entry
	if [ -f $BASE_DIR/docs/index.html ]
	then
		mkdir -p $(dirname $MENU_FILE)
		echo "[Desktop Entry]" >$MENU_FILE
		echo "Type=Application" >>$MENU_FILE
		echo "Name=Vibe Documentation" >>$MENU_FILE
		echo "Comment=Vibe web framework documentation" >>$MENU_FILE
		echo "Exec=xdg-open $BASE_DIR/docs/index.html" >>$MENU_FILE
		echo "Icon=html" >>$MENU_FILE
		echo "Categories=Development;" >>$MENU_FILE
	else
		unset MENU_FILE
	fi

	# create a symlink to the vibe script
	echo "Creating symlink in $SYMLINK_FILE..."
	ln -sf $BASE_DIR/bin/vibe $SYMLINK_FILE

	# creating group if he isn't already there
	if getent group $DEBIAN_GROUP >/dev/null
	then
		GROUP_NAME=$DEBIAN_GROUP
	elif ! getent group $GROUP_NAME >/dev/null
	then
		echo "Creating group $GROUP_NAME..."
		/usr/sbin/groupadd -r $GROUP_NAME >/dev/null
		mkdir -p $(dirname $LOG_FILE)
		echo "group: $GROUP_NAME" >>$LOG_FILE
	fi

	# creating user if he isn't already there
	if getent passwd $DEBIAN_USER >/dev/null
	then
		USER_NAME=$DEBIAN_USER
	elif ! getent passwd $USER_NAME >/dev/null
	then
		echo "Creating user $USER_NAME..."
		/usr/sbin/useradd -r -g $GROUP_NAME -c "$USER_COMMENT" $USER_NAME >/dev/null
		mkdir -p $(dirname $LOG_FILE)
		echo "user: $USER_NAME" >>$LOG_FILE
	fi

	# create/update config file
	echo "Creating new config file in $CONFIG_FILE..."
	mkdir -p $(dirname $CONFIG_FILE)
	echo '{' >$CONFIG_FILE
	echo '	"user": "'$USER_NAME'",' >>$CONFIG_FILE
	echo '	"group": "'$GROUP_NAME'"' >>$CONFIG_FILE
	echo '}' >>$CONFIG_FILE

	# set files/folders permissions
	chmod 0755 $(find $BASE_DIR/ -type d) $(dirname $CONFIG_FILE)
	chmod 0644 $(find $BASE_DIR/ ! -type d) $CONFIG_FILE $MENU_FILE
	chmod 0755 $SYMLINK_FILE

	# if everything went fine
	echo -e "\n \033[32;40;7;1m 'vibe' installed successfully! \033[0m\n"
	echo "You need to have the following dependencies installed:"
	echo "  ·dmd 2.061 - http://dlang.org"
	echo "  ·libssl (development files) - http://www.openssl.org/"
	echo "  ·libevent 2.0.x (development files) - http://libevent.org/"
	echo -e "\ntake a look at examples on $BASE_DIR/examples/"
}


# check if in vibe source root
if [ ! -f bin/vibe ] || [ ! -f source/vibe/vibe.d ]
then
	echo -e "Must be run from 'vibe' source root.\nExiting..." >&2
	exit 1
fi


# check argument
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
    echo -e "$0: missing argument\nTry '$0 -h' for more information." >&2
    exit 1
    ;;
*)
    echo -e "$0: unknown argument '$1'.\nTry '$0 -h' for more information." >&2
    exit 1
    ;;
esac
