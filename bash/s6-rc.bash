#!/usr/bin/env bash
#shellcheck disable=SC2016,SC2207

# bash completion for s6/s6-rc

# returns true if $1 looks like a long option
__is_gol() {
	[[ "$1" == --+([A-Za-z-])* ]]
}

# trims long options to option name
# side effect: sets opt
__trim_gol() {
	# shellcheck disable=SC2154
	__is_gol "${1}" || return 1
	opt=${1}
	opt=${opt#--}
	opt=${opt%%=*}
}

# FIXME: Whoever invented bash's handling of equals wanted completion writers to suffer
# usage __longopt_fix index
# index must be a var name
# cur and prev must be set
# return 0 if fix applied, 1 if not
# side effect: sets prev
__longopt_fix() {
	local i=${!1}
	if [ "$i" -ge 2 ] && [ "$prev" = = ] && __is_gol "${COMP_WORDS[i-2]}"; then
		prev=${COMP_WORDS[i-2]}
		return 0
	fi
	return 1
}

# adds yet-unused options and actions to COMPREPLY
# side effect: sets _s6_action and _s6_opt_[A-Za-z0-9] variables if they are found
# side effect: sets _s6_action_i (index of first non-option arg)
# side effect: can override compopt nospace
# usage: __s6_getopt optspec longopt=var longopt= actions
# example: __s6_getopt v:l:t:n:audDp change diff
# example: __s6_getopt upo:
__s6_getopt() {
	local i optspec="$1" opt val opts='' optsarg='' real_cur="$cur"
	declare -A longopts longoptsarg short2long

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

	# optspec 2.0
	while [[ "$1" == *'='* ]]; do
		opt=${1%%=*}
		val=${1#*=}
		longopts["${opt}"]='+'
		# if it corresponds to a short option without argument, don't count it as a long option with argument
		if [ "${#val}" -gt 1 ] || [[ -n "${val}" && "$optsarg" == *"-$val"* ]]; then
			longoptsarg["${opt}"]="${val}"
		fi
		if [ "${#val}" -eq 1 ]; then
			longopts["$opt"]="$val"
			short2long["$val"]="${opt}"
		fi
		shift
	done

	local cur prev action end_opt='' remain_opts=$opts fixret=0
	_s6_action_i=$COMP_CWORD
	for ((i=1;i<COMP_CWORD;i++)); do
		cur=${COMP_WORDS[i]} prev=${COMP_WORDS[i-1]}
		__longopt_fix i
		fixret=$?


		if [ ! "$end_opt" ]; then
			if [[ $prev = -[a-zA-Z0-9] ]] && [[ "$optsarg-" = *"$prev-"* ]]; then
				# TODO figure out the problem with declare -g
				eval "_s6_opt_${prev#-}=${cur@Q}"
			elif [ "$fixret" -eq 0 ] && __trim_gol "$prev" && [[ -v 'longoptsarg[$opt]' ]]; then
				eval "_s6_opt_${longoptsarg[$opt]}=${cur@Q}"
			elif [ "$cur" = '=' ] && __is_gol "$prev"; then
				: # prevent this from counting as "not option" below
			elif [[ "$cur" == -- ]] || [[ "$cur" != -* ]]; then
				# invalid option stops option processing in every s6 program
				remain_opts=''
				longopts=()
				end_opt=x
			else
				# current word is an option; delet it from list of available
				# TODO: check if any skarnet software allow giving an option more than once
				if __trim_gol "$cur" && [[ -v 'longopts[$opt]' ]]; then
					# remove corresponding short option
					remain_opts=${remain_opts/"-${longopts[$opt]}"}
					unset 'longopts[$opt]'
				fi
				if [[ $cur == -* ]]; then
					# remove corresponding long option
					# shellcheck disable=SC2034
					if [ -v 'short2long[${cur#-}' ]; then
						local longopt="${short2long[${cur#-}]}"
						unset 'longopts["$longopt"]'
					fi
					remain_opts=${remain_opts/"${cur}"}
				fi
			fi
		fi

		# first non option argument must be an action
		if [ "$end_opt" ]; then
			for action; do
				if [ "$cur" = "$action" ]; then
					set --
					_s6_action=$cur
					break
				fi
			done
			_s6_action_i="$i"
			break
		fi

	done

	# add options
	compopt +o nospace
	# check so we don't set -o nospace when it clearly won't happen
	if [ -z "$real_cur" ] || [[ "$real_cur" = -* ]]; then
		local IFS=-
		: remainopts "${remain_opts}"
		for opt in ${remain_opts#-}; do
			COMPREPLY+=( "-$opt" )
		done
		for opt in "${!longopts[@]}"; do
			if [[ -v 'longoptsarg[$opt]' ]]; then
				[[ "--$opt" != "$real_cur"* ]] || compopt -o nospace
				COMPREPLY+=( "--$opt=" )
			else
				COMPREPLY+=( "--$opt" )
			fi
		done
	fi
	# add actions
	COMPREPLY=( "${COMPREPLY[@]}" "$@" )
}

# shorthand for s6-rc-db list ...
__s6rc_db() {
	local args=()
	[ ! "$_s6_opt_c" ] || args+=( "-c$_s6_opt_c" )
	[ ! "$_s6_opt_l" ] || args+=( "-l$_s6_opt_l" )
	mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < <(command s6-rc-db "${args[@]}" -- list "$@")
}

__s6rc_rlist() {
	mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < <(command s6-rc-repo-list ${_s6_opt_r+-r"${_s6_opt_r}"})
}

# repo reference db
__s6rc_rdb() {
	local repo
	if [ -v _s6_opt_r ]; then
		repo=$_s6_opt_r
	else
		# TODO: somehow find the compiled-in defaults
		repo=/var/lib/s6-rc/repository
	fi
	mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < <(command s6-rc-db -c "$repo/compiled/.ref" -- list "$@")
}

_s6-svc() {
	local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]} i
	case $prev in
	(-w) COMPREPLY+=(u U d D r R) ;;
	(-T) return ;;
	(*)
		compopt -o plusdirs -o nosort
		# cursed_optspec.sh
		local _s6_opt_{w,T} _s6_action_i
		__s6_getopt w:abqhkKti12pPcCyrodDuxOXT:
	esac

	mapfile -t COMPREPLY <<< "$(compgen -W '${COMPREPLY[@]}' -- "${cur}")"
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
		local _s6_opt_o _s6_action_i
		__s6_getopt uwNrpesto:
	;;
	esac

	mapfile -t COMPREPLY <<< "$(compgen -W '${COMPREPLY[@]}' -- "${cur}")"
}

_s6-rc-db() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
	local _s6_opt_c='' _s6_opt_l='' _s6_action='' _s6_action_i

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
	mapfile -t COMPREPLY <<< "$(compgen -W '${COMPREPLY[@]}' -- "${cur}")"
}

_s6-rc() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}" startstop
	case $prev in
	(-v)
		COMPREPLY=( {0..3} )
		return
	;;
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
		local _s6_opt_{v,t,n} _s6_opt_l='' _s6_action='' _s6_action_i IFS=$'\n'
		__s6_getopt badDuv:t:n:l:Ee change list{,all} diff start stop help

		if [ "${_s6_action:-help}" != help ]; then
			__s6rc_db all
		fi
	;;
	esac

	mapfile -t COMPREPLY <<< "$(compgen -W '${COMPREPLY[@]}' -- "${cur}")"
}


# Meta wrapper for all s6-rc-set thing
# side effect: sets _s6_opt_{v,r} and possibly _s6_opt_{h,D,r,c,l,f}
# usage: _s6rc_set optspec longopts
_s6rc_set() {
	local pre=''
	if [ -v 1 ]; then
		pre=$1
		shift
	fi
	__longopt_fix COMP_CWORD

	case $prev in
		(--fdhuser|-h)
			mapfile -t COMPREPLY < <(cut -d: -f1 /etc/passwd)
			return
			;;
		(--default-bundle|-D) return ;;
		(-I|--if-dependencies-found)
			COMPREPLY=( fail pull warn )
			return
			;;
		(-r|--repository|-c|--bootdb|-l|--livedir)
			COMPREPLY=()
			compopt -o plusdirs
			return
			;;
		(-v|--verbosity)
			COMPREPLY=( {0..3} )
			return
			;;
		(-f|--conv-file)
			compopt -o filenames
			mapfile -t COMPREPLY <<< "$(compgen -A file -- "$cur")"
			return 1
		;;
	esac

	__s6_getopt "${pre}v:r:" 'verbosity=v' 'repository=r' "$@"
}

_s6-rc-set-new() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}" \
		_s6_opt_{v,r} _s6_action_i
	_s6rc_set
	mapfile -t COMPREPLY <<< "$(compgen -W '${COMPREPLY[@]}' -- "${cur}")"
}
_s6-rc-set-delete() { _s6-rc-set-new; }

_s6-rc-set-copy() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}" \
		_s6_opt_{v,r} _s6_action_i
	_s6rc_set f 'force=f'
	if [ "$((COMP_CWORD-_s6_action_i))" -eq 0 ]; then
		__s6rc_rlist
	fi
	mapfile -t COMPREPLY <<< "$(compgen -W '${COMPREPLY[@]}' -- "${cur}")"
}

_s6-rc-set-change() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}" \
		_s6_opt_{I,v,r} _s6_action_i
	_s6rc_set I:Eenf \
		'force-essential=e' 'no-force-essential=E' \
		'ignore-dependencies=f' 'if-dependencies-found=I' \
		'dry-run=n'
	case "$((COMP_CWORD-_s6_action_i))" in
		0) __s6rc_rlist ;;
		1) COMPREPLY=( masked disabled enabled essential ) ;;
		*) __s6rc_rdb all ;;
	esac
	mapfile -t COMPREPLY <<< "$(compgen -W '${COMPREPLY[@]}' -- "${cur}")"
}

_s6-rc-set-status() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}" \
		_s6_opt_{v,r} _s6_action_i
	_s6rc_set EeL 'with-essentials=E' 'without-essentials=E' 'list=L'
	case "$((COMP_CWORD-_s6_action_i))" in
		0) __s6rc_rlist ;;
		*) __s6rc_rdb all ;;
	esac
	mapfile -t COMPREPLY <<< "$(compgen -W '${COMPREPLY[@]}' -- "${cur}")"
}

_s6-rc-set-fix() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}" \
		_s6_opt_{v,r} _s6_action_i
	_s6rc_set udEen 'fix-up=u' 'fix-down=d' \
		'force-essential=e' 'no-force-essential=E' \
		'dry-run=n'
	__s6rc_rlist
	mapfile -t COMPREPLY <<< "$(compgen -W '${COMPREPLY[@]}' -- "${cur}")"
}

_s6-rc-set-commit() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}" \
		_s6_opt_{v,r,D,h} _s6_action_i
	_s6rc_set D:h:Kf \
		'default-bundle=D' 'fdhuser=h' 'keep=K' 'force=f'
	[ "$((COMP_CWORD-_s6_action_i))" -ne 0 ] || __s6rc_rlist
	mapfile -t COMPREPLY <<< "$(compgen -W '${COMPREPLY[@]}' -- "${cur}")"
}

_s6-rc-set-install() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}" \
		_s6_opt_{I,v,r,c,l,f} _s6_action_i
	__longopt_fix COMP_CWORD
	_s6rc_set c:l:f:bKeE \
		'bootdb=c' 'livedir=l' 'conversion-file=f' \
		'block=b' 'keep-old=K' \
		'force-essentials=e' 'no-force-essentials=E' \
		'no-update='
	[ "$((COMP_CWORD-_s6_action_i))" -ne 0 ] || __s6rc_rlist
	mapfile -t COMPREPLY <<< "$(compgen -W '${COMPREPLY[@]}' -- "${cur}")"
}

# s6-frontend completions
# For organization purposes, they're split in many smaller functions.
# An s6-frontend invocation looks like
# s6 [options] command subcommand [soptions] [args]
# Each subcommand gets dedicated functions. The main _s6 functions strips
# 's6 [options] command' from COMP_WORDS so they only see what they need:
# 'subcommand [soptions] [args]

_s6() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
	__longopt_fix COMP_CWORD || :

	case $prev in
	(-v|--verbosity)
		COMPREPLY=( {0..3} )
	;;
	(-s|--scandir|-l|--livedir|-r|--repodir|-c|--bootdb|--stmpdir|--storelist)
		compopt -o plusdirs
		return
	;;
	(--color)
		COMPREPLY=( yes no auto )
	;;
	(-h|--help|-V|--version) return ;;
	(*)
		local _s6_opt_{s,l,r,v,color,stmp} _s6_action _s6_action_i s6_cmd s6_subcmd

		__s6_getopt s:l:r:c:v: \
			'scandir=s' 'livedir=l' 'repodir=r' 'bootdb=c' 'verbosity=v' \
			'stmpdir=stmp' 'color=color' \
			help version process live repository set system

		case "$_s6_action" in
		(version|help) return ;;
		('') : ;; # if I could, I'd write goto #finish:
		(*)
			s6_cmd="$_s6_action"
			COMPREPLY=()
			((COMP_CWORD-=_s6_action_i))
			COMP_WORDS=( "${COMP_WORDS[@]:_s6_action_i}" )
			unset _s6_action _s6_action_i

			case "$s6_cmd" in
			(process) __s6_getopt '' help kill status start stop restart ;;
			(live)
				__s6_getopt '' help status \
					start stop restart \
					start-everything stop-everything \
					install
			;;
			(repository) __s6_getopt '' help init list check sync ;;
			(set)
				__s6_getopt '' help save load delete list status \
					enable disable mask unmask make-essential \
					check commit
			;;
			esac

			# mostly distro only, unless stuff really went wrong
			[ "$s6_cmd" != repository ] || return

			case $_s6_action in
			(help) return ;;
			('') : ;; # again, goto
			(*)
				s6_subcmd="$_s6_action"
				COMPREPLY=()
				((COMP_CWORD-=_s6_action_i))
				COMP_WORDS=( "${COMP_WORDS[@]:_s6_action_i}" )
				unset _s6_action _s6_action_i

				"_s6_${s6_cmd}_${s6_subcmd}" || return 0
			;;
			esac
		;;
		esac

	esac

#finish:
	if [ "$cur" != = ]; then
		mapfile -t COMPREPLY <<< "$(compgen -W '${COMPREPLY[@]}' -- "${cur}")"
	fi
}

# Begin subcommand functions.
# Subcommand functions must return 1 when they want _s6 to return immediately.
# They don't neet to set compreply to

# BEGIN: wrap common functionality of 's6 process start|stop' and 's6 live start|stop'

# Get configs from s6-frontend
# side effect: sets conf
_s6f_getconf() {
	conf=$(envfile -I -- "${S6_FRONTEND_CONF:-/etc/s6-frontend.conf}" \
		importas -i var "$1" \
		printf '%s\n' \$var 2>/dev/null)
}

_s6f_live() {
	local -I _s6_opt_l conf
	if [ ! -v _s6_opt_l ] && _s6f_getconf livedir; then
		_s6_opt_l="${conf}" __s6rc_db all
	else
		__s6rc_db all
	fi
}

# _s6f_repo list
# _s6f_repo db all|services|...
_s6f_repo() {
	local -I _s6_opt_r conf
	if [ ! -v _s6_opt_r ] && _s6f_getconf repodir; then
		_s6_opt_r="$conf" __s6rc_r"$1" "${@:2}"
	else
		__s6rc_r"$1" "${@:2}"
	fi
}

_s6f_processes() {
	local conf
	if [ -v _s6_opt_s ]; then
		conf=$_s6_opt_s
	elif _s6f_getconf scandir; then
		:
	else
		# TODO: find compiled-in default
		conf=/run/service
	fi
	mapfile -O "${#COMPREPLY[@]}" -td/ COMPREPLY <<< "$(cd -- "$conf" && printf '%s' */)"
}

# usage: _s6frontend_startstop servicename_source optspec longopts
_s6frontend_startstop() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}" svc_src=$1
	__longopt_fix COMP_CWORD
	shift

	case $prev in
		-t|--timeout) return 1 ;;
	esac

	local _s6_opt_t
	__s6_getopt "$@"
	"$svc_src"
}
# END: wrap

# s6 process

_s6_process_kill() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
	__longopt_fix COMP_CWORD

	case $prev in
		-t|--timeout) return 1 ;;
		# TODO: complete signal names
		-s) return 1 ;;
	esac

	local _s6_opt_{s,t}
	__s6_getopt Wws:t: 'wait=w' 'no-wait=W' 'signal=s' 'timeout=t'
	_s6f_processes
}

_s6_process_restartstop() {
	local pre=''
	if [ -v 1 ]; then
		pre="$1"
		shift
	fi
	_s6frontend_startstop \
		_s6f_processes \
		"${pre}wWt:" "$@" 'wait=w' 'no-wait=W' 'timeout=t'
}
_s6_process_start() { _s6_process_restartstop "pP" 'permanent=p' 'no-permanent=P'; }
_s6_process_stop() { _s6_process_start; }
_s6_process_restart() { _s6_process_restartstop; }

# s6 live

_s6_live_status() {
	__s6_getopt eE 'with-essentials=e' 'without-essentials=E'
	_s6f_live
}
_s6_live_start() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
	__longopt_fix COMP_CWORD
	case $prev in
		(-t|--timeout) return 1 ;;
	esac
	_s6frontend_startstop \
		_s6f_live \
		nt: 'dry-run=n' 'timeout=t'
}
_s6_live_stop() { _s6_live_start; }
_s6_live_restart() { _s6_live_start; }
_s6_live_install() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
	__longopt_fix COMP_CWORD

	case $prev in
		(-f|--conv-file)
			compopt -o filenames
			mapfile -t COMPREPLY <<< "$(compgen -A file -- "$cur")"
			return 1
		;;
	esac

	local _s6_opt_f
	__s6_getopt bKf: 'block=b' 'keep-old=K' 'conversion-file=f' 'init='
}
# mostly distro only commands
_s6_live_start-everything() { return 1; }
_s6_live_stop-everything() { return 1; }

# s6 set

_s6_set_save() { __s6_getopt f 'force=f'; }
_s6_set_load() { _s6f_repo list; }
_s6_set_delete() { _s6f_repo list; }
_s6_set_list() { __s6_getopt eE 'with-essentials=e' 'without-essentials=E'; }

_s6_set_status() {
	_s6_set_list
	_s6f_live
}

_s6_set_check() {
	__s6_getopt FduEe \
		'fix=F' 'no-force-essential=E' 'force-essential=e' \
		'up=u' 'down=d'
}

_s6_set_change() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
	__longopt_fix COMP_CWORD
	case $prev in
		-I|--if-dependencies-found)
			COMPREPLY=( fail pull warn )
			return
			;;
	esac
	__s6_getopt fnI: 'force=f' 'dry-run=n' 'if-dependencies-found=I'
	_s6f_repo db all
}
for _tool in enable disable mask unmask make-essential; do
	eval "_s6_set_${_tool}() { _s6_set_change; }"
done

_s6_set_commit() {
	local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
	__longopt_fix COMP_CWORD
	case $prev in
		-h|--fdholder-user)
			mapfile -t COMPREPLY < <(cut -d: -f1 /etc/passwd)
			return
			;;
		-D|--default-bundle) return 1 ;;
	esac
	__s6_getopt fKDh \
		'force=f' 'keep-old=K' 'fdholder-user=h' 'default-bundle=D'
}

complete -F {_,}s6-svc
complete -F {_,}s6-svstat
complete -F {_,}s6-rc
for _tool in new copy delete change status fix commit install
do
	complete -F {_,}s6-rc-set-"$_tool"
done
complete -F {_,}s6-rc-db
complete -F {_,}s6
