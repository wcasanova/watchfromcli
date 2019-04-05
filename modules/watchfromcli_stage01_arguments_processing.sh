
process_args() {
	# getopt from util-linux 2.24 is known to allow long options with a single dash
	#   independetly of whether the -a|--alternative option is passed.
	opts=$(getopt \
	             --options \
	                       acCd:eEFhH:IJlL:m:M:nNrRs:S:Tv \
	             --longoptions \
	allow-autosub,\
	basedir:,basepath:,\
	bashrc::,\
	check-for-update::,\
	compat:,\
	dvd-bd-nav,\
	group-indicator:,\
	help,\
	heuristics-level:,\
	ignore-disks,\
	interval:,\
	ionice-opts::,\
	journal-max-size:,\
	jpeg-compression::,\
	last-ep,\
	last-ep-command:,\
	last-ep-format:,\
	last-item-mark:,\
	limit-watching-to:,\
	loop,\
	match-all,\
	match-number,\
	mplayer-command:,\
	mplayer-opts:,\
	my-increment:,\
	my-decrement:,\
	no-color,\
	no-hints,\
	no-journal,\
	not-epnumbers:,\
	remember-sub-and-audio-delay,\
	resume,\
	resume-from-previous,\
	run-in-cycle,\
	screenshot-dir:,\
	screenshot-dir-skel:,\
	subfolders:,\
	taskset-cpulist:,\
	version,\
	             -n 'watch.sh' -- "$@")
	getopt_exit_code=$?
	[ $getopt_exit_code -gt 0 ] && err 'Error parsing options.'
	eval set -- "$opts"

	# while true; do
	while [ $# -ne 0 ]; do
		option="$1" # becasue this way it may be used in err()
		case "$option" in
			-a|'--match-all')
				MATCH_ALL=t
				MATCH_NUMBER=t # implies -n
				shift
				;;
			'--allow-autosub')
				unset NO_AUTOSUB
				shift
				;;
			'--bashrc') # I know I could simply add -i to shebang in order to make
				# the shell interactive and force it to source ~/.bash_profile,
				# but the chain of sourcing this way may be long and redundant.
				[ -z "$2" ] && . "$HOME/.bashrc" && shift || {
					[ -r "$2" ] && . "$2" && shift 2 \
						|| err 'Option --bashrc takes argument that has to be bash source file.'
				}
				;;
			-c|'--run-in-cycle')
				RUN_IN_CYCLE=t
				shift
				;;
			-C|'--no-color')
				NO_COLOR="never"
				shift
				;;
			'--check-for-update')
				[ -z "$2" ] && CHECK_FOR_UPDATE=now && shift || {
					[[ "$2" && "$2" = ^[0-9]{1,7}$ ]] && CHECK_FOR_UPDATE=$2 && shift 2 \
						|| err 'Option --check-for-update takes a number of days between which it should check releases on github as argument.'
				}
				;;
			'--compat')
				[[ "$2" == @(mplayer|mplayer2|mpv-03x|mpv-025x) ]] && COMPAT="$2" && shift 2 \
					|| err 'Option --compat requires argument to be one of ‘mplayer’, ‘mplayer2’, ‘mpv-03x’ or ‘mpv-025x’.'
				;;
			-d|'--basedir'|'--basepath')
				arg="$2"
				[ -d "$arg" ] \
					&& {
					[ "${arg:0-1}" = '/' ] || arg="$arg/"
					[ -v BASEPATH ] \
						&& __number_of_paths=${#BASEPATH[@]} \
						|| __number_of_paths=0
					BASEPATH[$__number_of_paths]="$arg"
				} || err "-d|--basedir: ‘$arg’ is not a readable directory."
				shift 2
				;;
			-e) # heuristics shorthand, cumulative
				[ $((++HEURISTICS_LEVEL)) -gt $MAX_HEURISTICS_LEVEL ] \
					&& HEURISTICS_LEVEL=$MAX_HEURISTICS_LEVEL
				shift
				;;
			'--group-indicator')
				[[ "$2" =~ .{4} ]] && GROUP_INDICATOR="$2" || err "Option ‘group-indicator’ takes four characters."
				shift 2
				;;
			'--heuristics-level')
				[[ "$2" =~ ^[0-9]$ ]] \
					&& [ $2 -le $MAX_HEURISTICS_LEVEL ] \
					&& HEURISTICS_LEVEL=$2 \
					|| err "Option --heuristics-level requires argument to be a number lower or equal to $MAX_HEURISTICS_LEVEL."
				shift 2
				;;
			-E) # W! Experimental code.
				E=t
				shift
				;;
			-F) # Treat KEYWORD as a fixed string (-F for grep).
				# It’s not actually meant to be in use, since it affects code only
				#   in two places – when assigning KEYWORD_FIND_PATTERNS and when
				#   looking for _other files_ matching by KEYWORD. In other cases
				#   job is done by find or grep -G, and -G is unavoidable, so
				#   further development of this key would actually be escaping to
				#   avoid KEYWORD being recognized as a pattern by grep -G.
				# Strings separated by newlines are another caveat.
				FIXED_STRING='F'
				shift
				;;
			-h|'--help')
				show_help
				exit 0
				;;
			-H)
				show_manpage "$2"
				exit 0
				;;
			# -i|'--input-line')
			#     # Take input values from the string supplied after this key
			#     #   instead of asking for manual typing.
			# 	shift 2
			# 	;;
			-I|'--ignore-disks')
				IGNORE_DISKS=t
				shift
				;;
			'--interval')
				[[ "$2" =~ ^[0-9]{1,7}$ ]] && INTERVAL="$2" || err "Option ‘interval’ requires a number of seconds to wait as an argument."
				shift 2
				;;
			'--ionice-opts')
				[ -z "$2" ] && IONICE_OPTS='-c best-effort -n0' && shift || {
					IONICE_OPTS="$2" && shift 2
				}
				;;
			-J|'--no-journal')
				NO_JOURNAL=t
				shift
				;;
			'--journal-max-size')
				[[ "$2" =~ ^[0-9]{1,7}[KMG]?$ ]] && JOURNAL_MAX_SIZE="$2" && shift 2 \
					|| err 'Option --journal-max-size requires argument to be a number of bytes that
	  may be followed by one of these suffixes: K M G to represent *2^10 once,\n  twice or three times.'
				;;
			'--jpeg-compression')
				[ -z "$2" ] && JPEG_COMPRESSION=92 && shift || {
					[[ "$2" =~ ^[0-9]{1,3}$ ]] && [ $2 -ge 0 ] && [ $2 -le 100 ] \
						&& JPEG_COMPRESSION=$2 && shift 2 \
						|| err 'Option --jpeg-compression takes argument that has to be a number between 0 and 100.'
				}
				;;
			-L|'--limit-watching-to')
				[[ "$2" =~ ^[0-9]{1,4}$ ]] && LIMIT_WATCHING_TO=$2 && shift 2 \
					|| err 'Option -L|--limit-watching-to requires argument to be a number of episodes.'
				;;
			-l|'--loop')
				LOOP=t
				shift
				;;
			'--last-ep')
				which figlet &>/dev/null \
					&& LAST_EP_NUMBER_PRINTING_COMMAND='figlet -t -f banner -c' \
					|| {
					warn 'I can’t use figlet? Is it and the font installed?
	  I will use ‘cat’ to print the last shown episode number.'
					LAST_EP_NUMBER_PRINTING_COMMAND='cat'
				}
				LAST_EP_NUMBER_PRINTING_FORMAT='%n'
				LAST_EP_NUMBER_SHOW_AFTER='both'
				shift
				;;
			'--last-ep-command')
				[ "$2" ] && LAST_EP_NUMBER_PRINTING_COMMAND="$2" && shift 2 \
					|| err "Option ‘$option’ requires an argument."
				;;
			'--last-ep-format')
				[ "$2" ] && LAST_EP_NUMBER_PRINTING_FORMAT="$2" && shift 2 \
					|| err "Option ‘$option’ requires an argument."
				;;
			'--last-ep-show-after')
				[[ "$2" == @(player|screenshots|both) ]] \
					&& LAST_EP_NUMBER_SHOW_AFTER="$2" && shift 2 || err 'Option --last-ep-show-after requires argument to be one of\n  - player;\n  - screenshots;\n  - both.'
				;;
			'--last-item-mark')
				[ "$2" ] && LAST_ITEM_MARK="$2" & shift 2 \
					|| err "Option ‘$option’ requires an argument."
				;;
			-M|'--mplayer-command')
				[ "$2" ] && MPLAYER_COMMAND="$2" && shift 2 || err "Option ‘$option’ requires an argument."
				;;
			-m|'--mplayer-opts')
				[ "$2" ] && MPLAYER_OPTS+=" $2" && shift 2 || err "Option ‘$option’ requires an argument."
				;;
			'--my-increment')
				[ "$2" ] && MY_INCREMENT="$2" && shift 2 || err "Option ‘$option’ requires an argument."
				;;
			'--my-decrement')
				[ "$2" ] && MY_DECREMENT="$2" && shift 2 || err "Option ‘$option’ requires an argument."
				;;
			-n|'--match-number')
				MATCH_NUMBER=t
				shift
				;;
			-N|'--dvd-bd-nav')
				DVD_BD_NAV=t
				shift
				;;
			'--no-hints') # hide hints
				NO_HINTS=t
				shift
				;;
			'--not-episodes')
				test='only letters here'
				[ "$2" ] && [ "${test%%$2}" ] \
					&& NOT_EPNUMBERS+=("$2") \
					&& shift 2 \
					|| err "Option ‘$option’ requires an argument."
				;;
			'--remember-sub-and-audio-delay')
				REMEMBER_SUB_AND_AUDIO_DELAY=t
				shift
				;;
			-R|'--resume-from-previous')
				RESUME_FROM_PREVIOUS=t
				;&
			-r|'--resume')
				# We still don’t know what MODE we’re resuming,
				#  so some variables may be unset in import_session_data
				RESUME=t
				IT_IS_NEXT_ITERATION=t  # Would ‘THIS_IS…’ be better?
				RUN_IN_CYCLE=t
				shift
				;;
			-s|'--subfolders')
				[ "$2" ] && {
					EXPECTED_SUBFOLDERS="$2"
					shift 2
				} || err "Option ‘$option’ requires an argument."
				;;
			-S|'--screenshot-dir')
				[ "$2" ] && {
					SCREENSHOT_DIR="$2"
					# We may need it to start the search, if the user has moved
					# the directory, but journal keeps the old directory
					# in a record.
					SCREENSHOT_DIR_FROM_CMDLINE="$2"
					# User has probably moved the directory.
					[ -d "$SCREENSHOT_DIR" ] || err "‘$SCREENSHOT_DIR’ passed to --screenshot-dir cannot be found. Did you move it?"
					shift 2
				} || err "Option ‘$option’ requires an argument."
				;;
			'--screenshot-dir-skel')
				[ "$2" ] && SCREENSHOT_DIR_SKEL="$2" && shift 2 || err "Option ‘$option’ requires an argument."
				;;
			'--taskset-cpulist')
				[[ "$2" =~ ^[0-9,-]{1,20}$ ]] && TASKSET_CPULIST="$2" && shift 2 || err 'Option -t|--taskset-cpulist requires argument to be a valid CPU list.\n See `man taskset` for the details.'
				;;
			-T) # Enable output for testing purposes.
				# [ -v T ] is a visual mark for them.
				T=t
				shift
				;;
			-v|'--version')
				show_version
				exit 0
				;;
			--)
				shift
				break
				;;
			*)
				KEYWORD="$1"
				shift
				;;
		esac
	done

	# This assignment must be here because -M itself is optional.
	which "${MPLAYER_COMMAND:=mpv}" &>/dev/null || {
		alias | grep -q "^alias $MPLAYER_COMMAND='.*'$" \
			&& alias=`alias -p | sed -nr "s/^alias $MPLAYER_COMMAND='(.*)'$/\1/"` \
			|| err "No such binary or alias found: ‘$MPLAYER_COMMAND’."
	}

	# Trying to be intellectual.
	# Versions of mpv vary, but calling mpv --version
	#   would be an unforgivable latency.
	[ ! -v COMPAT ] && {
		# Becasue we don’t let our guessing override an explicitly passed
		#   compatibility mode
		[ $MPLAYER_COMMAND = mplayer ] && COMPAT=mplayer
		[ $MPLAYER_COMMAND = mplayer2 ] && COMPAT=mplayer2
		[ -v alias ] && {
			grep -q "\bmplayer2\b" <<<"$alias" && COMPAT=mplayer2
			grep -q "\bmplayer\b" <<<"$alias" && COMPAT=mplayer
		}
		[ -v COMPAT ] && info "I’ve guessed COMPAT mode for $COMPAT."
	}

	# This is the default – for the latest mpv.
	dashes='--'
	declare -A mp_opts=(
		[bd-protocol]='bd'
		[sub-file]='sub-files'
		[audio-file]='audio-files'
		[sub-delay]='sub-delay'
		[audio-delay]='audio-delay'
	)

	case "${COMPAT:-}" in
		# The players are in the order of development, mpv-03x preceded mpv-026.
		mplayer) # the original MPlayer
			dashes='-'
			mp_opts[bd-protocol]='br'
			mp_opts[sub-file]='sub'
			mp_opts[audio-file]='audiofile'
			;;
		mplayer2) # mplayer2
			mp_opts[bd-protocol]='br'
			mp_opts[sub-file]='sub'
			mp_opts[audio-file]='audiofile'
			;;
		mpv-03x)
			mp_opts[sub-file]='sub'
			mp_opts[audio-file]='audiofile'
			;;
		mpv-025x)
			mp_opts[sub-file]='sub-file'
			mp_opts[audio-file]='audio-file'
			;;
		*);;
	esac

	# KEYWORD="$*"
	[ -v RESUME ] || {
		[ "$KEYWORD" ] || err 'No keyword given.'
		[ "${KEYWORD/@(*[^.]|)\**/}" ] || {
			warn "I’ve found that you used * in the pattern for keyword, and the patterns should
	  use ‘.*’ style, not just ‘*’."
			read -p 'Are you sure you want to continue? [N/y] > '
			[[ "$REPLY" =~ ^[yY]$ ]] || abort 'Cancelled.'
		}
	}

	alias grep="grep --color=${NO_COLOR:-auto}"
	[ -v NO_COLOR ] && unset g r s

	[ -v NO_JOURNAL ] || {
		# sed won’t work if there won’t be at least one line
		[ -e $JOURNAL ] || echo > $JOURNAL
	}

	GI_BEGIN=${GROUP_INDICATOR:0:1}
	GI_MIDDLE=${GROUP_INDICATOR:1:1}
	GI_END=${GROUP_INDICATOR:2:1}
	GI_SINGLE=${GROUP_INDICATOR:3:1}

	# Must be right before the first function
	[ -v D ] && grep -vFe "$vars" <<<"`set -o posix; set`" \
		| grep -v "^vars=" >"$DEBUG_DIR/vars"

	return 0
}


# EXPECTS:
#     SCREENSHOT_DIR – be unset, set by -S|--screenshot-dir or by evaling
#         journal entry.
#     KEYWORD – set, non-empty string
# ALTERS:
#     SCREENSHOT_DIR – path where pushd to, so the player  will store taken
#         screenshots there.
# EXIT_CODES:
#     0 if ok,
#    ‘scrdir_isnt_writeable’, ‘cant_create_scrdir’ in case
#     of insufficient rights to access $SCREENSHOT_DIR.
set_screenshot_subdir() {
	local screens_path folder valid
	# Set to true if the user employs --screenshot-dir (he may not need it).
	[ -v SCREENSHOT_DIR ] && {
		# With grep we check, that the endpoint directory answers
		#   our need to find something with $KEYWORD in its name.
		# With [ -d … ] we check, that the directory from the journal
		#   still does exist – user might move his screenshots,
		#   but the journal will not know about that.
		grep -qi${FIXED_STRING:-G} "$KEYWORD" <<<"${SCREENSHOT_DIR##*\/}" \
			&& [ -d "$SCREENSHOT_DIR" ] \
			&& valid=t
		[ -v valid ] || {
			# If user has moved screenshot_dir, then we default to the new
			# screenshot dir and try to find something there.
			# It is certain, that if the code goes here, that the user
			# has already fixed the path in the command line and we have
			# the new path in $SCREENSHOT_DIR_FROM_CMDLINE.
			# If there’s only one directory, we could silently
			# change the path in the journal transparently to the user!
			[ -d "$SCREENSHOT_DIR" ] || SCREENSHOT_DIR="$SCREENSHOT_DIR_FROM_CMDLINE"
			screens_path=$(find -L "$SCREENSHOT_DIR" -maxdepth 1 -type d \
			                    $KEYWORD_FIND_PATTERNS \
			                    -printf "%f\n" \
			                    2>/dev/null)
			if [ "$screens_path" ]; then
				[ `echo "$screens_path" | wc -l` -gt 1 ] && {
					echo "Which directory to store screenshots in?"
					choose_from "$screens_path" &&
					SCREENSHOT_DIR+="/$CHOSEN_ITEM" ||
					unset SCREENSHOT_DIR
				}|| SCREENSHOT_DIR+="/$screens_path"
			else
				warn 'No appropriate directory for screenshots found.'
				echo -en "Type a long, correct name to create one or press $g<Enter>$s to skip > "
				read
				[ "$REPLY" ] && {
					SCREENSHOT_DIR+="/$REPLY"
					[ -d "$SCREENSHOT_DIR" ] && {
						[ -w "$SCREENSHOT_DIR" ] && [ -x "$SCREENSHOT_DIR" ] \
							|| err "No sufficient rights to write to ‘$SCREENSHOT_DIR’."
					}||{
						## There was an idea to make all the folders at once.
						## This had two major drawbacks:
						##   1) if SCREENSHOT_DIR_SKEL is empty, eval failed on the
						##      closing } of {macro,misc}, which led in its turn
						##      to wrong directories made by mkdir, and the result
						##      depended on the bash version: 4.2.53(1) creates
						##      directories with spaces in them properly and puts
						##      folder named '}' in it, while 4.3.30(1) makes two
						##      directories not honoring space and puts '}' into the
						##      latter;
						##   2) eval required more escaping than just ' ' → '\ '.
						## eval is necessary for {} expansion in SCREENSHOT_DIR_SKEL
						# eval mkdir -pm775 "\"${SCREENSHOT_DIR// /\ }/${SCREENSHOT_DIR_SKEL:+{${SCREENSHOT_DIR_SKEL// /\ }}}\"" || err "Couldn’t create directory ‘$SCREENSHOT_DIR’."
						for folder in '' ${SCREENSHOT_DIR_SKEL//,/ }; do
							mkdir -m775 "$SCREENSHOT_DIR/$folder" || err "Couldn’t create directory ‘$SCREENSHOT_DIR’."
						done
					}
				}|| unset SCREENSHOT_DIR
			fi
		}
	}
	if [ -d "$SCREENSHOT_DIR" ]; then
		pushd "$SCREENSHOT_DIR" >/dev/null
	else
		# We don’t want the dot to go in the journal,
		#   the original directory should go there.
		SCREENSHOT_DIR_ORIG="$SCREENSHOT_DIR"
		SCREENSHOT_DIR='.'
		info 'Current directory is about to hold screenshots.'
	fi
	screendir_timestamp=`date +%s`
	return 0
}


return 0