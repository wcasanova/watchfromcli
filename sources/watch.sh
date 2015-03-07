#! /usr/bin/env bash

# watch.sh
# A shell wrapper for mpv/MPlayer to run videos easy via CLI.
# watch.sh © 2013–2015 deterenkelt.

# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 3 of the License,
# or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but without any warranty; without even the implied warranty
# of merchantability or fitness for a particular purpose.
# See the GNU General Public License for more details.


# Requires
# GNU sed >= 4.2.1 (started developing with it).
# GNU grep >= 2.9 (started developing with it).
# GNU bash >= 4.2 (strongly).
# file >= 5.17 (output format of that utility has been changing,
#        watch.sh conforms with 5.17 since v20140807).
# util-linux >= 2.20 (for getopt that is required, and taskset
#        which may be of use, but is optional).
# wget, xdg-open and your browser — to check for updates, and if there are,
#        suggest to open the current RELEASE_NOTES in the repository on github.
# mpv, mplayer2 or mplayer. Syntax was optimized
#        for the first and the latter.
#
# Works better with
# GNU parallel — to compress screenshots faster using all cores available
#       (or those available after restricting to those specified
#        to the -t or --taskset option).
# figlet — to draw last seen episode number with big ASCII art numbers.
# pngcrush — helps to reduce PNG image size, if you prefer it over JPEG.
#       (players tend to save PNG in an unoptimized format, which makes
#        screenshots very large. pngcrush recompresses them without quality
#        loss).
# pngtopam and cjpeg — are only needed for converting screenshots from PNG
#       (if you, for some reason use MPlayer, that can only save them to PNG)
#        to JPEG by the usage of --jpeg-compression. pngtopam is usually found
#        in the netpbm package and cjpeg in libjpeg-turbo.
# inotifywait, ps and pkill — for SUB_DELAY, is of use only with mpv.
#        The first belongs to intotify-tools and the latter—to procps package.


# extglob for the sake of it, expand_aliases to make aliases available for
#   MPLAYER_COMMAND
shopt -s extglob expand_aliases
# Disable pathname expansion. Asterisk in expressions with find may lead
#   to unforseen consequences.
set -f

show_help() {
cat <<"EOF"
Simpliest form:
    watch.sh [optional arguments] -d basepath  keyword

To start watching cycle:
    watch.sh [optional arguments] -c -d basepath  keyword

To resume watching cycle:
    watch.sh [optional arguments] -[r|R]  [keyword]

List recently entered keywords (useful for -r)
    watch.sh -j

Check for updates
    watch.sh -u

For the complete list of options see man watch.sh or call this script like
  watch.sh -H 'pattern'
  in order to open the man page on the first occurrence of the pattern.
EOF
}

# TAKES:
#     $1 — a pattern or a keyword to search on.
show_manpage() {
	[ "$1" ] && man -P"less -p '$1'" watch.sh || man watch.sh
}

apply_mimetype_fix() {
	local magicfile_version=`sed -rn '3s/.*\s([0-9]+)$/\1/p' \
	                        ~/.magic  2>/dev/null`
	[[ "$magicfile_version" =~ ^[0-9]+$ ]] \
		&& [ $VERSION -le $magicfile_version ] \
		|| {
		cp ~/.magic ~/.magic.`date +%Y%m%d`.backup
		cat <<EOF >~/.magic
# Magic local data for file(1) command.
# Insert here your local magic data. Format is described in magic(5).
# This file was created by watch.sh $VERSION
#------------------------------------------------------------------------------
4 byte 0x47
>5 beshort 0x4000
>>7 byte ^0xF
>>>196 byte 0x47
>>>>388 byte 0x47
>>>>>580 byte 0x47 M2TS MPEG transport stream, v2
!:mime video/MP2T
#------------------------------------------------------------------------------
# matroska:  file(1) magic for Matroska files
# See http://www.matroska.org/
#
# EBML id:
0       belong      0x1a45dfa3
# DocType id:
>5      beshort     0x4282
# DocType contents:
>>0x8       string      matroska    Matroska data
!:mime video/x-matroska
#------------------------------------------------------------------------------
# EBML id:
0       belong      0x1a45dfa3
# EMBL Version:
>5      beshort     0x4286      Version 1
# DocType id:
>0x15       beshort     0x4282
# DocType contents:
>>0x18      string      matroska    Matroska data
!:mime video/x-matroska
EOF
	}
}

show_version() {
cat <<EOF
watch.sh $VERSION
Copyright © 2013–2015 deterenkelt.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
EOF
}

# Respect the environment.
[ -v d ] || d='\e[39m'    # default fg
[ -v r ] || r='\e[31m'    # red
[ -v g ] || g='\e[32m'    # green
[ -v y ] || y='\e[33m'    # yellow
[ -v s ] || s='\e[0m'    # stop
[ -v b ] || b='\e[1m'    # bright/bold
[ -v rb ] || rb='\e[21m'    # reset bold/bright
[ -v u ] || u='\e[4m'    # underlined

# I’ve read changelog to v4.3 and can say that the single useful option, i.e.
#     local -r
#   does not work in my build, so if some day there will be changes to bash
#   version requirement, they won’t appear at least before v4.4 releases.
[ ${BASH_VERSINFO[0]:-0} -eq 4 ] &&
[ ${BASH_VERSINFO[1]:-0} -le 1 ] ||
[ ${BASH_VERSINFO[0]:-0} -le 3 ] && {
	echo -e "$r*$s Bash v4.2 or higher required." >&2
	return 3 2>/dev/null || exit 3
}

[ "$BASH_SOURCE" != "$0" ] && {
	echo -e "$r*$s This script shouldn’t be sourced. See usage (-h)." >&2
	return 4
}

# TAKES:
#     $1 — a string that has a message and exit code assigned to it.
# RETURNS: exit code corresponding to the messsage.
err() {
	# Don’t rely on these codes — they tend to shift each time a new one is added.
	# They are assembled here just for the ease of reparsing and future
	#   localization (if it will be done eventually).
	local code msg
	case $1 in
		no_getopt)
			code=5; msg='No getopt utility (that usually comes with util-linux package) was found.';;
		old_utillinux)
			code=6; msg='This script requires getopt from util-linux 2.20 or higher.';;
		homedir)
			code=7; msg='Couldn’t create directory ~/.watch.sh.';;
		debugdir)
			code=8; msg='Couldn’t create directory “$DEBUG_DIR”.';;
		getopt*)
			code=9; msg='getopt returned an error while parsing the command line. It was probably\n  caused by ';;&
		getopt_funcerr)
			msg+='the getopt() function error. If it’s not a common error, then see\n  man 3 getopt.';;
		getopt_wrongparam)
			msg+='the parameters getopt wasn’t been able to parse correctly.';;
		getopt_internal)
			msg+='an internal error. Is there enough memory available?';;
		getopt_dumbme)
			msg+='the reason you should probably know by yourself.';;
		opt_bashrc)
			code=10; msg='Option --bashrc takes argument that has to be bash source file.';;
		opt_chk4upd)
			code=11; msg='Option --check-for-update takes a number of days between which it should check releases on github as argument.';;
		opt_compat)
			code=12; msg='Option --compat requires argument to be one of “mplayer”, “mplayer2” or “mpv-03x”.';;
		opt_basedir)
			code=13; msg="-d|--basedir: “$arg” is not a readable directory.";;
		opt_heulevel)
			code=14; msg="Option --heuristics-level requires argument to be a number lower or equal to $MAX_HEURISTICS_LEVEL.";;
		opt_inputinvalid)
			code=15; msg='RESERVED';;
		opt_journalsize)
			code=17; msg='Option --journal-max-size requires argument to be a number of bytes that
  may be followed by one of these suffixes: K M G to represent *2^10 once,\n  twice or three times.';;
		opt_jpegcompression)
			code=18; msg='Option --jpeg-compression takes argument that has to be a number between 0 and 100.';;
		opt_lepshowafter)
			code=19; msg='Option --last-ep-show-after requires argument to be one of\n  - player;\n  - screenshots;\n  - both.';;
		opt_limitwatching)
			code=20; msg='Option -L|--limit-watching-to requires argument to be a number of episodes.';;
		opt_taskset)
			code=21; msg='Option -t|--taskset-cpulist requires argument to be a valid CPU list.\n See `man taskset` for the details.';;
		doushiyou)
			code=22; msg='Doushiyou~?';;
		bad_latestver)
			code=23; msg='Couldn’t determine the latest version available.
  If it’s not an internet connection problem, report a bug.';;
		mpcmd_not_found)
			code=24; msg="No such binary or alias found: “$MPLAYER_COMMAND”.";;
		no_keyword)
			code=25; msg='No keyword given.';;
		no_matches)
			code=26; msg='No matches!';;
		empty_folder)
			# FIRST_MATCH shall be set at the time of possibility of this error,
			#   so BASEPATH shouldn’t be an array already.
			code=27; msg="I couldn’t find any video files in
  $BASEPATH${FIRST_MATCH:-}${SUBFOLDERS:+$SUBFOLDERS\nConsider checking your --subfolders pattern.}";;
		chosen_one_is_unreadable)
			code=28; msg="“$FIRST_MATCH” is not readable!";;
		user_declined_input)
			code=29;;
		heu2_nan)
			code=30; msg="Error on heuristics 2nd level: “${matches_as_numbers[j]}” and “${matches_as_numbers[k]}” must be numbers.";;
		scrdir_isnt_writeable)
			code=31; msg="No sufficient rights to write to “$SCREENSHOT_DIR”.";;
		cant_create_scrdir)
			code=32; msg="Couldn’t create directory “$SCREENSHOT_DIR”.";;
		no_such_keyword_in_journal)
			code=33; msg='No such keyword.';;
		not_enough_data_to_restore)
			code=34; msg="Not enough data to restore.
Couldn’t retrieve $not_found_vars from the journal.
This might be caused by a broken file, truncated entry at the end of the journal (though such entries shouldn’t exist) or a new update that changed the mechanism of file searching and thus, the list of required variables.";;
		cant_retrieve_journal_size)
			code=35; msg='Couldn’t retrieve journal size.';;
		cant_compute_journal_maxsize)
			code=36; msg='Couldn’t compute journal maximum size.';;
		cant_truncate_journal)
			code=37; msg='Couldn’t truncate journal.';;
		aborted_by_user)
			code=38; msg='Aborted by user.';;
		opt_requires_an_arg)
			code=39; msg="Option “$option” requires an argument.";;
		opt_interval)
			code=40; msg="Option “interval” requires a number of seconds to wait as an argument.";;
		opt_gind)
			code=41; msg="Option “group-indicator” takes four characters.";;
		heu2_queue_is_2big4ahuman)
			code=42; msg="Debug output of the queue will be too big for a human to read.\n  Please reduce the number of files to 26 at least.";;
		*)
			code=107; msg='Unknown error.';;
	esac
    [ -v msg ] && echo -e "${D:+\n$di}$r*$s $msg${D:+\n$di}" | tee -a ${dbg_file:-/dev/null} >&2
    echo $code
}

msg() { echo -e "${D:+\n$di}$g$b*$s $1${D:+\n}" | tee -a ${dbg_file:-/dev/null}; }

warn() { echo -e "${D:+\n$di}$y*$s $1${D:+\n}" | tee -a ${dbg_file:-/dev/null} >&2; }

dmsg() {
	local var
	for var in "$@"; do
		[ "$var" = '' -o "$var" = $'\n' ] \
			&& echo >>$dbg_file \
			|| echo -e "$di$var" >>$dbg_file
	done
}

dil=0 # debug indentation level
di='' # debug indentation

# TAKES:
#    [$1] — number of times to increment dil.
dil_inc() {
	local z count=$1
	count=${count:-1}
	for ((z=0; z<count; z++)); do let dil++; done
	di=; for ((z=0; z<dil; z++)); do di+=$'\t'; done
}

# TAKES:
#    [$1] — number of times to decrement dil.
dil_dec() {
	local z count=$1
	count=${count:-1}
	for ((z=0; z<count; z++)); do let dil--; done
	di=; for ((z=0; z<dil; z++)); do di+=$'\t'; done
}

# TAKES:
#    $@ — a set of arguments which can be variable names for declare to print
#         to the logfile or empty/newline strings to put there an empty line.
#         '' is simply shorter to type than $'\n'.
dput_declare() {
	local var
	for var in "$@"; do
		[ "$var" = '' -o "$var" = $'\n' ] \
			&& echo >>$dbg_file \
			|| { echo -n "$di" >>$dbg_file && declare -p $var >>$dbg_file; }
	done
}

which getopt &>/dev/null || exit `err no_getopt`

# Checking util-linux version
read -d $"\n" major minor < <(getopt -V | sed -rn 's/^[^0-9]+([0-9]+)\.?([0-9]+)?.*/\1\n\2/p')
[[ "$major" =~ ^[0-9]+$ ]] && [[ "$minor" =~ ^[0-9]+$ ]] \
	&& [ $major -ge 2 ] && ( [ $major -gt 2 ] || \
	                         [ $major -eq 2 -a $minor -ge 20 ] ) || exit `err old_utillinux`

# Variables typed in caps are either
# - bash built-ins;
# - those ones that set parameters from the options passed through the command line;
# - used between functions;
# - or are important for maintaining the watching cycle between runs.

# 2nd level is 97% done, but I haven’t time to finish it while I was at it,
#   so the rest of the tests will require to dig up in all that again.
# MAX_HEURISTICS_LEVEL=2
MAX_HEURISTICS_LEVEL=1
HEURISTICS_LEVEL=0

JOURNAL=~/.watch.sh/journal
JOURNAL_MAX_SIZE="64K" # w/o suffix for bytes, K for KiB, M for MiB et al.
JOURNAL_MINVER='20150227'
[ -d ~/.watch.sh ] || {
	mkdir -m755 ~/.watch.sh/ >/dev/null \
		|| exit `err homedir`
}

VERSION="20150307"
CHECK_FOR_UPDATE=21 # each N days
updater_timestamp=~/.watch.sh/updater_timestamp
[ -f $updater_timestamp ] || touch $updater_timestamp

GROUP_INDICATOR='┌│└⋅' # upper part/middle part/lower part/single

# If any of these patterns is met in a filename, which episode number
#   can’t be guessed, then it and all numbers met further can’t be
#   taken as a presumed episode number.
# Patterns are to be given to bash with enabled extglob. To be precise,
#   they’ll be used in an expression like this:
#   "${var%${NOT_EPNUMBERS[i]}*}"
NOT_EPNUMBERS=("240p" "360p" "480p" "720p" "1280??(?)?(?)720" "1080p" "1920??(?)?(?)1080" "@(h|H|h.|H.|x)264" "10?bit")

# DEBUG MODE
# No function aggregator for debug messages because test [ -v D ]
#   is faster than function call (there would be lots of them).
# Also [ -v D ] is more visually distinguishable. descartes.jpg
[ -v D ] && {
	DEBUG_DIR="$HOME/.watch.sh/debug"
	[ -d "$DEBUG_DIR" ] && rm -rf "$DEBUG_DIR"
	mkdir -m755 "$DEBUG_DIR" >/dev/null || exit `err debugdir`
	for i in "$0" "$@"; do echo "\"$i\"" >>"$DEBUG_DIR/cmdline"; done
	vars="`set -o posix; set`"
}

# getopt from util-linux 2.24 is known to allow long options with a single dash
#   independetly of whether the -a|--alternative option is passed.
opts=`getopt \
             --options \
                       acCd:eEFhH:IJlL:m:M:nNrRs:S:uTv \
             --longoptions \
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
taskset-opts:,\
version,\
             -n 'watch.sh' -- "$@"`
getopt_exit_code=$?
[ $getopt_exit_code -gt 0 ] && {
	case $getopt_exit_code in
		1) exit `err getopt_funcerr`;;
		2) exit `err getopt_wrongparam`;;
		3) exit `err getopt_internal`;;
		4) exit `err getopt_dumbme`;;
	esac
}
eval set -- "$opts"

while true; do
	option="$1" # becasue this way it may be used in err()
	case "$option" in
		-a|'--match-all')
			MATCH_ALL=t
			MATCH_NUMBER=t # implies -n
			shift
			;;
		'--bashrc') # I know I could simply add -i to shebang in order to make
			# the shell interactive and force it to source ~/.bash_profile,
			# but the chain of sourcing this way may be long and redundant.
			[ -z "$2" ] && . "$HOME/.bashrc" && shift || {
				[ -r "$2" ] && . "$2" && shift 2 || exit `err opt_bashrc`
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
					|| exit `err opt_chk4upd`
			}
			;;
		'--compat')
			[[ "$2" == @(mplayer|mplayer2|mpv-03x) ]] && COMPAT="$2" && shift 2 \
				|| exit `err opt_compat`
			;;
		-d|'--basedir'|'--basepath')
			arg="$2"
			[ -d "$arg" ] \
				&& {
				[ "${arg:0-1}" = '/' ] || arg="$arg/"
				BASEPATH[${#BASEPATH[@]}]="$arg"
			}|| exit `err opt_basedir`
			shift 2
			;;
		-e) # heuristics shorthand, cumulative
			[ $((++HEURISTICS_LEVEL)) -gt $MAX_HEURISTICS_LEVEL ] \
				&& HEURISTICS_LEVEL=$MAX_HEURISTICS_LEVEL
			shift
			;;
		'--group-indicator')
			[[ "$2" =~ .{4} ]] && GROUP_INDICATOR="$2" || exit `opt_gind`
			shift 2
			;;
		'--heuristics-level')
			[[ "$2" =~ ^[0-9]$ ]] \
				&& [ $2 -le $MAX_HEURISTICS_LEVEL ] \
				&& HEURISTICS_LEVEL=$2 \
				|| exit `err opt_heulevel`
			shift 2
			;;
		-E) # W! Experimental code.
			E=t
			shift
			;;
		-F) # Treat KEYWORD as a fixed string (-F for grep).
			# It’s not actually meant to be in use, since it affects code only
			#   in two places — when assigning KEYWORD_FIND_PATTERNS and when
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
		# 	err opt_inputinvalid
		# 	shift 2
		# 	;;
		-I|'--ignore-disks')
			IGNORE_DISKS=t
			shift
			;;
		'--interval')
			[[ "$2" =~ ^[0-9]{1,7}$ ]] && INTERVAL="$2" || exit `err opt_interval`
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
				|| exit `err opt_journalsize`
			;;
		'--jpeg-compression')
			[ -z "$2" ] && JPEG_COMPRESSION=92 && shift || {
				[[ "$2" =~ ^[0-9]{1,3}$ ]] && [ $2 -ge 0 ] && [ $2 -le 100 ] \
					&& JPEG_COMPRESSION=$2 && shift 2 \
					|| exit `err opt_jpegcompression`
			}
			;;
		-L|'--limit-watching-to')
			[[ "$2" =~ ^[0-9]{1,4}$ ]] && LIMIT_WATCHING_TO=$2 && shift 2 \
				|| exit `opt_limitwatching`
			;;
		-l|'--loop')
			LOOP=t
			shift
			;;
		'--last-ep')
			which figlet &>/dev/null \
				&& LAST_EP_NUMBER_PRINTING_COMMAND='figlet -t -f clb6x10 -c' \
				|| {
				warn 'figlet is not installed.
  I will use “cat” to print the last shown episode number.'
				LAST_EP_NUMBER_PRINTING_COMMAND='cat'
			}
			LAST_EP_NUMBER_PRINTING_FORMAT='%n'
			LAST_EP_NUMBER_SHOW_AFTER='both'
			shift
			;;
		'--last-ep-command')
			[ "$2" ] && LAST_EP_NUMBER_PRINTING_COMMAND="$2" && shift 2 \
				|| exit `err opt_requires_an_arg`
			;;
		'--last-ep-format')
			[ "$2" ] && LAST_EP_NUMBER_PRINTING_FORMAT="$2" && shift 2 \
				|| exit `err opt_requires_an_arg`
			;;
		'--last-ep-show-after')
			[[ "$2" == @(player|screenshots|both) ]] \
				&& LAST_EP_NUMBER_SHOW_AFTER="$2" && shift 2 || exit `err opt_lepshowafter`
			;;
		'--last-item-mark')
			[ "$2" ] && LAST_ITEM_MARK="$2" & shift 2 \
				|| exit `err opt_requires_an_arg`
			;;
		-M|'--mplayer-command')
			[ "$2" ] && MPLAYER_COMMAND="$2" && shift 2 || exit `err opt_requires_an_arg`
			;;
		-m|'--mplayer-opts')
			[ "$2" ] && MPLAYER_OPTS+=" $2" && shift 2 || exit `err opt_requires_an_arg`
			;;
		'--my-increment')
			[ "$2" ] && MY_INCREMENT="$2" && shift 2 || exit `err opt_requires_an_arg`
			;;
		'--my-decrement')
			[ "$2" ] && MY_DECREMENT="$2" && shift 2 || exit `err opt_requires_an_arg`
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
				&& NOT_EPNUMBERS[${#NOT_EPNUMBERS[@]}]="$2" && shift 2 \
				|| exit `err opt_requires_an_arg`
			;;
		'--remember-sub-and-audio-delay')
			REMEMBER_SUB_AND_AUDIO_DELAY=t
			shift
			;;
		-R|'--resume-from-previous')
			RESUME_FROM_PREVIOUS=t
			;&
		-r|'--resume')
			RESUME=t
			IT_IS_NEXT_ITERATION=t  # Would “THIS_IS…” be better?
			RUN_IN_CYCLE=t
			shift
			;;
		-s|'--subfolders')
			[ "$2" ] && EXPECTED_SUBFOLDERS="$2" && shift 2 || exit `err opt_requires_an_arg`
			;;
		-S|'--screenshot-dir')
			[ "$2" ] && SCREENSHOT_DIR="$2" && shift 2 || exit `err opt_requires_an_arg`
			;;
		'--screenshot-dir-skel')
			[ "$2" ] && SCREENSHOT_DIR_SKEL="$2" && shift 2 || exit `err opt_requires_an_arg`
			;;
		'--taskset-opts')
			[[ "$2" =~ ^[0-9,-]{1,20}$ ]] && TASKSET_OPTS="$2" && shift 2 || exit `err opt_taskset`
			;;
		-T) # Enable output for testing purposes.
			# [ -v T ] is a visual mark for them.
			T=t
			shift
			;;
		-u)
			CHECK_FOR_UPDATE=now
			EXIT_AFTER_CHECK=t
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
			exit `err doushiyou`
			;;
	esac
done

[ $CHECK_FOR_UPDATE != 0 ] && {
	[[ $CHECK_FOR_UPDATE =~ ^[0-9]+$ ]] && {
		[ $(( (`date +%s`-`stat -L --format %Y $updater_timestamp`)/60/60/24 )) -gt $CHECK_FOR_UPDATE ] \
			&& CHECK_FOR_UPDATE=now || {
			grep -q 'New version is available!' $updater_timestamp \
				&& msg 'New version is available'
		}
	}
}
[ $CHECK_FOR_UPDATE = now ] && {
	which wget &>/dev/null && {
		# latest_ver=`wget -O- http://github.com/deterenkelt/watchsh/releases \
		#                 |& sed -nr '/<h1\s+class="release-title">/ {
		#                                 :be N; s|.*</h1>.*|&|; t
		#                                     s/.*v([0-9]{8}).*/\1/p; t qu
		#                                     b be
		#                                 :qu Q
		#                             }'`
		latest_ver=`wget -O- https://github.com/deterenkelt/watchsh/releases/latest \
		                |& sed -nr 's_^.*/deterenkelt/watchsh/tree/v([0-9]+)".*$_\1_p;T;Q'`
		[[ "$latest_ver" =~ ^[0-9]{8}$ ]] || exit `err bad_latestver`
		touch $updater_timestamp
		[ $latest_ver -gt $VERSION ] && {
			msg 'New version is available!'
			echo 'New version is available!' >$updater_timestamp
			while true; do
				read -p 'Would you like to view the RELEASE_NOTES in the repo? [Y/n]> '
				[[ "$REPLY" =~ ^[Nn]$ ]] && break || {
					[[ "$REPLY" =~ ^[Yy]$ ]] && {
						which xdg-open &>/dev/null ||{
							warn 'I’d like to open new RELEASE_NOTES from github, but it seems that you haven’t
  xdg-open installed.'
							break
						}
						xdg-open http://github.com/deterenkelt/watchsh/blob/master/sources/RELEASE_NOTES
						break
					}|| warn 'Deep breath, a pill and the right key.'
				}
			done
		}|| msg 'This version is the latest available.'
	}|| warn 'To check for updates I’d like to have wget.'
	[ -v EXIT_AFTER_CHECK ] && exit
}

# This assignment must be here because -M itself is optional.
which "${MPLAYER_COMMAND:=mpv}" &>/dev/null || {
	alias | grep -q "^alias $MPLAYER_COMMAND='.*'$" \
		&& alias=`alias -p | sed -nr "s/^alias $MPLAYER_COMMAND='(.*)'$/\1/"` \
		|| exit `err mpcmd_not_found`
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
	[ -v COMPAT ] && msg "I’ve guessed COMPAT mode for $COMPAT."
}

# This is the default — for the latest mpv.
dashes='--'
declare -A mp_opts=(
	[bd-protocol]='bd'
	[sub-file]='sub-file'
	[audio-file]='audio-file'
	[sub-delay]='sub-delay'
	[audio-delay]='audio-delay'
)

case "$COMPAT" in
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
esac

KEYWORD="$*"
[ -v RESUME ] || {
	[ "$KEYWORD" ] || exit `err no_keyword`
	[ "${KEYWORD/@(*[^.]|)\**/}" ] || {
		warn "I’ve found that you used * in the pattern for keyword, and the patterns should
  use “.*” style, not just “*”."
		read -p 'Are you sure you want to continue? [N/y] > '
		[[ "$REPLY" =~ ^[yY]$ ]] || exit `err aborted_by_user`
	}
	# Now script has the journal and resume may rely on its data.
	EXPECTED_SUBFOLDERS="${EXPECTED_SUBFOLDERS//%keyword/$KEYWORD}"
	# Pattern split for find
	[ -v FIXED_STRING ] && {
		# Perform escaping of | . * in the pattern for grep -G?
		KEYWORD_FIND_PATTERNS="-iname \"*$KEYWORD*\""
	}||{
		KEYWORD_FIND_PATTERNS=`
			sed -r 's/([^\])"/\1\\"/g                       # Escape unescaped "
			        s/([^\])\.\*/\1*/g                     # .* → * ; \.* → \.*
			        s/^/\\\\( -iname "*/; s/$/*" \\\\)/   # ^… …$ → \( -iname "*… …*" \)
			        s/([^\])\|/\1*" -o -iname "*/g       # | → *" -o -iname "* ; \| → \|
			       ' <<<"$KEYWORD"`
		KEYWORD_FIND_PATTERNS=`eval echo "$KEYWORD_FIND_PATTERNS"`
	}
}

apply_mimetype_fix

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

# And then goes heuristics

# EXPECTS:
#     KEYWORD — set, non-empty string
#     BASEPATH — set, non-empty string or an array
#     IGNORE_DISKS
#     EXPECTED_SUBFOLDERS
# SETS:
#     FIRST_MATCH — file or folder which reside directly in BASEPATH and which
#          name does match KEYWORD
#     MODE — 'single' means that script will play a single file. I’m not sure
#                 whether this mode should exist as a mode, but that at least
#                 helps to divide cases that need heuristics from those
#                 which do not.
#            'episodes' this way depends on IGNORE_DISKS variable, but in common
#                 that means at the end of the collected path there are
#                 videofiles, probably episodes. If IGNORE_DISKS is set, then
#                 any disk structure ignored and all files of your choice will
#                 be available to play _independently_ of the fact do they have
#                 KEYWORD in their names or not. If IGNORE_DISKS is not set,
#                 watch.sh will continue searching files matching KEYWORD
#                 at the end of the path.
#            'dvd'|'bd' give a directive to player to treat the stuff at the end
#                 of the path as a disk.
# EXIT CODES:
#     0 if ok;
#     “no_matches” in case no matches were found;
#     “empty_folder” if found a folder but nothing to play in it;
#     “chosen_one_is_unreadable” if couldn’t read file or folder.
do_initial_search() {
	[ -v D ] && dbg_file="$DEBUG_DIR/initial_search"
	unset MODE FIRST_MATCH SUBFOLDERS
	list_videofiles  search_by_keyword  ${BASEPATH[1]:+preserve_basepath} || return $?
	[ ${#BASEPATH[@]} -eq 1 ] \
		&& local dirs=`find -L "$BASEPATH" -maxdepth 1 -type d $KEYWORD_FIND_PATTERNS -printf "%f\n"` \
		|| local dirs=`find -L "${BASEPATH[@]}" -maxdepth 1 -type d $KEYWORD_FIND_PATTERNS -printf "%H: %f\n"`
	unset newline #  DELETE ME?

	[ "$dirs" ] && [ "$VIDEOFILES" ] && newline="\n"
	local matches="`echo -e "$dirs${newline:-}$VIDEOFILES"`"

	[ "$matches" ] && {
		# Primary basepath takes priority, so remove entries duplicated
		#   in other paths.
		local primary_basepath=`escape_for_sed_pattern "${BASEPATH[0]}"`
		[ ${#BASEPATH[@]} -gt 1 ] && for ((i=1; i<${#BASEPATH[@]}; i++)); do
			local slave_basepath=`escape_for_sed_pattern "${BASEPATH[i]}"`
			matches=`echo -e "$matches" | sed -rn "G; s/\n/&&/;
			         /^$slave_basepath: ([[:print:]]*\n).*\n$primary_basepath: \1/d;
			         s/\n//; h; P"`
		done
		# Okay, duplicates removed, now check if the list still contains
		#   matches sharing the same path
		for ((i=0; i<${#BASEPATH[@]}; i++)); do
			[ `grep -cF "${BASEPATH[i]}:" <<<"$matches"` \
				-eq `wc -l <<<"$matches"` ] && {
				BASEPATH[0]="${BASEPATH[i]}"
				# unset unnecessary basepaths for them to not appear
				#   in the “V:” list in choose_from()
				local old_bp_count=${#BASEPATH[@]}
				for ((j=1; j<$old_bp_count; j++)); do unset BASEPATH[j]; done
				break 2
			}
		done
		# If it’s clear that the BASEPATH is only one, there’s no need
		#   to confuse the user with unnecessary ones.
		# FIRST_MATCH that will be chosen from $matches, will never
		#   contain BASEPATH anyway.
		[ ${#BASEPATH[@]} -eq 1 ] && {
			local escaped_basepath=`escape_for_sed_pattern "${BASEPATH[0]}"`
			matches="`sed "s/^$escaped_basepath: //" <<<"$matches"`"
		}

		# Yeah, you might have noticed that the checks above cheated
		#   on the case with single match, that could be noticed yet after
		#   that sed expression with “primary” and “slave” basepath,
		#   but that has almost blown my mind so I decided to simplify it
		#   and do in one cut. Still works fine, huh?
		# We have at least 1 candidate but there can be more…
		if  [ `wc -l <<<"$matches"` -gt 1 ];  then
			choose_from "$matches" || return $?
			FIRST_MATCH="$CHOSEN_ITEM"
			# Now there can be the case that there were matches with different
			#   path, and the BASEPATH chosen by user is yet to be defined.
			# export -f escape_for_sed
			[ ${#BASEPATH[@]} -gt 1 ] && for ((i=0; i<${#BASEPATH[@]}; i++)); do
				# No local directive here!
				m=$(sed -rn "s/^`escape_for_sed_pattern "${BASEPATH[i]}"`: //p;T;Q1" <<<"$FIRST_MATCH") || {
					FIRST_MATCH="$m"
					BASEPATH[0]="${BASEPATH[i]}"
					break
				}
			done
			# export -nf escape_for_sed

		else  FIRST_MATCH="$matches";  fi
		local temp=${BASEPATH[0]}
		unset BASEPATH
		BASEPATH="$temp"
	}|| return `err no_matches`

	if  [ -r "$BASEPATH$FIRST_MATCH" ];  then
		if  [ -d "$BASEPATH$FIRST_MATCH" ];  then
			MODE='episodes'
			# Yep, it’s a directory. Trying to search subfolders.
			[ -v IGNORE_DISKS ] && EXPECTED_SUBFOLDERS+=" VIDEO_TS BDMV "
			unset same_path # important!
			check_for_subfolders || return $?
			[ "`find "$BASEPATH/$FIRST_MATCH${SUBFOLDERS:-}" -type d -name "VIDEO_TS"`" ] \
				&& { [ -v IGNORE_DISKS ] && INTERVAL=0 || MODE='dvd'; }
			[ "`find "$BASEPATH/$FIRST_MATCH${SUBFOLDERS:-}" -type d -name "BDMV"`" ] \
				&& { [ -v IGNORE_DISKS ] && INTERVAL=0 ||  MODE='bd'; }
# FIXME: Here must be check for the count of VIDEOFILES found at the end of
#        the path (with SUBFOLDERS). If count==1, change mode to single and
#        correct paths for “single” case appropriately. If there are
#        videofiles and they look like episodes, i.e. containing numbers
#        like 01, 02…
			[ $MODE != dvd -a $MODE != bd ] && {
				list_videofiles || return $?
				if  [ "$VIDEOFILES" ];  then
					[ "`echo "$VIDEOFILES" | wc -l`" -eq 1 ] && {
						MODE=single
						VIDEOFILE="$VIDEOFILES"
					}
				else  return `err empty_folder`;  fi
			}
		else
			VIDEOFILE="$FIRST_MATCH"
			unset FIRST_MATCH
			MODE='single'
		fi
	else  return `err chosen_one_is_unreadable`;  fi
	return 0
}

# EXPECTS:
#     KEYWORD ($1 requirement) — set, non-empty string
#     BASEPATH — set, non-empty string or an array
#     FIRST_MATCH — may be unset, if BASEPATH is an array
#     SUBFOLDERS — may be unset, if BASEPATH is an array
# TAKES:
#     $1 — whether or no search by the KEYWORD. This depends on the time this
#          function called, if the first time needed the keyword to define
#          FIRST_MATCH, for example, then the second time assumes anything lying
#          there is wanted by default.
#     $2 — whether to preserve BASEPATH. This is an important thing at an early
#          stage when called first time from do_initial_search() and BASEPATH
#          is an array.
# P.S. Be afraid—this function gave me very strange bugs not accepting second
#      parameter and pointing to the last line of the first subshell.
list_videofiles() {
	local result
	[ "$1" = search_by_keyword ] && local searchkeyword="$KEYWORD_FIND_PATTERNS"
	[ "$2" = preserve_basepath ] && local preserve_basepath=t
	# Single files residing directly in BASEPATH
	VIDEOFILES=`find -L "${BASEPATH[@]}${FIRST_MATCH:-}${SUBFOLDERS:-}" \
	                    -maxdepth 1 -type f ${searchkeyword:-} \
	                    -exec file -iL {} \; 2>/dev/null`
	result=$?;
	[ -v D ] && declare -p VIDEOFILES >>$dbg_file
	# exec known to fail when it’s not important.That’s probably
	#   due to invalid symbolic links in the folder with videofiles.
	# [ $result -gt 0 ] && return $result
	if [ -v preserve_basepath ]; then
		# colon (“:”) may be in a file name
		VIDEOFILES=`sed -rn 's|^(.*/)([^/]+)\:\svideo/.*|\1: \2|p' \
		            <<<"$VIDEOFILES"`
		result=$?; [ $result -gt 0 ] && return $result
	else
		VIDEOFILES=`sed -rn 's|^.*/([^/]+)\:\svideo/.*|\1|p' \
		            <<<"$VIDEOFILES"`
		result=$?; [ $result -gt 0 ] && return $result
	fi
	return 0
}

# EXPECTS:
#     BASEPATH — set, non-empty string
#     FIRST_MATCH — an existent and readable directory
#     EXPECTED_SUBFOLDERS — be a simple plaintext list of words,
#         except %keyword.
# SETS:
#     SUBFOLDERS — path between FIRST_MATCH and actual filename to play.
# RETURNS:
#     0 if ok;
#    >0 if error occured in internal function calls.
check_for_subfolders() {
	FUNCNEST=12 # to avoid possible bug with a loop in symlinked dirs.
	[ "$BASEPATH$FIRST_MATCH${SUBFOLDERS:-}" = "${same_path:-}" ] && {
		# IGNORE_DISKS is set and it is a bluray disk, but files for the
		#   list of episodes usually reside in BDMV/STREAM, unlike DVD do,
		#   where they’re directly in VIDEO_TS folder.
		[ "$SUBFOLDERS" -a -z "${SUBFOLDERS##*/BDMV/}" ] && SUBFOLDERS+='STREAM/'
		return 0
	}
	# Not local! Recursive call may fail!
	same_path="$BASEPATH$FIRST_MATCH${SUBFOLDERS:-}"
	for word in ${EXPECTED_SUBFOLDERS:-}; do
		internal_dirs=`find -L "$BASEPATH$FIRST_MATCH${SUBFOLDERS:-}" -mindepth 1 -maxdepth 1 -type d -iname "*${word}*" -printf "%f\n"`
		[ "$internal_dirs" ] && {
			[ `echo -e "$internal_dirs" | wc -l` -gt 1 ] && {
				choose_from "$internal_dirs" || return $?
				SUBFOLDERS+="/$CHOSEN_ITEM/"
			}|| SUBFOLDERS+="/$internal_dirs/"
		}
	done
	check_for_subfolders || return $?
}

# EXPECTS:
#     USE_1ST (in the future)
#     NO_COLOR
# TAKES:
#     $1 — list of strings
# SETS:
#     CHOSEN_ITEM — set to the line from the $1 which number is $CHOSEN_NUMBER
#     CHOSEN_NUMBER — number of the $CHOSEN_ITEM in the list. Will become
#         the VIDEO_NUMBER.
# RETURNS:
#     0 if line(s) was(were) successfully picked,
#    >0 some utility failed or the result of internal function call.
# EXIT CODES:
#    “user_declined” in case of
#    - <Return> was hit (choice was declined);
#    - wrong number entered;
#    - not a number entered (prevented).
choose_from() {
	LIST_TO_CHOOSE_FROM=`sort <<<"$1"`
	LIST_ITEMS_COUNT=`echo -e "$LIST_TO_CHOOSE_FROM" | wc -l`
	local cols=`tput cols`
	unset CHOSEN_NUMBER list_variants_available ROTATE_PATTERN_LIST group_patterns INDEX_AT_THE_TOP
	until [ -v CHOSEN_NUMBER ]; do
		# Showing current paths:
		# V: here is shown where the script looks for videofiles at this moment
		[ -v NO_HINTS ] || echo ' ↙ I currently look for videofiles here.'
		for ((i=0; i<${#BASEPATH[@]}; i++)); do
			local path_to_video="${BASEPATH[i]}${FIRST_MATCH:-}${SUBFOLDERS:-}"
			local max_width=$(($cols-4))
			[ ${#path_to_video} -gt $max_width ] && path_to_video="…${path_to_video:0-$max_width:$max_width}"
			echo -e "${w}V: $path_to_video$s"
		done
		# C: current working directory (CWD), the directory in which the shell
		#    operates.
		[ -v NO_HINTS ] || echo ' ↙ The directory screenshots will go to.'
		local cwd="$PWD"
		[ ${#cwd} -gt $max_width ] && cwd="…${cwd:0-$max_width:$max_width}"
		echo -e "C: $cwd"  | grep -iG "\($KEYWORD\|$\)"
		# S: screenshot directory as provided via -S option (see above),
		#    it shows only in case this call of “choose_from” came from
		#    “screenshots_preprocessing”, so the user could see the actual
		#    folder where screenshots will be saved to. This is important
		#    because of two things
		#    - portable hard drive;
		#    - very bad directory guessing, because it’s done by only matching
		#      the given keyword, e.g. I’m going to watch “Daria”, and type just
		#      “dar” as a keyword, because it’s enough to find it in the current
		#      BASEPATH on my netbook, but I’m going to save screenshots on
		#      my portable hard drive where in SCREENSHOT_DIR a folder named
		#      “darker_then_black” is already present, so script will choose it
		#      without asking, because of keyword matched the part of
		#      folder name. In most cases keyword would match correctly, so
		#      asking about “are you glad with the folder I’ve chosen for you?”
		#      would be annoying, so we just highlight the keyword, so the user
		#      can abort script executing and run it again with a more proper
		#      keyword.
		[ ${FUNCNAME[1]} = screenshots_preprocessing ] && {
			local safe_screenshot_dir="$SCREENSHOT_DIR"
			[ ${#safe_screenshot_dir} -gt $max_width ] && ="…${safe_screenshot_dir:0-$max_width:$max_width}"
			[ -v NO_HINTS ] || echo ' ↙ Screenshot directory as it was passed.'
			echo "S: $safe_screenshot_dir"
		}
		[ -v NO_HINTS ] || echo ' ↙ Pick a number from the list.'
		[ ${FUNCNAME[1]} = watch ] && {
			[ $HEURISTICS_LEVEL -ne 0 ] && {
				[ -v D ] && dbg_file="$DEBUG_DIR/choose_from_[watch]"
				[ -v group_patterns ] || create_groups_for_the_list || return $? # L1 HEU
				arrange_groups || return $?                                      # L1 HEU
				build_the_list || return $?                                      # L1/L2 HEU
			}|| local use_simple_list=t
		}|| local use_simple_list=t
		[ -v use_simple_list ] && echo -e "$LIST_TO_CHOOSE_FROM" | grep -niG "\($KEYWORD\|$\)"

		unset another_view prompt_heuristics
		[ ${FUNCNAME[1]} = watch -a "$MODE" = episodes ] && {
			[ $HEURISTICS_LEVEL -eq 1 -a -v list_variants_available ] && {
				local another_view="View: $b[${INDEX_AT_THE_TOP:=1}/${#group_patterns[@]}]$s, $g<Tab>$s to rearrange. "
			}
			case $HEURISTICS_LEVEL in
				0) local heu_lvl_as_txt="${r}Off";;
				1) local heu_lvl_as_txt="${g}On";;
				2) local heu_lvl_as_txt="${g}On$rb$y+$b";;
			esac
			local prompt_heuristics="Heuristics: $b[$heu_lvl_as_txt$d]$s, ${g}<h>${s} to switch. "
		}
		[ ${FUNCNAME[1]} = watch -a ! -v NO_HINTS ] && {
			local num_choosing_hint="[$MY_DECREMENT↓0-9↑$MY_INCREMENT] "
			echo ' ↙ Commands to rebuild the list in other way, if possible.'
		}
		local prompt_1st_line="${another_view:-}${prompt_heuristics:-}${g}<?>${s} hints."
		[ ${FUNCNAME[1]} = screenshots_preprocessing ] \
			&& local prompt_2nd_line="Pick line $g<number>$s or press $g<Enter>$s to skip ${num_choosing_hint:-}> " \
			|| local prompt_2nd_line="Pick line $g<number>$s and press $g<Enter>$s to confirm ${num_choosing_hint:-}> "
		local prompt="${prompt_1st_line:+$prompt_1st_line\n}${prompt_2nd_line}"
		echo -en "$prompt"

		# local is poinless for the second one, because big cycle and <TAB>.
		unset input input_is_ready
		# Use C-v <key> to print its escape sequence. P.S. Octals work, too!
		local up=$'\e[A' down=$'\e[B' backspace=$'\177' F1=$'\e[11~' # F1 requires another read to catch 4th char, wat do? ;_;
		until [ -v input_is_ready ]; do
			[ ${#input} -gt 30 ] && input=${input:0:30}
			read -sn1 -p "$input"
			[ "$REPLY" = $'\e' ] && read -sn2 rest && REPLY+="$rest"
			[ "$REPLY" ] && {
				# Commands that must be only available in the watch function.
				[ ${FUNCNAME[1]} = watch ] && {
					case "$REPLY" in
						$'\t')
							[ -v list_variants_available ] && ROTATE_PATTERN_LIST=t \
								&& echo && continue 2
							;;
						'h')
							let HEURISTICS_LEVEL++
							[ $HEURISTICS_LEVEL -gt $MAX_HEURISTICS_LEVEL ] \
								&& HEURISTICS_LEVEL=0
							INDEX_AT_THE_TOP=1
							echo && continue 2
							;;
						'-'|'>'|',')
							[[ "$input" =~ ^[-0-9,\>]+$ ]] && input+="$REPLY";;
					esac
				}

				# Commands that are related to number selection in any list.
				case "$REPLY" in
					"$backspace")
						[ ${#input} -gt 0 ] && input=${input::-1}
						;;
					"$up"|"$MY_INCREMENT")
						[ "$input" ] || input=0
						[[ "$input" =~ ^[0-9]+$ ]] \
							&& [ $input -lt $LIST_ITEMS_COUNT ] \
							&& let input++ || {
							[ $input -gt $LIST_ITEMS_COUNT ] \
								&& input=$LIST_ITEMS_COUNT
						}
						;;
					"$down"|"$MY_DECREMENT")
						[ "$input" ] || input=1
						[[ "$input" =~ ^[0-9]+$ ]] \
							&& [ $input -gt 1 ] && {
							[ $input -gt $LIST_ITEMS_COUNT ] \
								&& input=$LIST_ITEMS_COUNT \
								|| let input--
						}
						;;
					'?')
						[ -v NO_HINTS ] && unset NO_HINTS || NO_HINTS=t
						echo -en '\n\n' && continue 2
						;;
					[0-9])
						input+="$REPLY"
						;;
					esac
				echo -en "\r\e[K$prompt_2nd_line" # \K lear line
			}||{
				echo
				[[ "$input" =~ ^[0-9]+$ || ! "$input" ]] && {
					input_is_ready=t
				}||{
					MANUAL_REARRANGEMENT="$input"
					continue 2
				}
			}
		done

		unset CHOSEN_ITEM # may be left from some previous call
		[ "$input" ] && {
			[[ "$input" =~ ^[0-9]+$ ]] && {
				[ $input -le $LIST_ITEMS_COUNT ] && [ $input -gt 0 ] \
					&& CHOSEN_ITEM=`echo -e "$LIST_TO_CHOOSE_FROM" | sed -n "$input p"` \
					|| warn "Number must be a correct line number, from 1 to $LIST_ITEMS_COUNT." # copypaste, C-v etc.
			}|| warn "“$input” must be a number."
		}
		[ -v CHOSEN_ITEM ] && CHOSEN_NUMBER="$input" || return `err user_declined_input`
	done
return 0
}

# A “group” is nothing more, but its index.
# Data of each record are contained in group_* arrays elements having
#   corresponding index. No variable should be named with prefix “group_”
#   unless it is supposed to contain the actual group data of some sort
#  (certain functions operating on groups use this prefix for automatization,
#   because it would be a pain to rewrite all these keys every now and then if
#   something changes).

# TAKES:
#     $1 — pattern
#     $2 — matches
#     $3 — matches_count
group_create() {
	group_patterns[${#group_patterns[@]}]=$1
	group_matches[${#group_patterns[@]}-1]=$2
	group_matches_count[${#group_patterns[@]}-1]=$3

	# group_occupied_numbers[] is to be filled later on, when we’ll know
	#   which episodes will be left to each group.
}

# TAKES:
#     $1 — source group index
#     $2 — destination group index
group_copy() {
	local group
	for group in ${!group_@}; do
		local group1=$group[$1]
		local group2=$group[$2]
		eval $group2=\""${!group1}"\"
	done
}

# TAKES:
#     $1 — index to delete from group_* arrays.
group_delete() {
	local group
	for group in ${!group_@}; do unset $group[$1]; done
}

# TAKES:
#     $1 — index of the group A
#     $2 — index of the group B
group_swap() {
	local buffer_index=${#group_patterns[@]}
	group_copy $1 $buffer_index
	group_copy $2 $1
	group_copy $buffer_index $2
	group_delete $buffer_index
}

# This function’s purpose is to create patterns that file names in the current
#   path match against, so arrange_groups() could build (and rebuild)
#   the file list in accordance with the conception that we must line up
#   the list in the correct order of episodes.
create_groups_for_the_list() {
	[ -v D ] && {
		dbg_file="$DEBUG_DIR/patterns"
		echo "$LIST_TO_CHOOSE_FROM" >"$DEBUG_DIR/patterns_ltcf"
	}

	# Level 1 heuristics.
	# If some filenames conform with a certain pattern, then numbers in them
	#   must show sequence presence. Each such pattern will be called a group.
	#   Several patterns may comprise same elements, thus allowing to signifi-
	#   cantly change the order by simply rearranging those groups.
	# Filename which don’t belong to any sequence forms a group from itself.
	unset group_patterns group_matches group_matches_count
	while IFS= read -r filename; do
		[ -v D ] && echo "FN: “$filename”." >>$dbg_file
		# Match current filename against known patterns
		[ -v group_patterns ] && {
			for pattern in "${group_patterns[@]}"; do
				# if pattern does match, drop that filename
				echo "$filename" | sed 's/'"$pattern"'/&/;T;Q1' >/dev/null || {
					[ -v D ] && echo -e "\tMatches against pattern: “$pattern”.\nDROP.\n" >>$dbg_file
					continue 2
				}
			done
		}
		# Splitting the string "$filename" by “numbers” and “not numbers”
		readarray -t < <(echo "$filename" | sed -r 's/([0-9]+)/\n\1\n/g')
		[ -v D ] && {
			echo -e "\tFilename is unique and is about to start a new sequence.
\tFilename is to be broken into ${#MAPFILE[@]} pieces:" >>$dbg_file
			declare -p MAPFILE | sed -r 's/\[[0-9]+]="[^"]+"/\t&\n/g' >>$dbg_file
		}
		combine_left_and_right_parts() {
			unset left_part right_part
			for ((j=0; j<${#MAPFILE[@]}; j++)); do
				if [ $j -ne $i ]; then
					[ -v right_part ] \
						&& right_part="${right_part}${MAPFILE[j]}" \
						|| left_part="${left_part:-}${MAPFILE[j]}"
				else
					right_part=
				fi
			done
			parts_combined=t
		}

		unset inc_patterns_found_a_sequence_for_this_file
		for ((i=0; i<${#MAPFILE[@]}; i++)); do
			unset parts_combined
			[ -v D ] && {
				# Mark the current piece with ^^^^
				combine_left_and_right_parts
				echo -en "\n\t$i: “$filename”\n\t" >>$dbg_file
				for ((j=0; j<$(( ${#i}+ ${#left_part} +3 )); j++)); do
					echo -n ' ' >>$dbg_file
				done
				for ((j=0; j<${#MAPFILE[i]}; j++)); do
					echo -n '^' >>$dbg_file
				done
				echo -en "\n\tLeft part: “$left_part”.\n\tRight part: “$right_part.”
\tIs this a number?\t" >>$dbg_file
			}
			if  [[ "${MAPFILE[i]}" =~ ^[0-9]+$ ]];  then
				[ -v D ] && echo 'Yes.' >>$dbg_file
				# parts combined beforehands if D is set
				[ -v parts_combined ] || combine_left_and_right_parts
				# Building a new file name with found number substituted by incremented one.
				left_part=`escape_for_sed_pattern "$left_part"`
				right_part=`escape_for_sed_pattern "$right_part"`
				piece_orig_length=${#MAPFILE[i]}
				# Might start with zeroes, so make it explicit decimal number.
				inc_num=$(( 10#${MAPFILE[i]} +1 ))
				# Restoring original length if shorter
				while [ ${#inc_num} -lt $piece_orig_length ]; do
					inc_num="0$inc_num"
				done
				[ -v D ] && echo -e "\tInc. number: “$inc_num”." >>$dbg_file

				# Incremental patterns: to match the current line of
				#   $LIST_TO_CHOOSE_FROM with number substituted with
				#   an incremented one to define a sequence presence.
				# There was a trouble with sed being ungreedy while matching
				#   what is supposed to be an episode number. The \b for
				#   boundary helped for some time, but then filenames having
				#   episode number surrounded with underscores (“_”) appeared,
				#   and, because \b matches letters, digits and underscores
				#   as a single word, this caused patterns to fail on such
				#   names. That’s why \b was replaced by a “possible non-
				#   number” — [^0-9]\?. It should be replaced with pre-condition
				#   when I got my hands to perl.
				# Multinum counterparts are used to hook all the filenames
				#   within a sequence defined by an inc_pattern.
				#
				# These checks are important, see bug #2.
				# We rely with knowledge of whether $i is at start (/^$i/) or
				#   at the end (/$i$/), so we could use [^0-9] safely for the
				#   border check. Could be simplier with perl, though…
				[ $i -eq $((${#MAPFILE[@]}-1)) ] \
					&& {
					inc_patterns[0]="^$left_part$inc_num$"
					multinum_patterns[0]="^$left_part\([0-9]\+\)$"
				}||{
					inc_patterns[0]="^$left_part$inc_num[^0-9].*$"
					multinum_patterns[0]="^$left_part\([0-9]\+\)[^0-9].*$"
				}
				[ $i -eq 0 ] \
					&& {
					inc_patterns[1]="^$inc_num$right_part$"
					multinum_patterns[1]="^\([0-9]\+\)$right_part$"
				}||{
					inc_patterns[1]="^.*[^0-9]$inc_num$right_part$"
					multinum_patterns[1]="^.*[^0-9]\([0-9]\+\)$right_part$"
				}
				# Both parts — the last!
				inc_patterns[2]="^$left_part$inc_num$right_part$"
				multinum_patterns[2]="^$left_part\([0-9]\+\)$right_part$"
				# If you noticed that the two last elements of both arrays with
				#   regular expressions are redundant. That’s because I’ve rea-
				#   lized only at this point, that sed capabilities are not
				#   enough.
				# Below, in the “watch” function, at the end of the “episodes”
				#   case, one of the patterns above this text will be applied to
				#   a file name in attempt to acquire episode number. And there
				#   is the rub: sed behaves non-greedy when it searches for
				#   ([0-9]+) and that makes first digits of the number to fall
				#   out of the \1 match. The first thing I did was to add boun-
				#   dary separators \b around the regex matching the number,
				#   but then sed appeared to include not only alphanumeric
				#   characters, BUT DIGITS AND THE UNDERSCORE SIGN, TOO, i.e.
				#   in file name “Durarara_01_2F4B8D2.mkv” there’s only one word
				#   boundary (except the beginning and the end of the line) —
				#   at the punctuation mark, the dot.
				# Since google tells only lies about perl mode for sed, activa-
				#   ting lookahead and lookbehind syntax with -R switch,
				#   the only option left is to prepend episode number with
				#   [^0-9] and match those starting with episode number
				#   explicitly.
				[ -v D ] && declare -p inc_patterns multinum_patterns \
					| sed -r 's/\[[0-9]+]="[^"]+"/\t&\n/g'>>$dbg_file

				# If either left or right parts appear empty, this will cause
				#   the non-empty one and the pattern with both of them
				#  (which is supposed to be the last element) to be the same,
				#   causing a bug with duplication.
				[ -z "$left_part" -o -z "$right_part" ] && {
					unset inc_patterns[${#inc_patterns}]
					[ -v D ] && echo -e '\t Unsetting pattern with incremented number and both (left and right) parts
\t   of the filename in attempt to avoid pattern duplicate.' >>$dbg_file
				}
				for ((j=0; j<${#inc_patterns[@]}; j++)); do
				[ -v D ] && echo -en "\t\tInc. pattern: “${inc_patterns[j]}”.\n\t\t\tSequence found? " >>$dbg_file
				matches=$(echo "$LIST_TO_CHOOSE_FROM" | sed -n '/'"${inc_patterns[j]}"'/p' )
				if  [ "$matches" ];  then
					local inc_patterns_found_a_sequence_for_this_file=t
					[ -v D ] && echo 'Yes.' >>$dbg_file
					# Okay, there is at least two files that show sequence in that place.
					#   I mean, at this part of filename, MAPFILE[i].
					# Is there more those two?
					unset matches
					matches=$(echo "$LIST_TO_CHOOSE_FROM" | sed -n "/${multinum_patterns[j]}/p")
					matches_count=`echo "$matches" | wc -l`
					[ -v D ] && echo -e "\t\t\tMultinum matches: $matches_count." >>$dbg_file
					# -gt 1 because wc -l  will _must not_ use echo -n, so one newline by echo may be an empty string
					#   but may be also a string with a pattern; tl;dr -gt 1 means 2 or more
					if  [[ "$matches_count" =~ ^[0-9]+$ ]] && [ $matches_count -gt 1 ];  then
						[ -v D ] && echo -en "\t\t\tUnique? " >>$dbg_file
						unset same_matches_found # better than 2 unsets, because the one inside for cycle may occur and may not.
						# Now check if any pattern already produced the same list of matches.
						for ((k=0; k<${#group_matches[@]}; k++)); do
							[ "$matches" = "${group_matches[k]}" ] && {
								same_matches_found=t
								[ -v D ] && echo 'No.' >>$dbg_file
								break
							}
						done
						[ -v same_matches_found ] || {
							[ -v D ] && echo -e "Yes.\nADD\t\t\tMultinum pattern: “${multinum_patterns[j]}”." >>$dbg_file
							# TODO: make some flag to define the situation when no number is present. # Er… how’s that?
							# I thouhgt about renaming these variables to fname_*, but  group_* clearly points at the place of origin.
							group_create \
								"${multinum_patterns[j]}" \
								"$matches" \
								$matches_count
#								"$(sed -n "s/${multinum_patterns[j]}/\1/p" <<<"$matches")"
						} # list of matches is unique
					else
						[ -v D ] && echo -e "\n#\t\t\tMULTINUM EXPRESSION FAILED!
\t\t\tSequence was found, but multinum pattern couldn’t find even two filenames.\n" >>$dbg_file
					fi # if multinumber pattern found two or more matches
				else  [ -v D ] && echo 'No.' >>$dbg_file;  fi # if inc_pattern[j] found a sequence (non-empty match list)
				done # for j in inc_patterns[@]
			else [ -v D ] && echo 'No.' >>$dbg_file;  fi  # if MAPFILE[i] is a number
		done # for i in MAPFILE[@]
		[ ! -v inc_patterns_found_a_sequence_for_this_file ] && {
			[ -v D ] && \
				echo 'This file happened to be unique enough to create a group from itself!' >>$dbg_file
			group_create \
				"$(escape_for_sed_pattern "$filename")" \
				"$filename" \
				1
		}
	done  < <(echo "$LIST_TO_CHOOSE_FROM")  # $LIST_TO_CHOOSE_FROM _never_ has literal '\n' here.
	return 0
}

# EXPECTS:
#   - that you know why some characters should be escaped;
#   - that the output will be used in a subshell, i.e. $(…)
#     so don’t make assignings like
#       var1=`escape_for_sed_pattern "blablabla"`
#     but use a subshell in place.
# TAKES:
#     $1 – a string to escape.
# RETURNS:
#     An escaped string.
escape_for_sed_pattern() {
	# Add second parameter to set number of additional escapes so it
	#   would escape properly a string that would be able to undergo eval?
	local str="$1"
	# Really not sure how many backslashes needed to escape
	#   slash and backslash itself, think one is alright.
	str=${str//\\/\\} # must be first
	str=${str//\./\\.}
	str=${str//\$/\\$}
	str=${str//\*/\\*}
	# Your syntax checker may fail here,
	#   and indentaion may also be fucked up, but it’s ok.
	str=${str//\[/\\[}   # …add round parentheses too?
	# str=${str//\]/\\]}
	# Just in case. There must be no slashes. If sed suddenly starts
	#   throw errors like
	#     sed: -e expression #1, char 84: extra characters after command
	#     sed: -e expression #1, char 77: unknown command: `o'
	#     sed: -e expression #1, char 102: Invalid range end
	#   especially when BASEPATH is an array, this may mean that folder paths
	#   have appeared in the pattern when they should not, because
	#   create_groups_for_the_list() must only process _file names_ when
	#   MODE == episodes and choose_from() was called from watch().
	# P.S. Slashes are used in do_initial_search() when removing
	#   duplicates from d.
	str=${str//\//\\/}
	str=${str//\^/\\^}
	echo -en "$str" # TODO: check for what purpose is -e here
}


arrange_groups() {
	[ -v MANUAL_REARRANGEMENT ] && return 0
	[ -v D ] && {
		dbg_file="$DEBUG_DIR/pattern_groups"
		declare -p group_patterns group_matches group_matches_count >>$dbg_file
	}
	# If we have no patterns and therefore, no matches, that’s bad
	#   and we have to fallback, there’s no error produced since
	#   the list_to_choose_from still exist, so we just don’t touch it.
	[ ${#group_patterns[@]} -eq 0 ] && {
		# That can’t be.
		[ -v D ] && echo 'No patterns.' >>$dbg_file
		return 106
	}

	[ ${#group_patterns[@]} -gt 1 ] \
		&& list_variants_available=${#group_patterns[@]}

	[ -v list_variants_available ] && {
		[ -v D ] && echo "List variants available: $list_variants_available." >>$dbg_file
		# There is >1 pattern, we can sort and rotate patterns.
		[ -v ROTATE_PATTERN_LIST ] && {
			[ -v D ] && echo 'ROTATING' >>$dbg_file
			# ┌─────────────────────>──────────┐
			# ^   TAB in menu rotates groups   v
			# └──────────<─────────────────────┘
			local buffer_index=${#group_patterns[@]}
			group_copy 0 $buffer_index
			for ((i=1; i<${#group_patterns[@]}; i++)); do
				group_copy $i $((i-1))
			done
			group_copy $buffer_index $((${#group_patterns[@]}-2))
			group_delete $buffer_index
			[ $((++INDEX_AT_THE_TOP)) -gt ${#group_patterns[@]} ] \
				&& INDEX_AT_THE_TOP=1 # why not 0?
			[ -v D ] && declare -p INDEX_AT_THE_TOP >>$dbg_file
			unset ROTATE_PATTERN_LIST
		}||{
			[ -v D ] && echo 'SORTING' >>$dbg_file
			# Do initial groups sorting.
			# Sort patterns descending by the number of matches OR
			#   lexicographically if numbers are equal
			for (( i=0; i<${#group_patterns[@]}-1; i++)); do
				for (( j=$i+1; j<${#group_patterns[@]}; j++)); do
					# Biggest number of matches → to the top of the array.
					( [ ${group_matches_count[i]} -lt ${group_matches_count[j]} ] ||
						( [ ${group_matches_count[i]} -eq ${group_matches_count[j]} ] &&
							[[ "${group_patterns[i]}" > "${group_patterns[j]}" ]] ) ) && {
						group_swap $i $j
					}
				done
			done
			[ -v D ] && echo 'Sorted patterns:' >>$dbg_file
		}
	}
	[ -v D ] && {
		echo 'Some elements may span on multiple lines if they contain double quotes.
This is not a bug.' >>$dbg_file
		declare -p group_patterns group_matches group_matches_count >>$dbg_file
	}
	return 0
}

build_the_list() {
	local i j k header manual_rearrangement_was_in_effect \
		total_items_count=$LIST_ITEMS_COUNT # because choose_from() may be called again from here
	[ -v D ] && {
		dbg_file=$DEBUG_DIR/build_the_list
		echo -e 'Building the list. # View me with `less -S`.\nManual reararngement, end of HEU1, HEU2.\n\nInitial data:' >>$dbg_file
		header="Index   Pattern   Matches   Matches count"
		for ((i=0; i<${#group_patterns[@]}; i++)); do
			[ $i -eq 0 ] && echo -e "$header\n${header//[^ ]/—}"
			local match next_run
			unset next_run
			while IFS= read -r match; do
				[ -v next_run ] \
					&& echo "        $match        " \
					|| echo "$i   ${group_patterns[i]}   $match   ${group_matches_count[i]}"
				next_run=t
			done <<<"${group_matches[i]}"
		done | column -o ' ' -s '   ' -t  >>$dbg_file
	}

	# SETS:
	#     VIDITEM_* — arrays for manipulation while doing heuristics.
	#         NB All these arrays start from zero, while line numbers in
	#         selection dialog and VIDEO_NUMBER starting from 1.
	# TAKES:
	#     $1 — filename
	#     $2 — group id (for pattern) # wait, where do we need the pattern?..
	#     $3 — episode number OR supposed episode number OR line number
	#          Ex. "1"           Ex. "1?"                   Ex. "L1"
	#         (temporarily may comprise of space-separated numbers)
	viditem_create() {
		# If HEU LVL == 0, constructed in choose_from().
		VIDITEM_FILE[${#VIDITEM_FILE[@]}]=$1
		# Global, but used only within build_the_list() scope in order
		#   to make us able to build the list with accordance to groups when
		#   lowering heuristics level.
		# Doesn’t go to journal—caps is used for conformance with viditem_*().
		VIDITEM_GID[${#VIDITEM_GID[@]}]=$2
		# Global. If HEU LVL == 0, filled with L# in choose_from().
		# Removing leading zeroes to avoid misinterpretation as octal.
		VIDITEM_EPNUMBER[${#VIDITEM_EPNUMBER[@]}]=${3##0}
	}

	# TAKES:
	#     $1 — source viditem index
	#     $2 — destination viditem index
	viditem_copy() {
		local viditem
		for viditem in ${!VIDITEM_@}; do
			local viditem1=$viditem[$1]
			local viditem2=$viditem[$2]
			eval $viditem2=\""${!viditem1}"\"
		done
	}

	# TAKES:
	#     $1 — index to delete from VIDITEM_* arrays
	viditem_delete() {
		local viditem
		for viditem in ${!VIDITEM_@}; do unset $viditem[$1]; done
	}

	# TAKES:
	#     $1 — index of the viditem A
	#     $2 — index of the viditem B
	viditem_swap() {
		local buffer_index=${#VIDITEM_FILE[@]}
		viditem_copy $1 $buffer_index
		viditem_copy $2 $1
		viditem_copy $buffer_index $2
		viditem_delete $buffer_index
	}

	# USES:
	#     queue_* — arrays that specify queue. Because there are batch jobs
	#         in manual rearrangement as well as in HEU2.
	# ALTERS:
	#     VIDITEM_* — alter the order of items.
	# RETURNS:
	#     0 — if OK;
	#     3 — illegal queue construct, immediate return;
	#     42 — queue is 2big4ahuman to read the debug output (only when D is set).
	#          The latter is exit code.
	rearrange_list_items() {
		# These are example values I used to build this algo.
		#
		#      0 1 2 3 4 5 6 7 8 9 10     total: 11
		# arr=(a b c d e f g h i j k)
		#
		# q[0]='6/7/1'    # g h a b c d e f i j k
		# # q[0]='6/10/8'   # illegal move. Unlike 0-4>10 we’re going out of the borders
		# # q[0]='2/6/4'    # allowed variant of the above, that doesn’t cause any problems.
		# # q[0]='6/6/7'    # test for a single move for borders adjacent to the source item.
		# q[1]='0/2/9'    # g h d e f i j a b c k      # INV!
		# q[2]='9/10/1'   # g h j k d e f i a b c
		#
		# q format: start/end/dest

		local c i j k l _arr _old_arr _new_arr _item item_index buffer_placed \
			header
		[ -v D ] && {
# Replace viditems with a b c…
			echo -e "\nRunning queue\nInitial setup:" >>$dbg_file
			header="Index   File   GID   Episode number"
			for ((i=0; i<total_items_count; i++)); do
				[ $i -eq 0 ] && echo -e "\n$header\n${header//[^ ]/—}"
				echo "$i   ${VIDITEM_FILE[i]}   ${VIDITEM_GID[i]}   ${VIDITEM_EPNUMBER[i]}"
			done | column -o ' ' -s '   ' -t  >>$dbg_file
			echo -e "" >>$dbg_file
			header="Index   Start/end/dest"
			for ((i=0; i<${#queue_start[@]}; i++)); do
				[ $i -eq 0 ] && echo -e "$header\n${header//[^ ]/—}"
				echo "$i   ${queue_start[i]}/${queue_end[i]}/${queue_dest[i]}"
			done | column -o ' ' -s '   ' -t  >>$dbg_file
			echo -e '^Queue is running on VIDITEM indices.\n' >>$dbg_file
		}

		# We’ll have to create arrays of actual items instead of relying upon
		#   where the group starts and where ends—such groups may be split
		#   after iterations. So, instead of groups—indices of what will be
		#   moving. Eval is because we can’t into arrays of arrays here.
		for ((i=0; i<${#queue_dest[@]}; i++)); do
			for ((j=queue_start[i]; j<queue_end[i]+1; j++)); do
				eval queue_items_$i[\${#queue_items_$i[@]}]=$j
				[ -v D ] && eval dmsg \""queue_items_$i=( \${queue_items_$i[@]} )"\"
			done
		done
		[ -v D ] && declare -p queue_dest
		# Since we’re going to transpose indices, let’s create an array for them
		for ((i=0; i<${#VIDITEM_FILE[@]}; i++)); do _arr[i]=$i; done

		# Performing rearrangement
		# [ -v T ] && iter=1 # which iteration to perform debug on
		for ((i=0; i<${#queue_start[@]}; i++)); do
			[ -v D ] && {
				dil_inc
				echo -e "\n\tRunning queue item $i:\n${di}_arr:" >>$dbg_file
				{
					for ((j=0; j<${#_arr[@]}; j++)); do
						[ $j -eq 0 ] && echo -en "${di}Index:   " \
							|| echo -n "$j   "
						[ $j -eq $((${#_arr[@]}-1)) ] && echo
					done
					for ((j=0; j<${#_arr[@]}; j++)); do
						[ $j -eq 0 ] && echo -en "${di}Value:   " \
							|| echo -n "${_arr[j]}   "
					done
				} | column -o ' ' -s '   ' -t  >>$dbg_file
			}
			_old_arr=("${_arr[@]}") # to see how things change
			eval _queue_items=(\${queue_items_$i[@]})
			[ -v D ] && dmsg "_queue_items=( ${_queue_items[@]} )"
			# [ -v T ] && [ $i -eq $iter ] && set -x
			unset buf
			for ((j=0; j<${#_queue_items[@]}; j++)); do
				buf[${#buf[@]}]=${_arr[_queue_items[j]]}
				[ -v D ] && echo "${di}Unsetting _arr[${_queue_items[j]}] = ${_arr[_queue_items[j]]]}." >>$dbg_file
				unset _arr[_queue_items[j]] # removing source lines from the array
			done
			# [ -v T ] && [ $i -eq $iter ] && { set +x; declare -p buf; }
			[ -v D ] && {
				echo -n "$di" >> $dbg_file && declare -p buf >>$dbg_file
				[ $(( ${queue_dest[i]} + ${#_queue_items[@]} )) -gt ${#_old_arr[@]} ] \
					&& dmsg '' 'Possible error: ${queue_dest[i]} + ${#_queue_items[@]} are out of range (${#_old_arr[@]}).\n'
			}

			# If destination happens to reside within the removed group,
			#   it shouldn’t be altered. To know whether it is the case,
			#   we check how many removed items were residing to the left
			#   of the destination. If it equals to ${#_queue_items[@]}, then
			#   the group and destination are separated.
			c=0
			for _item in ${_queue_items[@]}; do
				[ $_item -lt ${queue_dest[i]} ] && let c++
				#\
				#	&& [ $((++c)) -eq ${#_queue_items[@]} ] \
				#	&& let queue_dest[i]-=${#_queue_items[@]}-1
			done
			[ $c -eq ${#_queue_items[@]} ] && {
				let queue_dest[i]-=${#_queue_items[@]}-1
				[ -v D ] && dmsg "Destination was shifted by -$((${#_queue_items[@]}-1))"
			}
			unset _new_arr
			c=0
			# [ -v T ] && echo -------------------------------------------------------------
			# item_index, because we have unset certain variables that might
			#   have been in the middle (so, to not leave a gap
			#   that we don’t want to fix).
			unset buffer_placed
			# [ -v T ] && [ $i -eq $iter ] && set -x
			for item_index in ${_arr[@]}; do
				[ $((c++)) -eq ${queue_dest[i]} ] && {
					[ -v D ] && {
						dmsg "Destination place! Placing the buffer:"
						dil_inc
					}
					for ((k=0; k<${#buf[@]}; k++)); do
						_new_arr[${#_new_arr[@]}]=${buf[k]}
						[ -v D ] && dmsg "_new_arr[$((${#_new_arr[@]}-1))] = ${buf[k]}"
					done
					buffer_placed=t
					[ -v D ] && dil_dec
				}
				_new_arr[${#_new_arr[@]}]=$item_index
				[ -v D ] && dmsg "_new_arr[$((${#_new_arr[@]}-1))] = $item_index"
			done
			# [ -v T ] && [ $i -eq $iter ] && set +x
			[ -v buffer_placed ] || {
				warn "やべっ！ Buffer wasn’t placed possibly because of illegal move, stopping the queue.\n  No changes were made."
				return 3
			}

			[ -v D ] && {
				dmsg "Rearrangements for queue $i complete."
				dput_declare '' _old_arr '' _new_arr ''
				dmsg "Brigning subsequent queue items into correspondence with current order:"
				dil_inc
			}
			# [ -v T ] && exit
			for ((j=i+1; j<${#queue_dest[@]}; j++)); do
				# [ -v T ] && [ $i -eq $iter ] && echo j = $j
				eval _queue_items=(\${queue_items_$j[@]})
				[ -v D ] && {
					dmsg "Adjusting queue item $j."
					dil_inc
					dput_declare _queue_items
					dmsg "Walking the _queue_items:"
					dil_inc
				}
				unset dest_j_found
				for ((k=0; k<${#_queue_items[@]}; k++)); do
					[ -v D ] && dmsg "Searching for item = ${_queue_items[k]} (idx:$k):" && dil_inc
					for ((l=0; l<${#_new_arr[@]}; l++)); do
						# [ -v T ] && [ $i -eq $iter ] && set -x
						[ ! -v dest_j_found -a  ${_new_arr[l]} -eq ${queue_dest[j]} ] && {
							[ -v D ] && dmsg "Looks lile _new_arr[$l] is our destination: ${queue_dest[j]}."
							queue_dest[j]=$l
							local dest_j_found=t
						}
						# [ -v T ] && [ $i -eq $iter ] && set +x
						[ ${_new_arr[l]} -eq ${_queue_items[k]} ] && {
							eval queue_items_$j[k]=$l
							[ -v D ] && {
								dmsg "Looks like _new_arr[$l]=${_new_arr[l]} is also equal to the item in _queue_items[$k]!"
								dmsg "Setting queue_items_$j (←the true one) to $l."
								dput_declare queue_items_$j
							}
							# [ -v T ] && [ $i -eq $iter ] && echo -en '\t'; declare -p queue_items_$j
							[ -v dest_j_found ] && break
						}
					done
					[ -v D ] && dil_dec
				done
				[ -v D ] && dil_dec 2
				# [ -v T ] && [ $i -eq $iter ] && exit
			done
			_arr=(${_new_arr[@]})
			[ -v D ] && {
				for ((j=0; j<${#queue_start[@]}; j++)); do
					dput_declare queue_items_$j
				done
				dput_declare queue_dest
				dil_dec 2
			}
			# [ -v T ] && {
			# 	echo --- END -------------------------------
			# 	[ $i -eq $iter ] && exit
			# }
		done
		for ((i=0; i<${#_arr[@]}; i++)); do
			_arr_file[i]=${VIDITEM_FILE[_arr[i]]}
			_arr_gid[i]=${VIDITEM_GID[_arr[i]]}
			_arr_epnumber[i]=${VIDITEM_EPNUMBER[_arr[i]]}
		done
		for ((i=0; i<${#_arr[@]}; i++)); do
			VIDITEM_FILE[i]=${_arr_file[i]}
			VIDITEM_GID[i]=${_arr_gid[i]}
			VIDITEM_EPNUMBER[i]=${_arr_epnumber[i]}
		done
		return 0
	} # rearrange_list_items()

	# TAKES:
	#     $1 — start line
	#     $2 — end line
	#     $3 — destination line
	queue_create() {
		local start=$1 end=$2 dest=$3
		# [ $start -eq $dest ] && return 0 # Actually, when itemd get shifted, that’s okay.
		# queue_* items would be used to operate on VIDITEM_* arrays
		#   that start from 0, unlike lines, hence this decrement.
		queue_start[${#queue_start[@]}]=$(( $start - 1 ))
		queue_end[${#queue_end[@]}]=$((     $end   - 1 ))
		queue_dest[${#queue_dest[@]}]=$((   $dest  - 1 ))

# Subject for removal (except the comment)
#[ ${queue_dest[-1]} -gt ${queue_end[-1]} ] && {
			# For moves like 4>3, i.e. from the down to top, it works as you
			#   think it does, but when you give it a command to put something
			#   from up to down, it… works, however the result is _not_ what
			#   a human would expect, e.g. 4>3 swaps the third line with
			#   the fourth, while 3>4 would seem to do nothing. This is because
			#   in general case the source, i.e. 3rd line in our example, is
			#   removed from the list, the list then shifted for one line up,
			#   and then the time comes to put destination to the new place.
			#   But before placing the destination [line], it must put what’s
			#   in the buffer, i.e. the 3rd line, before, and only after—
			#   the destination, what was the 4th line.
			# Since it makes the operation obscure to the user, we put
			#   the destination before what is in the buffer in that case, so
			#   it would act like the user expects it to.
#queue_put_dest_line_first[${#queue_start[@]}-1]=t # t or unset
#}
	}

	# TAKES:
	#     $1 — index to delete from queue_* arrays
	queue_delete() {
		local queue
		for queue in ${!queue_@}; do unset $queue[$1]; done
	}

	test_queue_for_intersections() {
		[ -v D ] && echo -e "\nTesting queue for intersections." >>$dbg_file
		local i j list_is_before list_is_after
		for ((i=0; i<${#queue_start[@]}-1; i++)); do
			for ((j=i+1; j<${#queue_start[@]}; j++)); do
				unset list_is_before list_is_after
				[ ${queue_start[j]} -lt ${queue_start[i]} -a ${queue_end[j]} -lt ${queue_start[i]} ] \
					&& list_is_before=t
				[ ${queue_start[j]} -gt ${queue_end[i]} -a ${queue_end[j]} -gt ${queue_end[i]} ] \
					&& list_is_after=t
				[ -v list_is_before -o -v list_is_after ] && [ ${queue_dest[j]} -ne ${queue_dest[i]} ] || {
					warn "An intersection was found between ${queue_start[i]}-${queue_end[i]}>${queue_dest[i]} and ${queue_start[j]}-${queue_end[j]}>${queue_dest[j]}."
					return 0
				}
			done
		done
		return 0
	}

	[ -v MANUAL_REARRANGEMENT ] && {
		readarray -t <<<"`echo -e ${MANUAL_REARRANGEMENT//,/\\\n}`"
		[ -v D ] && echo -e "Manual rearrangement requested.\nRaw MAPFILE: ‘$MAPFILE’." >>$dbg_file
		unset MANUAL_REARRANGEMENT
		for ((i=0; i<${#MAPFILE[@]}; i++)); do
			[ -v D ] && echo -e "\tPiece $i: ‘${MAPFILE[i]}’." >>$dbg_file
			[[ "${MAPFILE[i]}" =~ ^[0-9]+(-[0-9]+)?\>[0-9]+$ ]] || {
				warn "“${MAPFILE[i]}” is not a valid rearrangement instruction."
				warn "The format is: “10>1”, “9-11>2”, “1-3>5,7-8>1,…”."
				return 0
			}
			local start="${MAPFILE[i]%>*}" \
			      end="${MAPFILE[i]%>*}" \
			      dest="${MAPFILE[i]#*>}"
			local start="${start%-*}" \
			      end="${end#*-}"
			[ $start -gt $total_items_count ] && {
				warn "“${MAPFILE[i]}”: start value must be lower than $total_items_count."
				return 0
			}
			[ $end -lt $start ] && {
				warn "“${MAPFILE[i]}”: end value must be lower than start value."
				return 0
			}
			[ $dest -gt $total_items_count ] && {
				warn "“${MAPFILE[i]}”: destination value must be lower than $total_items_count."
				return 0
			}
			[ $start -eq $dest ] && {
				warn "“${MAPFILE[i]}”: what’s the point in this?.."
				return 0
			}
			[ -v D ] && echo -e "\tAdding queue start/end/dest: $start $end $dest." >>$dbg_file
			queue_create $start $end $dest
		done
		test_queue_for_intersections || return $?
		rearrange_list_items && manual_rearrangement_was_in_effect=t || return $?
	}||{  # First run of this function should start here (no manual rearrangement was requested).
		# At this point we need to assign an episode number to each match, and
		#   thus operate with VIDITEM_* arrays, but at the same time we still
		#   need group_*, because keeping a sequence raises the chance
		#   of building list in the correct order.
		unset VIDITEM_FILE VIDITEM_GID VIDITEM_EPNUMBER
		local line_count=1  list_indicators=() groups_borders=() pat_for_grep=() \
			i j k match new_match_found _ep_number sequence_started_at
		for ((i=0; i<${#group_patterns[@]}; i++)); do
			# ---For HEU2
			local gb_index=${#groups_borders[@]}
			[ $i -gt 0 ] && [ -v groups_borders[gb_index-1] ] \
				&& [[ ${groups_borders[gb_index-1]} =~ \;$ ]] \
				&& groups_borders[gb_index-1]="$((total_items_count+1));$((total_items_count+1))" # mark of not being present in the current set
			groups_borders[gb_index]="$line_count;"
			# ---For HEU2
			# May need check for bordering pattern here. group_pattern_is_bordering[i]
			pat_for_grep[i]=${group_patterns[i]%\[^0-9]\.\**}
			[ "${pat_for_grep[i]}" = "${group_patterns[i]}" ] \
				&& pat_for_grep[i]=${group_patterns[i]#^\.\*\[^0-9]}
			for ((j=0; j<${group_matches_count[i]}; j++)); do
				unset new_match_found
				until [ -v new_match_found ]; do
					match=`sed -n $((j+1))p <<<"${group_matches[i]}"`
					[ $i -eq 0 ] && break # matches of the 1st pattern are unique
					new_match_found=t
					for ((k=0; k<$total_items_count; k++)); do
						[ "${VIDITEM_FILE[k]}" = "$match" ] && unset new_match_found
					done
					[ -v new_match_found ] || {
						# If there are no new matches, it will simply accumulate until j reaches its limit
						[ $((++j)) -eq ${group_matches_count[i]} ] && break 2 # Yes, it works. Think!
					}
				done
				# ‘extracted number’, what is supposed to be an ‘episode number’.
				# (For HEU1 just ‘Line No. N’)
				[ ${group_matches_count[i]} -eq 1 ] && {
					# Getting rid off false numbers like hashes, resolution,
					#   codecs, etc.
					local _match="$match" _pattern
					for _pattern in "${NOT_EPNUMBERS[@]}"; do
						_match=${_match%%$_pattern*}
					done
					group_occupied_numbers[i]="$(sed -r 's/[^0-9]+/ /g; s/(^\s|\s$)//g; #hypotetical numbers!'<<<"$_match")"
					_ep_number="L$line_count"
				}|| _ep_number="$(sed -n "s/${group_patterns[i]}/\1/p" <<<"$match")"
				viditem_create "$match" $i $_ep_number
				# ---For HEU2
				groups_borders[gb_index]=${groups_borders[gb_index]%;*}
				groups_borders[gb_index]+=";$line_count"
				# ---For HEU2
				[ $((++line_count)) -gt $((total_items_count+1)) ] && break 2
			done
		done

		[ -v D ] && {
			echo -e '\n\nBuilding VIDITEM_* arrays and groups_borders[@]:' >>$dbg_file
			local _prev_viditem_gid=-1 \
				header="Index-->   File   GID   Episode number   Line-->   Group starts at   Group ends at"
			for ((i=0; i<total_items_count; i++)); do
				[ $i -eq 0 ] && echo -e "$header\n${header//[^ ]/—}"
				[ $_prev_viditem_gid -ne ${VIDITEM_GID[i]} ] \
					&& echo "$i   ${VIDITEM_FILE[i]}   ${VIDITEM_GID[i]}   ${VIDITEM_EPNUMBER[i]}   $((i+1))   ${groups_borders[VIDITEM_GID[i]]%;*}   ${groups_borders[VIDITEM_GID[i]]#*;}" \
					|| echo "$i   ${VIDITEM_FILE[i]}   ${VIDITEM_GID[i]}   ${VIDITEM_EPNUMBER[i]}   $((i+1))        "
				_prev_viditem_gid=${VIDITEM_GID[i]}
			done | column -o ' ' -s '   ' -t  >>$dbg_file
		}

		# Composing group indicators.
		# It is better to be done outside the cycle above.
		#   Much more readable and clearer this way.
		VIDITEM_GID[${#VIDITEM_GID[@]}]='dummy' # just a hack to walk the whole array ↓
		# i=0 won’t do, because we need the result of subtraction to have same
		#   ranges for 2-1=1 and 1-0=1, while 0 - 0 will give us… 0.
		for ((i=1; i<${#VIDITEM_GID[@]}; i++)); do
			[ "${VIDITEM_GID[i]}" = "${VIDITEM_GID[i-1]}" ] || {
				# A consecutive sequence has ended and a new one just started.
				# Let’s look at the sequence to know how we should transform it
				[ -v sequence_started_at ] || sequence_started_at=0
				[ $((i-sequence_started_at)) -ge 2 ] && {
					list_indicators[sequence_started_at]=$GI_BEGIN # ┌
					list_indicators[i-1]=$GI_END # └
				}
				[ $((i-sequence_started_at)) -ge 3 ] && {
					for ((j=sequence_started_at+1; j<i-1; j++ )); do
						list_indicators[j]=$GI_MIDDLE # │
					done
				}
				[ $sequence_started_at -eq $((i-1)) ] \
					&& list_indicators[i-1]=$GI_SINGLE # ⋅
				local sequence_started_at=$i
			}
		done
		unset VIDITEM_GID[-1]

		# The last thing HEU1 does is sorting items in groups in accordance
		#   with their episode numbers, becuase multinumber patern only hooked
		#   the filenames which had numbers in a specified position.
		# Why was it separated from the new queue assembling in HEU2? HEU2 doesn’t
		#   simply forget about groups and rebuilds the list by numbers—this would
		#   only mess the order if it has several actual sequences, like
		#     - Animu EP XX [hash].mkv
		#     - Animu extra XX [hash].mkv
		#     - Animu OVA XX [hash].mkv
		#   Groups are respected and only so called holes are filled in them, before,
		#   after and  between them. So the actual sort between the group members
		#   should be done before it.

		# Okay, we have groups and arranged them. But currenlty it’s not much
		#   far away from the “sort” command, that would find these numbers too
		#  (and put 1 after 10), we are a step forward only by finding a hint
		#   for a presence of sequence in those numbers. Now arrange these
		#   numbers to represent the actual sequence.
		# We’re going to do a bubble sort of VIDITEM_* based on the numbers
		#   we found (i.e. VIDITEM_EPNUMBER[@]).
		# Why not rebuilding all group_matches[@] like before? Too much work.
		#   I don’t see any reason to rebuild all these, when there’s 1/3
		#   of groups that don’t get to the list, and it’s just waste of CPU time.
		for ((i=0; i<${#list_indicators[@]}; i++)); do
			case ${list_indicators[i]} in
				$GI_BEGIN) local _gr_start=$i;;
				$GI_MIDDLE) continue;;
				$GI_END)
					local _gid=${VIDITEM_GID[i]}
					# Usually I’d go with j<i here, but +1 is for not making
					#   another (last) assignment for group_occupied_numbers
					#   after the j cycle.
					for ((j=_gr_start; j<i+1; j++)); do
						[ $j -lt $i ] && for ((k=_gr_start+j; k<i+1; k++)); do
							[ ${VIDITEM_EPNUMBER[j]} -gt ${VIDITEM_EPNUMBER[k]} ] \
								&& viditem_swap $j $k
						done
						group_occupied_numbers[_gid]="${group_occupied_numbers[_gid]:+${group_occupied_numbers[_gid]} }${VIDITEM_EPNUMBER[j]}"
					done
					;;
			esac
		done

		[ -v D ] && {
			echo -e '\n\nAfter items within groups were sorted:' >>$dbg_file
			local _prev_viditem_gid=-1 \
				header="Index-->   I   File   GID   Episode number   Numbers occupied by group"
			for ((i=0; i<total_items_count; i++)); do
				[ $i -eq 0 ] && echo -e "$header\n${header//[^ ]/—}"
				[ $_prev_viditem_gid -ne ${VIDITEM_GID[i]} ] \
					&& echo "$i   ${list_indicators[i]}   ${VIDITEM_FILE[i]}   ${VIDITEM_GID[i]}   ${VIDITEM_EPNUMBER[i]}   ${group_occupied_numbers[VIDITEM_GID[i]]}" \
					|| echo "$i   ${list_indicators[i]}   ${VIDITEM_FILE[i]}   ${VIDITEM_GID[i]}   ${VIDITEM_EPNUMBER[i]}   "
				_prev_viditem_gid=${VIDITEM_GID[i]}
			done | column -o ' ' -s '   ' -t  >>$dbg_file
			echo -e '\nHEU LVL 1 ends.' >>$dbg_file
		}

		# TAKES:
		#    $1 — group index to check
		#    $2 — bottom border for episode value
		#   [$3] — top border for episode value
		# USES:
		#    group_occupied_numbers[@]
		#    NOT_EPNUMBERS
		# SETS:
		#    EP — episode number that fits specified borders.
		# RETURNS:
		#    0 — if this is not a single group or a sinlge group which episode
		#      number does reside within specified borders (what matters is
		#      whether we can continue safely with current VIDITEM_EPNUMBER[]).
		#    1 — if this is a single group and none of its possible episode
		#      numbers reside within specified borders.
		retrieve_single_group_epnumber() {
			local gid=$1 bottom_border=$2 top_border gr_size _ep
			[ "$3" ] && top_border=$3 || top_border=$bottom_border
			gr_size=$(( ${groups_borders[gid]#*;} - ${groups_borders[gid]%;*} + 1 ))
			[[ "$gr_size" =~ ^[0-9]+$ ]] || {
				warn "Couldn’t compute size for group $gid."
				return 5
			}

			[ $gr_size -eq 1 ] && {
				# This is an L#, need to find out what it can offer
				[ -v D ] && echo -e "\t\t\tThis is group of a single item. Need to look at occupied numbers to retrieve possible episode numbers." >>$dbg_file
				for _ep in ${group_occupied_numbers[gid]}; do
					_ep=${_ep##0} # avoiding misinterpretation as octal number
					[ -v D ] && echo -en "\t\t\t\tPiece: ‘$_ep’. Does it reside within our borders $bottom_border..$top_border?" >>$dbg_file
					[ $_ep -ge $bottom_border -a $_ep -le $top_border ] && {
						[ -v D ] && echo -e "\tYES." >>$dbg_file
						EP="$_ep" && return 0
					}||{ [ -v D ] && echo -e "\tNO." >>$dbg_file; }
				done
				[ -v EP ] || return 6
			}|| return 0
		}


		# Level 2 heuristics.
		[ $HEURISTICS_LEVEL -eq 2 ] && {
			[ -v D ] && echo -e '\n\nHEU LVL 2 starts. Finding gaps and filling them.

Entering cycle of groups supplementing.' >>$dbg_file

			# Cycle starts here.
			# 1. Check if group we work on is the topmost.
			# 1.1. If it is, see if the gap in the beginning present.
			# 1.1.1. If it is, add it to gap filling queue.
			# 2. Look for gaps inside group.
			# 3. If there are some, add them to the gap filling queue.
			# 4. Look if there is a group that can be continuation
			#    of this group (single or beginning with a fitting ep number).
			# 5. If there is, add it to the queue.
			# 6. Run the queue.
			# 7. Start new iteration.

			# The list is built from top to bottom, We _never_ put something
			#   before a group except if it’s the first one: because the default
			#   algorithm is, as you should remember, to place _the biggest_
			#   group at the top, and that doesn’t mean that it should contain
			#   the first episode.

			local bottom_line=0 # we filled the list continuously up till this line.
			local there_is_a_group_to_supplement=0 # rotation was done on values, not indices, remember?
			while [ -v there_is_a_group_to_supplement ]; do
				local gr_index=$there_is_a_group_to_supplement \
					gr_start=${groups_borders[gr_index]%;*} \
					gr_end=${groups_borders[gr_index]#*;} \
					queue=() \
					sum_of_gaps=0 \
					gaps=() # format: "<start>-<end>", e.g. "12;65"
				local gr_size=$((gr_end - gr_start + 1))
				let bottom_line+=gr_size
				unset there_is_a_group_to_supplement sum_of_gaps
				[ -v D ] && {
					echo "Supplementing group $gr_index (from the top) that is:" >>$dbg_file
					local header="Index   Matches   Group starts at   Group ends at   Size (lines)   Numbers occupied by group" \
						match next_run
					unset next_run
					while IFS= read -r match; do
						[ -v next_run ] \
							&& echo "    $match                " \
							|| {
							echo -e "$header\n${header//[^ ]/—}"
							echo "$gr_index   $match   $gr_start   $gr_end   $gr_size   ${group_occupied_numbers[gr_index]}"
						}
						next_run=t
					done <<<"${group_matches[gr_index]}" | column -o ' ' -s '   ' -t  >>$dbg_file
				}
				# 1.—1.1.1. Is this group the initial one?
				[ $gr_index -eq 0 ] && {
					[ -v D ] && echo -e "\n\tThis is initial group (idx:0)." >>$dbg_file
					# Is this a single group by accident?
					[ $gr_size -eq 1 ] && {
						[ -v D ] && echo -e "\tThis is a single group (items:1)." >>$dbg_file
						[[ "${group_occupied_numbers[0]}" =~ ^[0-9]+$ ]] && {
							[ -v D ] && echo -e "\t\tLooks like this file has only one number: ${group_occupied_numbers[0]}, assigning it to VIDITEM_EPNUMBER[0]." >>$dbg_file
							VIDITEM_EPNUMBER[0]=${group_occupied_numbers[0]##0} # avoiding misinterpretation as octal
						}||{
							warn 'I can’t  guess episode number for the first group that is single—no basic data.\n    Choose what’ll become the first episode number:'
							choose_from "`echo -en "${group_occupied_numbers[0]// /\\\n}"`" || {
								local exit_code=$?
								echo -e '\t\tUser has aborted procedure of choosing episode number for the initial group.' >>$dbg_file
								return $exit_code
							}
							[ -v D ] && echo -e "\t\tAssigning CHOSEN_ITEM: ‘${CHOSEN_ITEM##0}’ to VIDITEM_EPNUMBER[0]." >>$dbg_file
							VIDITEM_EPNUMBER[0]=${CHOSEN_ITEM##0} # avoiding misinterpretation as octal
						}
					}
					[ ${VIDITEM_EPNUMBER[0]} -gt 1 ] && {
						gaps[0]="1;$((VIDITEM_EPNUMBER[0]-1))"
						[ -v D ] && echo -e "\t\tFirst episode is not 1. Adding gap 1;$((VIDITEM_EPNUMBER[0]-1))." >>$dbg_file
					}
				}
				# 2.—3. Does the group have gaps?
				[ $gr_size -gt 1 -a $(( ${group_occupied_numbers[gr_index]##* } - ${group_occupied_numbers[gr_index]%% *} + 1 )) -ne $gr_size ] && {
					[ -v D ] && echo -e "\tThis group spans over at least two lines and has gaps within it (last_ep - start_ep ≠ gr_size)." >>$dbg_file
					for ((i=gr_start; i<gr_end; i++)); do
						local diff=$(( VIDITEM_EPNUMBER[i] - VIDITEM_EPNUMBER[i-1] ))
						[ $diff -ne 1 ] && {
							gaps[${#gaps[@]}]="$((VIDITEM_EPNUMBER[i-1]+1));$((VIDITEM_EPNUMBER[i]-1))"
							[ -v D ] && echo -e "\t\tFound a gap between lines $i and $((i+1)) (episodes $((VIDITEM_EPNUMBER[i-1]+1));$((VIDITEM_EPNUMBER[i]-1)))." >>$dbg_file
						}
					done
				}

				[ -v D ] && {
					echo -e '\n\tFound gaps:' >>$dbg_file
					local _prev_viditem_gid=-1 \
						header="Index   Starts from episode   Ends on episode"
					for ((i=0; i<${#gaps[@]}; i++)); do
						[ $i -eq 0 ] && echo -e "    $header\n    ${header//[^ ]/—}"
						echo "    $i   ${gaps[i]%;*}   ${gaps[i]#*;}"
					done | column -o ' ' -s '   ' -t  >>$dbg_file
					echo >>$dbg_file
				}
				# 4. Filling gaps
				for ((i=0; i<${#gaps[@]}; i++)); do
					unset gap_filled gap_partly_filled lines_filled_with_parts \
						groups_that_fill_entire_gap groups_that_fill_gap_partly
					local _ep \
						gap_start=${gaps[i]%;*} \
						gap_end=${gaps[i]#*;}
					local gap_size=$((gap_end - gap_start + 1))
					[ -v D ] && {
						echo -e "\tFilling gap $i:\n\tStart ep: $gap_start\n\tEnd ep: $gap_end\n\tSize (eps): $gap_size" >>$dbg_file
						echo -e "\t\tLooking for suitable groups:" >>$dbg_file
					}
					for ((j=1; j<${#groups_borders[@]}; j++)); do
						unset that_group_fits _ep _eps
						local _ep _eps \
							_gr_start=${groups_borders[j]%;*} \
							_gr_end=${groups_borders[j]#*;}
						local _gr_size=$((_gr_end - _gr_start + 1))
						[ $_gr_start -lt $((total_items_count+1)) ] || {
							[ -v D ] && echo -e "\t\t\tGroup $j seems to be already used or not used in this set." >>$dbg_file
							continue
						}
						[ -v D ] && echo -e "\t\tChecking group $j:\n\t\t\tStart line: $_gr_start\n\t\t\tEnd line: $_gr_end\n\t\t\tSize (lines): $_gr_size" >>$dbg_file
						unset EP
						retrieve_single_group_epnumber $j $gap_start $gap_end && [ ! -v EP ] && {
							[ -v D ] && echo -en "\t\t\tThis is group of multiple items. Do they reside within gap borders?" >>$dbg_file
							[ ${VIDITEM_EPNUMBER[_gr_start-1]} -ge $gap_start \
						   -a ${VIDITEM_EPNUMBER[_gr_end-1]}   -le $gap_end   ] && {
								[ -v D ] && echo -e "\tYES." >>$dbg_file
								_eps=${group_occupied_numbers[j]}
								local that_group_fits=t
							}||{ [ -v D ] && echo -e "\tNO." >>$dbg_file; }
						}
						[ -v EP -o -v that_group_fits ] && {
							# format: "<group no.>;<ep no. 1> <ep no. 2> …<ep no. N>"
							[ $gap_size -eq $_gr_size ] \
								&& local groups_that_fill_entire_gap[${#groups_that_fill_entire_gap[@]}]="$j;${_eps:-$EP}" \
								|| local groups_that_fill_gap_partly[${#groups_that_fill_gap_partly[@]}]="$j;${_eps:-$EP}"
						}
					done
					[ -v D ] && {
						header="Index   Group index   Episodes that fill the gap   Fills entirely?"
						unset header_put
						for ((j=0; j<${#groups_that_fill_entire_gap[@]}; j++)); do
							[ $j -eq 0 ] && echo -e "\n\n        $header\n        ${header//[^ ]/—}" && local header_put=t
							echo -e "        $j   ${groups_that_fill_entire_gap[j]%;*}   ${groups_that_fill_entire_gap[j]#*;}   YES"
						done | column -o ' ' -s '   ' -t  >>$dbg_file
						for ((j=0; j<${#groups_that_fill_gap_partly[@]}; j++)); do
							[ $j -eq 0 -a ! -v header_put ] && echo -e "    $header\n    ${header//[^ ]/—}"
							echo -e "        $j   ${groups_that_fill_gap_partly[j]%;*}   ${groups_that_fill_gap_partly[j]#*;}   NO"
						done | column -o ' ' -s '   ' -t  >>$dbg_file
						echo >>$dbg_file
					}
					if [ ${#groups_that_fill_entire_gap[@]} -gt 1 ]; then
						echo -e "\t\tToo many candidates for the gap ${gap[i]}." >>$dbg_file
					elif [ ${#groups_that_fill_entire_gap[@]} -eq 1 ]; then
						# Now we can tell how many groups are pretending to fill this gap,
						#   and we can check, if the only one to do that is a group of single item,
						#   which ‘L#’ can be finally replaced with actual episode number.
						[ -v D ] && echo -e "\t\tThere is only one group (idx:${groups_that_fill_entire_gap[0]%;*}) that fills entire gap." >>$dbg_file
						[[ "${groups_that_fill_entire_gap[0]#*;}" =~ ^[0-9]+$ ]] && {
							VIDITEM_EPNUMBER[${groups_borders[${groups_that_fill_entire_gap[0]%;*}]%;*}-1]=$gap_end
							[ -v D ] && echo -e "\t\tSince this is group of a single item, assigning VIDITEM_EPNUMBER[$((${groups_borders[${groups_that_fill_entire_gap[0]%;*}]%;*}-1))] episode ‘$gap_end’." >>$dbg_file
						}
						queue_create ${groups_borders[${groups_that_fill_entire_gap[0]%;*}]//;/ } $gap_start
						[ -v D ] && echo -e "\t\tAdding queue start/end/dest: ${groups_borders[${groups_that_fill_entire_gap[0]%;*}]//;/ } $gap_start." >>$dbg_file
						local gap_filled=t
					elif [ ${#groups_that_fill_gap_partly[@]} -ne 0 ]; then
						# Damn, this is going deeper and deeper >_>
						# Actually, this part must be much longer, deeper and tougher,
						#   but I’m not looking forward to implementing recursive calls
						#   for finding all possible permutations with variable N
						#   and checks for same sets. It’s 24 for 4! and recursive calls
						#   always slower than those where a finite number is known.
						# So, we’ll make it working for the simplest and, probably,
						#   the closest case for the real life—when a directory contains
						#   hodgepodge, but the files represent one and only sequence.
						# With a minimal check, of course…

						# Resorting this array to bring first episodes of its
						#   items in order.
						# In bash, it’s okey to start from 1—if there’s no such
						#   item, cycle won’t start, but in other languages…
#set -x
						for ((j=0; j<${#groups_that_fill_gap_partly[@]}-1; j++)); do
							for ((k=j+1; k<${#groups_that_fill_gap_partly[@]}; k++)); do
								local _this_gr_1st_ep=${groups_that_fill_gap_partly[k]#*;} \
									_prev_gr_1st_ep=${groups_that_fill_gap_partly[j]#*;}
								local _this_gr_1st_ep=${_this_gr_1st_ep%% *} \
									_prev_gr_1st_ep=${_prev_gr_1st_ep%% *}
								# What if they’re equal? Maybe put the bigger one to the top?
								[ $_prev_gr_1st_ep -gt $_this_gr_1st_ep ] && {
									local buffer=${groups_that_fill_gap_partly[j]}
									groups_that_fill_gap_partly[j]=${groups_that_fill_gap_partly[k]}
									groups_that_fill_gap_partly[k]=$buffer
								}
							done
						done
#set +x
						[ -v D ] && {
							echo -e "\t\tTrying to fill the gap from parts (resorted array):" >>$dbg_file
							header="Index   Group index   Episodes" # Episodes here ≠ group_matches[N]
							for ((j=0; j<${#groups_that_fill_gap_partly[@]}; j++)); do
								[ $j -eq 0 ] && echo -e "        $header\n        ${header//[^ ]/—}"
								echo "        $j   ${groups_that_fill_gap_partly[j]%;*}   ${groups_that_fill_gap_partly[j]#*;}"
							done | column -o ' ' -s '   ' -t  >>$dbg_file
						}
						local lines_filled_with_parts=0
						unset _old_gr_end_ep # cause we’ll rely upon it in the following cycle
						for ((j=0; j<${#groups_that_fill_gap_partly[@]}; j++)); do
							[ $j -gt 0 ] && {
								_this_gr_1st_ep=${groups_that_fill_gap_partly[j]#*;}
								_this_gr_1st_ep=${_this_gr_1st_ep%% *}
								[ -v D ] && echo -en "\t\t\tGroup $j starts with episode $_this_gr_1st_ep, while previous group have ended at $_old_gr_ending_ep.\n\t\t\tDoes current group suit us?" >>$dbg_file
								[ $_this_gr_1st_ep -le $_old_gr_ending_ep ] && {
									[ -v D ] && echo -e "\tNO." >>$dbg_file
									continue
								}
								[ -v D ] && echo -e "\tYES." >>$dbg_file
							}
							local _gr_index=${groups_that_fill_gap_partly[j]%;*}
							local _gr_start=${groups_borders[_gr_index]%;*} \
								_gr_end=${groups_borders[_gr_index]#*;}
							local _gr_size=$((_gr_end - _gr_start + 1))
							[ -v D ] && {
								echo -e "\t\t\tIdx:$j. Group $_gr_index of size $_gr_size starts at line $_gr_start and ends at $_gr_end." >>$dbg_file
								echo -e "\t\t\tAdding to queue: $_gr_start $_gr_end $((gap_start + lines_filled_with_parts))." >>$dbg_file
							}
							queue_create $_gr_start $_gr_end $((gap_start + lines_filled_with_parts))
							let lines_filled_with_parts+=_gr_size
							[ -v D ] && echo -e "\t\tVolume of the gap filled so far: $lines_filled_with_parts/$gap_size." >>$dbg_file
							[ $_gr_size -eq 1 ] && {
								VIDITEM_EPNUMBER[${groups_borders[_gr_index]%;*}-1]=${groups_that_fill_gap_partly[j]#*;}
								[ -v D ] && echo -e "\t\t\tSince this is group of a single item, assigning VIDITEM_EPNUMBER[$((${groups_borders[_gr_index]%;*}-1))] episode number ${groups_that_fill_gap_partly[j]#*;}." >>$dbg_file
								local _old_gr_ending_ep=${groups_that_fill_gap_partly[j]#*;}
							}|| local _old_gr_ending_ep=${groups_that_fill_gap_partly[j]##* }
							local gap_partly_filled=t
						done
					fi
					[ -v gap_filled ] && {
						let sum_of_gaps+=gap_size
						[ -v D ] && echo -e "\tGap filled ENTIRELY. Total episodes filled in gaps: $sum_of_gaps." >>$dbg_file
					}
					[ -v gap_partly_filled ] && {
						let sum_of_gaps+=lines_filled_with_parts
						[ -v D ] && echo -e "\tGap is considered to be filled ONLY PARTIALLY. Total episodes filled in gaps: $sum_of_gaps." >>$dbg_file
					}
				done
				let bottom_line+=sum_of_gaps
				[ -v D ] && echo -e "\n\tAll gaps filled. Bottom line is now $bottom_line.\n" >>$dbg_file

				# 5. Searching for continuation.
				next_group_must_start_with=$((VIDITEM_EPNUMBER[gr_end-1]+1))
				[ -v D ] && {
					echo -e "\n\nNext group is expected to start with $next_group_must_start_with episode." >>$dbg_file
					echo -en "\tSearching for a suitable group… " >>$dbg_file
				}
				for ((i=0; i<${#groups_borders[@]}; i++)); do
					local _gr_start=${groups_borders[i]%;*} \
						_gr_end=${groups_borders[i]#*;}
					local _gr_size=$((_gr_end - _gr_start + 1))
					[ $_gr_start -lt $total_items_count ] && {
						unset EP
						retrieve_single_group_epnumber $i $next_group_must_start_with \
							&& [ ${VIDITEM_EPNUMBER[_gr_start-1]} -eq $next_group_must_start_with ] && {
							# 5. Adding group for continuation.
							[ -v D ] && echo -e "Looks like group $i fits." >>$dbg_file
							there_is_a_group_to_supplement=$i
							groups_borders[i]="$((total_items_count+1));$((total_items_count+1))" # used.
							[ -v D ] && echo -e "\tAdding queue ${groups_borders[i]//;/ } $((bottom_line+1))" >>$dbg_file
							queue_create ${groups_borders[i]//;/ } $((bottom_line+1))
						}
					}
				done
				[ -v D -a ! -v there_is_a_group_to_supplement ] && echo -e "None was found." >>$dbg_file

				# 6. Running the queue
				test_queue_for_intersections || return $?
				rearrange_list_items
				# Fixing group_borders[@] elements, that probably have become skewed.
				#  (increasing groups borders that are between new bottom and the next
				#   group by the amount of items we have incorparated).
				for ((i=0; i<${#groups_borders[@]}; i++)); do
					_gr_start=${groups_borders[i]%;*}
					_gr_end=${groups_borders[i]#*;}
					[ $_gr_start -lt $total_items_count -a $_gr_end -lt $total_items_count ] && {
						# We assign initial group size at the beginning of the while cycle,
						#   so we can’t add next group size to bottom line after finding it.
						_bottom_line=$((bottom_line + _gr_size))
						[ $_gr_end -le $_bottom_line -o $_gr_start -gt $_bottom_line ] && continue
						let _gr_start+=sum_of_gaps
						let _gr_end+=sum_of_gaps
						groups_borders[i]="$_gr_start;$_gr_end"
					}
				done
				[ $bottom_line -eq $total_items_count ] && break
			done # while there_is_a_group_to_supplement
		} # if HEU_LVL = 2
	} # [ -v MANUAL_REARRANGEMENT ] && { … }||{ …

	# Fixing leftover L# numbers that possibly may be skewed now.
	for ((i=0; i<${#VIDITEM_EPNUMBER[@]}; i++)); do
		[ "${VIDITEM_EPNUMBER[i]/L*/}" ] || VIDITEM_EPNUMBER[i]=L$((i+1))
	done

	[ -v D ] && {
		echo -e "\n\nResulting VIDITEM_* arrays:" >>$dbg_file
		header="Index   File   GID   Episode number"
		for ((i=0; i<total_items_count; i++)); do
			[ $i -eq 0 ] && echo -e "$header\n${header//[^ ]/—}"
			echo "$i   ${VIDITEM_FILE[i]}   ${VIDITEM_GID[i]}   ${VIDITEM_EPNUMBER[i]}"
		done | column -o ' ' -s '   ' -t  >>$dbg_file
		echo -e "\n\n\n    ----- Exiting from build_the_list ------------------------------------------\n\n\n" >>$dbg_file
	}

	# Composing new LIST_TO_CHOOSE_FROM to return to choose_from()
	unset LIST_TO_CHOOSE_FROM
	for ((i=0; i<total_items_count; i++)); do
	   printf "${g}%*d:${s}" ${#total_items_count} $((i+1))
		[ -v manual_rearrangement_was_in_effect -o $HEURISTICS_LEVEL -gt 1 ] \
			|| echo -en "${list_indicators[i]}"
		local pattern=${pat_for_grep[${VIDITEM_GID[i]}]}
		# If the match is unique, i.e. pattern is equal to the match itself,
		#   restrain grep from highlighting the whole string.
		[ $HEURISTICS_LEVEL -lt 2 ] && {
			[ "`grep -oG "$pattern"<<<"${VIDITEM_FILE[i]}"`" = "${VIDITEM_FILE[i]}" ] \
				&& echo "${VIDITEM_FILE[i]}" | grep -iG "\($KEYWORD\|${VIDITEM_EPNUMBER[i]}\)" \
				|| echo "${VIDITEM_FILE[i]}" | grep -iG "$pattern"
			:
		}|| echo "${VIDITEM_FILE[i]}"
		LIST_TO_CHOOSE_FROM="${LIST_TO_CHOOSE_FROM:+$LIST_TO_CHOOSE_FROM\n}${VIDITEM_FILE[i]}"
	done
	return 0
}

## Functions below this line never execute during `do_initial_search`

# EXPECTS:
#     SCREENSHOT_DIR — be unset, set by -S|--screenshot-dir or by evaling
#         journal entry.
#     KEYWORD — set, non-empty string
# ALTERS:
#     SCREENSHOT_DIR — path where pushd to, so the player  will store taken
#         screenshots there.
# EXIT_CODES:
#     0 if ok,
#    “scrdir_isnt_writeable”, “cant_create_scrdir” in case
#     of insufficient rights to access $SCREENSHOT_DIR.
screenshots_preprocessing() {
	[ -v SCREENSHOT_DIR ] && {
		grep -qi${FIXED_STRING:-G} "$KEYWORD" <<<"${SCREENSHOT_DIR##*\/}" ||{
			local screens_path=`find -L "$SCREENSHOT_DIR" -maxdepth 1 -type d $KEYWORD_FIND_PATTERNS -printf "%f\n"`
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
						[ -w "$SCREENSHOT_DIR" ] && [ -x "$SCREENSHOT_DIR" ] || return `err scrdir_isnt_writeable`
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
						# eval mkdir -pm775 "\"${SCREENSHOT_DIR// /\ }/${SCREENSHOT_DIR_SKEL:+{${SCREENSHOT_DIR_SKEL// /\ }}}\"" || return `err cant_create_scrdir`
						for folder in '' ${SCREENSHOT_DIR_SKEL//,/ }; do
							mkdir -m775 "$SCREENSHOT_DIR/$folder" || return `err cant_create_scrdir`
						done
					}
				}|| unset SCREENSHOT_DIR
			fi
		}
	}
	[ -d "$SCREENSHOT_DIR" ] \
		&& pushd "$SCREENSHOT_DIR" >/dev/null \
		||{
			SCREENSHOT_DIR='.'
			msg 'Current directory is about to hold screenshots.'
		}
	screendir_timestamp=`date +%s`
	return 0
}

# EXPECTS:
#     MODE — set and be one of 'single', 'episodes' or 'dvd' strings.
#     IT_IS_NEXT_ITERATION — set only when execution is on the next iteration
#         of `until` cycle, or it was resumed after interruption, i.e. RESUME,
#         and therefore IT_IS_NEXT_ITERATION, is set.
#     RUN_IN_CYCLE — set only if script was called with -c or -r option.
#     RESUME_AND_REPLAY (aka INTERRUPTED) — set if previous run of the player
#         in resumed session was interrupted in the middle of playing a file
#         by <q>, <Esc>, SIGKILL etc.
# SETS:
#     findpath — where to search for additional files (subtitles, audiotracks
#         etc.)
#     VIDEO_NUMBER — line number from the list of VIDEOFILES.
#     VIDEOFILE — videofile that will be playing, must be unset to play a disk
#         as a disk.
#     CLEAN_EP_NUMBER — EP_NUMBER[VIDEO_NUMBER-1] with L and ? removed.
#         Used in search for other files.
#     INTERRUPTED — used in “resume” case, means episode wasn’t watched till
#         the end and must be replayed on resume.
#     STOP — if the player was interrupted by key, that stops the cycle too.
# RETURNS:
#     0 if ok, >0 if internal function call returned an error.
watch() {
	case $MODE in
		single)
			[ -v LOOP ] && MPLAYER_OPTS+=" --loop-file=inf"
			;;
		episodes)
			MATCH_NUMBER=t
			# Add check for -L option limiting the number of
			#   sequentially playing files to LIMIT_SEQUNCE.
			# Add check to stop cycle when last episode finished?
			#   -e for “stop at the end”?
			if  [ -v IT_IS_NEXT_ITERATION ];  then
				# If playback was interrupted, play last watched episode
				#   once again, otherwise increment episode number and play
				#   the next one otherwise.
				[ -v RESUME_AND_REPLAY ] || let VIDEO_NUMBER++
				[ -v RESUME_FROM_PREVIOUS ] && {
					[ $VIDEO_NUMBER -gt 0 ] \
						&& let VIDEO_NUMBER-- \
						|| VIDEO_NUMBER=$VIDEOFILES_COUNT
				}
				unset RESUME_AND_REPLAY RESUME_FROM_PREVIOUS
				VIDEOFILE=`echo -e "$VIDEOFILES" | sed -n "$VIDEO_NUMBER p"`
			else
				# The beginning of watching cycle
				[ `echo "$VIDEOFILES" | wc -l` -gt 1 ] && {
					choose_from "$VIDEOFILES" || return $?
					VIDEOFILES="$LIST_TO_CHOOSE_FROM" # now rearranged
					VIDEOFILES_COUNT="$LIST_ITEMS_COUNT"
					VIDEOFILE="$CHOSEN_ITEM"
					VIDEO_NUMBER=$CHOSEN_NUMBER
					[ -v LIMIT_WATCHING_TO ] \
						&& EXIT_AFTER_THIS_EPISODE=$((VIDEO_NUMBER+3))
					[ -v VIDITEM_EPNUMBER ] \
						&& EP_NUMBERS=("${VIDITEM_EPNUMBER[@]}") \
						|| readarray -t EP_NUMBERS < <(seq -f "L%g" 1 $VIDEOFILES_COUNT)
				}||{ # Eeeeh? One videofile in episodes mode?
					[ -v RUN_IN_CYCLE ] && {
						warn 'Cannot start watching cycle: only one video file.'
						unset RUN_IN_CYCLE
					}
					# Just in case the rules for single videofiles may be bypassed
					warn 'There was only 1 file for episodes mode. Please report a bug.'
				}
			fi
			CLEAN_EP_NUMBER=${EP_NUMBERS[VIDEO_NUMBER-1]#L}
			CLEAN_EP_NUMBER=${CLEAN_EP_NUMBER%?}
			[ -v SUB_DELAY ] && MPLAYER_OPTS+=" $dashes${mp_opts[sub-delay]}=$SUB_DELAY"
			[ -v AUDIO_DELAY ] && MPLAYER_OPTS+=" $dashes${mp_opts[audio-delay]}=$AUDIO_DELAY"
			[ -v REMEMBER_SUB_AND_AUDIO_DELAY ] && MPLAYER_OPTS+=" --write-filename-in-watch-later-config"
			;;
		dvd|bd)
			local device protocol
			unset VIDEOFILE
			if [ $MODE = dvd ]; then
				[ -v DVD_BD_NAV ] && protocol=dvdnav || protocol=dvd
				device='dvd-device'
			else
				# bdnav is only supported by the mpv mplayer.
				[ -v DVD_BD_NAV ] && protocol=bdnav || protocol=${mp_opts[bd-protocol]}
				device='bluray-device'
			fi

			# Replace it with MPLAYER_OPTS+=" ${dashes}profile protocol.$protocol"
			#   when rejecting mplayer and mplayer2.
			if $MPLAYER_COMMAND ${dashes}profile help \
				|& grep -q "\<protocol.$protocol\>" ; then
				MPLAYER_OPTS=`echo "$MPLAYER_OPTS" \
				    | sed "s/${dashes}profile[= ]^\S+/&,protocol.$protocol/;T;Q1"`
				[ $? -eq 0 ] && \
					MPLAYER_OPTS+=" ${dashes}profile protocol.$protocol"
			else
				warn "$MPLAYER_COMMAND config doesn’t have profile “protocol.$protocol” set."
			fi
			MPLAYER_OPTS+=" $protocol:// ${dashes}$device "
			;;
	esac

	## From now on, no more exits (except errors during the export to journal).
	[ $MODE = single -o $MODE = episodes ] && {
		[ "$SUBFOLDERS" ] || SUBFOLDERS='/'
		# Subtitles
		get_other_files "srt ass sub ssa" || return $?
		subtitles="$OTHER_FILES_LIST"
		findpath="$BASEPATH${FIRST_MATCH:-}${SUBFOLDERS:-}"
		[ "$subtitles" ] && {
			[ -v COMPAT ] && { # subtitles in one line, --sub file1,file2,…fileN
				# Because MPlayer’s syntax for subtitles is "-sub file1,file2"
				#   we must escape commas in path and file names.
				findpath="${findpath//,/\\\,}"
				subtitles="${subtitles//,/\,}"
				subtitles=`echo "$subtitles" | sed -r " # Here we combine all subtitles in one line.
				1s/^/$(escape_for_sed_replacement "$findpath")/  # Padding 1st sub file with path.
				:loop  # For every next line
				    N; s/\n/,$(escape_for_sed_replacement "$findpath")/;  # …append its line to pattern space
				    # …and replace newline between those lines with a comma
				    # …and path that goes for the second file (after \n).
				    t loop  # Successful replace → goto loop."`
				subtitles="${dashes}${mp_opts[sub-file]} \"$subtitles\""
			}||{ # each subtitle file passed with the key --sub file1 --sub file2 etc.
				subtitles=`echo "$subtitles" | sed -r "s/.*/--sub-file='$(escape_for_sed_replacement "$findpath")&'/g"` # '…'"$findpath"'…'
			}
		}
		# Soundtracks
		# NB: old format of passing files via comma is broken in latest MPlayer,
		#     only one file can be passed through -audiofile. Multiple -audiofile
		#     options are ignored except the last one. The same goes for mpv-0.3.x
		#     but it was fixed in git version, where multilpe -audio-file options
		#     are allowed and work.
		get_other_files "mka dst ac3" || return $?
		tracks="${OTHER_FILES_LIST}"
		[ "$tracks" ] && {
			if  [ -v COMPAT ];  then
				[ "`sed -n '$=' <<<"$OTHER_FILES_LIST"`" -gt 1 ] \
					&& warn 'Multiple external tracks were found, but only the last one can be loaded.
Consider switching to the latest mpv if you want to load multiple tracks
  at once.'
				# tracks="${OTHER_FILES_LIST// /\\\ }"
				tracks=`sed -n "$ s/.*/${dashes}${mp_opts[audio-file]} '$(escape_for_sed_replacement "$findpath")&'/p" <<<"$tracks"`
			else  tracks=`sed -r "s/.*/--audio-file='$(escape_for_sed_replacement "$findpath")&'/g" <<<"$tracks"`;  fi
		}
	} # MODE = single -o $MODE = episodes

	# Path explanation
	#
	# <BASEPATH> <FIRST_MATCH> [ <SUBFOLDERS> [VIDEOFILE] ]
	#             ^^^^^^^^^^^                  ^^^^^^^^^
	# The matched parts of the path may be ending ones.
	# As of possible cases:
	# 1. Single VIDEOFILE in BASEPATH
	# /home/video/  MononokeHime.mkv
	# BASEPATH      VIDEOFILE
	#
	# 2. Videofile inside of a folder found in BASEPATH
	# /home/video/  Azumanga_Daioh       /           Azumanga_Daioh_01.mkv
	# BASEPATH      FIRST_MATCH          SUBFOLDERS  VIDEOFILE
	#
	# 3. Videofile found inside of a subfolder under the folder found in BASEPATH
	# /home/video/  Exosquad             /Season_1/  Exosquad_01.mkv
	# BASEPATH      FIRST_MATCH          SUBFOLDERS  VIDEOFILE
	#
	# 4.a. The same goes for videofiles in VIDEO_TS folder, when option IGNORE_DISKS is set.
	# /home/video/  Zeta_Project_Disk_1  /VIDEO_TS/  VTS_04_01.VOB
	# BASEPATH      FIRST_MATCH          SUBFOLDERS  VIDEOFILE
	#
	# 4.b. If IGNORE_DISKS is not present, then the folder containing disk stuff
	#      and matched KEYWORD becomes the path.
	# /home/video/  Zeta_Project_Disk_1
	# BASEPATH      FIRST_MATCH
	#
	# NB: FIRST_MATCH never has surrounding slashes. Neither in front nor behind.
	#     VIDEOFILE never has a slash in front of it.
	#
	# If something is still not clear enough, here are the rules:
	#
	#    part     |         whether it can be
	#  of a path  |  a folder    a file   not present
	# ------------+-----------------------------------
	# BASEPATH    |     ✔           ✘          ✘
	# FIRST_MATCH |     ✔           ✔          ✘
	# SUBFOLDERS  |     ✔           ✘          ✔
	# VIDEOFILE   |     ✘           ✔          ✔

	local path_to_videofile="$BASEPATH$FIRST_MATCH${SUBFOLDERS:-}${VIDEOFILE:-}"
	[ -v D ] && dbg_file="$DEBUG_DIR/mpv_run"
	[ -v TASKSET_OPTS ] \
		&& which taskset >/dev/null \
		&& taskset_cmd="taskset $TASKSET_OPTS"
	[ -v IONICE_OPTS ] \
		&& which ionice >/dev/null \
		&& ionice_cmd="ionice $IONICE_OPTS"
	# $MPLAYER_OPTS must be right before path because of protocol:// things
	# --msg-level=all=info because coproc will make mpv spam its status line.
	{ coproc \
		{ eval ${ionice_cmd:-} ${taskset_cmd:-} $MPLAYER_COMMAND  ${subtitles:-} ${tracks:-} \
			--msg-level=all=info "$MPLAYER_OPTS" "\"$path_to_videofile\"" \
			|& sed '$s/End of file/&/p;T;Q1' # Thank God we have sed…
		} >&3
	} 3>&1 # let mpv’s output flow to the stdout.
	local mpvsed_pipe_pid=$!
	[ -v REMEMBER_SUB_AND_AUDIO_DELAY ] && [ ! -v COMPAT -a "$MODE" = episodes ] && {
		if which inotifywait pkill &>/dev/null; then
			local config \
				watch_later="$HOME/.mpv/watch_later"
			local inotifywait_cmd="inotifywait -q --monitor --format %f -e modify $watch_later"
			while true; do
				sleep 1
				[ -e /proc/$mpvsed_pipe_pid ] || {
					[ -v D ] && {
						echo "Trying to kill “$inotifywait_cmd” with session id $PPID." >>$dbg_file
						ps -Ao session,ppid,pid,cmd,start,user | grep -v grep \
							| grep -E "($PPID|${0##*/}|inotifywait)" >>$dbg_file
					}
					pkill -13 --session $PPID -xf "$inotifywait_cmd" # SIGPIPE to suppress the message.
					break
				}
			done &
			while IFS= read -r config; do
				if [ "`sed -nr '1s/^#\s(.*)$/\1/p' "$watch_later/$config"`" -ef "$path_to_videofile" ];  then
					# The user must have run write_watch_later_config from mpv.
					# Would it be good to sleep here for 3 seconds and not spam
					#   about found delays while the user shifts them to, say,
					#   from zero to 20000, or it may lead to confusion?
					[ -v D ] && echo "$config changed in $watch_later\!" >>$dbg_file
					local _sub_delay="`sed -nr 's/^sub-delay=(.*)$/\1/p' "$watch_later/$config"`"
					[ "$_sub_delay" -a "$_sub_delay" != "$SUB_DELAY" ] && {
						SUB_DELAY="$_sub_delay"
						msg "${0##*/}: remembering sub-delay=$SUB_DELAY"
					}
					local _audio_delay="`sed -nr 's/^audio-delay=(.*)$/\1/p' "$watch_later/$config"`"
					[ "$_audio_delay" -a "$_audio_delay" != "$AUDIO_DELAY" ] && {
						AUDIO_DELAY="$_audio_delay"
						msg "${0##*/}: remembering audio-delay=$AUDIO_DELAY"
					}
				else [ -v D ] && echo 'Something changed, but that wasn’t our file.' >>$dbg_file;  fi
			done < <($inotifywait_cmd)
		else
			warn 'For --remember-sub-and-audio-delay inotifywait and pkill are required!'
		fi
	}
	wait $mpvsed_pipe_pid && {
		# Should I make a test case and parse the last line for known exit
		#   messages and ask what to do if none were found? It matters
		#   when mpv output changes if verbosity level was increased from default.
		INTERRUPTED=t
		STOP=t
	}
	WE_HAVE_BEEN_IN_WATCH_FUNC=t # for export_session_data()
	return 0
}

# EXPECTS:
#     findpath — where to search for additional files (subtitles, audiotracks etc.)
#     VIDEOFILE – exact name match
#     KEYWORD — set, non-empty string
#     MATCH_NUMBER — set if called with -n, -a.
# TAKES:
#     $1 — non-empty string with a list of extensions to match agaist, must be
#         separated by space and contain no trailing space, like "abc def ghi"
# SETS:
#     OTHER_FILES_LIST — list of files that reside in findpath, match by extension to what
#         was through $1 passed and all collected match_* rules
# RETURNS:
#     0 if ok, >0 if internal function call returned an error.
get_other_files() {
	local matchext="$1"
	unset match_by_keyword_and_num match_by_num
	# W! This asterisk in the line below is under shell pathname expansion.
	local ext=`echo "$matchext" | sed -r 's/\s/ -o /g; s^([a-zA-Z0-9_-]{3,})^-iname *.\1^g'`
	local found_other_files=`find -L "$BASEPATH${FIRST_MATCH:-}${SUBFOLDERS:-}" -maxdepth 1 -type f \( $ext \) -printf "%f\n"`
	local match_by_name=`echo "$found_other_files" | grep -Fi "${VIDEOFILE%.*}" | sort`
	OTHER_FILES_LIST="$match_by_name" # exact name
	# TODO: This is the only place where KEYWORD is used as a fixed string.
	#       Need to replace KEYWORD with two variables
	#       KEYWORD_FOR_FIND with space substituted with “?” and
	#       KEYWORD_FOR_GREP with space replaced with “.”.
	#       Also either escape special symbols in KEYWORD, or somehow
	#       check UNICODE symbol class to be letter/hieroglyph.
	local match_by_keyword=`echo "$found_other_files" | grep -i -${FIXED_STRING:-G} "$KEYWORD" | sort`
	[ -v D ] && {
		dbg_file="$DEBUG_DIR/other_files"
		declare -p ext found_other_files match_by_name >>$dbg_file
	}
	[ $MODE = episodes ] && {
		# This must be a very thorough check,
		#    but that‘s all we can afford right now.                                EP               20               v2
		local match_by_keyword_and_num=`echo "$match_by_keyword" | grep -E "[^0-9a-oA-Oq-zQ-Z]$CLEAN_EP_NUMBER[^0-9a-uA-Uw-zW-Z]" | sort`
		# That’s no good                                                    ^^^^^^^^^^^^^^^^^^                ^^^^^^^^^^^^^^^^^^
		# Shoulda check whether the group_number_at_the_beginning[VIDEO_NUMBER-1] or group_number_at_the_end[VIDEO_NUMBER-1] were set.
		OTHER_FILES_LIST="${OTHER_FILES_LIST:+${OTHER_FILES_LIST}\n}$match_by_keyword_and_num"
		local match_by_num=`echo "$found_other_files" | grep -E "[^0-9]$CLEAN_EP_NUMBER[^0-9]" | sort`
		[ -v D ] && {
			echo -e "\nEpisodes: AYE.\nother_files == exact_name + keyword_and_number\n" >>$dbg_file
			declare -p match_by_keyword_and_num match_by_num >>$dbg_file
		}
	}
	# For subtitles that must be picked, but all what they have in common
	#   with corresponding files is episode number. I.e if subs are named
	#   with only number like 01.srt or the video is named in English tran-
	#   scription, while downloaded subs are in native language with hie-
	#   roglyphs.
	[ -v MATCH_ALL -o -v MATCH_NUMBER ] \
		&& OTHER_FILES_LIST="${OTHER_FILES_LIST:+${OTHER_FILES_LIST}\n}${match_by_num:-}"
	# Including files matching by keyword in search results requires MATCH_ALL
	#   to be set, because in case of lots of files matching that keyword many
	#   other unnecessary may be included (e.g. subtitles to 20 episodes). But,
	#   in case of the file is a single, in gives some confidence that there are
	#   not many other files, at least, not that much like in previous case.
	[ -v MATCH_ALL -o $MODE = single ] \
		&& OTHER_FILES_LIST="${OTHER_FILES_LIST:+${OTHER_FILES_LIST}\n}$match_by_keyword"
	# Remove duplicates and empty lines
	OTHER_FILES_LIST=`echo -e "$OTHER_FILES_LIST" \
	                  | sed -nr 'G; s/\n/&&/; /^([[:print:]]*\n).*\n\1/d; s/\n//; h; P'`
	[ -v D ] && declare -p OTHER_FILES_LIST >>$dbg_file
	return 0
}

# EXPECTS:
#     SCREENSHOT_DIR — if set, then we should be in screenshot directory
#         and therefore, will be popd’d later inside of the trap.
#     *.png — screenshots taken.
# RETURNS:
#     0 if the function processed screenshots, 1 if not. This is needed
#     to distinguish cases when it did the job and when it didn’t to avoid
#     printing last shown episode number twice.
screenshots_postprocessing() {
	# Seeking screenshots
	[ -d "$SCREENSHOT_DIR" ] && {
		compress_screenshot() {
			local shot="$1"
			[ -v pngcrush ] && {
				# In place overwriting wasn’t supposed to run under parallel.
				# Should check how to run optipng some day.
				pngcrush -reduce "$shot" "/tmp/$shot"
				mv "/tmp/$shot" "$shot"
			}
			[ -v JPEG_COMPRESSION ] && [ -v pngtopbm ] && [ -v cjpeg ] && {
				$pngtopbm "$shot" 2>/dev/null \
					| cjpeg -quality $JPEG_COMPRESSION -progressive \
					 -outfile "${shot%.*}.jpg" &>/dev/null
				rm "$shot"
			}
		}

		local new_screenshots=`find "$SCREENSHOT_DIR" -maxdepth 1 \
		                      -type f -iname "*.png" \
		                      -newermt @$screendir_timestamp -printf "%f\n"`
		[ "$new_screenshots" ] && {
			if which parallel &>/dev/null; then
				# Exporting the function doing the job to the environment,
				#   so it would be available in the subshell. Also doing `which`
				#   here, so the function wouldn’t call it each time.
				export -f compress_screenshot
				export JPEG_COMPRESSION # if unset, then not exported
				which pngcrush &>/dev/null && export pngcrush=t
				# pngtopnm is old binary and as far as I know it is removed
				#   from the upstream package, but symlinked to pngtopam in
				#   many distributives. Except debean >_>
				which pngtopnm &>/dev/null && export pngtopbm=pngtopnm
				# Modern distrubutives won’t use symlink, Debean won’t get
				#   an inexisting binary.
				which pngtopam &>/dev/null && export pngtopbm=pngtopam
				which cjpeg &>/dev/null && export cjpeg=t
				echo -e "$new_screenshots" | ${taskset_cmd:-} parallel --eta compress_screenshot
				export -nf compress_screenshot
			else
				cpu_cores=`grep -c processor /proc/cpuinfo`
				[[ "$cpu_cores" =~ ^[0-9]+$ && "$cpu_cores" -gt 1 ]] \
					&& warn 'No parallel was found. Using 1 CPU core.'
				for shot in $new_screenshots; do
					${taskset_cmd:-} compress_screenshot "$shot"
				done
			fi
		}
	}
	return  $((1-0${new_screenshots:+1}))
}

# EXPECTS:
#     ~/.watch.sh/journal to exist and contain at least one \n (for sed).
# EXIT CODES:
#     0 if OK, “no_such_keyword_in_journal”, “not_enough_data_to_restore”.
import_session_data() {
	[ -v NO_JOURNAL ] || {
		# Checking journal version
		local j_ver=`sed -nr '1 s/.*v([0-9]+)$/\1/p' $JOURNAL` start_line=3
		[[ "$j_ver" =~ ^[0-9]+$ ]] && [ $j_ver -ge $JOURNAL_MINVER ] || {
			warn "The journal version ($j_ver) is incompatibe with current watch.sh version ($VERSION)."
		}
		[ "`stat --format='%s' $JOURNAL`" -gt 1 ] && {
			if [ "$KEYWORD" ]; then
				# KEYWORD present, search among entries in the journal
				# We can’t pass exiot code from sed to eval, since eval’s
				#   exit code is the result of what it _executes_, and it
				#   executes either an empty string, if sed found nothing
				#  (=instant 0), or some variable assignment VAR='value',
				#   that will most probably result in 0 return value.
				#   So add some assignment that will tell us we found nothing :D
				eval "`sed -n "/^KEYWORD='$(escape_for_sed_pattern "$KEYWORD")'/,/^$/ {
				               s/^declare/declare -g/; p; /^$/ Q0 }; $ Q1 # Force global namespace—we’re inside function." \
				       $JOURNAL 2>/dev/null || echo local no_such_keyword=t`"
			else	# KEYWORD is not given, take 1st one from the journal
				# If this is the old style journal without header, start with 1st line.
				sed -rn '1s/^# watch.sh journal v[0-9]+$/&/;T;Q1' $JOURNAL && start_line=1
				eval "$(sed -n "$start_line,/^$/ {
				               s/^declare/declare -g/; p } # Force global namespace—we’re inside function." \
				$JOURNAL 2>/dev/null || echo local no_such_keyword=t)"
			fi

			[ -v no_such_keyword ] && return `err no_such_keyword_in_journal`

			check_required_vars() {
				local var
				for var in $@; do
					[ -v $var ] || {
						not_found_vars="${not_found_vars:+$not_found_vars }$var"
						not_enough_data=t
					}
				done
			}

			# Nothing bad will happen if SCREENSHOT_DIR won’t be set.
			check_required_vars 'BASEPATH' 'FIRST_MATCH' 'FIXED_STRING' 'KEYWORD' 'KEYWORD_FIND_PATTERNS' 'MODE' 'SUBFOLDERS'
			[ "$MODE" = single ] \
				&& check_required_vars 'VIDEOFILE'
			[ "$MODE" = episodes ] \
				&& check_required_vars 'VIDEOFILES' 'VIDEO_NUMBER' 'EP_NUMBERS' 'INTERRUPTED' 'REMEMBER_SUB_AND_AUDIO_DELAY'
		}
		[ -v not_enough_data ] && return `err not_enough_data_to_restore`
		# Yes, it could be just one variable, but with two names, its purpose
		#   is clearer, hence easier to understand at both stages. Moreover,
		#   INTERRUPTED can’t be used to launch “until” cycle with “watch”
		#   function.
		[ "$INTERRUPTED" = t ] && RESUME_AND_REPLAY=t
		unset INTERRUPTED
		local var
		for var in 'FIXED_STRING' 'REMEMBER_SUB_AND_AUDIO_DELAY'; do
			[ "${!var}" = f ] && unset $var
		done
	}
	return 0
}

# TAKES:
#     $1 — string to prepare to be put in sed replacement string.
escape_for_sed_replacement() {
	# local str="$1" # as it was before 20140915
	# to cover issue with ' in file names, when it goes through the journal
	# NB  suited for export_session_data, for being read through eval in
	#     import_session_data
	local str=${1//\\/\\\\} # must be first
	str=${str//\'/\'\"\'\"\'} # glue: var='bla bl'a bla'  →  var='bla bl'"'"'a bla'
	str=${str//&/\\&}
	str=${str//\//\\/}
	# str=${str//\"/\\\"} # Just for the case if a bug will appear
	echo -en "$str"
}

# SETS:
#     SESSION_DATA_EXPORTED — to prevent this function running twice.
# EXIT_CODES:
#     0 if OK, “cant_retrieve_journal_size”,
#    “cant_compute_journal_max_size”, “cant_truncate_journal”.
export_session_data() {
	[ -v SESSION_DATA_EXPORTED -o ! -v WE_HAVE_BEEN_IN_WATCH_FUNC ] && return 0
	[ -v NO_JOURNAL ] || {
		local data videofiles_in_one_row j_size j_max_size
		data="KEYWORD='$(escape_for_sed_replacement "$KEYWORD")'"
		# [ -v T ] && data+="\nSTAMP=\\\"`date`\\\""
		data+="\nKEYWORD_FIND_PATTERNS='$(escape_for_sed_replacement "$KEYWORD_FIND_PATTERNS")'"
		data+="\nFIXED_STRING=${FIXED_STRING:-f}"
		data+="\nMODE='$MODE'"
		data+="\nBASEPATH='$(escape_for_sed_replacement "$BASEPATH")'"
		data+="\nFIRST_MATCH='$(escape_for_sed_replacement "$FIRST_MATCH")'" # Remember? No slashes here, “&” and “'” only
		data+="\nSUBFOLDERS='$(escape_for_sed_replacement "$SUBFOLDERS")'"
		[ $MODE = single ] \
			&& data+="\nVIDEOFILE='$(escape_for_sed_replacement "$VIDEOFILE")'"
		[ $MODE = episodes ] && {

			# I did think about serialization of VIDITEM_* arrays into journal
			#   and operating on them in watch() instead of introducing its own
			#   personal variables, but a test snippet doing this with items
			#   containing ' and " in their names has shown that it’s better
			#   to restrain from that. Though the output of retrieval, i.e.
			#   evaling declare directives back, could be considered satisfying—
			#   nothing was lost—there were disadvantages, that held me from
			#   implementing it here:
			#   1. Declare introduces another level of obscurity and quoting
			#      hell, that seems impossible to deal with having human sight.
			#   2. Output of eval returned error about not found matching double
			#      quote whenever ' or " happened to exist in array item values.
			#      It didn’t change the fact, that the results of retrieval were
			#      successful, but would require removal of eval result check,
			#      which may lead to unforseen consequences if the output
			#      of eval will be actually broken.
			#   3. It required another escaping procedure for the double quote
			#      in escape_for_sed_replacement().
			#   4. Any attempt to read the contents of journal by human would
			#      lead to brain explosion, while in present it’s easy to spot
			#      a missing symbol or error by unaided eye.
			# Ultimately, I came to conclusion that making a new set of vari-
			#   ables in watch() is not a bad idea, but a rather good one. It
			#   helps to differentiate between variables that exist on the first
			#   run and those that are used after RESUME.

			# NB extra backslash in sed replacement. It’s there because sed called in a subshell.
			videofiles_in_one_row="`echo -n "$(escape_for_sed_replacement "$VIDEOFILES")" | sed ':be N; s/\n/\\\n/g; b be'`"
			data+="\nVIDEOFILES='$videofiles_in_one_row'"
			data+="\nVIDEOFILES_COUNT=$VIDEOFILES_COUNT"
			data+="\nVIDEO_NUMBER=$VIDEO_NUMBER"
			data+="\n$(declare -p EP_NUMBERS)"
			data+="\nINTERRUPTED=${INTERRUPTED:-f}"
		}
		data+="\nSCREENSHOT_DIR='$(escape_for_sed_replacement "$SCREENSHOT_DIR")'"
		[ -v TASKSET_OPTS ] && data+="\nTASKSET_OPTS='$TASKSET_OPTS'"
		[ -v IONICE_OPTS ] && data+="\nIONICE_OPTS='$IONICE_OPTS'"
		[ -v EXIT_AFTER_THIS_EPISODE ] && data+="\nEXIT_AFTER_THIS_EPISODE='$EXIT_AFTER_THIS_EPISODE'"
		[ -v SUB_DELAY ] && data+="\nSUB_DELAY='$SUB_DELAY'"
		[ -v AUDIO_DELAY ] && data+="\nAUDIO_DELAY='$AUDIO_DELAY'"
		data+="\nREMEMBER_SUB_AND_AUDIO_DELAY=${REMEMBER_SUB_AND_AUDIO_DELAY:-f}"
		[ -v INTERVAL ] && data+="\nINTERVAL='$INTERVAL'"
		# Removing old header, if present, and the next line, if it’s empty.
		sed -ri "/^# watch.sh journal v[0-9]+$/ {s/.*//;N;s/\n//;/^\s*$/ d }" $JOURNAL
		# Removing old data related to KEYWORD.
		sed -ri "/^KEYWORD='$(escape_for_sed_pattern "$KEYWORD")'/,/^$/ d" $JOURNAL
		# Exporting new header and data.
		sed -ri "1 i # watch.sh journal v$VERSION\n\n$data\n" $JOURNAL
		# truncate to JOURNAL_MAX_SIZE
		j_size=`stat --format='%s' $JOURNAL`
		[[ "$j_size" =~ ^[0-9]+$ ]] || return `err cant_retrieve_journal_size`
		j_max_size=`echo "$(sed 's/K/*1024/;s/M/*1024*1024/' <<<"$JOURNAL_MAX_SIZE")" | bc -q`

		[[ "$j_max_size" =~ ^[0-9]+$ ]] || return `err cant_compute_journal_maxsize`
		[ $j_size -gt $j_max_size ] && {
			truncate --size=$JOURNAL_MAX_SIZE $JOURNAL || return `err cant_truncate_journal`
			# TODO: Clean the stump that might have left at the end of the file
			# sed -i '/^$/,$ d' $JOURNAL # (this doesn’t work — sed is too greedy)
			# Though I’m not sure if the cleaning is really needed, simple tests
			# had shown that it may be fine as is, but more complicated ones must
			# be done.
		}
	}
	SESSION_DATA_EXPORTED=t
	return 0
}

is_this_the_last_item() {
	[ $VIDEO_NUMBER -eq $VIDEOFILES_COUNT \
   -o $VIDEO_NUMBER -eq ${EXIT_AFTER_THIS_EPISODE:- -1} ]
}

print_last_shown_episode_number() {
	echo
#	declare -p EP_NUMBERS
	local ep_number=${EP_NUMBERS[VIDEO_NUMBER-1]##*(0)}
	is_this_the_last_item && local last_item_finishing_mark=$LAST_ITEM_MARK
	$LAST_EP_NUMBER_PRINTING_COMMAND < \
		<( echo -e "${LAST_EP_NUMBER_PRINTING_FORMAT//%n/$ep_number}${last_item_finishing_mark:-}" )
}

## Main algorithm starts here

if [ -v RESUME ]; then
	import_session_data || exit $?
else
	do_initial_search || exit $?
fi
screenshots_preprocessing || exit $?
# Exit trap should be here—after all the necessary data are collected or
#   imported. There is no point in altering the journal on exit, if user
#   declined to start watching something halfway.
trap "export_session_data || exit $?" EXIT HUP INT QUIT KILL
# A good place to check the $MODE.
until [ -v STOP ]; do
	watch || exit $?
	[ $MODE = episodes ] \
		&& [ "$LAST_EP_NUMBER_SHOW_AFTER" = player \
		  -o "$LAST_EP_NUMBER_SHOW_AFTER" = both   ] \
		&& print_last_shown_episode_number
	[ -v STOP ] || {
		[ -v RUN_IN_CYCLE ] && {
			is_this_the_last_item && {
				[ -v LOOP ] || break
				VIDEO_NUMBER=1
			}
			echo -en "Press $g<Space>$s to stop > "
			read -n1 -t ${INTERVAL:-3}
			# Avoiding [C to get to mpv’s input in case right arrow
			#   is still hold. If mpv reads them, it’ll try to interpret
			#   them as commands, and [ is usually bound to decrease speed
			#   by multiplying it on 0.9.
			[ "$REPLY" = $'\e' ] && read -sn2 rest && REPLY+="$rest"
			echo
			[ "$REPLY" = ' ' ] && break || IT_IS_NEXT_ITERATION=t
		}|| break
	}
done
screenshots_postprocessing && [ $MODE = episodes ] \
	&& [ "$LAST_EP_NUMBER_SHOW_AFTER" = screenshots \
	  -o "$LAST_EP_NUMBER_SHOW_AFTER" = both ] \
	&& print_last_shown_episode_number



# IDEAS
# ————————
# Add ED/OP as something equal to episode numbers in terms of sequences?
# Make a true check for multiple manual rearrangements expression.
# Create journal header to contain version for compatibility check.
# Write bash completion module (at least for -r).
# And integration with MyAnimeList.
# Write modular localization.
# Rewrite it with C++.
#
# I’ve given it much thought, but still can’t decide, whether I should reduce heuristics levels down to two,
#   i.e. ‘enabled’ and ‘disabled’. On the one hand, this is how it’s meant to be—user either uses full-featured
#   heuristics or satisfies with basic sort that saves his CPU time. On the other hand, it’s hard to keep up
#   all stages clean from bugs, and redevelop early stages without altering the ones above them. The posiibility
#   to gradually disable applied heuristics methods makes it possible to work on deep stages and see the results.
# Switching between heuristic levels with ‘h’ key would be ideal with two levels, but having three is not much
#   of a burden, considering that it’s meant to be set [to 2] once and for all in an alias, and remembered only
#   when something goes… not as it should. I thought about reducing levels down to two in ‘user-mode’, i.e. make
#   it a part of usual behaviour, enabling three levels when D (for DEBUG) is set, but what if
#   - there are users who’d prefer a bit faster heuristics for the more precise one for the common use?
#   - there are some users who would like to switch heuristics level just because of babyduck syndrome or
#     unexplainable love to click switches (aka hacky and cool)?
#   - there are something more I didn’t think about? Test cases are very small.

# WAT DONE
# ————————
# Fix bug #2. Good bye, sequences from hashes.
# Fix bug drawing episode_number twice after cycle has reached the end of the list.
# Fix division of what’s done for the watch() and the other functions in choose_from().
# -l goes for --loop. Now watch.sh will stop after reaching the end of the list (in episodes mode),
#    and will loop the list only when the corresponding option is specified.
# Fix triggering of export_session_data() for cases when watching wasn’t started.

# TODO
# ————————
# The purpose of this update is^W shoud have been to make HEU1 better (actual sorting by number included) and to make HEU2
#   ready for use, so this program would put on title ‘version 1.0’ with dignity.
# GROUP_INDICATOR must be 4 unique chars! Or not? Try to combine an array which would contain indices of groups
#   and start/end indices of the elements in VIDITEM_FILE[@], so we could use them instead of GI_*. // GI_*
#   must be unique in that case, and that may be inconvenient for the user and will require another cycle
#   for checking his own GROUP_INDICATOR.
# Change 1 to 2 in expressions writing and reading from journal and look if that would be enough to add a header.
# Group placed at the top, however, will still persist, and the topmost will be used for complementing in HEU2.
