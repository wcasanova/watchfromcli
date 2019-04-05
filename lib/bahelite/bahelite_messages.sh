# Should be sourced.

#  bahelite_messages.sh
#  Provides messages for console and desktop.
#  deterenkelt © 2018

# Require bahelite.sh to be sourced first.
[ -v BAHELITE_VERSION ] || {
	echo 'Must be sourced from bahelite.sh.' >&2
	return 5
}
. "$BAHELITE_DIR/bahelite_colours.sh" || return 5

# Avoid sourcing twice
[ -v BAHELITE_MODULE_MESSAGES_VER ] && return 0
#  Declaring presence of this module for other modules.
BAHELITE_MODULE_MESSAGES_VER='2.2.1'

 # Define this variable for info messages to have icon
#
# BAHELITE_INFO_MSG_USE_ICON=t

# Bahelite offers keyword-based messages, which allows
# for creation of localised programs.

 # Message lists
#
#  List of informational messages
#
declare -A BAHELITE_INFO_MESSAGES=()
#
#  List of warning messages
#
declare -A BAHELITE_WARNING_MESSAGES=()
#
#  List of error messages
#  Keys are used as parameters to err() and values are printed via msg().
#  Keys may contain spaces – e.g. ‘my key’. Passing them to err()
#  doesn’t require quoting and the number of spaces is not important.
#  You can add your messages just by adding elements to this array,
#  and perform localisation just by redefining it after sourcing this file!
#
declare -A BAHELITE_ERROR_MESSAGES=(
	[just quit]='Quitting.'
	[old util-linux]='Need util-linux-2.20 or higher.'
	[missing deps]='Dependencies are not satisfied.'
	[no such msg]='Bahelite: No such message: “$1”.'
	[no util]='Utils are missing: $1.'
)

 # Colours for the console and log messages
#  Regular functions (info, warn, err) apply the colour only to the asterisk.
#
BAHELITE_INFO_MESSAGE_COLOUR=$__green
BAHELITE_WARN_MESSAGE_COLOUR=$__yellow
BAHELITE_ERR_MESSAGE_COLOUR=$__red


 # Message indentation level
#  Checking, if it’s already set, in case one script calls another –
#  so that indentaion would be inherited in the inner script.
#
[ -v BAHELITE_MI_LEVEL ] || BAHELITE_MI_LEVEL=0
#
#  The whitespace indentation itself.
#  As it belongs to markup, that user may use, it follows
#  the corresponding style, akin to terminal sequences.
[ -v __mi ] || __mi=''
#
#
#  Number of spaces to use per indentation level.
#  No tabs, because predicting the tab length in a particular terminal
#  is impossible anyway.
[ -v BAHELITE_MI_SPACENUM ] || BAHELITE_MI_SPACENUM=4
#
export BAHELITE_MI_LEVEL     \
       BAHELITE_MI_SPACENUM  \
       __mi


 # Assembles __mi according to the current BAHELITE_MI_LEVEL
#
mi_assemble() {
	#  Internal – called in the module itself!
	#  There should be no xtrace_on/off, as the main code in the module
	#  should do this!
	declare -g __mi=''
	local i
	for (( i=0; i < (BAHELITE_MI_LEVEL*BAHELITE_MI_SPACENUM); i++ )); do
		__mi+=' '
	done
	#  Without this, multiline messages that occur on BAHELITE_MI_LEVEL=0,
	#  when $__mi is empty, won’t be indented properly. ‘* ’, remember?
	[ "$__mi" ] || __mi='  '
	return 0
}


 # Increments the indentation level.
#  [$1] — number of times to increment $MI_LEVEL.
#         The default is to increment by 1.
#
milinc() {
	xtrace_off && trap xtrace_on RETURN
	local count=${1:-1}  z
	for ((z=0; z<count; z++)); do
		let '++BAHELITE_MI_LEVEL || 1'
	done
	mi_assemble || return $?
}


 # Decrements the indentation level.
#  [$1] — number of times to decrement $MI_LEVEL.
#  The default is to decrement by 1.
#
mildec() {
	xtrace_off && trap xtrace_on RETURN
	local count=${1:-1}  z
	if (( BAHELITE_MI_LEVEL == 0 )); then
		warn "No need to decrease indentation, it’s on the minimum."
	else
		for ((z=0; z<count; z++)); do
			let '--BAHELITE_MI_LEVEL || 1'
		done
		mi_assemble || return $?
	fi
	return 0
}


 # Sets the indentation level to a specified number.
#  $1 – desired indentation level, 0..9999.
#
milset () {
	xtrace_off && trap xtrace_on RETURN
	local mi_level=${1:-}
	[[ "$mi_level" =~ ^[0-9]{1,4}$ ]] || {
		warn "Indentation level should be an integer between 0 and 9999."
		return 0
	}
	BAHELITE_MI_LEVEL=$mi_level
	mi_assemble || return $?
}


 # Removes any indentation.
#
mildrop() {
	xtrace_off && trap xtrace_on RETURN
	BAHELITE_MI_LEVEL=0
	mi_assemble || return $?
}


 # Desktop notifications
#
#  To send a notification to both console and desktop, main script should
#  call info-ns(), warn-ns() or err() function. As err() always ends the
#  program, its messages can’t be of lower importance. Thus they are always
#  sent to desktop (if only NO_DESKTOP_NOTIFICATIONS is set).
#
 # If set, disables all desktop notifications.
#  All message functions will print only to console.
#  By default it is unset, and notifications are shown.
#
#NO_DESKTOP_NOTIFICATIONS=t

 # Shows a desktop notification
#  $1 – message.
#  $2 – icon type: empty, “information”, “warning” or “error”.
#
bahelite_notify_send() {
	xtrace_off && trap xtrace_on RETURN
	[ -v NO_DESKTOP_NOTIFICATIONS ] && return 0
	local msg="$1" icon="$2" duration urgency='normal'
	case "$icon" in
		error)
			icon='dialog-error'
			;&
		dialog-error)
			urgency=critical
			duration=10000
			;;
		warning)
			icon='dialog-warning'
			;&
		dialog-warning)
			duration=10000
			;;
		*) duration=3000;;  # info: 3s
	esac
	# The hint is for the message to not pile in the stack – it is limited.
	# ||:  is for running safely under set -e.
	which notify-send &>/dev/null \
		|| warn 'Cannot show error message on desktop: notify-send not found.'
	notify-send --hint int:transient:1 \
	            --urgency "$urgency" \
	            -t $duration \
	            "$MY_DESKTOP_NAME"  "$msg" \
	            ${icon:+--icon=$icon} || :
	return 0
}



 # Shows an info message.
#  Features asterisk, automatic indentation with mil*, keeps lines
#  $1 — a message or a key of an item in the corresponding array containing
#       the messages. Depends on whether $MSG_USE_ARRAYS is set (see above).
#
info() {
	xtrace_off && trap xtrace_on RETURN
	msg "$@"
}

 # Same as info(), but omits the ending newline, like “echo -n” does.
#  This allows to print whatever with just simple “echo” later.
#
infon() {
	xtrace_off && trap xtrace_on RETURN
	msg "$@"
}

 # Like info(), but has a higher rank than usual info(),
#  which allows its message to be also shown on desktop.
#  $1 – a message to be shown both in console and on desktop.
#
info-ns() {
	xtrace_off && trap xtrace_on RETURN
	msg "$@"
}

 # Shows an info message and waits for the given command to finish,
#  to print its result, and if it’s not zero, print the output
#  of that command.
#
#  $1 – a message. Something like ‘Starting up servicename… ’
#  $2 – a command.
#  $3 – any string to force the output even if the result is [OK].
#       Handy for faulty programs that return 0 even on error.
#
infow() {
	xtrace_off && trap xtrace_on RETURN
	local message=$1 command=$2 force_output="$3" outp result
	msg "$message"
	outp=$( bash -c "$command" 2>&1 )
	result=$?
	[ $result -eq 0 ] \
		&& printf "${__bri}%s${__g}%s${__s}${__bri}%s${__s}\n"  ' [ ' OK ' ]' \
		|| printf "${__bri}%s${__r}%s${__s}${__bri}%s${__s}\n"  ' [ ' Fail ' ]'
	[ $result -ne 0 -o "$force_output" ] && {
		milinc
		info "Here is the output of ‘$command’:"
		plainmsg "$outp"
		mildec
	}
	return 0
}


 # Like info, but the output goes to stderr.
#
warn() {
	xtrace_off && trap xtrace_on RETURN
	msg "$@"
}


 # Like warn(), but has a higher rank than usual info(),
#  which allows its message to be also shown on desktop.
#  $1 – a message to be shown both in console and on desktop.
#
warn-ns() {
	xtrace_off && trap xtrace_on RETURN
	msg "$@"
}


 # Shows an error message and calls “exit”.
#  Error messages always go
#    - to console in stderr, prepended with red asterisk;
#    - to desktop with notify-send, with “crirical” urgency
#      and a corresponding icon.
#  The exit code is 5, unless you explicitly set MSG_USE_ARRAYS and defined
#    error messages with corresponding codes in the table.
#
err() {
	xtrace_off && trap xtrace_on RETURN
	msg "$@" || exit $?
}


 # Same as err(), but prints the whole line in red.
#
errw() {
	xtrace_off && trap xtrace_on RETURN
	msg "$@" || exit $?
}


abort() {
	xtrace_off && trap xtrace_on RETURN
	msg "$@" || exit $?
}


 # For Bahelite internal warnings and errors.
#  These functions use BAHELITE_*_MESSAGES and should be preferred
#  for use within Bahelite.
#
iwarn() {
	xtrace_off && trap xtrace_on RETURN
	msg "$@"
}
ierr() {
	xtrace_off && trap xtrace_on RETURN
	msg "$@" || exit $?
}

 # For internal use in alias functions, such as infow(), where we cannot use
#  msg() as is, because FUNCNAME[1] will be set to the name of that alias
#  function. Hence, to avoid additions and get a plain msg(), we must call it
#  from another function, for which no additions are specified in msg().
#
plainmsg() {
	xtrace_off && trap xtrace_on RETURN
	msg "$@"
}


 # Shows an info, a warning or an error message
#  on console and optionally, on desktop too.
#  $1 — a text message or, if MSG_USE_ARRAYS is set, a key from
#       - INFO_MESSAGES, if called as info*();
#       - WARNING_MESSAGES,  if called as warn*();
#       - ERROR_MESSAGES, if called as err*().
#       That key may contain spaces, and the number of spaces between words
#       in the key is not important, i.e.
#         $ warn "no needed file found"
#         $ warn  no needed file found
#       and
#         $ warn  no   needed  file     found
#       will use the same item in the WARNING_MESSAGES array.
#  RETURNS:
#    If called as an err* function, then quits the script
#    with exit/return code 5 or 5–∞, if ERROR_CODES is set.
#    Returns zero otherwise.
#
msg() {
	# Internal! There should be no xtrace_off!
	# xtrace_off && trap xtrace_on RETURN
	declare -g  BAHELITE_EXIT_FROM_ERR_FUNC
	local  colour  cs="$__s"  nonl  asterisk='  '  \
	       message  message_nocolours  \
	       redir=stdout  code=5  internal  key  msg_key_exists  \
	       notifysend_rank  notifysend_icon
	case "${FUNCNAME[1]}" in
		*info*|abort)  # all *info*
			msgtype=info
			local -n  msg_array=INFO_MESSAGES
			local -n  colour=BAHELITE_INFO_MESSAGE_COLOUR
			;;&
		info|infon|info-ns|abort)
			asterisk="* ${MSG_ASTERISK_PLUS_WORD:+INFO: }"
			;;&
		info-ns|abort)
			notifysend_rank=1
			[ -v BAHELITE_INFO_MSG_USE_ICON ] && notifysend_icon='info'
			;;&
		infow)
			asterisk="* ${MSG_ASTERISK_PLUS_WORD:+RUNNING: }"
			nonl=t
			;;
		infon)
			nonl=t
			;;
		*warn*)
			msgtype=warn redir='stderr'
			local -n  msg_array=WARNING_MESSAGES
			local -n  colour=BAHELITE_WARN_MESSAGE_COLOUR
			asterisk="* ${MSG_ASTERISK_PLUS_WORD:+WARNING: }"
		    ;;&
		warn-ns)
			notifysend_rank=1
			notifysend_icon='dialog-warning'
			;;
		*err*)
			msgtype=err redir='stderr'
			local -n  msg_array=ERROR_MESSAGES
			local -n  colour=BAHELITE_ERR_MESSAGE_COLOUR
			asterisk="* ${MSG_ASTERISK_PLUS_WORD:+ERROR: }"
			notifysend_rank=1
			notifysend_icon='dialog-error'
			;;&
		errw)
			asterisk='  '
			cs=''  # print whole line in red, no asterisk.
			;;
		iwarn|ierr|iinfo)
			internal=t
			;;&
		iwarn)
			# For internal messages.
			local -n  msg_array=BAHELITE_WARNING_MESSAGES
			notifysend_rank=1
			notifysend_icon='dialog-warning'
			;;
		ierr)
			# For internal messages.
			local -n  msg_array=BAHELITE_ERROR_MESSAGES
			;;
		abort)
			msgtype='abort'
			code=7
			;;
	esac
	[ -v nonl ] && nonl='-n'
	[ -v QUIET ] && redir='devnull'
	[ -v MSG_USE_ARRAYS -o -v internal ] && {
		#  What was passed to us is not a message per se,
		#  but a key in the messages array.
		message_key="${1:-}"
		for key in "${!msg_array[@]}"; do
			[ "$key" = "$message_key" ] && message_key_exists=t
		done
		if [ -v message_key_exists ]; then
			#  Positional parameters "$2..n" now can be substituted
			#  into the message strings. To make these substitutions go
			#  from the number 1, drop the $1, holding the message key.
			shift
			eval message=\"${msg_array[$message_key]}\"
		else
			ierr 'no such msg' "$message_key"
		fi
	}|| message="${1:-No message?}"
	#  Removing blank space before message lines.
	#  This allows strings to be split across lines and at the same time
	#  be well-indented with tabs and/or spaces – indentation will be cut
	#  from the output.
	message=$(sed -r 's/^\s*//; s/\n\t/\n/g' <<<"$message")
	message_nocolours=$(strip_colours "$message")
	#  Both fold and fmt use smaller width,
	#  if they deal with non-Latin characters.
	if [ -v BAHELITE_FOLD_MESSAGES ]; then
		message=$(echo -e ${nonl:-} "${colour:-}$asterisk$cs$message$cs" \
		              | fold  -w $((TERM_COLS - ${#__mi} -2)) -s \
		              | sed -r "1s/^/${__mi#  }/; 1!s/^/$__mi/g" )
	else
		message=$(echo -e ${nonl:-} "${colour:-}$asterisk$cs$message$cs" \
		              | sed -r "1s/^/${__mi#  }/; 1!s/^/$__mi/g" )
	fi
	case $redir in
		stdout)  echo ${nonl:-} "$message";;
		stderr)  echo ${nonl:-} "$message" >&2;;
		devnull) : ;;
	esac
	[ ${notifysend_rank:--1} -ge 1 ] && {
		#  Stripping colours, that might be placed in the $message by user.
		bahelite_notify_send "$message_nocolours" "${notifysend_icon:-}"
	}
	[ "$msgtype" = err ] && BAHELITE_EXIT_FROM_ERR_FUNC=t
	[[ "$msgtype" =~ ^(err|abort)$ ]] && {
		#  If this is an error message, we must also quit
		#  with a certain exit/return code.
		[ -v MSG_USE_ARRAYS ] && [ ${#ERROR_CODES[@]} -ne 0 ] \
			&& code=${ERROR_CODES[$*]}
		#  Bahelite can be used in both sourced and standalone scripts.
		#  Default error codes are 5 for an error, 7 for abort.
		#  Abort is for the case when user stops the program at some step.
		#  Return codes are defined in pairs: “usual” and “from subshell”,
		#    this is done to catch returns from the functions, that are
		#    capable of triggering an exit. When err() for example is called
		#    from within a subshell, it’s easy to place “|| exit $?” after
		#    “$(…)” to exit properly, but this isn’t enough to clean tidily –
		#    because such functions may set variables, that will be lost
		#    within the subshell, however, top-level hooks on signals (aka
		#    trap functions) will expect those variables to be set. By check-
		#    ing, if the exit code would be “from subshell”, these functions
		#    may do their work without variables.
		[ $BASH_SUBSHELL -ne 0 ] && let ++code
		return $code
	}
	return 0
}


xtrace_off
mi_assemble
xtrace_on


return 0