# Should be sourced.

#  bahelite_set_overrides.sh
#  Overrides for the set builtin – for internal use within Bahelite
#  and helpers for the main script.
#  © deterenkelt 2019

#  Require bahelite.sh to be sourced first.
[ -v BAHELITE_VERSION ] || {
	echo "Bahelite error on loading module ${BASH_SOURCE##*/}:"  >&2
	echo "load the core module (bahelite.sh) first."  >&2
	return 4
}

#  Avoid sourcing twice
[ -v BAHELITE_MODULE_SET_OVERRIDES_VER ] && return 0
#  Declaring presence of this module for other modules.
declare -grx BAHELITE_MODULE_SET_OVERRIDES_VER='1.1.4'



                            #  Internals  #

 # Overrides for the “set” builtin to be used internally by Bahelite.
#  A library function may need to enable or disable some shell option tem-
#    porarily, but it should restore their state (on/off) to the one, that was
#    before the call. That is, it must leave the option in the same state,
#    as it was in the main script, before call to a Bahelite internal occurred.
#    Look at this example to see, what these hooks help to avoid:
#
#      In the main script:                   In some library file:
#      set -f                                library_call() {
#      . . .                                     set +f
#      set +f                                    list_of_files=$(ls ./*)
#      . . .                                     set -f   # ← wrong!
#      library_call                              return 0
#      . . .    # ← library restored          }
#      . . .    #   -f already!
#      set -f
#
#  The fact that calls can go deeper than one level (i.e. one library func-
#    tion that needs a specific shell option set or unset calls another, that
#    also needs the same options set or unset), complicates the issue.


 # To turn on extglob (shopt -s extglob) temporarily.
#
bahelite_extglob_on() {
	#  Internal! No xtrace_off/on needed!
	shopt -q extglob || {
		builtin shopt -s extglob
		declare -gx BAHELITE_BRING_BACK_EXTGLOB=t
	}
	return 0
}
bahelite_extglob_off() {
	#  Internal! No xtrace_off/on needed!
	[ -v BAHELITE_BRING_BACK_EXTGLOB ] && {
		unset BAHELITE_BRING_BACK_EXTGLOB
		builtin shopt -u extglob
	}
	return 0
}
export -f  bahelite_extglob_on  \
           bahelite_extglob_off


 # To turn off errexit (set -e) and disable trap on ERR temporarily.
#  bahelite_toggle_onerror_trap() is defined in bahelite_error_handling.sh,
#  which is an optional module.
#
bahelite_errexit_off() {
	#  Internal! No xtrace_off/on needed!
	[ -o errexit ] && {
		builtin set +e
		[ "$(type -t bahelite_toggle_onerror_trap)" = 'function' ]  \
			&& bahelite_toggle_onerror_trap  unset
		declare -gx BAHELITE_BRING_BACK_ERREXIT=t
	}
	return 0
}
bahelite_errexit_on() {
	#  Internal! No xtrace_off/on needed!
	[ -v BAHELITE_BRING_BACK_ERREXIT ] && {
		unset BAHELITE_BRING_BACK_ERREXIT
		builtin set -e
		[ "$(type -t bahelite_toggle_onerror_trap)" = 'function' ]  \
			&& bahelite_toggle_onerror_trap  set
	}
	return 0
}
export -f  bahelite_errexit_off  \
           bahelite_errexit_on


 # To turn noglob on and off (usually done with set -f/+f) temporarily,
#  This comes handy when shell needs to use globbing like for “ls *.sh”,
#    but it is disabled by default for safety.
#
bahelite_noglob_off() {
	#  Internal! No xtrace_off/on needed!
	[ -o noglob ] && {
		declare -gx BAHELITE_BRING_BACK_NOGLOB=t
		builtin set +f
	}
	return 0
}
bahelite_noglob_on() {
	#  Internal! No xtrace_off/on needed!
	[ -v BAHELITE_BRING_BACK_NOGLOB ] && {
		unset BAHELITE_BRING_BACK_NOGLOB
		builtin set -f
	}
	return 0
}
export -f  bahelite_noglob_off  \
           bahelite_noglob_on


 # Analogous to errexit functions. You may actually need them in your
#  main script, if you experience some weird issues related to subshells
#  or pipes.
#
bahelite_functrace_off() {
	#  Internal! No xtrace_off/on needed!
	[ -o functrace ] && {
		builtin set +T
		[ "$(type -t bahelite_toggle_ondebug_trap)" = 'function' ]  \
			&& bahelite_toggle_ondebug_trap  unset
		declare -gx BAHELITE_BRING_BACK_FUNCTRACE=t
	}
	return 0
}
bahelite_functrace_on() {
	#  Internal! No xtrace_off/on needed!
	[ -v BAHELITE_BRING_BACK_FUNCTRACE ] && {
		unset BAHELITE_BRING_BACK_FUNCTRACE
		builtin set -T
		[ "$(type -t bahelite_toggle_ondebug_trap)" = 'function' ]  \
			&& bahelite_toggle_ondebug_trap  set
	}
	return 0
}
export -f  bahelite_functrace_off  \
           bahelite_functrace_on


 # Turn off xtrace output (usually enabled with set -x) during the execution
#    of Bahelite internal functions. Their output is normally not needed
#    in the mother script.
#  What these two functions essentially do is hiding Bahelite code from xtrace,
#    so that when “set -x” is called in the main script, only the main script
#    code is shown in the xtrace output.
#  These two functions are supposed to be used only in this expression
#      bahelite_xtrace_off  &&  trap bahelite_xtrace_on  RETURN
#    that should be the first line in an internal fucntion of the first level
#    (i.e. not the secondary helpers to them). The bahelite_xtrace_off func-
#    tion is responsible for switching xtrace off temporarily, and bahelite_
#    xtrace_on  is a trap on RETURN signal, that is set on the first call to
#    an internal function. The trap on RETURN is set only in case bahelite_
#    xtrace_off has actually changed the state of xtrace, hence the “&&” in
#    the expression. The trap returns the state of xtrace to the original
#    state, when the execution leaves internal function and return to the
#    code of the main script.
#  To show Bahelite code anyway, add  BAHELITE_SHOW_UP_IN_XTRACE=t  in the
#    main script someplace after sourcing bahelite.sh.
#
bahelite_xtrace_off() {
	#  If this function was already called on a higher level,
	#    there’s no need to run it twice.
	#  The return code 1 prevents the run of bahelite_xtrace_on().
	[ -v BAHELITE_BRING_BACK_XTRACE ] && return 1

	#  If xtrace is not enabled, there’s no need to continue.
	[ -o xtrace ] || return 1

	if [ -v BAHELITE_SHOW_UP_IN_XTRACE ]; then
		#  When set -x enables trace, the commands are prepended with ‘+’.
		#  To differentiate between main script commands and Bahelite,
		#  we temporarily change the plus ‘+’ from PS4 to a middle dot ‘⋅’.
		#  (The mnemonic is “objects further in the distance look smaller”.)
		declare -gx OLD_PS4="$PS4"  &&  declare -gx PS4='⋅'
	else
		#  Won’t that lead to unexpected behaviour because of the regular
		#  xtrace_off()?
		builtin set +x
		declare -gx BAHELITE_BRING_BACK_XTRACE=${#FUNCNAME[*]}
	fi
# declare -gx PS4="$__bri$__y$PS4"
	return 0
}
bahelite_xtrace_on() {
	#  If this function runs not on the level, where its counterpart
	#  has set BAHELITE_BRING_BACK_XTRACE, quit.
	(( ${BAHELITE_BRING_BACK_XTRACE:- -1} != ${#FUNCNAME[*]} ))  &&  return 0

	unset BAHELITE_BRING_BACK_XTRACE
	#  Salty experience of learning how traps on RETURN work resulted
	#  in the following:
	#  - a trap on RETURN defined in a function persists after that func-
	#    tion quits. That means that one cannot set a trap on RETURN on
	#    entering a function and hope that it will only work once. Even
	#    though without “functrace” shell option set other functions
	#    *will not* inherit it, the source command *will*. In other words,
	#    each time you source an external file and the control returns
	#    back to the main file, the trap on RETURN triggers;
	#  - thus the trap on RETURN has a wider scope than it seems – and this
	#    means, that it’s possible to remove it from global scope when it
	#    completes what it needs. This way set/unset should come strictly
	#    in pairs – as needed for hiding xtrace diving into bahelite func-
	#    tions;
	#  - in order to be sure, that the return trap is executed and unset
	#    only the level, when it was set, BAHELITE_BRING_BACK_XTRACE
	#    contains the current function nesting level.
	trap '' RETURN

	# #  Restoring the original PS4.
	# [ -v BAHELITE_SHOW_UP_IN_XTRACE ] && {
	# 	# declare -gx PS4='+'
	# 	declare -gx PS4="$OLD_PS4"
	# }

	#  Restoring the original PS4.
	declare -gx PS4='+'

	builtin set -x
	#  No return, because after PS4 changes back to '+' a line like
	#  “+return 0” may be mistaken for a line from the main script,
	#  while it actually belongs to this Bahelite internal function.
}
export -f  bahelite_xtrace_off  \
           bahelite_xtrace_on
#
#  ^ The functions above could be made into a single function “bahelite_set”
#  that would work analogous to the overridden “set” above, but this would be
#  less convenient:
#    - to hide xtrace output as much as possible for the internal functions,
#      it is necessary to limit down to the bare minimum extra commands before
#      the xtrace can be temporarily disabled. This makes a dedicated function
#      (like bahelite_xtrace_off) the preferrable choice, because it saves
#      commands that would need to determine, for which purpose (with which
#      parameters) that hypotetical common function “bahelite_set” is called.
#    - as xtrace functions cannot be put into one common function, this would
#      create a confusion about the role of the function that would be put
#      in the body of the “common” function (e.g. bahelite_errexit_on/off and
#      bahelite_noglob_on/off). Being implemented all in one style helps to
#      distinguish they closeness.
#  ^ That would be a mistake to merge the above functions with the overridden
#  “set”, for that would require knowledge about which of the functions in
#  “internals” and “facilities” play primary and which – secondary roles.



                            #  Facilities  #

 # Overrides user calls to ‘set’ builtin.
#
#  If the + and − confuse you (to disable noglob you use +f as if enabling it),
#  you can use these alias functions. They will leave no place for a mistake.
#
errexit_off() { set +e; }
errexit_on()  { set -e; }
functrace_off() { set +T; }
functrace_on()  { set -T; }
xtrace_off() { set +x; }
xtrace_on()  { set -x; }
noglob_off() { set +f; }
noglob_on()  { set -f; }
#
set() {
	#  Hiding the output of the function itself.
	builtin set +x
	local command=()  param  retval

	for param in "$@"; do
		[ "$param" = '--' ] && {
			redmsg "${__bri}Please put “builtin” before “set” to avoid using this override.

			        Bahelite overrides the set builtin to ease the debugging,
			          because it involves xtrace, functrace and errexit.
			        However, it is technically impossible to make the use of over-
			          ridden “set” fully transparent. Technically, because “set” is
			          often used with “--” to assign positional arguments, and when
			          this override calls “builtin set -- something”… yes, it sets
			          arguments to the override function itself. So just avoid using
			          this helper function and call “set” directly, for example

			              builtin set -- your arguments here
			          ${__s}"
			err "${__bri}Use “builtin set” when setting arguments with double dash.${__s}"
		}
	done

	case "$1" in
		#  `set ±x` calls are overridden, because of a trap on DEBUG, that
		#  dramatically – but in 99.99% cases unnecessarily – increases ver-
		#  bosity. The trap is only set when “functrace” shell option is enab-
		#  led in the main script (usually with “set -T”) and “error_handling”
		#  module is sourced.
		'-x')
			#  Xtrace is available on console verbosity (or the log verbosity,
			#  if logging was started) from the level 50 or higher (the default
			#  level is 30). The reasons are:
			#  1. To put the activation of xtrace behind the default verbosity
			#     level and behind the extra (moderately verbose) output, im-
			#     plemented in Bahelite or in the main script.
			#  2. If the lines activating xtrace would happen to be forgotten
			#     in the main script and it gets published with them, this
			#     wouldn’t cause a problem for regular users, as the default
			#     verbosity level doesn’t allow activation of xtrace.
			#  The controlling variable is set in bahelite_messages.sh after
			#  checking VERBOSITY_LEVEL for console/log.
			[ -v BAHELITE_XTRACE_ALLOWED ] && {
				bahelite_functrace_off
				command=(builtin set -x)
			}
			;;
		'+x')
			bahelite_functrace_on
			command=(builtin set +x)
			;;
		'+T')
			bahelite_functrace_off
			;;
		'-T')
			bahelite_functrace_on
			;;
		'-e')
			[ "$(type -t bahelite_toggle_onerror_trap)" = 'function' ]  \
				&& bahelite_toggle_onerror_trap  set
			command=(builtin set -e)
			;;
		'+e')
			[ "$(type -t bahelite_toggle_onerror_trap)" = 'function' ]  \
				&& bahelite_toggle_onerror_trap  unset
			command=(builtin set +e)
			;;
		*)
			#  For any arguments, that are not ‘-x’ or ‘+x’, pass them as they
			#  are. This is a potential bug, as adding -x in the main ‘set’
			#  declaration like
			#    set -xfeEuT
			#  or using “-o xtrace” will not use the override above. Hope-
			#  fully, everyone would just use ‘set -x’ or ‘set +x’.
			command=(builtin set "$@")
			;;
	esac

	#  May be empty, not an error.
	"${command[@]}"

	#  No return to be maximally transparent: a “return 0” showing up will be
	#  unexpected for those who enabled xtrace and expect that the first line
	#  will be a line of their code.
}
export -f  set  \
               errexit_off    \
               errexit_on     \
               xtrace_off     \
               xtrace_on      \
               noglob_off     \
               noglob_on      \
               functrace_off  \
               functrace_on


 # Overrides env to allow running a child process in a clean environment.
#  The reason why this override is needed, is that “env -i” is not good enough.
#    It runs processes in a literally *wiped* environment, that doesn’t even
#    have $HOME set any more. While what you probably want is just to have
#    an environment, identical to what you had at the start of the main script.
#    It’s only needed, that all created and exported variables would be magi-
#    cally found and unset. This override does exactly this.
#  All the variables, that appeared since Bahelite was loaded are passed to
#    env with “-u” flag to unset them. Moreover, variables preset for Bahelite
#    are remove too (it’s those variables, that can be set *before* sourcing
#    bahelite.sh to alternate its behaviour).
#
env() {
	local current_varlist  new_vars  retval
	current_varlist=$(compgen -A variable)
	new_vars=(
		$(
			echo "$BAHELITE_VARLIST_BEFORE_STARTUP"$'\n'"$current_varlist" \
				| sort | uniq -u | sort
		)
		${!BAHELITE_*}  ${!MSG_*}  LOGPATH  LOGDIR  TMPDIR
	)
			#  Other variables for removal, that could be set before Bahelite
		#  startup procedure, hence may not appear in the VARLIST_BEFORE_STARTUP
		#  variable, that actually collects variables at the time of startup.
		#
	bahelite_functrace_off

	command env $(sed -r 's/\S+/-u &/g' <<<"${new_vars[*]}")  \
	            TERM_COLS=${TERM_COLS:-80}  \
	            TERM_LINES=${TERM_LINES:-25}  \
	            STDIN_ORIG_FD_PATH="$STDIN_ORIG_FD_PATH"  \
	            STDOUT_ORIG_FD_PATH="$STDOUT_ORIG_FD_PATH"  \
	            STDERR_ORIG_FD_PATH="$STDERR_ORIG_FD_PATH"  \
	            MSG_INDENTATION_LEVEL="$MSG_INDENTATION_LEVEL"  \
	            "$@"

	retval=$?
	bahelite_functrace_on
	return $retval
}
export -f  env



return 0