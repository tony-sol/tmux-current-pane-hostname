#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $CURRENT_DIR/shared.sh

main() {
	# @TODO user-formatted pane_ssh_connect output
	# local info user host port
	# info="$(get_info)"
	# IFS='#' read -r user host port <<< "$info"
	# # eval is literaly evil, so i won't use this
	# # eval echo $(get_tmux_option $pane_ssh_connect_format)
	# get_tmux_option $pane_ssh_connect_format | sed \
	# 	-e "s/%{user}/$user/" \
	# 	-e "s/%{host}/$host/" \
	# 	-e "s/%{port}/$port/"

	get_info
}

main
