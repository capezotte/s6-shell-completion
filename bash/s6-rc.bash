#!/usr/bin/env bash
# bash completion for s6/s6-rc

# adds yet-unused options and actions to COMPREPLY
# side effect: sets _s6_action and _s6_opt_[A-Za-z0-9] variables if they are found
# usage: __s6_getopt optspec actions
# example: __s6_getopt v:l:t:n:audDp change diff
# example: __s6_getopt upo:
__s6_getopt() {
	local i optspec="$1" opt opts='' optsarg=''

	# basic optspec parse
	for ((i=0;i<${#optspec};i++)); do
		opt="-${optspec:i:1}"
		if [ "${optspec:i+1:1}" = : ]; then
			optsarg="${optsarg}${opt}"
			((i++))
		fi
		opts="${opts}${opt}"
	done

	shift

	local word prevword action end_opt='' remain_opts=$opts
	for ((i=1;i<COMP_CWORD;i++)); do
		word=${COMP_WORDS[i]} prevword=${COMP_WORDS[i-1]}

		if [ ! "$end_opt" ]; then
			if [[ $prevword = -[a-zA-Z0-9] ]] && [[ "$optsarg-" = *"$prevword-"* ]]; then
				# TODO figure out the problem with declare -g
				eval "_s6_opt_${prevword#-}=${word@Q}"
			elif [[ "$word" = -- ]] || [[ "$word" != -* ]]; then
				# invalid option stops option processing in every s6 program
				remain_opts=''
				end_opt=x
				# quit here if no actions
				(($#>0)) || break
			else
				# current word is an option; delet it from list of available
				# TODO: check if any skarnet software allow giving an option more than once
				[[ $word != -* ]] || remain_opts=${remain_opts/"${word}"}
			fi
		fi

		# first non option argument must be an action
		if [ "$end_opt" ]; then
			for action; do
				if [ "$word" = "$action" ]; then
					set --
					_s6_action=$word
					break 2
				fi
			done
		fi

	done

	# add options
	local IFS=-
	for opt in ${remain_opts#-}; do
		COMPREPLY+=( "-$opt" )
	done
	# add actions
	COMPREPLY=( "${COMPREPLY[@]}" "$@" )
}

# shorthand for s6-rc-db list ...
__s6rc_db() {
	local IFS=$'\n' args=()
	[ ! "$_s6_opt_c" ] || args+=( "-c$_s6_opt_c" )
	[ ! "$_s6_opt_l" ] || args+=( "-l$_s6_opt_l" )
	COMPREPLY+=( $(command s6-rc-db "${args[@]}" -- list "$@") )
}

_s6-svc() {
	local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]} i words=${#COMP_WORDS[@]}
	case $prev in
	(-w) COMPREPLY+=(u U d D r R) ;;
	(-T) return ;;
	(*)
		compopt -o plusdirs -o nosort
		# cursed_optspec.sh
		local _s6_opt_{w,T}
		__s6_getopt w:abqhkKti12pPcCyrodDuxOXT:
	esac
	# Do matching
	COMPREPLY=( $(compgen -W '${COMPREPLY[@]}' -- "${cur}") )
}

_s6-svstat() {
	local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]} IFS=,
	case $prev in
	(-o)
		# So we can give commas
		compopt -o nospace
		# Find current and previous items.
		local curitem="${cur##*,}" before="${cur%,*}" \
		fields='up,wantedup,normallyup,ready,paused,pid,pgid,exitcode,signal,signum,updownsince,readysince,updownfor,readyfor,'

		# Remove already used fields
		for i in $before; do
			fields=${fields//"$i,"}
		done

		if [[ ",$fields" = *",$curitem,"* ]]; then
			# we have a full field name, just give user a comma
			COMPREPLY=( "$cur," )
		elif [[ "$before" = "$curitem" ]]; then
			# first field, give them all as option
			COMPREPLY=( $fields )
		else
			# Buld actual reply
			for i in $fields; do
				COMPREPLY+=( "$before,$i" )
			done
		fi
	;;
	(*)
		compopt -o plusdirs
		local _s6_opt_o
		__s6_getopt uwNrpesto:
	;;
	esac
	# change IFS
	IFS=$'\n'
	COMPREPLY=( $(compgen -W '${COMPREPLY[@]}' -- "${cur}") )
}

_s6-rc-db() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
	local _s6_opt_c='' _s6_opt_l='' _s6_action=''

	# Need to set _s6_opt_{c,l} for __s6rc_db
	__s6_getopt udbc:l: \
		help check list \
		type timeout contents \
		dependencies pipeline script \
		flags atomics all-dependencies

	case $prev in
	(help|check) return ;;
	(list) COMPREPLY=( all services oneshots longruns bundles ) ;;
	(type) __s6rc_db all ;;
	(timeout|flags) __s6rc_db services ;;
	(contents) __s6rc_db bundles ;;
	(pipeline) __s6rc_db longruns ;;
	(script) __s6rc_db oneshots ;;
	(-c|-l)
		compopt -o plusdirs
		return
	;;
	(*)
		case $_s6_action in
		(*dependencies|atomics) __s6rc_db all ;;
		esac
	;;
	esac
	COMPREPLY=( $(compgen -W '${COMPREPLY[@]}' -- "${cur}") )
}

_s6-rc() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}" startstop
	case $prev in
	(-v) COMPREPLY=( {1..3} ) ;;
	(-t|-n) return ;;
	(-l)
		compopt -o plusdirs
		return
	;;
	(start|stop)
		if [ "$prev" = start ]; then
			startstop=-u
		else
			startstop=-d
		fi
		COMP_WORDS=( "${COMP_WORDS[@]:0:COMP_CWORD-1}" "$startstop" change "$cur" )
		((COMP_CWORD+=2))
	;&
	(*)
		local _s6_opt_{v,t,n} _s6_opt_l='' _s6_action='' IFS=$'\n'
		__s6_getopt badDuv:t:n:l: change list{,all} diff start stop help

		if [ "${_s6_action:-help}" != help ]; then
			__s6rc_db all
		fi

		COMPREPLY=( $(compgen -W '${COMPREPLY[@]}' -- "$cur") )
	;;
	esac
}

complete -F {_,}s6-svc
complete -F {_,}s6-svstat
complete -F {_,}s6-rc
complete -F {_,}s6-rc-db
