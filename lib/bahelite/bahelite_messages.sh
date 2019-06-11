# Should be sourced.

#  bahelite_messages.sh
#  Provides messages for console and desktop (if messages_to_desktop module
#  is included too).
#  © deterenkelt 2018–2019

#  Require bahelite.sh to be sourced first.
[ -v BAHELITE_VERSION ] || {
	echo "Bahelite error on loading module ${BASH_SOURCE##*/}:"
	echo "load the core module (bahelite.sh) first." >&2
	return 4
}

#  Avoid sourcing twice
[ -v BAHELITE_MODULE_MESSAGES_VER ] && return 0
[ -v MSG_DISABLE_COLOURS ] || {
	bahelite_load_module 'colours' || return $?
}
#  Declaring presence of this module for other modules.
declare -grx BAHELITE_MODULE_MESSAGES_VER='2.8.1'



                         #  Message types  #

#  See the wiki. (It’s not written yet.)



                        #  Verbosity levels  #

#  See the wiki. (It’s not written yet.)

 # Removes spacing characters: “-”, “_” and “ ” from VERBOSITY_LEVEL
#
bahelite_sanitise_verbosity_level() {
	declare -g VERBOSITY_LEVEL
	if [[ "$VERBOSITY_LEVEL" =~ ^([0-9]{2})[\ _-]?([0-9]{2})[\ _-]?([0-9]{2}) ]]; then
		#  All six numbers? Just remove spacing.
		VERBOSITY_LEVEL="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"

	elif [[ "$VERBOSITY_LEVEL" =~ ^([0-9])[\ _-]?([0-9])[\ _-]?([0-9]) ]]; then
		#  Short form of three numbers? Remove spacing, add zeroes
		#  for user-level verbosity.
		VERBOSITY_LEVEL="${BASH_REMATCH[1]}0${BASH_REMATCH[2]}0${BASH_REMATCH[3]}0"

	else
		redmsg "Incorrect value for VERBOSITY_LEVEL: “$VERBOSITY_LEVEL”.
		        Should be a string of six numbers, optionally divided by either
		        a space, a hyphen or an underscore, e.g. 303030 or 30-10-00."
		err "VERBOSITY_LEVEL must be a string of six numbers."
	fi
	return 0
}
#  No export: init stage function.


 # Verifies, that VERBOSITY_LEVEL is a correct string.
#  To be used in runtime calls to get_bahelite/user_verbosity().
#
bahelite_verify_verbosity_level() {
	#  In the future more format may appear, e.g. as an associative array
	#  or as a string with spaces like “30 30 30”.
	[[ "$VERBOSITY_LEVEL" =~ ^[0-9]{6}$ ]] || {
		redmsg "Incorrect value for VERBOSITY_LEVEL: “$VERBOSITY_LEVEL”.
		        Should be a string of six numbers, optionally divided by either
		        a space, a hyphen or an underscore."
		err "VERBOSITY_LEVEL must be a string of six numbers."
	}
	return 0
}
export -f  bahelite_verify_verbosity_level


 # Extracts output (log/console/desktop) verbosity level from VERBOSITY_LEVEL.
#
#  Returns the first number of the output verbosity number,
#  e.g. 123456 for requested output “log” will return “1”
get_bahelite_verbosity()  { __get_verbosity "$1" bahelite; }
#
#  Returns the second digit of the output verbosity number,
#  e.g. 123456 for requested output “log” will return “2”
get_user_verbosity()      { __get_verbosity "$1" user; }
#
#  Returns both digits of the output verbosity number,
#  e.g. 123456 for requested output “log” will return “10”
get_overall_verbosity()   { __get_verbosity "$1" overall; }
#
#
__get_verbosity() {
	local output="$1" mode="$2"
	bahelite_verify_verbosity_level
	case "$output" in
		log)
			case "$mode" in
				'bahelite')
					echo "${VERBOSITY_LEVEL:0:1}"
					;;
				'user')
					echo "${VERBOSITY_LEVEL:1:1}"
					;;
				'overall')
					echo "${VERBOSITY_LEVEL:0:2}"
					;;
			esac
			;;

		console)
			case "$mode" in
				'bahelite')
					echo "${VERBOSITY_LEVEL:2:1}"
					;;
				'user')
					echo "${VERBOSITY_LEVEL:3:1}"
					;;
				'overall')
					echo "${VERBOSITY_LEVEL:2:2}"
					;;
			esac
			;;

		desktop)
			case "$mode" in
				'bahelite')
					echo "${VERBOSITY_LEVEL:4:1}"
					;;
				'user')
					echo "${VERBOSITY_LEVEL:5:1}"
					;;
				'overall')
					echo "${VERBOSITY_LEVEL:4:2}"
					;;
			esac
			;;
		*)
			err "Unknown verbosity output: “$output”.
			     Must be one of: log, console, desktop."
			;;
	esac
	return 0
}
export -f  __get_verbosity  \
               get_bahelite_verbosity  \
               get_user_verbosity  \
               get_overall_verbosity  \

[ -v VERBOSITY_LEVEL ]  \
	|| declare -gx VERBOSITY_LEVEL='333'
bahelite_sanitise_verbosity_level




                         #  Message lists  #

 # Internal message lists
#
declare -gAx BAHELITE_INFO_MESSAGES=()
declare -gAx BAHELITE_WARNING_MESSAGES=()
#
 # Error messages
#  Keys are used as parameters to err() and values are printed via msg().
#  The keys can contain spaces – e.g. ‘my key’. Passing them to err() doesn’t
#    require quoting and the number of spaces is not important.
#  You can localise messages by redefining this array in some file
#    and sourcing it.
#
declare -gAx BAHELITE_ERROR_MESSAGES=(
	[no such msg]='No such message keyword: “$1”.'
	[no util]='Utils are missing: $1.'
)
#
#
 # User lists
#  By default, functions like info(), warn(), err() will accept a text string
#  and display it. However, it’s possible to replace strings with keywords
#  and hold them separately. This comes handy, when
#  - the messages are too big and ruin the length of lines in the code;
#  - especially when you’d like to use the text of the message as a template,
#    and pass parameters to err(), so that it would substitute them – making
#    a big string with big variable names inside may be really ugly.
#  - when you want to localise your script and keep language-agnostic keywords
#    in the code while pulling the actual messages from a file with localisa-
#    tion.
#  In order to enable keyword-based messages, define MSG_USE_KEYWORDS with
#  any value in the main script. This will switch off the messaging system
#  to arrays.
#
# declare -x MSG_USE_KEYWORDS=t
#
declare -gAx INFO_MESSAGES=()
declare -gAx WARNING_MESSAGES=()
declare -gAx ERROR_MESSAGES=()
#
#  Custom exit codes, the keys should be the same as in ERROR_MESSAGES.
declare -gAx ERROR_CODES=()


 # Colours for the console and log messages
#  Regular functions (info, warn, err) apply it only to asterisk.
#  Somebody may have an idea to use these variables to colour their own
#    output, but if MSG_DISABLE_COLOURS would be set, such usage may end
#    with a bash error, so there should be at least an empty value.
#
declare -gx INFO_MESSAGE_COLOUR=${__green:-}
declare -gx WARN_MESSAGE_COLOUR=${__yellow:-}
declare -gx ERR_MESSAGE_COLOUR=${__red:-}
declare -gx PLAIN_MESSAGE_COLOUR=${__fg_rst:-}
declare -gx HEADER_MESSAGE_COLOUR=${__yellow:-}${__bright:-}


 # Define this variable to start each message not with just an asterisk
#    ex:  * Stage 01 completed.
#  but with a keyword that would define the type of the message. Especially
#  handy if you use MSG_DISABLE_COLOURS=t to suppress colours.
#    ex:  * INFO: Stage 01 completed.
#
# declare -gx MSG_ASTERISK_WITH_MSGTYPE=t
#
#
 # Define this variable in the main script to disable colouring the messages.
#  This will not untie the dependencies to the colours module. The variables
#  from bahelite_colours.sh will still be available, however, they will be
#  stripped or not added to any *info*() *warn*() or *err*() messages.
#
# declare -gx MSG_DISABLE_COLOURS=t
#
#
 # When printing to console/logs, use “fold” for better appearance. This uti-
#  lity, however, is not aware of wide characters (in the bit-wise sense),
#  so if you deal with non-ascii characters, you may get only 1/2 of the
#  terminal width used.
#
# declare -gx MSG_FOLD_MESSAGES=t

 # Message indentation level
#  Checking, if it’s already set, in case one script calls another –
#  so that indentaion would be inherited in the inner script.
[ -v MSG_INDENTATION_LEVEL ]  \
	|| declare -gx MSG_INDENTATION_LEVEL=0
#
#  So that mildrop() could decrease the level properly in chainloaded scripts.
declare -gx MSG_INDENTATION_LEVEL_UPON_ENTRANCE=$MSG_INDENTATION_LEVEL
#
#  The whitespace indentation itself.
#  As it belongs to markup, that user may use in the main script for custom
#    messages, it follows the corresponding style, akin to terminal sequences.
#  The string will be set according too the MSG_INDENTATION_LEVEL on the call
#    to mi_assemble() below.
declare -gx __mi=''
#
#  Number of spaces to use per indentation level.
#  Not tabs, because predicting the tab length in a particular terminal
#  is impossible anyway.
[ -v MSG_INDENTATION_SPACES_PER_LEVEL ]  \
	|| declare -gx MSG_INDENTATION_SPACES_PER_LEVEL=4


 # Assembles __mi according to the current MSG_INDENTATION_LEVEL
#
mi_assemble() {
	#  Internal! No xtrace_off/on needed!
	__mi=''
	local i
	for	((	i=0;
			i < (    MSG_INDENTATION_LEVEL
			       * MSG_INDENTATION_SPACES_PER_LEVEL);
			i++
		))
	do
		__mi+=' '
	done
	#  Without this, multiline messages that occur on MSG_INDENTATION_LEVEL=0,
	#  when $__mi is empty, won’t be indented properly. ‘* ’, remember?
	[ "$__mi" ] || __mi='  '
	return 0
}
export -f  mi_assemble


 # Increments the indentation level.
#  [$1] — number of times to increment $MI_LEVEL.
#         The default is to increment by 1.
#
milinc() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	local count=${1:-1}  z
	for ((z=0; z<count; z++)); do
		let '++MSG_INDENTATION_LEVEL,  1'
	done
	mi_assemble || return $?
}
export -f  milinc


 # Decrements the indentation level.
#  [$1] — number of times to decrement $MI_LEVEL.
#  The default is to decrement by 1.
#
mildec() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	local count=${1:-1}  z
	if (( MSG_INDENTATION_LEVEL == 0 )); then
		warn "No need to decrease indentation, it’s on the minimum."
	else
		for ((z=0; z<count; z++)); do
			let '--MSG_INDENTATION_LEVEL,  1'
		done
		mi_assemble || return $?
	fi
	return 0
}
export -f  mildec


 # Sets the indentation level to a specified number.
#  The use of this function is discouraged. milinc, mildec and mildrop are
#  better for handling increases and drops in the message indentation level.
#  $1 – desired indentation level, 0..9999.
#
milset () {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	local mi_level=${1:-}
	[[ "$mi_level" =~ ^[0-9]{1,4}$ ]] || {
		warn "Indentation level should be an integer between 0 and 9999."
		return 0
	}
	MSG_INDENTATION_LEVEL=$mi_level
	mi_assemble || return $?
}
export -f  milset


 # Removes any indentation.
#
mildrop() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	MSG_INDENTATION_LEVEL=$MSG_INDENTATION_LEVEL_UPON_ENTRANCE
	mi_assemble || return $?
}
export -f  mildrop



              #  Messages to console, log and desktop  #

 # Some of the message functions below send messages only to log, and not
#  console and not to desktop.
#
#
 # Message properties
#
# __msg_properties=(
# 	#  A role is an anchor, that tells about the sense, the context,
# 	#  in which a certain message is used. It explains, why the rest
# 	#  of the properties ended up in such a set.
# 	[role]=''
# 	#  If MSG_USE_KEYWORDS is set, then the actual texts and exit codes
# 	#  would be taken from there.
# 	[message_array]=''
# 	#  The colour to output the asterisk with. For certain types the en-
# 	#  tire message is coloured. When MSG_ASTERISK_WITH_MSGTYPE is set,
# 	#  a type (role) of the message is added to the asterisk and gets
# 	#  coloured too. If MSG_DISABLE_COLOURS is defined, the message will go
# 	#  in plain text.
# 	[colour]=''
# 	#  Whether only the asterisk at the beginning, or the entire message
# 	#  should be coloured.
# 	[whole_message_in_colour]=''
# 	#  The string, that has an asterisk, space next to it, and the message
# 	#  type/role, if MSG_ASTERISK_WITH_MSGTYPE is set.
# 	[asterisk]=''
# 	#  A string, that etermines, whether the message should go desktop
# 	#  (at the default VERBOSITY_LEVEL). Should be “yes” or “no”.
# 	[desktop_message]=''
# 	#  The type of message to pass for “notify-send”, if the message goes
# 	#  to desktop. Either “info”, “dialog-warning” or “dialog-error”.
# 	#  This type also determines urgency in bahelite_notify_send().
# 	[desktop_message_type]=''
# 	#  Whether the message is wholesome or it’s just a part of a compound
# 	#  message. Setting “yes” here makes the console message to be printed
# 	#  without a newline on the end, and the output can continue on this
# 	#  same line. For most messages this is set to “no”. Desktop messages
# 	#  ignore this option – even there’d be a newline on the end, it will
# 	#  be cut.
# 	[stay_on_line]=''
# 	#  Whether the message should go to “stdout” or “stderr” (at the
# 	#  default VERBOSITY_LEVEL).
# 	[output]=''
# 	#  Whether the message is internal, i.e. generated by Bahelite itself.
# 	#  Internal messages always use keywords, and this is a hook to tell
# 	#  __msg to enter the necessary part of code without activating
# 	#  MSG_USE_KEYWORDS.
# 	[internal]=''
# 	#  Whether the message should also initiate an exit from the program.
# 	#  Only *err*() and abort() use exit codes. All other message func-
# 	#  tion don’t have an exit code and __msg will simply return.
# 	[exit_code]=''
# )


 # Shows an info message.
#  $1 — a message or a key of an item in the corresponding array containing
#       the messages. Depends on whether $MSG_USE_KEYWORDS is set (see above).
#
info() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='info'
		[message_array]='INFO_MESSAGES'
		[colour]='INFO_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]="* ${MSG_ASTERISK_WITH_MSGTYPE:+INFO: }"
		[desktop_message]='no'
		[desktop_message_type]=''
		[stay_on_line]='no'
		[output]='stdout'
		[internal]='no'
		[exit_code]=''
	)
	__msg "$@"
	return 0
}
export -f  info


 # Same as info(), but omits the ending newline, like “echo -n” does.
#  This allows to print whatever with just simple “echo” later.
#
infon() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='info'
		[message_array]='INFO_MESSAGES'
		[colour]='INFO_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]="* ${MSG_ASTERISK_WITH_MSGTYPE:+INFO: }"
		[desktop_message]='no'
		[desktop_message_type]=''
		[stay_on_line]='yes'
		[output]='stdout'
		[internal]='no'
		[exit_code]=''
	)
	__msg "$@"
	return 0
}
export -f  infon


 # Like info(), but has a higher rank than usual info(),
#  which allows its message to be also shown on desktop.
#  $1 – a message to be shown both in console and on desktop.
#
info-ns() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='info'
		[message_array]='INFO_MESSAGES'
		[colour]='INFO_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]="* ${MSG_ASTERISK_WITH_MSGTYPE:+INFO: }"
		[desktop_message]='yes'
		[desktop_message_type]='info'
		[stay_on_line]='no'
		[output]='stdout'
		[internal]='no'
		[exit_code]=''
	)
	__msg "$@"
	return 0
}
export -f  info-ns


 # Shows an info message and waits for the given command to finish,
#  to print its result, and if it’s not zero, print the output
#  of that command.
#
#  $1 – a message. Something like ‘Starting up servicename… ’
#  $2 – a command.
#  $3 – any string to force the output even if the result is [OK].
#       Handy for faulty programs that return 0 even on error.
#
info-wait() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	local message=$1 command=$2 force_output="$3" outp result
	declare -A __msg_properties=(
		[role]='info'
		[message_array]='INFO_MESSAGES'
		[colour]='INFO_MESSAGE_COLOUR'
		[whole_message_in_colour]='yes'
		[asterisk]="  ${MSG_ASTERISK_WITH_MSGTYPE:+RUNNING: }"
		[desktop_message]='no'
		[desktop_message_type]=''
		[stay_on_line]='yes'
		[output]='stdout'
		[internal]='no'
		[exit_code]=''
	)
	__msg "$message"

	outp=$( bash -c "$command" 2>&1 )
	result=$?
	[ $result -eq 0 ] \
		&& echo -e "${__bri:-} [ ${__g:-}OK${__s:-}${__bri:-} ] ${__s:-}"  \
		|| echo -e "${__bri:-} [ ${__r:-}Fail${__s:-}${__bri:-}]${__s:-}"
	[ $result -ne 0 -o "$force_output" ] && {
		milinc
		info "Here is the output of ‘$command’:"
		plainmsg "$outp"
		mildec
	}
	return 0
}
export -f  info-wait


 # Like info, but the output goes to stderr.
#
warn() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='warn'
		[message_array]='WARNING_MESSAGES'
		[colour]='WARN_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]="* ${MSG_ASTERISK_WITH_MSGTYPE:+WARNING: }"
		[desktop_message]='no'
		[desktop_message_type]=''
		[stay_on_line]='no'
		[output]='stdout'
		[internal]='no'
		[exit_code]=''
	)
	__msg "$@"
	return 0
}
export -f  warn


 # Like warn(), but has a higher rank than usual info(),
#  which allows its message to be also shown on desktop.
#  $1 – a message to be shown both in console and on desktop.
#
warn-ns() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='warn'
		[message_array]='WARNING_MESSAGES'
		[colour]='WARN_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]="* ${MSG_ASTERISK_WITH_MSGTYPE:+WARNING: }"
		[desktop_message]='yes'
		[desktop_message_type]='warn'
		[stay_on_line]='no'
		[output]='stderr'
		[internal]='no'
		[exit_code]=''
	)
	__msg "$@"
	return 0
}
export -f  warn-ns


 # Shows an error message and calls “exit”.
#  Good to show a resume of the error. For the big descriptions better
#    use redmsg() before calling err().
#  The exit code is 5, unless you explicitly set MSG_USE_KEYWORDS and defined
#    error messages with corresponding codes in that array.
#
err() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='err'
		[message_array]='ERROR_MESSAGES'
		[colour]='ERR_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]="* ${MSG_ASTERISK_WITH_MSGTYPE:+ERROR: }"
		[desktop_message]='yes'
		[desktop_message_type]='err'
		[stay_on_line]='no'
		[output]='stderr'
		[internal]='no'
		[exit_code]='5'
	)
	__msg "$@"
	#  ^ Exits.
}
export -f  err


 # Has the appearance of err(), but doesn’t call “exit” afterwards.
#  It suites for printing big descriptive messages to console/logs,
#  while using err() to print the final – short! – message, that is also
#  suites to be shows as a desktop notification.
#
redmsg() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='redmsg'
		[message_array]='ERROR_MESSAGES'
		[colour]='ERR_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]="* ${MSG_ASTERISK_WITH_MSGTYPE:+ERROR: }"
		[desktop_message]='no'
		[desktop_message_type]=''
		[stay_on_line]='no'
		[output]='stderr'
		[internal]='no'
		[exit_code]=''
	)
	__msg "$@"
	return 0
}
export -f  redmsg


 # A forbidding info message. Close to warn, but unlike that it tells about
#  something expected: important, but not worrisome. Consider this as a road-
#  block or a guard on some slave route, that is not accessible in the cur-
#  rent situation. A road block sign or a barrier should be visible, distinc-
#  tive, as well as a guard would make distinctive hand moves, showing that
#  there’s no passing and probably whistling – hence the cross and the red
#  colour.
#
denied() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='info'
		[message_array]='INFO_MESSAGES'
		[colour]='ERR_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]="× ${MSG_ASTERISK_WITH_MSGTYPE:+DENIED: }"
		[desktop_message]='no'
		[desktop_message_type]=''
		[stay_on_line]='no'
		[output]='stdout'
		[internal]='no'
		[exit_code]=''
	)
	__msg "$@"
	return 0
}
export -f  denied


 # Shows a hint for the previous message
#  There are times, when you run some program, that may print weird messages.
#  They are numerous and you cannot do anything about them, because the verbo-
#  sity of that program is already turned off to minimum. (ffmpeg is one exam-
#  ple.) For such programs, it is handy to print a hint – in which cases the
#  messages should be worried about, and in which they are just unavoidable
#  clutter, that the user may safely ignore.
#
sub-msg() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='info'
		[message_array]='INFO_MESSAGES'
		[colour]='PLAIN_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]="^ ${MSG_ASTERISK_WITH_MSGTYPE:+INFO: }"
		[desktop_message]='no'
		[desktop_message_type]=''
		[stay_on_line]='no'
		[output]='stdout'
		[internal]='no'
		[exit_code]=''
	)
	__msg "$@"
	return 0
}
export -f  sub-msg


 # Same as err(), but prints the whole line in red.
#
errw() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='err'
		[message_array]='ERROR_MESSAGES'
		[colour]='ERR_MESSAGE_COLOUR'
		[whole_message_in_colour]='yes'
		[asterisk]="  ${MSG_ASTERISK_WITH_MSGTYPE:+ERROR: }"
		[desktop_message]='yes'
		[desktop_message_type]='err'
		[stay_on_line]='no'
		[output]='stderr'
		[internal]='no'
		[exit_code]='5'
	)
	__msg "$@"
	#  ^ Exits.
}
export -f errw


 # Like err(), but has the appearance of info message to both console
#  and desktop. For the case when user aborts an action – for him this is
#  something exprected and normal, while error is for the unexpected and wrong.
#
abort() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='abort'
		[message_array]='INFO_MESSAGES'
		[colour]='INFO_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]="* ${MSG_ASTERISK_WITH_MSGTYPE:+ABORT: }"
		[desktop_message]='yes'
		[desktop_message_type]='info'
		[stay_on_line]='no'
		[output]='stdout'
		[internal]='no'
		[exit_code]='6'
	)
	__msg "$@"
	#  ^ Exits.
}
export -f  abort


 # For Bahelite internal warnings and errors.
#  These functions use BAHELITE_*_MESSAGES and should be preferred
#  for use within Bahelite.
#
 #  1. Needs iinfo and iwarn to show only when BAHELITE_MODULES_ARE_VERBOSE
#      is set.
#   2. iinfo and iwarn must print which module (file) and which function
#      they are called from (as they don’t stop the program, there’d be no
#      call trace).
#   3. Internal info and warning messages should have different colours:
#      light cyan would suit for info and purple for warnings.
#
#iinfo () {
#
#}
#
#
#
iwarn() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='warn'
		[message_array]='BAHELITE_WARNING_MESSAGES'
		[colour]='WARN_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]="* ${MSG_ASTERISK_WITH_MSGTYPE:+WARNING: }"
		[desktop_message]='no'
		[desktop_message_type]=''
		[stay_on_line]='no'
		[output]='stdout'
		[internal]='yes'
		[exit_code]=''
	)
	__msg "$@"
	return 0
}
export -f  iwarn


 # CHANGE IERR
#  it must show call stack, as a failure in a library function should
#    probably be serious and hard to find without it.
#
#
 # Characteristics of “err”:
#    - the source of error is self-evident and unique, one of a kind.
#    - the error is always clear to the user.
#    - the error does not need a stack trace.
#  Typical use: wrong arguments to the program, lack of some dependency,
#    encountering unsupported formats in the middle of execution, user forci-
#    bly interrupts execution (from the inside) or kills the program (from the
#    outside), other knows and understandable to user reasons, why the program
#    may stop without success.
#
#
 # Characteristics of “ierr”:
#    - the source of error is entangled in the code, the function is probably
#      not on the surface, but rather at some level of depth, quite possibly
#      an universal helper, that can be called from multiple places in the
#      code.
#    - the error says nothing, that user can fix or even understand.
#    - the error requires a stack trace to make sure, where it happens.
#  Typical use: a function didn’t receive a required argument (or the argument
#    is wrong), a protocol error.
#
#
 # (The unforseen errors that happen due to language syntax errors or because
#  a command fails are currently printed with err(), but maybe they should
#  use ierr() instead)
#
 # Things that need to be changed:
#  1. err and ierr must recognise both predefined messages and messages as is.
#     Maybe use some prefix for the rpedefined one? like start them with
#      a semicolon?  > err ':wahaha' "$some_var_for_substitution"



ierr() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='err'
		[message_array]='BAHELITE_ERROR_MESSAGES'
		[colour]='ERR_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]="* ${MSG_ASTERISK_WITH_MSGTYPE:+ERROR: }"
		[desktop_message]='yes'
		[desktop_message_type]='err'
		[stay_on_line]='no'
		[output]='stderr'
		[internal]='yes'
		[exit_code]='4'
	)
	__msg "$@"
	#  ^ Exits.
}
export -f  ierr


 # For internal use in alias functions, such as infow(), where we cannot use
#    __msg() as is, because FUNCNAME[1] will be set to the name of that alias
#    function. Hence, to avoid additions and get a plain msg(), we must call
#    it from another function, for which no additions are specified in msg().
#  It can, however, be use in the main script for a message lower in level
#    than info, that still maintains the indentation.
#
msg() { plainmsg "$@"; }
plainmsg() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -A __msg_properties=(
		[role]='plainmsg'
		[message_array]='BAHELITE_INFO_MESSAGES'
		[colour]='PLAIN_MESSAGE_COLOUR'
		[whole_message_in_colour]='no'
		[asterisk]='  '
		[desktop_message]='no'
		[desktop_message_type]=''
		[stay_on_line]='no'
		[output]='stdout'
		[internal]='no'
		[exit_code]=''
	)
	__msg "$@"
	return 0
}
export -f  msg  plainmsg


 # Shows an info, a warning or an error message
#  on console and optionally, on desktop too.
#  $1 — a text message or,
#
#       if MSG_USE_KEYWORDS is set, a key from
#         - INFO_MESSAGES, if called as *info*();
#         - WARNING_MESSAGES,  if called as *warn*();
#         - ERROR_MESSAGES, if called as *err*();
#         - PLAIN_MESSAGES, if called as msg().
#       That key may contain spaces, and the number of spaces between words
#       in the key is not important, i.e.
#         $ warn "no needed file found"
#         $ warn  no needed file found
#       and
#         $ warn  no   needed  file     found
#       will use the same item in the WARNING_MESSAGES array.
#
__msg() {
	#  Internal! There should be no xtrace_off!
	declare -gx  BAHELITE_STIPULATED_ERROR
	local role  message_array  colour  whole_message_in_colour  asterisk  \
	      desktop_message  desktop_message_type  stay_on_line  output  \
	      internal  exit_code  \
	      f  f_count=0  already_printing_call_stack  \
	      message=''  message_key  message_key_exists  \
	      _message=''  message_nocolours  \
	      term_cols=$TERM_COLS  console_or_log

	[[ "$-" =~ .*i.* ]] || term_cols=80

	#  As a precaution against internal bugs, check how many times __msg()
	#  is called in the call stack. If the number will be more than 3,
	#  this hints at a recursive error.
	for f in "${FUNCNAME[@]}"; do
		[ "$f" = "${FUNCNAME[0]}" ] && let '++f_count,  1'
	done
	(( f_count >= 3 )) && {
		echo "Bahelite error: call to ${FUNCNAME[0]} went into recursion." >&2
		[ "$(type -t bahelite_print_call_stack)" = 'function' ]  && {
			#  Print call stack, unless already in the middle of doing it
			for f in "${FUNCNAME[@]}"; do
				[ "$f" = "bahelite_print_call_stack" ]  \
					&& already_printing_call_stack=t
			done
			[ -v already_printing_call_stack ] \
				|| bahelite_print_call_stack
		}
		#  Unsetting the traps, or the recursion may happen again.
		trap '' EXIT TERM INT HUP PIPE   ERR   DEBUG   RETURN
		#  Now the script will exit guaranteely.
		exit 4
	}

	role=${__msg_properties[role]}
	declare -n message_array=${__msg_properties[message_array]}
	[ -v MSG_DISABLE_COLOURS ]  \
		|| declare -n colour=${__msg_properties[colour]}
	[ "${__msg_properties[whole_message_in_colour]}" = 'yes' ] \
		&& whole_message_in_colour=${__msg_properties[whole_message_in_colour]}
	asterisk=${__msg_properties[asterisk]}
	[ "${__msg_properties[desktop_message]}" = 'yes' ]  \
		&& desktop_message=${__msg_properties[desktop_message]}
	desktop_message_type=${__msg_properties[desktop_message_type]}
	[ "${__msg_properties[stay_on_line]}" = 'yes' ]  \
		&& stay_on_line=${__msg_properties[stay_on_line]}
	output=${__msg_properties[output]}
	[ "${__msg_properties[internal]}" = 'yes' ]  \
		&& internal=${__msg_properties[internal]}
	[[ "${__msg_properties[exit_code]}" =~ ^[0-9]{1,3}$ ]]  \
		&& exit_code=${__msg_properties[exit_code]}

	 # Checks, if the stdout/stderr stream is going to be disabled, judging
	#  by the VERBOSITY_LEVEL, but the logging module will redirect the
	#  streams to log.
	#
	is_log_gonna_catch_the_message() {
		local log_verbosity=$(get_bahelite_verbosity 'log')  \
		      console_verbosity=$1  \
		      output=$2
		case "$output" in
			'stdout')
				(( console_verbosity < 2  &&  log_verbosity >= 2 ))  \
					&& return 0  \
					|| return 1
				;;
			'stderr')
				(( console_verbosity < 1  &&  log_verbosity >= 1 ))  \
					&& return 0  \
					|| return 1
				;;
		esac
	}

	 # See also the second part at the end of bahelite.sh.
	#
	case "$(get_bahelite_verbosity  'console')" in
		0)	#  Actually handled in the code piece below __msg.
			#  Here output is specified to expose the internal mechanism.
			#  This also prevents any message being actually echoed anywhere,
			#  so there’s no need to catch it later.
			is_log_gonna_catch_the_message '0' "$output"  \
				|| output='devnull'
			;;

		1)	#  Actually handled in the code piece below __msg.
			#  Here output is specified to expose the internal mechanism.
			#  This also prevents any non-error message being echoed anywhere,
			#  so there’s no need to catch it later.
			[[ "$role" =~ ^(redmsg|err)$  &&  "$output" = 'stderr' ]]  || {
				is_log_gonna_catch_the_message '1' "$output"  \
					|| output='devnull'
			}
			;;

		2)
			[[ "$role" =~ ^(warn|redmsg|err)$  &&  "$output" = 'stderr' ]]  \
				|| output='devnull'
			;;

		3|4|5|6|7|8|9)
			: "All messages allowed."
			;;
		#  See also stream control below.
	esac

	case "$(get_bahelite_verbosity  desktop)" in
		0)
			unset desktop_message
			;;

		1)
			[ -v desktop_message  -a  "$role" = 'err' ]  \
				|| unset desktop_message
			;;

		2)
			[[ -v desktop_message  &&  "$role" =~ ^(err|warn)$ ]]  \
				|| unset desktop_message
			;;

		3|4|5|6|7|8|9)
			: "All messages allowed."
			;;
	esac


	if [ -v MSG_USE_KEYWORDS  -o  -v internal ]; then
		#  What was passed to us is not a message per se,
		#  but a key in the messages array.
		message_key="${1:-}"
		for key in "${!message_array[@]}"; do
			[ "$key" = "$message_key" ] && message_key_exists=t
		done
		if [ -v message_key_exists ]; then
			#  Positional parameters "$2..n" now can be substituted
			#  into the message strings. To make these substitutions go
			#  from the number 1, drop the $1, holding the message key.
			shift
			eval message=\"${message_array[$message_key]}\"
		else
			ierr 'no such msg' "$message_key"
		fi
	else
		# message="${1:-No message?}"
		message="${1:-}"
	fi
	#  Removing blank space before message lines.
	#  This allows strings to be split across lines and at the same time
	#  be well-indented with tabs and/or spaces – indentation will be cut
	#  from the output.
	message=$(sed -r 's/^\s*//; s/\n\t/\n/g' <<<"$message")
	#  Before the message gets coloured, prepare a plain version.
	[ -v MSG_DISABLE_COLOURS ]  \
		&& message_nocolours="$message"  \
		|| message_nocolours="$(strip_colours "$message")"
	#  Removing any colour alternating rules, that may be in effect.
	_message+="${__s}"
	_message+="${colour:-}"
	_message+="$asterisk"
	_message+="${whole_message_in_colour:-${__stop:-}}"  # colour stop
	_message+="$message"
	_message+="${whole_message_in_colour:+${__stop:-}}"  # colour stop
	#  See the description to MSG_FOLD_MESSAGES.
	if [ -v MSG_FOLD_MESSAGES ]; then
		message=$(echo -e ${stay_on_line:+-n} "$_message" \
		              | fold  -w $((term_cols - ${#__mi} -2)) -s \
		              | sed -r "1s/^/${__mi#  }/; 1!s/^/$__mi/g" )
	else
		message=$(echo -e ${stay_on_line:+-n} "$_message" \
		              | sed -r "1s/^/${__mi#  }/; 1!s/^/$__mi/g" )
	fi
	case "$output" in
		stdout)	if (( BASH_SUBSHELL == 0 )); then
					echo ${stay_on_line:+-n} "$message"
				else
					#  If this is the subshell, use the parent shell’s
					#    file descriptors to send messages, because they
					#    shouldn’t be grabbed along with the output.
					#  The parent shell’s FD may be closed, so a check
					#    is needed to confirm, that it’s still writeable.
					[ -w "$STDOUT_ORIG_FD_PATH" ]  \
						&& echo ${stay_on_line:+-n} "$message"   \
						        >$STDOUT_ORIG_FD_PATH
				fi
				;;

		stderr)	if (( BASH_SUBSHELL == 0 )); then
					echo ${stay_on_line:+-n} "$message" >&2
				else
					#  If this is the subshell, use the parent shell’s
					#    file descriptors to send messages, because they
					#    shouldn’t be grabbed along with the output.
					#  The parent shell’s FD may be closed, so a check
					#    is needed to confirm, that it’s still writeable.
					[ -w "$STDERR_ORIG_FD_PATH" ]  \
						&& echo ${stay_on_line:+-n} "$message"   \
						        >$STDERR_ORIG_FD_PATH
				fi
				;;

		devnull)
				:  #  Not sending anything
				;;
	esac
	if	[ -v desktop_message ]  \
		&& [ "$(type -t bahelite_notify_send)" = 'function' ]
	then
		bahelite_notify_send "$message_nocolours" "$desktop_message_type"
	fi
	[ "$role" = err ] && BAHELITE_STIPULATED_ERROR=t
	[[ "$role" =~ ^(err|abort)$ ]]  &&  {
		(( BASH_SUBSHELL > 0 ))  \
			&& touch "$TMPDIR/BAHELITE_STIPULATED_ERROR_IN_SUBSHELL"
		#  If this is an error message, we must also quit
		#  with a certain exit code.
		if	[ -v internal ]; then
			exit $exit_code
		elif  [ -v MSG_USE_KEYWORDS ]  \
		      &&  bahelite_verify_error_code "${ERROR_CODES[$*]}"
		then
			exit ${ERROR_CODES[$*]}
		else
			exit $exit_code
		fi
	}
	return 0
}
export -f  __msg


 # A divider is a message, that is printed highlighted and takes the entire
#  line. It is intended to improve readability for the cases, when the output
#  of the main script is temporarily suspended, and another program prints
#  to console: for this reason the divider message also increases and decreases
#  the message indentation level accordingly.
#
headermsg() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	milinc
	#  Bad idea: to add a spacing “echo”.
	#  It would confuse the one reading the inner output (probably a log)
	#    with a question “Does this space belong to the log? Is this what
	#    causes an error?”
	divider_message "$@"
	return 0
}
export -f headermsg


footermsg() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	divider_message "$@"
	#  No spacing echo for the same reason, as above.
	mildec
	return 0
}
export -f footermsg


 # Print a message, that will span over entire line
#  $1  – text message.
# [$2] – character to use for the divider line. If unspecified, set to “+”.
# [$3] – style to use for the line. If unspecified, uses whatever is set
#        in the $HEADER_MESSAGE_COLOUR variable.
#
divider_message() {
	#  Internal! There should be no xtrace_off!
	local message="$1"  divider_line_character="${2:-+}"  \
	      style="${3:-$HEADER_MESSAGE_COLOUR}"  \
	      i  line_to_print=''  line_to_print_length
	(( MSG_INDENTATION_LEVEL > 0 ))  \
		&& line_to_print+="$__mi"
	line_to_print+="$style"
	for	(( i=0; i<3; i++ )); do
		line_to_print+="$divider_line_character"
	done
	line_to_print+=" $message "
	if [ -v MSG_DISABLE_COLOURS ]; then
		line_to_print_length=${#line_to_print}
	else
		line_to_print_length="$(strip_colours "$line_to_print")"
		line_to_print_length=${#line_to_print_length}
	fi
	for	(( i=0;  i < TERM_COLS - line_to_print_length;  i++ )); do
		line_to_print+="$divider_line_character"
	done
	if (( BASH_SUBSHELL == 0 )); then
		echo -e "$line_to_print${__s}"
	else
		#  If this is the subshell, use the parent shell’s
		#    file descriptors to send messages, because they
		#    shouldn’t be grabbed along with the output.
		#  The parent shell’s FD may be closed, so a check
		#    is needed to confirm, that it’s still writeable.
		[ -w "$STDOUT_ORIG_FD_PATH" ]  \
			&& echo -e "$line_to_print${__s}"  >$STDOUT_ORIG_FD_PATH
	fi
	return 0
}
export -f divider_message



bahelite_xtrace_off
mi_assemble
bahelite_xtrace_on

 # Stream control
#
#  Remembering the original FD paths. They are needed to send info, warn etc.
#  messages from subshells properly.
#
if (( BASH_SUBSHELL == 0 )); then
	declare -gx STDIN_ORIG_FD_PATH="/proc/$$/fd/0"
	declare -gx STDOUT_ORIG_FD_PATH="/proc/$$/fd/1"
	declare -gx STDERR_ORIG_FD_PATH="/proc/$$/fd/2"
else
	[ -v STDIN_ORIG_FD_PATH ]  \
		|| declare -gx STDIN_ORIG_FD_PATH="/proc/$$/fd/0"
	[ -v STDOUT_ORIG_FD_PATH ]  \
		|| declare -gx STDOUT_ORIG_FD_PATH="/proc/$$/fd/1"
	[ -v STDERR_ORIG_FD_PATH ]  \
		|| declare -gx STDERR_ORIG_FD_PATH="/proc/$$/fd/2"
fi
#
#
#  Setting initial verbosity according to VERBOSITY_LEVEL.
#
case "$(get_bahelite_verbosity  'console')" in
	0)	exec {STDOUT_ORIG_FD}>&1;  exec 1>/dev/null
		exec {STDERR_ORIG_FD}>&2;  exec 2>/dev/null
		;;

	1)	exec {STDOUT_ORIG_FD}>&1;  exec 1>/dev/null
		;;

	4|5|6|7|8|9)
		BAHELITE_XTRACE_ALLOWED=t
		;;&

	5|6|7|8|9)
		BAHELITE_MODULES_ARE_VERBOSE=t
		BAHELITE_DONT_CLEAR_TMPDIR=t
		;;
esac

return 0