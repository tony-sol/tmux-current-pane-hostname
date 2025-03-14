#!/usr/bin/env bash

get_info() {
	local host port user
	local cmd=$(__current_pane_command)
	if __ssh_cmd "$cmd"; then
		cmd=$(echo "$cmd" | grep -E 'ssh' | sed -E 's/^.*ssh //')
		IFS=' ' read -r host port user <<<$(__get_ssh_info "$cmd")
	elif __mosh_cmd "$cmd"; then
		cmd=$(echo "$cmd" | grep -E 'mosh' | sed -E 's/^.*mosh(-client)? //')
		IFS=' ' read -r host port user <<<$(__get_mosh_info "$cmd")
	elif __containered_cmd "$cmd"; then
		cmd=$(echo "$cmd" | grep -E 'docker|podman' | sed -E 's/^[[:blank:]]* //')
		IFS=' ' read -r host user <<<$(__get_container_info "$cmd")
	else
		IFS=' ' read -r host user <<<$(__get_local_info)
	fi
	# Set defaults
	user="${user:-$(__get_username)}"
	host="${host:-$(__get_hostname)}"

	# Return requested info
	case "$1" in
		"user")
			echo "$user"
			;;
		"host")
			echo "$host"
			;;
		"host_short")
			[[ -z "$host" ]] && __get_hostname_short || echo "$host"
			;;
		"port")
			echo "$port"
			;;
		*)
			echo "${user}#${host}#${port}"
			;;
	esac
}

ssh_connected() {
	local cmd=$(__current_pane_command)
	__ssh_cmd "$cmd"
}

mosh_connected() {
	local cmd=$(__current_pane_command)
	__mosh_cmd "$cmd"
}

containered() {
	local cmd=$(__current_pane_command)
	__containered_cmd "$cmd"
}

__ssh_cmd() {
	[[ $1 =~ (^|^[[:blank:]]*|/)ssh[[:blank:]] ]] || [[ $1 =~ (^|^[[:blank:]]*|/)sshpass[[:blank:]] ]]
}

__mosh_cmd() {
	[[ $1 =~ (^|^[[:blank:]]*|/)mosh[[:blank:]] ]] || [[ $1 =~ (^|^[[:blank:]]*|/)mosh-client[[:blank:]] ]]
}

__containered_cmd() {
	[[ $1 =~ (^|^[[:blank:]]*|/)docker[[:blank:]] ]] || [[ $1 =~ (^|^[[:blank:]]*|/)podman[[:blank:]] ]]
}

__current_pane_command() {
	local ppid=$(tmux display-message -p "#{pane_pid}")
	local pid command cmd

	while [[ -n "$ppid" ]] ; do
		IFS=' ' read -r ppid pid command <<<$(ps a -o ppid=,pid=,command= | grep -E "^[[:blank:]]*$ppid")
		[[ -z "$command" ]] && break
		# @hack in case of ProxyJump, ssh spawns a new ssh connection to jump host as child process
		# in that case, check if both parent and child processes are ssh, select parent one's cmd
		__ssh_cmd "$cmd" && __ssh_cmd "$command" && break
		ppid="$pid"
		cmd="$command"
	done

	echo "$cmd"
}

__get_ssh_info() {
	local cmd="$1"
	# Fetch configuration with given cmd
	# Depending of ssh version, configuration output may or may not contain `host` directive
	# Check both `host` and `hostname` for old ssh versions compatibility and prefer `host` if exists
	ssh -TGN $cmd 2>/dev/null | grep -E -e '^host(name)?\s' -e '^port\s' -e '^user\s' | sort --unique --key 1,1.4 | cut -f 2 -d ' ' | xargs
}

# @see https://github.com/mobile-shell/mosh/blob/master/scripts/mosh.pl#L465
__get_mosh_info() {
	local cmd="$1"

	# ip and port placed after pipe separator in cmd
	local ip port
	IFS=' ' read -r ip port <<<"${cmd##*|[[:blank:]]}"

	# Clean cmd from ip-port
	cmd="${cmd%%|*}"

	# @bug the main problem starts here:
	# i don't see, how to fetch `--ssh` from cmd not touching original hostname (to parse mosh2ssh overrides)
	# due to passing variables into functions in bash is tricky:
	# @see https://mywiki.wooledge.org/BashFAQ/050
	# and `--ssh` may be before or after original hostname
	# So, next code works only in the simplest scenarios, like `mosh hostname`
	# @todo probably, passing $cmd all over the places should be rewritten to passing an array instead of string

	# Fetch initial ssh command
	local ssh
	ssh="${cmd#*#[[:blank:]]}"
	ssh="${ssh%%[[:blank:]]*}"

	# Fetch extra ssh options
	local ssh_options
	if [[ $cmd =~ ' --ssh' ]]; then
		ssh_options="${cmd##* --ssh}"
		ssh_options="${ssh_options/[[:blank:]]ssh[[:blank:]]/}"
		# @bug must trim short flags after `--ssh`
		ssh_options="${ssh_options%%--*}"
	fi

	local host user
	IFS=' ' read -r host _ user <<<$(__get_ssh_info "$ssh_options $ssh")
	echo "${host:-$ip} $port $user"
}

__get_container_info() {
	local cmd="$1"

	local container
	local runner=${cmd%% *}
	if [[ $cmd =~ ' --name' ]]; then
		container=$(echo ${cmd##* --name} | cut -f 1 -d ' ')
		container=${container##*=}
	else
		# @TODO get dynamic named container
		# local all_running_containers=$($runner ps -q | xargs $runner inspect)
		__get_local_info
		return
	fi

	local format
	case $runner in
		'docker')
			format='{{ .Config.Hostname }}/{{ .Config.Domainname }}/{{ .Config.User }}'
			;;
		'podman')
			format='{{ .Config.Hostname }}/{{ .Config.DomainName }}/{{ .Config.User }}'
			;;
	esac

	local info=$($runner inspect --format "$format" "$container")
	local host=$(echo $info | cut -f 1 -d '/')
	local domain=$(echo $info | cut -f 2 -d '/')
	local user=$(echo $info | cut -f 3 -d '/')

	echo "${host}${domain:+.$domain} ${user}"
}

__get_local_info() {
	local user=$(__get_username)
	local host=$(__get_hostname)

	echo "${host} ${user}"
}

__get_username() {
	command -v whoami > /dev/null && whoami
}

__get_hostname() {
	command -v hostname > /dev/null && hostname || echo "${HOSTNAME}"
}

__get_hostname_short() {
	command -v hostname > /dev/null && hostname --short || echo "${HOSTNAME%%.*}"
}
