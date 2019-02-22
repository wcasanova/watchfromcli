# Should be sourced.

#  bahelite_logging.sh
#  Organises logging and maintains logs in a separate folder.
#  © deterenkelt 2018–2019

# Require bahelite.sh to be sourced first.
[ -v BAHELITE_VERSION ] || {
	echo 'Must be sourced from bahelite.sh.' >&2
	return 5
}
. "$BAHELITE_DIR/bahelite_messages.sh" || return 5
. "$BAHELITE_DIR/bahelite_directories.sh" || return 5

# Avoid sourcing twice
[ -v BAHELITE_MODULE_LOGGING_VER ] && return 0
#  Declaring presence of this module for other modules.
BAHELITE_MODULE_LOGGING_VER='1.5.1'
BAHELITE_INTERNALLY_REQUIRED_UTILS+=(
	date  #  to add date to $LOG file name and to the log itself.
	pkill  #  to find and kill the logging tee nicely, so it wouldn’t hang.
)
if [ -v BAHELITE_LOG_MAX_COUNT ]; then
	[[ "$BAHELITE_LOG_MAX_COUNT" =~ ^[0-9]{1,4}$ ]] \
		|| err "BAHELITE_LOG_MAX_COUNT should be a number,
		        but it is currently set to “$BAHELITE_LOG_MAX_COUNT”."
else
	BAHELITE_LOG_MAX_COUNT=5
fi

# BAHELITE_LOGFD_PATH="$TMPDIR/bahelite_logfd"


 # Call this function to start logging.
#  To keep logs under $CACHEDIR, run prepare_cachedir() before calling this
#  function, or logs will be written under $MYDIR.
#
start_log() {
	xtrace_off && trap xtrace_on RETURN
	declare -g BAHELITE_LOGGING_STARTED
	local arg
	if [ -v LOGDIR ]; then
		bahelite_check_directory "$LOGDIR"  'Logging'
	else
		LOGDIR="${CACHEDIR:-$MYDIR}/logs"
		[ -d "$LOGDIR"  -a  -w "$LOGDIR" ] || {
			mkdir "$LOGDIR" &>/dev/null || {
				warn "Cannot create “$LOGDIR”. Will write to “$TMPDIR/logs”."
				LOGDIR="$TMPDIR/logs"
				mkdir "$LOGDIR"
			}
		}
	fi
	LOG="$LOGDIR/${MYNAME%.*}_$(date +%Y-%m-%d_%H:%M:%S).log"
	#  Removing old logs, keeping maximum of $LOG_KEEP_COUNT of recent logs.
	pushd "$LOGDIR" >/dev/null
	#  Deleting leftover variable dump.
	rm -f variables
	noglob_off
	( ls -r "${MYNAME%.*}_"* 2>/dev/null || : ) \
		| tail -n+$BAHELITE_LOG_MAX_COUNT \
		| xargs rm -v &>/dev/null || :
	noglob_on
	popd >/dev/null
	echo "${__mi}Log started at $(LC_TIME=C date)." >"$LOG"
	echo "${__mi}Command line: $CMDLINE" >>"$LOG"
	for ((i=0; i<${#ARGS[@]}; i++)) do
		echo "${__mi}ARGS[$i] = ${ARGS[i]}" >>"$LOG"
	done
	#  When we will be exiting (even successfully), we will need to send
	#  SIGPIPE to that tee, so it would quit nicely, without terminating
	#  and triggering an error. It will, however, quit with a code >0,
	#  so we catch it here with “||:”.
	exec &> >(tee -i -a "$LOG" ||:)

	#  An attempt to avoid sending tee signals at exit, and just use
	#  a separate file descriptor for a copy of stdin and stdout.

	#  № 1
	# exec 2>&1 1>>&"$LOG"

	#  № 2
	# exec {BAHELITE_LOGFD}<>"$BAHELITE_LOGFD_PATH"
	# exec &>{BAHELITE_LOGFD}
	# ( tee -a "$LOG" <{BAHELITE_LOGFD} ) &

	#  № 3
	# exec {BAHELITE_LOGFD}<>"$LOG"
	# exec 1>&{BAHELITE_LOGFD} 2>&1
	# exec 1>&"$LOG" 2>&"$LOG"

	#  № 4
	# exec {BAHELITE_LOGFD}<>"$BAHELITE_LOGFD_PATH"
	# exec &>{BAHELITE_LOGFD}
	# exec {BAHELITE_LOGFD}> >(tee -ia "$LOG" ||:)

	BAHELITE_LOGGING_STARTED=t
	return 0
}


show_path_to_log() {
	xtrace_off && trap xtrace_on RETURN
	if [ -v BAHELITE_MODULE_MESSAGES_VER ]; then
		info "Log is written to
		      $LOG"
	else
		cat <<-EOF
		Log is written to
		$LOG
		EOF
	fi
	return 0
}


 # Returns absolute path to the last modified log in $LOGDIR.
#  [$1] – log name prefix, if not set, equal to $MYNAME
#         without .sh at the end (caller script’s own log).
#
set_last_log_path() {
	xtrace_off && trap xtrace_on RETURN
	declare -g LAST_LOG_PATH
	local logname="${1:-}" last_log
	[ "$logname" ] || logname=${MYNAME%.*}
	pushd "$LOGDIR" >/dev/null
	noglob_off
	last_log=$(ls -tr ${logname}_*.log | tail -n1)
	noglob_on
	[ -f "$last_log" ] || return 1
	popd >/dev/null
	LAST_LOG_PATH="$LOGDIR/$last_log"
	return 0
}


 # Reads the contents of the log file by path set in LAST_LOG_PATH
#    into LAST_LOG_TEXT.
#  Also checks, if the last log has an error message, and if it does, then
#    copies the portion from where the error message starts in LAST_LOG_TEXT
#    up to the end of file, and sets this text as the value for LAST_LOG_ERROR
#    variable. The indicator of an error message is whatever is specified in
#    BAHELITE_ERR_MESSAGE_COLOUR varaible (should be set to $__r from the
#    bahelite_colours.sh). As all error handling functions in bahelite (that
#    is err, abort, errw and ierr) are final commands resulting in the call
#    to the “exit” builtin, there can be only one error message in the log.
#
read_last_log() {
	xtrace_off && trap xtrace_on RETURN
	# declare -g LAST_LOG_ERROR
	local err_msg_marker  err_msg_text
	set_last_log_path "$@" || return $?
	declare -g LAST_LOG_TEXT
	#  Stripping control characters, primarily to delete colours codes.
	LAST_LOG_TEXT=$(
		sed -r 's/[[:cntrl:]]\[[0-9]{1,3}[mKG]//g' "$LAST_LOG_PATH"
	)

	 # Setting LAST_LOG_ERROR is disabled, for it’s easier to just
	#  heave-ho the entire log into another log, than to parse its errors.
	#
	#  However, the following two methods can be consiedered:
	#  1. Finding “--- Call stack”
	#     Conditions:
	#       - the error must be caught by bahelite (some are still not).
	#       - catching one line before “--- Call stack” sometimes is very
	#         useful in understanding the real error.
	#     How to grab:
	#         log_call_stack=$(
	#             grep -B 1 -A 99999 '\-\-\- Call stack ' "$LAST_LOG_PATH"
	#         )
	#  2. Finding the first entrance of the red colour, or whatever sequence
	#     is put into BAHELITE_ERR_MESSAGE_COLOUR.
	#     Conditions:
	#       - the error must be caught.
	#       - catching it is equally necessary as the error with call stack,
	#         because error messages with red colour are expected and there-
	#         fore, do not print the call stack. And vice versa unexpected
	#         errors do not use an error message, they just print the trace.
	#         So there are at least two types, and both of them are important.
	#     How to grab:
	#       Replace shell’s own alias for the escape sequence (\e)
	#       with its real hex code (\x1b), so that it could be used
	#       in the pattern for sed.
	#         err_msg_marker="${BAHELITE_ERR_MESSAGE_COLOUR//\\e/\\x1b}"
	#         err_msg_marker="${err_msg_marker//\[/\\\[}"
	#         sed -rn "/$err_msg_marker/,$ p" "$LAST_LOG_PATH"
	#       or simply
	#         log_err_message=$(
	#             sed -rn "/\x1b\[31m/,$ p" "$LAST_LOG_PATH"
	#         )
	#  3. Finding uncaught errors. There is no way to tell for sure,
	#       if a line in the log would, so, unless all of the error could be
	#       caught, it is more reasonable to perform all these checks from
	#       a script above the one, whose LOG is parsed, i.e. the script call-
	#       ing the mother script. The script above should receive a non-zero
	#       exit code from the inner script, and this provides the reason
	#       to do every possible check for an error, including this one.
	#     Indeed, this check should be the last one among the three.
	#     How to grab:
	#         log_last_line=$(
	#             tac "$LAST_LOG_PATH" | grep -vE '^\s*$' | head -n1  \
	#                 | sed -r "s/.*/$__mi&/" >&2
	#         )

	return 0
}


return 0