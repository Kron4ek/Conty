#!/bin/bash

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

chrootEnvPath="${script_dir}"/root.x86_64



#### This part is for args pharm
if [ "$1" = "" ];then
container_command="bash"
else
container_command="$1"
shift
for arg in "$@"; do
        arg="$(echo "${arg}x" | sed 's|'\''|'\'\\\\\'\''|g')"
        arg="${arg%x}"
        container_command="${container_command} '${arg}'"
done
fi
#########################################################################################
##########Construct bwrap command Step 1. Basic functions
# Init EXEC_COMMAND as bwrap 
EXEC_COMMAND="bwrap"



# add_command 
function add_command() {
    # pharm merge
    for arg in "$@"; do
        EXEC_COMMAND="${EXEC_COMMAND} ${arg}"
    done
}

function add_env_var() {
    local var_name="${1}"
    local var_value="${2}"
    if [ "$var_value" != "" ]; then    
	add_command "--setenv $var_name $var_value"
	
    fi
}
##########Construct bwrap command Step 2. Other functions config

# Fix: cursor theme can not be the same as the host machine
function cursor_theme_dir_integration() {

local directory=""
if [ "$(id -u)" = "0" ]; then #####We don't want bother root to install themes,but will try to fix the unwriteable issue
	mkdir -p $chrootEnvPath/usr/share/icons
	chmod 777 -R $chrootEnvPath/usr/share/icons
	return
fi

for directory in "/usr/share/icons"/*; do
    # 检查是否为目录
    if [ -d "$directory" ]; then
        # 检查目录中是否存在 cursors 文件
        if [ -d "$directory/cursors" ]; then
        	if [ -w $chrootEnvPath/usr/share/icons ];then
			add_command "--ro-bind-try $directory $directory"
		fi
        fi
    fi
done







}
##########Construct bwrap command Step 3. Env vars and directory mounting
ENV_VARS=(
    "LANG $LANG"
    "LC_COLLATE $LC_COLLATE"
    "LC_CTYPE $LC_CTYPE"
    "LC_MONETARY $LC_MONETARY"
    "LC_MESSAGES $LC_MESSAGES"
    "LC_NUMERIC $LC_NUMERIC"
    "LC_TIME $LC_TIME"
    "LC_ALL $LC_ALL"
    "PULSE_SERVER /run/user/\$uid/pulse/native"
    "IS_ACE_ENV 1"
)

BIND_DIRS=(
    "--dev-bind $chrootEnvPath/ /"
    "--dev-bind-try /media /media"
    "--dev-bind-try /mnt /mnt"
    "--dev-bind-try /tmp /tmp"
    "--dev-bind-try /data /data"
    "--dev-bind-try /dev /dev"
    "--proc /proc"
    "--dev-bind /sys /sys"
    "--dev-bind /run /run"
    "--dev-bind-try /run/user/\$uid/pulse /run/user/\$uid/pulse"
    "--dev-bind / /host"
    "--ro-bind-try /usr/share/themes /usr/local/share/themes"
    "--ro-bind-try /usr/share/icons /usr/local/share/icons"
    "--ro-bind-try /usr/share/fonts /usr/local/share/fonts"
    "--dev-bind-try /etc/resolv.conf /etc/resolv.conf"
    "--dev-bind-try /home /home"
)
EXTRA_ARGS=(
    "--hostname Amber-CE-Arch"
    "--unshare-uts"
    "--cap-add CAP_SYS_ADMIN"
)

EXTRA_SCRIPTS=(
    cursor_theme_dir_integration
)

##########Construct bwrap command Step 4. Merge and run

for var in "${ENV_VARS[@]}"; do
    add_env_var $var
done

for var in "${BIND_DIRS[@]}"; do
    add_command "$var"
done

for var in "${EXTRA_ARGS[@]}"; do
    add_command "$var"
done

for var in "${EXTRA_SCRIPTS[@]}"; do
    $var
done


add_command "bash -c \"${container_command}\""

eval ${EXEC_COMMAND}


