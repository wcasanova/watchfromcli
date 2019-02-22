# Should be sourced.

#  bahelite.sh
#  BAsh HElper LIbrary – To Everyone!
#  ――――――――――――――――――――――――――――――――――
#  © deterenkelt 2018–2019
#  https://github.com/deterenkelt/Bahelite
#
#  This work is based on the Bash Helper Library for Large Scripts,
#  that I’ve been initially developing for Lifestream LLC in 2016. The old
#  code of BHLLS can be found at https://github.com/deterenkelt/bhlls.

#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License as published
#  by the Free Software Foundation; either version 3 of the License,
#  or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but without any warranty; without even the implied warranty
#  of merchantability or fitness for a particular purpose.
#  See the GNU General Public License for more details.


#  Bahelite doesn’t enable or disable any shell options, leaving it
#  to the programmer to set the appropriate ones. Bahelite will only tempo-
#  rarely enable or disable them as needed for its internal functions.

 # bash >= 4.3 for declare -n.
#  bash >= 4.4 for the fixed typeset -p behaviour.
#
if  (( ${BASH_VERSINFO[0]:-0} <= 3 )) \
	|| (( ${BASH_VERSINFO[0]:-0} == 4 && ${BASH_VERSINFO[1]:-0} <= 3 ))
then
	echo -e "Bahelite error: bash v4.4 or higher required." >&2
	# so it would work for both sourced and executed scripts
	return 3 2>/dev/null ||	exit 3
fi

 # Scripts usually shouldn’t be sourced. And so that your main script wouldn’t
#  be sourced by an accident, Bahelite checks, that the main script is called
#  as an executable. Set BAHELITE_LET_MAIN_SCRIPT_BE_SOURCED to skip this.
#
if	[ ! -v BAHELITE_LET_MAIN_SCRIPT_BE_SOURCED ] \
	&& [ "${BASH_SOURCE[-1]}" != "$0" ]
then
	echo -e "${BASH_SOURCE[-1]} shouldn’t be sourced." >&2
	return 4
fi


             #  Cleaning the environment before start  #

 # Wipe user functions from the environment
#  This is done by default, because of the custom things, that often
#    exist in ~/.bashrc or exported from mother shell. Being supposed to
#    simplify the work in terminal, they may – and often will – complicate
#    things for the mother script running in the terminal.
#  Define BAHELITE_KEEP_ENV_FUNCS variable before sourcing bahelite.sh
#    to override the default behaviour.
#
if [ ! -v BAHELITE_KEEP_ENV_FUNCS ]; then
	#  This wipes every function, which name doesn’t start with an underscore
	#  (those that start with “_” or “__” are internal functions mostly
	#  related to completion)
	unset -f $(declare -F | sed -rn 's/^declare\s\S+\s([^_]*+)$/\1/p')
fi
#
#  env in shebang will not recognise -i, so an internal respawn is needed
#  in order to run the script in a clean environment.
if [ -v BAHELITE_TOTAL_ENV_CLEAN ]; then
	[ ! -v BAHELITE_ENV_CLEANED ] && {
		exec /usr/bin/env -i BAHELITE_ENV_CLEANED=t bash "$0" "$@"
		exit $?
	}
fi

 # Bahelite requires util-linux >= 2.20
#  Shoulda move that to a function-check, i.e. this should become a part
#  of the check_required_utils.
#
read -d '' major minor  < <(
	getopt -V \
		| sed -rn 's/^[^0-9]+([0-9]+)\.?([0-9]+)?.*/\1\n\2/p'; \
	echo -e '\0'
)
[[ "$major" =~ ^[0-9]+$  &&  "$minor" =~ ^[0-9]+$ ]] \
&&  (
		((  ( major == 2  &&  minor >= 20 )  ||  major >= 2  ))
	) \
	|| err 'old util-linux'
unset  major minor


 # Overrides ‘set’ bash builtin to change beahviour of set ±x:
#    regular set -x output would include traponeachcommand(),
#    which is triggered by bahelite_toggle_ondebug_trap(), which is necessary for precise
#    tracing in case of an error, but it clogs the normal trace, when user
#    calls set -x.
#  Thus there needs to be a hook on set -x that will temporarily
#    unset trap_on_debug, and bring it back on set +x.
#  There were special functions debug_on and debug_off, that
#    were intended to use instead of ‘set ±x’, but the habit of using
#    ‘set ±x’ is too strong, so this function has to be made.
#
set() {
	#  Hiding the output of the function itself.
	builtin set +x
	local command=()
	if [ "$1" = -x ]; then
		[ -v BAHELITE_TRAPONDEBUG_SET ] && {
			#  The purpose of  bahelite_toggle_ondebug_trap  is to catch the
			#  line, where an error happened, better and provide a sensible
			#  trace stack. When the programmer enables xtrace, he already
			#  got the information from the bahelite_toggle_ondebug_trap, so
			#  we disable it on the time of enabling xtrace, for it will clog
			#  the output dramatically.
			bahelite_toggle_ondebug_trap  unset
			declare -g BAHELITE_BRING_BACK_TRAPONDEBUG=t
		}
		command=(builtin set -x)
	elif [ "$1" = +x ]; then
		[ -v BAHELITE_BRING_BACK_TRAPONDEBUG ] && {
			unset BAHELITE_BRING_BACK_TRAPONDEBUG
			#  When xtrace if switched off, we can bring the trap on debug
			#  back. The desired behaviour is solely to clear the shell trace
			#  from bahelite functions.
			#  This enables functrace / set -T!
			#  Functions will inherit trap on RETURN!
			bahelite_toggle_ondebug_trap  set
		}
		command=(builtin set +x)
	else
		#  For any arguments, that are not ‘-x’ or ‘+x’,
		#    pass them as they are.
		#  This is a potential bug, as adding -x in the
		#  main ‘set’ declaration like
		#      set -xfeEu  #T
		#  or using “-o xtrace” will not use the override above.
		#  Hopefully, everyone would just use ‘set -x’ or ‘set +x’.
		command=(builtin set "$@")
	fi
	"${command[@]}"  # No “return”, to not confuse people looking at the trace.
}


 # To turn off xtrace output (enabled with set -x) during the execution
#    of Bahelite own functions. You don’t need them in mother script, just
#    use set +x/-x, as usual.
#  What these functions essentially do is hiding Bahelite code from xtrace,
#    so that you could run set -x and see *only your code*, as you used to.
#    To show Bahelite code anyway, add “unset BAHELITE_HIDE_FROM_XTRACE”
#    in the mother script someplace after sourcing bahelite.sh.
#
xtrace_off() {
	 # This prevents disabling xtrace recursively.
	#  In case some higher level function would call a lower-level function
	#  and both of them would use xtrace_off, xtrace_on would break off
	#  the hiding once it’s called inside the lover-level function, and we
	#  need to hide trace until xtrace_on would be called in the higher
	#  level function
	#[ -z "$BAHELITE_XTRACE_HIDING_KEY" ] && {
	[ ! -v BAHELITE_BRING_XTRACE_BACK ] && {
		 # If xtrace is not enabled, we have nothing to do.
		#    Calling xtrace_off by mistake may initiate unwanted hiding,
		#    which will lead to unexpected results.
		#  Essentially, this prevents calling it by a lowskilled user mistake.
		[ -o xtrace ] || return 0

		 # When set -x enables trace, the commands are prepended with ‘+’.
		#  To differentiate between user’s commands and bahelite,
		#  we temporarily change ‘+’ to ‘⋅’
		declare -g OLD_PS4="$PS4" && declare -g PS4='⋅'
		[ -v BAHELITE_HIDE_FROM_XTRACE ] && {
			builtin set +x
			declare -g BAHELITE_BRING_XTRACE_BACK=${#FUNCNAME[*]}
		}
		return 0
	}
	return 1
}
xtrace_on() {
	(( ${BAHELITE_BRING_XTRACE_BACK:-0} == ${#FUNCNAME[*]} )) && {
		unset BAHELITE_BRING_XTRACE_BACK
		builtin set -x
		#  Salty experience of learning how traps on RETURN work resulted
		#  in the following:
		#  - a trap on RETURN defined in a function persists after that func-
		#    tion quits. That means that one cannot set a trap on RETURN on
		#    entering a function and hope that it will only work once. Even
		#    though without “functrace” shell option set other functions
		#    *will not* inherit it, the source command *will*. In other words,
		#    each time you source an external file and the control returns
		#    back to the main file, the trap on RETURN triggers;
		#  - thus the trap on RETURN has a global scope anyway – and that
		#    means, that it’s possible to remove it from global scope when it
		#    completes what it needs. This way set/unset should come strictly
		#    in pairs – as needed for hiding xtrace diving into bahelite func-
		#    tions;
		#  - in order to be sure, that the return trap is executed and unset
		#    only the level, when it was set, BAHELITE_BRING_XTRACE_BACK
		#    contains the current function nesting level.
		trap '' RETURN
		#  Restoring the original PS4.
		#  Currently doesn’t work well, because xtrace off and on somehow
		#  don’t go in pairs sometimes. Needs an investigation.
		#  Most users presumably don’t alter PS4 anyway, so just set it to ‘+’.
		#declare -g PS4="${OLD_PS4:-+}"
		declare -g PS4='+'
	}
	return 0
}

 # To turn off errexit (set -e) and disable trap on ERR temporarily.
#  bahelite_toggle_onerror_trap() is defined in bahelite_error_handling.sh,
#  which is an optional module. Handling this optionality creates the need
#  in simplifying of the way to turn errexit on and off – so here is this
#  function.
#
errexit_off() {
	[ -o errexit ] && {
		set +e
		[ "$(type -t bahelite_toggle_onerror_trap)" = 'function' ]  \
			&& bahelite_toggle_onerror_trap  unset
		declare -g BAHELITE_BRING_BACK_ERREXIT=t
	}
	return 0
}
errexit_on() {
	[ -v BAHELITE_BRING_BACK_ERREXIT ] && {
		unset BAHELITE_BRING_BACK_ERREXIT
		set -e
		[ "$(type -t bahelite_toggle_onerror_trap)" = 'function' ]  \
			&& bahelite_toggle_onerror_trap  set
	}
	return 0
}


 # (For internal use) To turn off noglob (set -f) temporarily,
#    but bring it back to the main script’s defaults afterwards.
#  This comes handy when shell needs to use globbing like for “ls *.sh”,
#    but it is disabled by default for safety.
#
noglob_off() {
	[ -o noglob ] && {
		set +f
		declare -g BAHELITE_BRING_BACK_NOGLOB=t
	}
	return 0
}
noglob_on() {
	[ -v BAHELITE_BRING_BACK_NOGLOB ] && {
		unset BAHELITE_BRING_BACK_NOGLOB
		set -f
	}
	return 0
}


BAHELITE_VERSION="2.13"
#  $0 == -bash if the script is sourced.
[ -f "$0" ] && {
	MYNAME=${0##*/}
	#  Sourced scripts cannot operate on the main script’s $0,
	#  as it is changed for them to “bash”.
	MYNAME_AS_IN_DOLLARZERO="$0"
	MYPATH=$(realpath --logical "$0")
	MYDIR=${MYPATH%/*}
	#  Used for desktop notifications in bahelite_messages.sh
	#  and in the title for dialog windows in bahelite_dialog.sh
	[ -v MY_DESKTOP_NAME ] || {
		MY_DESKTOP_NAME="${MYNAME%.*}"
		MY_DESKTOP_NAME="${MY_DESKTOP_NAME^}"
	}
	BAHELITE_DIR=${BASH_SOURCE[0]%/*}  # The directory of this file.
}

CMDLINE="$0 $@"
ARGS=("$@")
#
#  Terminal variables
if [[ "$-" =~ ^.*i.*$ ]]; then
	TERM_COLS=$(tput cols)
else
	#  For non-interactive shells restrict the width to 80 characters,
	#  in order for the logs to not be excessively wi-i-ide.
	TERM_COLS=80
fi
TERM_LINES=$(tput lines)


 # Script’s tempdir
#  bahelite_on_exit removes it – don’t forget anything there.
#  You may want to define BAHELITE_LOCAL_TMPDIR in order to create
#    TMPDIR not in /tmp (or TMPDIR, if it is defined beforehand), but in
#    a local directory, under ~/.cache. This is useful, when something
#    creates very large files, and your /tmp is in RAM and too small.
[ -v BAHELITE_LOCAL_TMPDIR ] && BAHELITE_LOCAL_TMPDIR="$HOME/.cache"
TMPDIR=$(mktemp --tmpdir=${BAHELITE_LOCAL_TMPDIR:-${TMPDIR:-/tmp/}} \
                -d ${MYNAME%*.sh}.XXXXXXXXXX )


 # Desktop directory
#
DESKTOP=$(which xdg-user-dir &>/dev/null && xdg-user-dir DESKTOP) ||:
[ -d "$DESKTOP" ] || DESKTOP="$HOME"


 # Dummy logfile
#  To enable proper logging, call start_log().
LOG=/dev/null


 # By default Bahelite turns off xtrace for its internal functions.
#  Call “unset BAHELITE_HIDE_FROM_XTRACE” after sourcing bahelite.sh
#  to view full xtrace output.
#
BAHELITE_HIDE_FROM_XTRACE=t


 # Lists of utilities, the lack of which must trigger an error.
#  For internal dependencies of bahelite.sh and bahelite_*.sh.
#  Long name to make it distinctive from the REQUIRED_UTILS, which is
#    the facility for the mother script. This array was separated from
#    REQUIRED_UTILS to avoid accidental redefinition in the mother script
#    instead of extension. It would be good to set this array readonly
#    at the end of the bahelite.sh execution, but it’s not possible, because
#    modules must remain optional – mother script may want to include addi-
#    tional modules after receiving certain options, e.g. include
#    bahelite_github.sh
#
BAHELITE_INTERNALLY_REQUIRED_UTILS=(
	getopt
	grep
	sed
)
#
#  Holds a short info on which package a missing binary may be found in.
declare -A BAHELITE_INTERNALLY_REQUIRED_UTILS_HINTS=()
#
#  User list for required utils
#  Ex. REQUIRED_LIST=( mimetype ffmpeg )
#  This list is initially empty to separate internally required utils from
#    the dependencies of the main script itself. If that would be a single
#    list, users could accidently wipe it with = instead of addition to it
#    with +=.
REQUIRED_UTILS=()
#
#  Holds descriptions for missing utils: which packages they can be found in,
#  which versions were used for development etc. A hint is printed when
#  a corresponding utility in REQUIRED_UTILS is not found.
#  Syntax: REQUIRED_UTILS_HINTS=( [prog1]='Prog1 can be found in Package1.' )
#  (Hints are not required, this array may be left empty.)
declare -A REQUIRED_UTILS_HINTS=()
#
#  In the future, add an array that would hold function names, that should
#  run sophisticated checks over the binaries, e.g. query their version,
#  or that grep is GNU grep and not BSD grep.
#declare -A REQUIRED_UTILS_CHECKFUNCS=()



                        #  Module verbosity  #

 # When everything goes right, modules do not output anything to stdout. Only
#  in case of a potential trouble or an error they output messages. Sometimes
#  however, it would be useful to make the modules print intermediate infor-
#  mation, i.e. info messages. In regular use such messages would only unneces-
#  sarily clog the output, so they are allowed only on the increased verbosity
#  level.
#     The array below controls displaying extra info and warn messages, that
#  are normally not shown. Works per module. Redefine elements in the mother
#  script after sourcing bahelite.sh, but before calling any bahelite func-
#  tions. For example, to enable verbose messages for bahelite_rcfile.sh:
#  BAHELITE_VERBOSE=( [rcfile]=t )
#
declare -A BAHELITE_VERBOSE=(
	[bahelite]=f                  # the main module = bahelite.sh = this file.
	[colours]=f                   # bahelite_colours.sh
	[dialog]=f                    # etc.
	[directories]=f
	[error_handling]=f
	[github]=f
	[logging]=f
	[menus]=f
	[messages]=f
	[misc]=f
	[rcfile]=f
	[versioning]=f
	[x_desktop]=f
)


 # Checks whether verbosity is enabled for a certain module
#  This function is supposed to be called from within a Bahelite module,
#  i.e. bahelite_*.sh files, in the following manner:
#      bahelite_check_module_verbosity \
#          && info "Trying RC file:
#                   $rcfile"
#
bahelite_check_module_verbosity() {
	local caller_module_funcname=${FUNCNAME[1]}
	local caller_module_filename=${BASH_SOURCE[1]}
	caller_module_filename=${caller_module_filename##*/}
	caller_module_filename=${caller_module_filename%.sh}
	caller_module_filename=${caller_module_filename#bahelite_}
	[ "${BAHELITE_VERBOSE[$caller_module_filename]}" = t ]  \
		&& return 0  \
		|| return 1
}

bahelite_module_verbosity_test() {
	bahelite_check_module_verbosity \
		&& info "Hai, dozo."
	return 0
}

if [ -v BAHELITE_CHERRYPICK_MODULES ]; then
	for module in "${BAHELITE_CHERRYPICK_MODULES[@]}"; do
		. "$BAHELITE_DIR/bahelite_$module.sh" || return 5
	done
else
	noglob_off
	for bahelite_module in "$BAHELITE_DIR"/bahelite_*.sh; do
		. "$bahelite_module" || return 5
	done
	noglob_on
fi


[ -v BAHELITE_MODULE_MESSAGES_VER ] || {
	echo "Bahelite: cannot find bahelite_messages.sh." >&2
	return 5
}




 # Call this function in your script after extending the array above.
#
check_required_utils() {
	local  util  missing_utils req_utils=()
	req_utils=$(printf "%s\n" ${BAHELITE_INTERNALLY_REQUIRED_UTILS[@]} \
	                          ${REQUIRED_UTILS[@]} \
	                | sort -u  )
	for util in ${req_utils[@]}; do
		which "$util" &>/dev/null || {
			missing_utils="${missing_utils:+$missing_utils, }“$util”"
			if [ "${REQUIRED_UTILS_HINTS[$util]:-}" ]; then
				warn "$util was not found on this system!
				      ${REQUIRED_UTILS_HINTS[$util]}"
			elif [ "${BAHELITE_INTERNALLY_REQUIRED_UTILS_HINTS[$util]:-}" ]; then
				warn "$util was not found on this system!
				      ${BAHELITE_INTERNALLY_REQUIRED_UTILS_HINTS[$util]}"
			else
				warn "$util was not found on this system!"
			fi
		}
	done
	[ "${missing_utils:-}" ] && ierr 'no util' "$missing_utils"
	return 0
}

 # It’s a good idea to extend REQUIRED_UTILS list in your script
#  and then call check_required_utils like:
#      REQUIRED_UTILS+=( bc )
#      check_required_utils
#
check_required_utils

 # Before the main script starts, gather variables. In case of an error
#  this list would be compared to the other, created before exiting,
#  and the diff will be placed in "$LOGDIR/variables"
#
BAHELITE_STARTUP_VARLIST="$(compgen -A variable)"


return 0