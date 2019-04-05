# Should be sourced.

#  bahelite_misc.sh
#  Miscellaneous helper functions.
#  deterenkelt © 2018–2019

# Require bahelite.sh to be sourced first.
[ -v BAHELITE_VERSION ] || {
	echo 'Must be sourced from bahelite.sh.' >&2
	return 5
}
. "$BAHELITE_DIR/bahelite_messages.sh" || return 5

# Avoid sourcing twice
[ -v BAHELITE_MODULE_MISC_VER ] && return 0
#  Declaring presence of this module for other modules.
BAHELITE_MODULE_MISC_VER='1.9.1'

BAHELITE_INTERNALLY_REQUIRED_UTILS+=(
	pgrep   # Single process check
	wc      # Single process check
	shuf    # random(), that works better than $RANDOM
)
BAHELITE_INTERNALLY_REQUIRED_UTILS_HINTS+=(
	[pgrep]='pgrep is a part of procps-ng.
	http://procps-ng.sourceforge.net/
	https://gitlab.com/procps-ng/procps'
)

#  It is *highly* recommended to use “set -eE” in whatever script
#  you’re going to source it from.


 # Returns 0 if the argument is a variable, that has a value, that can be
#    treated as positive – yes, Yes, t, True, 1 and so on. Returns 1 if it
#    has a value, that corresponds with a negative value: no, No, f, False,
#    0 etc. Returns an error in case the value is neither.
#  If the second argument -u|--unset-if-not is passed, unsets the variable,
#    if it has a ngeative value and returns with code 0.
#  The purpose is to turn the very existence of a variable into a flag,
#    that can be checked with a simple [ -v flag_variable ] in the code.
#  Arguments:
#     $1 – variable name
#    [$2] – “-u” or “--unset-if-not” to unset a negative variable.
#
is_true() {
	xtrace_off && trap xtrace_on RETURN
	local varname="${1:-}"
	[ -v "$varname" ] || {
		if [ "${FUNCNAME[1]}" = read_rcfile ]; then
			err "Config option “$varname” is requried, but it’s missing."
		else
			err "Cannot check variable “$varname” – it doesn’t exist."
		fi
	}
	[[ "${2:-}" =~ ^(-u|--unset-if-not)$ ]] \
		&& local unset_if_false=t
	declare -n varval="$varname"
	if [[ "$varval" =~ ^(y|Y|[Yy]es|1|t|T|[Tt]rue|[Oo]n|[Ee]nable[d])$ ]]; then
		return 0
	elif [[ "$varval" =~ ^(n|N|[Nn]o|0|f|F|[Ff]alse|[Oo]ff|[Dd]isable[d])$ ]]; then
		[ -v unset_if_false ] && {
			unset $varname
			return 0
		}
		return 1
	else
		if [ -v BAHELITE_MODULE_MESSAGES_VER ]; then
			err "Variable “$varname” must have a boolean value (0/1, on/off, yes/no),
			     but it has “$varval”."
		else
			cat <<-EOF >&2
			Variable “$varname” must have a boolean value (0/1, on/off, yes/no),
			but it has “$varval”.
			EOF
		fi
	fi
	return 0
}


 # Dumps values of variables to stdout and to the log
#  $1..n – variable names
#
dumpvar() {
	xtrace_off && trap xtrace_on RETURN
	local var
	for var in "$@"; do
		msg "$(declare -p $var)"
	done
	return 0
}


 # These two functions are handy to temporarily export bahelite
#  functions into environment, so that when parallel, for example,
#  when it runs a bash function, would pass Bahelite functions
#  and variables to it.
#
bahelite_export() {
	export -f  info  warn  err  msg  strip_colours  \
	           xtrace_off  xtrace_on  milinc  mildec
	return 0
}
bahelite_unexport() {
	export -nf  info  warn  err  msg  strip_colours  \
	            xtrace_off  xtrace_on  milinc  mildec
	return 0
}


 # Sets MYRANDOM global variable to a random number either fast or secure way
#  Secure way may take seconds to complete.
#  $1 – an integer number, which will define the range, [0..$1].
#
random-fast()   { random fast   "$@"; }
random-secure() { random secure "$@"; }
#
 # Generic function
#  $1 – mode, either “fast” or “secure”
#  $2 – an integer number, which will define the range, [0..$1].
#
random() {
	declare -g MYRANDOM
	local mode="${1:-}" max_number="${2:-}"

	case "$mode" in
		fast)    random_source='/dev/urandom';;
		secure)  random_source='/dev/random';;
		*)  err 'Random source must be set to either “fast” or “secure”.'
	esac
	[ -r "$random_source" ] \
		|| err "Random source file $random_source is not a readable file."

	[[ "$max_number" =~ ^[0-9]+$ ]] \
		|| err "The max. number is not specified, got “$max_number”."

	 # $RANDOM is too bad to use even when security is not a concern,
	#  because its seed works bad in containers, and 9/10 times returns
	#  the same value, if you call $RANDOM with equal time spans of one hour.
	#
	#  MYRANDOM will be set to a number between 0 and $max_number inclusively.
	#
	MYRANDOM=$(shuf --random-source=$random_source -r -n 1 -i 0-$max_number)
	return 0
}


 # Removes or replaces characters, that are forbidden in Windows™ filenames.
#  $1 – a string, in which the characters have to be replaced.
#  Returns a new string to stdout.
#
remove_windows_unfriendly_chars() {
	local str="${1:-}"
	str=${str//\</\(}
	str=${str//\>/\)}
	str=${str//\:/\.}
	str=${str//\"/\'}
	str=${str//\\/}
	str=${str//\|/}
	str=${str//\?/}
	str=${str//\*/}
	echo "$str"
	return 0
}


 # Allows only one instance of the main script to run.
#
single_process_check() {
	local our_processes        total_processes \
	      our_processes_count  total_processes_count  our_command
	[ ${#ARGS[*]} -eq 0 ]  \
		&& our_command="bash $MYNAME_AS_IN_DOLLARZERO"  \
		|| our_command="bash $MYNAME_AS_IN_DOLLARZERO ${ARGS[@]}"
	our_processes=$(
		pgrep -u $USER -afx "$our_command" --session 0 --pgroup 0
	)
	total_processes=$(
		pgrep -u $USER -af  "bash $MYNAME_AS_IN_DOLLARZERO"  # sic!
	)
	our_processes_count=$(echo "$our_processes" | wc -l)
	total_processes_count=$(echo "$total_processes" | wc -l)
	(( our_processes_count < total_processes_count )) && {
		warn "Processes: our: $our_processes_count, total: $total_processes_count.
		Our processes are:
		$our_processes
		Our and foreign processes are:
		$total_processes"
		err 'Still running.'
	}
	return 0
}


 # Expands a string like “1-5” into the range of numbers “1 2 3 4 5”.
#  $1 – string with range, format: N-N, where N is an integer.
#
expand_range() {
	local range="$1" expanded_range
	[[ "$range" =~ ^([0-9]+)-([0-9]+)$ ]] || {
		warn "Invalid input range for expansion: “$range”."
		return 1
	}
	seq -s ' ' ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}
	return 0
}


 # Echo plural “s” to stdout, if the passed number is bigger than 1.
#  $1 – number to test.
# [$2] – custom ending to output instead of “s” (i.e. when you need “ies”).
# [$3] – custom singular ending to output instead of nothing.
#        (Use it when the plural ending of the word isn’t just a suffix
#         added to it.)
#
plural_s() {
	local num="$1"  plural_ending  singular_ending="${3:-}"
	#  There is a case inverse to generic “plural s”: when it’s a verb that
	#    has to be pluralised. Verbs’ plural forms have no ending, while in
	#    singular form they take an “s” at the end.
	#  Hence plural_ending=${2:-} is not going to work, as specifically
	#    passed empty string ("") as the second parameter will make no diffe-
	#    rence in this case, it would be as if the parameter was unset.
	#    The number of the parameters should be checked in order to set
	#    plural_ending explicitly to whatever is passed (including an empty
	#    string) or “s” if the parameter wasn’t in the command line.
	if [ $# -ge 2 ]; then
		plural_ending="$2"
	else
		plural_ending='s'
	fi
	if [[ "$num" =~ ^1$ ]]; then
		echo -n "$singular_ending"
	else
		echo -n "$plural_ending"
	fi
	return 0
}


return 0