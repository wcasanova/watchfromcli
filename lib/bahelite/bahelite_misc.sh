# Should be sourced.

#  bahelite_misc.sh
#  Miscellaneous helper functions.
#  © deterenkelt 2018–2019

#  Require bahelite.sh to be sourced first.
[ -v BAHELITE_VERSION ] || {
	echo "Bahelite error on loading module ${BASH_SOURCE##*/}:"
	echo "load the core module (bahelite.sh) first." >&2
	return 4
}

#  Avoid sourcing twice
[ -v BAHELITE_MODULE_MISC_VER ] && return 0
#  Declaring presence of this module for other modules.
declare -grx BAHELITE_MODULE_MISC_VER='1.11'

BAHELITE_INTERNALLY_REQUIRED_UTILS+=(
	pgrep   # (procps) Single process check.
#	wc      # (coreutils) Single process check.
#	shuf    # (coreutils) For random(), it works better than $RANDOM.
)
BAHELITE_INTERNALLY_REQUIRED_UTILS_HINTS+=(
	[pgrep]='pgrep is a part of procps-ng.
	http://procps-ng.sourceforge.net/
	https://gitlab.com/procps-ng/procps'
)



 # Checks, whether a variable contains a logical or human-readable value,
#  that can be treated as positive or negative.
#  $1  – variable name
# [$2] – “-u” or “--unset-if-not” to unset a negative variable.
#        The purpose of this option is to turn the very existence of a vari-
#        able into a flag. Running “is_true flag_variable --unset-if-not”
#        allows to check it later with [ -v flag_variable ] in the code.
#
#  This function can be used two ways. One way it can be a sanitiser
#    for a script, that reads a config file, for example:
#        for var in ${config_variables[@]}; do
#            is_true  $var  --unset-if-not
#        done
#    This way is_true will return with a success code, as long as the value
#    in the variable could be recognised as either positive or negative.
#    If it couldn’t be recognised, is_true will trigger an error.
#  But is_true can also function as a value checker.
#        if is_true $varname; then
#            …
#        fi
#    When used without -u/--unset-if-true, the function will return 0
#    for positive values and 1 for negative. And if it would be neither,
#    there will be an error.
#
is_true() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	local varname="${1:-}"  unset_if_false
	[ -v "$varname" ] || {
		if [ "${FUNCNAME[1]}" = read_rcfile ]; then
			err "Config option “$varname” is requried, but it’s missing."
		else
			err "Cannot check variable “$varname” – it doesn’t exist."
		fi
	}
	[[ "${2:-}" =~ ^(-u|--unset-if-not)$ ]] \
		&& unset_if_false=t
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
		err "Variable “$varname” must have a boolean value (0/1, on/off, yes/no),
		     but it has “$varval”."
	fi
	return 0
}
export -f  is_true


is_function() {
	[ "$(type -t "$1")" = 'function' ]
}
export -f  is_function


 # Sets MYRANDOM global variable to a random number either fast or secure way
#  Secure way may take seconds to complete.
#  $1 – an integer number, which will define the range, [0..$1].
#
random-fast()   {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	__random fast "$@"
}
random-secure() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	__random secure "$@"
}
#
 # Generic function
#  $1 – mode, either “fast” or “secure”
#  $2 – an integer number, which will define the range, [0..$1].
#
__random() {
	#  Internal! No need for xtrace_off/on.
	declare -gx MYRANDOM
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
export -f  __random  \
               random-fast  \
               random-secure


 # Removes or replaces characters, that are forbidden in Windows™ filenames.
#  $1 – a string, in which the characters have to be replaced.
#  Returns a new string to stdout.
#
remove_windows_unfriendly_chars() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	local str="${1:-}"
	str=${str//\</\(}
	str=${str//\>/\)}
	str=${str//\:/\.}
	str=${str//\"/\'}
	str=${str//\\/}
	str=${str//\|/}
	str=${str//\?/}
	str=${str//\*/}
	echo -n "$str"
	return 0
}
export -f  remove_windows_unfriendly_chars


 # Allows only one instance of the main script to run.
#
single_process_check() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
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
		redmsg "Processes: our: $our_processes_count, total: $total_processes_count.
		        Our processes are:
		        $our_processes
		        Our and foreign processes are:
		        $total_processes"
		err 'Still running.'
	}
	return 0
}
#  No export: init stage function.


 # Expands a string like “1-5” into the range of numbers “1 2 3 4 5”.
#  $1 – string with range, format: N-N, where N is an integer.
#
expand_range() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	local range="$1" expanded_range
	[[ "$range" =~ ^([0-9]+)-([0-9]+)$ ]] || {
		warn "Invalid input range for expansion: “$range”."
		return 1
	}
	seq -s ' ' ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}
	return 0
}
export -f  expand_range


 # Check a number and echo either a plural string or a singular string.
#   $1  – the number to test.
#  [$2] – plural string. If unset, equals to “s”. 
#  [$3] – singular string. By default has no value (and no value is needed).
#
#  Examples
#  1. line – lines
#     echo "The file has $line_number line$(plur_sing  $line_number)."
#        line_number == 1  -->  “The file has 1 line.”
#        line_number == 2  -->  “The file has 2 lines.”
#
#  2. dummy – dummies, mouse – mice
#  echo "We’ve found $mice_count $(plur_sing  $mice_count  mice  mouse)."
#     mice_count == 1   -->  “We’ve found 1 mouse.”
#     mice_count == 2   -->  “We’ve found 2 mice.”
#
#  3. await – awaits
#  echo "$task_count task$(plur_sing  $task_count) await$(plur_sing  $task_count  '' s) your attention."
#     task_count == 1  -->  “1 task awaits your attention.”
#     task_count == 2  -->  “2 tasks await your attention.”
#
#  The name of the function is the mnemonic for the argument order. That they
#    go first plural, then singular may look anti-intuitive, but if the func-
#    tion was called sing_plur, it would add yet another problem,
#    because “plur_sing” sounds more natural.
#
#  As specifying the default plural ending “s” for the function may often seem
#    logical, though not obligatory, the form of the call with the 2nd argument
#    set and the 3rd omitted is also allowed.
#
plur_sing() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	local num="$1"  plural_ending  singular_ending="${3:-}"
	(( $# >= 2 ))  \
		&& plural_ending="$2"  \
		|| plural_ending='s'
	[[ "$num" =~ ^[0-9]+$ ]] || {
		bahelite_print_call_stack
		warn "${FUNCNAME[0]}: “$num” is not a number!"
	}
	#  Avoiding shell arithmetic
	#  Even in case of error in the main script, this way there’s
	#  a 50/50 chance, that the right string would be printed.
	[ "${num##0}" = '1' ]  \
		&& echo -n "$singular_ending"  \
		|| echo -n "$plural_ending"
	return 0
}
export -f  plur_sing


nth() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	local number="$1"
	[[ "$number" =~ ^[0-9]+$ ]]  \
		|| err "The argument must be a number, but “$number” was given."
	echo -n "$number"
	case $number in
		1) echo -n 'st';;
		2) echo -n 'nd';;
		3) echo -n 'rd';;
		*) echo -n 'th';;
	esac
	return 0
}
export -f nth


 # Determine bash variable type
#  Returns: “string”, “regular array”, “assoc. array”
#  $1 – variable name.
#
vartype() {
	local varname="${1:-}" varval vartype_letter
	[ -v "$varname" ] || {
		bahelite_print_call_stack
		err "misc: $FUNCNAME: “$1” must be a variable name!"
	}
	declare -n varval=$varname
	vartype_letter=${varval@a}
	case "${vartype_letter:0:1}" in
		a)	echo 'regular array';;
		A)  echo 'assoc. array';;
		*)  echo 'string';;
	esac
	return 0
}



return 0