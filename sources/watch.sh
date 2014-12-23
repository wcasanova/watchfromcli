#! /usr/bin/env bash

### Multiple manual rearrangement is broken.
## Проверить на Wiki пример, -A → --no-hints
## EP_NUMBERS как экспортируется, как печатается номер последнего эпизода, как играется после resume
## EP_NUMBERS[i] надо подсвечивать для одиночек в выхлопе, когда есть эвристика
# Create journal header to contain version for compatibility check.
#? Write bash completion module (at least for -r)
#? А ещё myanimelist


# watch.sh
# A shell wrapper for mpv/MPlayer to run videos easy via CLI.
# watch.sh © 2013,2014 deterenkelt.

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
Copyright © 2013,2014 deterenkelt.
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
			code=9;	msg='getopt returned an error while parsing the command line. It was probably\n  caused by ';;&
		getopt_funcerr)
			msg+='the getopt() function error. If it’s not a common error, then see\n  man 3 getopt.';;
		getopt_wrongparam)
			msg+='the parameters getopt wasn’t been able to parse correctly.';;
		getopt_internal)
			msg+='an internal error. Is there enough memory available?';;
		getopt_dumbme)
			msg+='the reason you shall probably know by yourself.';;
		opt_bashrc)
			code=10; msg='Option --bashrc takes an argument that has to be bash source file.';;
		opt_chk4upd)
			code=11; msg='Option --check-for-update takes a number of days between which it should check releases on github as an argument.';;
		opt_compat)
			code=12; msg='Option --compat requires an argument to be one of “mplayer”, “mplayer2” or “mpv-03x”.';;
		opt_basedir)
			code=13; msg="-d|--basedir: “$arg” is not a readable directory.";;
		opt_heulevel)
			code=14; msg="Option --heuristics-level requires an argument to be a number lower or equal to $MAX_HEURISTICS_LEVEL.";;
		opt_inputinvalid)
			code=15; msg='RESERVED';;
		opt_jentries)
			code=16; msg='Option -j|--list-journal takes
  - a number between 1 and 65535;
  - a single letter “a” or “all” to display all keywords.';;
		opt_journalsize)
			code=17; msg='Option --journal-max-size requires an argument to be a number of bytes that
  may be followed by one of these suffixes: K M G to represent *2^10 once,\n  twice or three times.';;
		opt_jpegcompression)
			code=18; msg='Option --jpeg-compression takes an argument that has to be a number between 0 and 100.';;
		opt_lepshowafter)
			code=19; msg='Option --last-ep-show-after requires an argument to be one of\n  - player;\n  - screenshots;\n  - both.';;
		opt_limitsec)
			code=20; msg='RESERVED';;
		opt_taskset)
			code=21; msg='Option -t|--taskset-cpulist requires an argument to be a valid CPU list.\n See `man taskset` for the details.';;
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
			code=29; nomsg=t ;;
		heu2_nan)
			code=30; msg="Error on heuristics 2nd level: “${matches_as_numbers[j]}” and “${matches_as_numbers[k]}” must be numbers.";;
		scrdir_isnt_writeable)
			code=31; msg="No sufficient rights to write to “$SCREENSHOT_DIR”.";;
		cant_create_scrdir)
			code=32; msg="Couldn’t create directory “$SCREENSHOT_DIR”.";;
		cant_retrieve_from_journal)
			code=33; msg='Couldn’t retrieve data from journal.'
			[ "$KEYWORD" ] && msg+='\nThis was probably caused by a record at the end of journal and happened because\n  cleansing of broken entries is not implemented yet.';;
		nothing_to_restore)
			code=34; msg="Not enough data to restore.
Couldn’t retreive $not_found_vars from the journal.
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
		*)
			code=107; msg='Unknown error.';;
	esac
    [ -v nomsg ] || echo -e "$r*$s $msg" >&2
    echo $code
}

msg() { echo -e "$g$b*$s $1"; }

warn() { echo -e "$y*$s $1" >&2; }

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

MAX_HEURISTICS_LEVEL=2
HEURISTICS_LEVEL=0

JOURNAL=~/.watch.sh/journal
JOURNAL_MAX_SIZE="64K" # w/o suffix for bytes, K for KiB, M for MiB etc.
JOURNAL_MINVER='20141222'
[ -d ~/.watch.sh ] || {
	mkdir -m755 ~/.watch.sh/ >/dev/null \
		|| exit `err homedir`
}

VERSION="20141121"
CHECK_FOR_UPDATES=21 # each N days
updater_timestamp=~/.watch.sh/updater_timestamp
[ -f $updater_timestamp ] || touch $updater_timestamp

GROUP_INDICATOR='┌│└⋅'

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
                       acCd:eEFhH:Ij::JlM:m:nNrRs:S:t:uTv \
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
list-journal::,\
journal-max-size:,\
jpeg-compression::,\
last-ep,\
last-ep-command:,\
last-ep-format:,\
match-all,\
match-number,\
mplayer-command:,\
mplayer-opts:,\
my-increment:,\
my-decrement:,\
no-hints,\
no-color,\
no-journal,\
remember-sub-and-audio-delay,\
resume,\
resume-from-previous,\
run-in-cycle,\
screenshot-dir:,\
screenshot-dir-skel:,\
subfolders:,\
taskset:,\
version,\
             -n 'watch.sh' -- "$@"`
getopt_exit_code=$?
[ $getopt_exit_code -gt 0 ] && {
	case $getopt_exit_code in
		1) exit `err getopt_funcerr `;;
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
		'--no-hints') # hide hints
			NO_HINTS=t
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
			[ -z "$2" ] && CHECK_FOR_UPDATES=now && shift || {
				[[ "$2" && "$2" = ^[0-9]+$ ]] && CHECK_FOR_UPDATES=$2 && shift 2 \
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
			[[ "$2" =~ ^[0-9]+$ ]] \
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
			[[ "$2" =~ ^[0-9]$ ]] && INTERVAL="$2" || exit `err opt_interval`
			shift 2
			;;
		-j|'--list-journal')
			[ -z "$2" ] && JOURNAL_ENTRIES=10 || {
				[ "$2" = a -o "$2" = all ] && JOURNAL_ENTRIES=65535 || {
					[[ "$2" =~ ^[0-9]+$ ]] \
						&& [ $2 -gt 0 ] && [ $2 -le 65535 ] \
						&& JOURNAL_ENTRIES=$2 \
						|| exit `err opt_jentries`
				}
			}
			sed -nr "s/^KEYWORD='(.*)'$/\1/p" $JOURNAL | head -n$JOURNAL_ENTRIES
			exit 0
			;;
		-J|'--no-journal')
			NO_JOURNAL=t
			shift
			;;
		'--journal-max-size')
			[[ "$2" =~ ^[0-9]+[KMG]?$ ]] && JOURNAL_MAX_SIZE="$2" && shift 2 \
				|| exit `err opt_journalsize`
			;;
		'--jpeg-compression')
			[ -z "$2" ] && JPEG_COMPRESSION=92 && shift || {
				[[ "$2" =~ ^[0-9]+$ ]] && [ $2 -ge 0 ] && [ $2 -le 100 ] \
					&& JPEG_COMPRESSION=$2 && shift 2 \
					|| exit `err opt_jpegcompression`
			}
			;;
		-l|'--last-ep')
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
		# -L)
		# 	# Limit sequence iterations to $2.
		# 	err opt_limitsec
		# 	shift 2
		# 	;;
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
		-t|'--taskset-cpulist')
			[[ "$2" =~ ^[0-9,-]+$ ]] && TASKSET_CPULIST="$2" && shift 2 || exit `err opt_taskset`
			;;
		-T) # Enable output for testing purposes.
			# [ -v T ] is a visual mark for them.
			T=t
			shift
			;;
		-u)
			CHECK_FOR_UPDATES=now
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

[ $CHECK_FOR_UPDATES != 0 ] && {
	[[ $CHECK_FOR_UPDATES =~ ^[0-9]+$ ]] && {
		[ $(( (`date +%s`-`stat -L --format %Y $updater_timestamp`)/60/60/24 )) -gt $CHECK_FOR_UPDATES ] \
			&& CHECK_FOR_UPDATES=now || {
			grep -q 'New version is available!' $updater_timestamp \
				&& msg 'New version is available'
		}
	}
}
[ $CHECK_FOR_UPDATES = now ] && {
	which wget &>/dev/null && {
		latest_ver=`wget -O- http://github.com/deterenkelt/watchsh/releases \
		                |& sed -nr '/<h1\s+class="release-title">/ {
		                                :be N; s|.*</h1>.*|&|; t
		                                    s/.*v([0-9]{8}).*/\1/p; t qu
		                                    b be
		                                :qu Q
		                            }'`
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

# This assignation  must be here because -M itself is optional.
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
	unset disable_heuristics
	# [ ${FUNCNAME[1]} != watch ] && local disable_heuristics=t
	LIST_TO_CHOOSE_FROM=`sort <<<"$1"`
	LIST_ITEMS_COUNT=`echo -e "$LIST_TO_CHOOSE_FROM" | wc -l`
	local cols=`tput cols`
	unset CHOSEN_NUMBER list_variants_available ROTATE_PATTERN_LIST group_patterns INDEX_AT_THE_TOP
	until [ -v CHOSEN_NUMBER ]; do
		unset EP_NUMBERS
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
		[ -v NO_HINTS ] || echo ' ↙ The directory I’m currently in.'
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
		[ ${FUNCNAME[1]} = watch ] && [ $HEURISTICS_LEVEL -ne 0 ] && {
				[ -v D ] && dbg_file="$DEBUG_DIR/choose_from_[watch]"
				[ -v group_patterns ] || create_groups_for_the_list || return $? # L1 HEU
				arrange_groups || return $?                                      # L1 HEU
				build_the_list || return $?                                      # L1/L2 HEU
		}|| echo -e "$LIST_TO_CHOOSE_FROM" | grep -niG "\($KEYWORD\|$\)"
		# Just not leaving this empty if heuristics is not enabled.
		[ -v EP_NUMBERS ] || readarray -t EP_NUMBERS < <(seq 1 $LIST_ITEMS_COUNT)

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
		local up=$'\e[A' down=$'\e[B' backspace=$'\177' F1=$'\e[11~' # F1 requires another read to catch 4 chars, wat do?
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
#     $4 — occupied numbers
#     $5 — maximum number length
group_create() {
	group_patterns[${#group_patterns[@]}]=$1
	group_matches[${#group_patterns[@]}-1]=$2
	group_matches_count[${#group_patterns[@]}-1]=$3
	group_occupied_numbers[${#group_patterns[@]}-1]=$4
	group_max_number_length[${#group_patterns[@]}-1]=$5
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
#     $1 — index of the group to delete
group_delete() {
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
 			   inc_patterns=( "^$left_part$inc_num.*$" \
					"^.*$inc_num$right_part$" \
					"^$inc_num$right_part$" \
					"^$left_part$inc_num$right_part$" ) # Both parts — the last!
				# There was a trouble with sed being ungreedy while matching
				#   what is supposed to be an episode number. The \b for
				#   boundary helped for some time, but then filenames having
				#   episode number surrounded with underscores (“_”) appeared,
				#   and, because \b matches letters, digits and underscores
				#   as a single word, this caused patterns to fail on such
				#   names. That’s why \b was replaced by a “possible non-
				#   number” — [^0-9]\?. It should be replaced with pre-condition
				#   when I got my hands to perl.
				# multinum counterparts are used to hook all the filenames
				#   within a sequence defined by an inc_pattern.
				multinum_patterns=( "^$left_part\([0-9]\+\)[^0-9].*$" \
					"^.*[^0-9]\([0-9]\+\)$right_part$" \
					"^\([0-9]\+\)$right_part$" \
					"^$left_part\([0-9]\+\)$right_part$" ) # Both parts — the last!
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
								$matches_count \
								"$(sed -n "s/${multinum_patterns[j]}/\1/p" <<<"$matches")" \
								0
							while IFS= read number; do
								[ "${#number}" -gt "${group_max_number_length[${#group_patterns[@]}-1]}" ] \
									&& group_max_number_length[${#group_patterns[@]}-1]=${#number}
							done < <(echo "${group_occupied_numbers[${#group_patterns[@]}-1]}")
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
				1 \
				"$(sed -r 's/[^0-9]+/ /g; s/^\s//; s/\s$//  #hypotetical!'<<<"$filename"))" \
				-1 # because potential episode numbers are only hypotetical
		}
	done  < <(echo "$LIST_TO_CHOOSE_FROM")  # $LIST_TO_CHOOSE_FROM _never_ has literal '\n' here.


# Придумать как сделать заполнение дыр.

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
# echo -----
# echo 'ENTERED ARRANGE_GROUPS (start)'
# echo -----
# local group
# for group in ${!group_@}; do declare -p $group; done
# unset group
# echo -----
# echo 'ENTERED ARRANGE_GROUPS (end)'
# echo -----
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
# set -x
			local buffer_index=${#group_patterns[@]}
			group_copy 0 $buffer_index
			for ((i=1; i<${#group_patterns[@]}; i++)); do
				group_copy $i $((i-1))
			done
			group_copy $buffer_index $((${#group_patterns[@]}-2))
			group_delete $buffer_index
# set +x
			[ $((++INDEX_AT_THE_TOP)) -gt ${#group_patterns[@]} ] \
				&& INDEX_AT_THE_TOP=1 # why not 0?
			[ -v D ] && declare -p INDEX_AT_THE_TOP >>$dbg_file
# echo -----
# echo 'AFTER ROTATION ARRANGE_GROUPS (start)'
# echo -----
# local group
# for group in ${!group_@}; do declare -p $group; done
# unset group
# echo -----
# echo 'AFTER_ROTATION ARRANGE_GROUPS (end)'
# echo -----
			unset ROTATE_PATTERN_LIST
		}||{
			[ -v D ] && echo 'SORTING' >>$dbg_file
			# Do initial groups sorting.
			# Sort patterns descending by the number of matches OR
			#   lexicographically if numbers are equal
			for (( i=0; i<${#group_patterns[@]}-1; i++)); do
				for (( j=$i+1; j<${#group_patterns[@]}; j++)); do
					( [ ${group_matches_count[i]} -lt ${group_matches_count[j]} ] ||
						( [ ${group_matches_count[i]} -eq ${group_matches_count[j]} ] &&
							[[ "${group_patterns[i]}" > "${group_patterns[j]}" ]] ) ) && {
						# Biggest number of matches → to the top of the array.
						group_swap $j $i
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
# EP_NUMBERS=()
#    watch needs a variable containing list of episodes. 1 2 3 4? (guessed by HEU2) L5 (list item 5),
# ${#EP_NUMBERS[@]}
#    will serve as the total count of files
	[ -v D ] && {
		dbg_file=$DEBUG_DIR/build_the_list
		declare -p group_patterns group_matches group_matches_count >>$dbg_file
	}
	[ -v MANUAL_REARRANGEMENT ] && {
		readarray -t <<<"`echo -e ${MANUAL_REARRANGEMENT//,/\\\n}`"
		unset MANUAL_REARRANGEMENT
		for ((i=0; i<${#MAPFILE[@]}; i++)); do
			[[ "${MAPFILE[i]}" =~ ^[0-9]+(-[0-9]+)?\>[0-9]+$ ]] || {
				warn "“${MAPFILE[i]}” is not a valid rearrangement instruction."
				warn "The format is: “10>1”, “9-11>2”, “1-3>5,7-8>1,…”."
				return 0
			}
			local start="${MAPFILE[i]%>*}" \
			      end="${MAPFILE[i]%>*}" \
			      dest="${MAPFILE[i]#*>}"
			      put_dest_line_first=f
			local start="${start%-*}" \
			      end="${end#*-}"
			[ $start -gt $LIST_ITEMS_COUNT ] && {
				warn "“${MAPFILE[i]}”: start value must be lower than $LIST_ITEMS_COUNT."
				return 0
			}
			[ $end -lt $start ] && {
				warn "“${MAPFILE[i]}”: end value must be lower than start value."
				return 0
			}
			[ $dest -gt $LIST_ITEMS_COUNT ] && {
				warn "“${MAPFILE[i]}”: destination value must be lower than $LIST_ITEMS_COUNT."
				return 0
			}
			[ $start -eq $dest ] && {
				warn "“${MAPFILE[i]}”: what’s the point in this?.."
				return 0
			}
			[ $dest -gt $end ] && {
				# For moves like 4>3, i.e. from the down to top, it works as you suppose it to.
				#   When you give it a command to put something from up to down, it _would_ work,
				#   but _not_ as you expect it to, e.g. 4>3 swaps the third line with the fourth,
				#   while 3>4 would seem to do nothing. This is because in general case the source,
				#   i.e. 3rd line in our example, is removed from the list, the list then shifted
				#   for one line up, and then the time comes to put destination to the new place.
				#   But before placing the destination [line], it must put what’s in the buffer,
				#   i.e. the 3rd line, before, and only after—the destination, what was the 4th line.
				# Since it makes the operation obscure to the user, we put the destination before
				#   what is in the buffer in that case, so it would act like the user expects it to.
				local put_dest_line_first=t
			}
			# Forming a queue.
			local queue_start[${#queue_start[@]}]=$start
			local queue_end[${#queue_end[@]}]=$end
			local queue_dest[${#queue_dest[@]}]=$dest
			local queue_size[${#queue_size[@]}]=$((queue_end[i] - queue_start[i] +1))
			local queue_put_dest_line_first[${#queue_put_dest_line_first[@]}]=$put_dest_line_first
		done
		# Testing the queue for intersections

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
			# If we’re here, we’re safe.
			# Now the numbers in the queue must be shifted by -1, because the actual
			#   indices of the list items are starting from 0.
			let queue_start[i]-- queue_end[i]--
			# Okay, now to remember where which destination was would be a burden,
			#   and, since the possible conflicts are solved, we can simply replace
			#   the destination numbers with respective file names from the list.
			#   Usually, filesystem doesn’t allow two files with the same name
			#   to exist within one folder.
			# This will save us a cycle later.
			#   There’s no need to seek for the destination for the first rearrangement,
			#   because only operations after it move dest to a place unknown.
			[ $i -eq 0 ] && local queue_dest_index[0]=$((queue_dest[i]-1))
			local queue_dest[i]=${LIST_ITEMS[${queue_dest[i]}-1]} \

		done
		# Since the cycle above was generally made for looking for intersections,
		#   last element wasn’t affected by the additional (to the cycle’s task) shifting.
		let queue_start[i]-- queue_end[i]--
		[ $i -eq 0 ] && local queue_dest_index[0]=$((queue_dest[i]-1))
		local queue_dest[i]=${LIST_ITEMS[${queue_dest[i]}-1]}
		# Finally, the rearrangement.
		for ((i=0; i<${#queue_start[@]}; i++)); do
			unset dest_index buffer buffer_gids
			[ $i -eq 0 ] \
				&& local dest_index=${queue_dest_index[0]} \
				|| for ((j=0; j<LIST_ITEMS_COUNT; j++)); do
				[ "${LIST_ITEMS[j]}" = "${queue_dest[i]}" ] \
					&& dest_index=$j && break
			done
			for ((j=0; j<${queue_size[i]}; j++)); do
				# Copy what will be moving to the new destination to the buffer.
				local buffer[j]=${LIST_ITEMS[queue_start[i]+j]} \
				      buffer_gids[j]=${LIST_ITEMS_GIDS[queue_start[i]+j]}
				unset LIST_ITEMS[queue_start[i]+j] \
				      LIST_ITEMS_GIDS[queue_start[i]+j]
			done
			# Now we must shift the items so the ‘hole’ appear in the appropriate place.
			# We’ll create LIST_ITEMS from scratch, using its double.
			local gap=0 \
			      _list_items=("${LIST_ITEMS[@]}") \
			      _list_items_gids=("${LIST_ITEMS_GIDS[@]}") # indices will be consecutive!
			for ((j=0; j<${#_list_items[@]}; j++)); do
				unset dest_line_is_already_put
				# Going through the double, place the elements until the destination item is found.
				[ "${_list_items[j]}" = "${queue_dest[i]}" ] && {
					local gap=${queue_size[i]}
# declare -p j gap LIST_ITEMS _list_items
					# Then decide what we shall put first—what’s in the buffer or the dest line.
					[ "${queue_put_dest_line_first[i]}" = t ] \
						&& LIST_ITEMS[j]=${_list_items[j]} \
						&& LIST_ITEMS_GIDS[j]=${_list_items_gids[j]} \
						&& local dest_line_is_already_put=t
						# Placing the buffer.
					for ((k=0; k<gap; k++)); do
						LIST_ITEMS[      j+k ${dest_line_is_already_put:+ +1} ]=${buffer[k]}
						LIST_ITEMS_GIDS[ j+k ${dest_line_is_already_put:+ +1} ]=${buffer_gids[k]}
					done
				}
				# Don’t put the line from double if it was destination
				#   and it was already put back to the LIST_ITEMS.
				[ -v dest_line_is_already_put ] || {
					LIST_ITEMS[gap+j]=${_list_items[j]}
					LIST_ITEMS_GIDS[gap+j]=${_list_items_gids[j]}
				}
			done
		done

		local manual_rearrangement_was_in_effect=t
	}

	[ -v manual_rearrangement_was_in_effect ] || {
	# At this point we need to assign an episode number to each match, and
	#   thus operate with 2 arrays, but at the same time we still need groups,
	#   because keeping a sequence raises the chance of building list
	#   in the correct order.
	unset EP_NUMBERS LIST_ITEMS LIST_ITEMS_GIDS pat_for_grep
	# LIST_ITEMS* are actually used only within this function, but need
	#   to persist between runs, so the list wouldn’t be empty if
	#   manual rearrangement will fail.
	# EP_NUMBERS[0]='Left unused in order to conform with list numbering.'
	local i j k lcount=1  list_indicators=() \
		match new_match_found _ep_number sequence_started_at
	for ((i=0; i<${#group_patterns[@]}; i++)); do
		pat_for_grep[i]=${group_patterns[i]%\[^0-9]\.\**}
		[ "${pat_for_grep[i]}" = "${group_patterns[i]}" ] \
			&& pat_for_grep[i]=${group_patterns[i]#^\.\*\[^0-9]}
		for ((j=0; j<${group_matches_count[i]}; j++)); do
			unset new_match_found
			until [ -v new_match_found ]; do
				match=`sed -n $((j+1))p <<<"${group_matches[i]}"`
				[ $i -eq 0 ] && break # matches of the 1st pattern are unique
				new_match_found=t
				for ((k=0; k<${#LIST_ITEMS[@]}; k++)); do
					[ "${LIST_ITEMS[k]}" = "$match" ] && unset new_match_found
				done
				[ -v new_match_found ] || {
					# If there are no new matches, it will simply accumulate until j reaches its limit
					[ $((++j)) -eq ${group_matches_count[i]} ] && break 2 # Yes, it works. Think!
				}
			done
			_ep_number="$(sed -n "s/${group_patterns[i]}/\1/p" <<<"$match" 2>>${dbg_file:-/dev/null})"
			[[ "$_ep_number" =~ ^[0-9]+$ ]] \
				&& EP_NUMBERS[${#EP_NUMBERS[@]}]=$_ep_number \
				|| { # it’s a match that formed a group from itself
				_ep_number="$(sed -r 's/[^0-9]+/ /g; s/^\s//; s/\s$//  #hypotetical numbers!'<<<"${group_patterns[j]}")"
				[[ "$_ep_number" =~ ^[0-9\s]+$ ]] \
					&& EP_NUMBERS[${#EP_NUMBERS[@]}]="$_ep_number" \
					|| EP_NUMBERS[${#EP_NUMBERS[@]}]="L${#EP_NUMBERS[@]}" # i.e. ‘Line number #’
			}
			LIST_ITEMS[${#LIST_ITEMS[@]}]=$match
			LIST_ITEMS_GIDS[${#LIST_ITEMS_GIDS[@]}]=$i
			[ $((++lcount)) -gt $LIST_ITEMS_COUNT ] && break 2
		done
	done

	# Composing group indicators.
	# It is better to be done outside the cycle above.
	# Much more readable and clearer this way.
	LIST_ITEMS_GIDS[${#LIST_ITEMS_GIDS[@]}]='dummy'
	for ((i=1; i<${#LIST_ITEMS_GIDS[@]}; i++)); do
		[ "${LIST_ITEMS_GIDS[i]}" = "${LIST_ITEMS_GIDS[i-1]}" ] || {
			# A consecutive sequence has ended and a new one just started.
			# Let’s look at the sequence to know how we should transform it
			[ -v sequence_started_at ] || sequence_started_at=0
			[ $((i-sequence_started_at)) -ge 2 ] && {
				list_indicators[sequence_started_at]=${GROUP_INDICATOR:0:1} # ┌
				list_indicators[i-1]=${GROUP_INDICATOR:2:1} # └
			}
			[ $((i-sequence_started_at)) -ge 3 ] && {
				for ((j=sequence_started_at+1; j<i-1; j++ )); do
					list_indicators[j]=${GROUP_INDICATOR:1:1} # │
				done
			}
			[ $sequence_started_at -eq $((i-1)) ] \
				&& list_indicators[i-1]=${GROUP_INDICATOR:3:1} # ⋅
			local sequence_started_at=$i
		}
	done

# declare -p EP_NUMBERS

# Заполнение дырок:
# Это кандидат с номером, который подходит к дырке
#  Это единственный кандидат на это место
# ???↑
# В группах встречается EP_PATTERN
# У кандидата есть EP_PATTERN

#	[ $HEURISTICS_LEVEL -gt 1 ] && {

# Всё переделать.
# Найти подходящие по ширине числа в униках.
# Отсортировать по возрастанию!



	# Level 2 heuristics.
	# We discard the way of building LIST_TO_CHOOSE_FROM by arranging groups
	#   and try to deeper, into where sequences don’t spread. It is case
	#   when the folder contains a hodge-podge, or there are several tiny
	#   sequences.
	# Many conflict situations may rise, so the place swapping is only performed
	#   when there are not more than one candidate for that place.
	[ -v D ] && echo -e '\n\nHEU LVL 2 start.' >>$dbg_file
# [ $HEURISTICS_LEVEL -eq 2 ] && {
# 	for ((i=0; i<${#group_matches[@]}; i++)); do
# 		# Okay, we have them. But now it’s not much far away from the “sort” command.
# 		# Sort would find these numbers too (and put 1 after 10), we are a step forward
# 		#   only by finding a hint for a presence of sequence in those numbers.
# 		#   Now arrange these numbers to make them reflect this sequence.
# 		# Change pattern so it could grab found number in ([0-9]+).
# 		[ -v D ] && {
# 			echo -e "\tProcessing group_matches[$i]\n\tList:" >>$dbg_file
# 			echo "${group_matches[i]}" | sed 's/.*/\t\t“&”/g' >>$dbg_file
# 			echo -e "\tCount: ${group_matches_count[i]}" >>$dbg_file
# 		}
# 		# Removing leading zeroes just to avoid possible misinterpretation as octal.
# 		subst_pattern=$(echo "${group_patterns[i]}" | sed 's/\(\[0-9]\\+\)/0*\\([0-9]\\+\\)/' )
# 		# We’re going to do a bubble sort against $matches_*,
# 		#   and to accomplish that, we save matched filenames and what
# 		#   is supposed to be episode numbers which formed a sequence,
# 		#   into respective arrays, so we could rebuild group_matches[i]
# 		#   not from scratch, but in a new way.
# 		local matches_as_array matches_as_numbers buffer
# 		readarray -t matches_as_array < <(echo -e "${group_matches[i]}")
# 		readarray -t matches_as_numbers < <(echo -e "${group_matches[i]}" | sed -n "s/$subst_pattern/\1/p")
# 		[ -v D ] && declare -p matches_as_array matches_as_numbers >>$dbg_file
# 		unset group_matches[i]
# 		for ((j=0; j<${#matches_as_array[@]}-1; j++)); do
# 			for ((k=$j+1; k<${#matches_as_array[@]}; k++)); do
# 				# Big numbers (of an episode) → to the end of the list
# 				[[ "${matches_as_numbers[j]}" =~ ^[0-9]+$
# 						&& "${matches_as_numbers[k]}" =~ ^[0-9]+$ ]]  || return `err heu2_nan`
# 				[ ${matches_as_numbers[j]} -gt ${matches_as_numbers[k]} ] && {
# 					buffer="${matches_as_array[j]}"
# 					matches_as_array[j]="${matches_as_array[k]}"
# 					matches_as_array[k]="$buffer"
# 					buffer="${matches_as_numbers[j]}"
# 					matches_as_numbers[j]="${matches_as_numbers[k]}"
# 					matches_as_numbers[k]="$buffer"
# 				}
# 			done
# 			# Each j should be the smallest number from what’s left, i.e. 1, 2, 3…
# 			group_matches[i]="${group_matches[i]:+${group_matches[i]}\n}${matches_as_array[j]}"
# 		done
# 		# We deleted the original item, remember? And now the last
# 		#  (and the biggest) match wasn’t added to the original array
# 		#   element back. Don’t be confused with a similar sort above,
# 		#   there was no deleteion of original mapfile elements!
# 		group_matches[i]="${group_matches[i]}\n${matches_as_array[j]}"
# 		group_matches[i]=`echo -e "${group_matches[i]}"` # `\n`
# 		[ -v D ] && {
# 			echo -e "\tList after resorting:" >>$dbg_file
# 			echo "${group_matches[i]}" | sed 's/.*/\t\t“&”/g' >>$dbg_file
# 			echo -e "\tCount: ${group_matches_count[i]}\n" >>$dbg_file
# 		}
# 	done
# }
	}

	unset LIST_TO_CHOOSE_FROM
	for ((i=0; i<LIST_ITEMS_COUNT; i++)); do
	   printf "${g}%*d:${s}" ${#LIST_ITEMS_COUNT} $((i+1))
		[ -v manual_rearrangement_was_in_effect -o $HEURISTICS_LEVEL -gt 1 ] \
			|| echo -en "${list_indicators[i]}"
			# echo -en "${g}$b«$i» «${group_occupied_numbers[i]}» «${group_max_number_length[i]}»${s}"
		local pattern=${pat_for_grep[${LIST_ITEMS_GIDS[i]}]}
		# If the match is unique, i.e. pattern is equal to the match itself,
		#   restrain grep from highlighting the whole string.
		[ "`grep -oG "$pattern"<<<"${LIST_ITEMS[i]}"`" = "${LIST_ITEMS[i]}" ] \
			&& echo "${LIST_ITEMS[i]}" | grep -iG "\($KEYWORD\|${EP_NUMBERS[i]}\)" \
			|| echo "${LIST_ITEMS[i]}" | grep -iG "$pattern"
		LIST_TO_CHOOSE_FROM="${LIST_TO_CHOOSE_FROM:+$LIST_TO_CHOOSE_FROM\n}${LIST_ITEMS[i]}"
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
#     episode_number — retrieved from EP_NUMBERS array. NB that VIDEO_NUMBER
#         contains the line number, i.e. starts with 1, and this array starts
#         with 0.
#     INTERRUPTED — used in “resume” case, means episode wasn’t watched till
#         the end and must be re-played on resume.
#     STOP — if MPlayer was interrupted by key, that stops the cycle too.
# RETURNS:
#     0 if ok, >0 if internal function call returned an error.
watch() {
	case $MODE in
		single)
			# Already nothing to do!
			# See adding subs/tracks after esac.
			;;
		episodes)
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
				[ $VIDEO_NUMBER -gt `echo -e "$VIDEOFILES" | wc -l` ] \
					&& VIDEO_NUMBER=1 && STOP=t && return 0 # needs a test case
				VIDEOFILE=`echo -e "$VIDEOFILES" | sed -n "$VIDEO_NUMBER p"`
			else
				# The beginning of watching cycle
				[ `echo "$VIDEOFILES" | wc -l` -gt 1 ] && {
					choose_from "$VIDEOFILES" || return $?
					VIDEOFILES="$LIST_TO_CHOOSE_FROM" # now rearranged
# Do we really need it?
VIDEOFILES_COUNT="LIST_ITEMS_COUNT"
					VIDEOFILE="$CHOSEN_ITEM"
					VIDEO_NUMBER=$CHOSEN_NUMBER
				}||{ # eh? 1 videofile in eps mode?!
					[ -v RUN_IN_CYCLE ] && {
						warn 'Cannot start watching cycle: only one video file.'
						unset RUN_IN_CYCLE
					}
				}
			fi
			episode_number=${EP_NUMBERS[VIDEO_NUMBER-1]}
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
	# part        |         whether it can be
	# of the path |  a folder    a file   not present
	# ------------+-----------------------------------
	# BASEPATH    |     ✔           ✘          ✘
	# FIRST_MATCH |     ✔           ✔          ✘
	# SUBFOLDERS  |     ✔           ✘          ✔
	# VIDEOFILE   |     ✘           ✔          ✔

	local path_to_videofile="$BASEPATH$FIRST_MATCH${SUBFOLDERS:-}${VIDEOFILE:-}"
	[ -v D ] && dbg_file="$DEBUG_DIR/mpv_run"
	[ -v TASKSET_CPULIST ] && which taskset >/dev/null &&
	taskset_cmd="taskset --cpu-list $TASKSET_CPULIST"
	# $MPLAYER_OPTS must be right before path because of protocol:// things
	{ coproc \
		{ eval ${taskset_cmd:-} $MPLAYER_COMMAND  ${subtitles:-} ${tracks:-} \
			"$MPLAYER_OPTS" "\"$path_to_videofile\"" \
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
		#   messages and ask what to do if none were found? This matters
		#   when the mpv output changes when verbosity level is increased.
		INTERRUPTED=t
		STOP=t
	}
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
		# This check may be not needed, but it’s safer to have it                    vvv     EP20v2    vvv
		local match_by_keyword_and_num=`echo "$match_by_keyword" | grep -e "[^0-9a-oA-Oq-zQ-Z]${episode_number#L}[^0-9a-uA-Uw-zW-Z]" | sort`
		OTHER_FILES_LIST="${OTHER_FILES_LIST:+${OTHER_FILES_LIST}\n}$match_by_keyword_and_num"
		local match_by_num=`echo "$found_other_files" | grep -e "[^0-9]${episode_number#L}[^0-9]" | sort`
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
#     0 if OK, “cant_retrieve_from_journal”, “nothing_to_restore”.
import_session_data() {
	[ -v NO_JOURNAL ] || {
		[ "`stat --format='%s' $JOURNAL`" -gt 1 ] && {
			if [ "$KEYWORD" ]; then
				# KEYWORD present, search among entries in the journal
				eval "`sed -n "/^KEYWORD='$(escape_for_sed_pattern "$KEYWORD")'/,/^$/ p" \
				$JOURNAL 2>/dev/null`" || local shell_failed=t
			else
				# KEYWORD is not given, take 1st one from the journal
				eval "`sed -n '1,/^$/ p' $JOURNAL 2>/dev/null`" || local shell_failed=t
			fi
			[ -v shell_failed ] && return `err cant_retrieve_from_journal`

			check_required_vars() {
				local var
				for var in $@; do
					[ -v $var ] || {
						not_found_vars+=" $var"
						no_enough_data=t
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
		[ -v no_enough_data ] && return `err nothing_to_restore`
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
	# str=${str//\'/\\\'} # as it was before 20140915
	str=${str//\//\\/}
	# str=${str//\"/\\\"} # Just for the case if a bug will appear
	echo -en "$str"
}

# SETS:
#     session_data_exported — to prevent this function running twice.
# EXIT_CODES:
#     0 if OK, “cant_retrieve_journal_size”,
#    “cant_compute_journal_max_size”, “cant_truncate_journal”.
export_session_data() {
	[ -v session_data_exported ] && return 0
	[ -v NO_JOURNAL ] || {
		local data="KEYWORD='$(escape_for_sed_replacement "$KEYWORD")'"
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
			# NB extra backslash in sed replacement. It’s there because sed called in a subshell.
			local videofiles_in_one_row="`echo -n "$(escape_for_sed_replacement "$VIDEOFILES")" | sed ':be N; s/\n/\\\n/g; b be'`"
			data+="\nVIDEOFILES='$videofiles_in_one_row'"
			data+="\nVIDEOFILES_COUNT=$VIDEOFILES_COUNT"
			data+="\nVIDEO_NUMBER=$VIDEO_NUMBER"
			# For what reason escape_for_sed_pattern was used here?
			#   was it just a mistake or not?
#data+="\nEP_NUMBERS"
			data+="\nINTERRUPTED=${INTERRUPTED:-f}"
		}
		data+="\nSCREENSHOT_DIR='$(escape_for_sed_replacement "$SCREENSHOT_DIR")'"
		[ -v SUB_DELAY ] && data+="\nSUB_DELAY='$SUB_DELAY'"
		[ -v AUDIO_DELAY ] && data+="\nAUDIO_DELAY='$AUDIO_DELAY'"
		data+="\nREMEMBER_SUB_AND_AUDIO_DELAY=${REMEMBER_SUB_AND_AUDIO_DELAY:-f}"
		[ -v INTERVAL ] && data+="\nINTERVAL='$INTERVAL'"
		# removing old data
		sed -ri "/^KEYWORD='$(escape_for_sed_pattern "$KEYWORD")'/,/^$/ d" $JOURNAL
		# exporting last data
		sed -ri "1s/^/$data\n\n&/" $JOURNAL
		# truncate to JOURNAL_MAX_SIZE
		local j_size=`stat --format='%s' $JOURNAL`
		[[ "$j_size" =~ ^[0-9]+$ ]] || return `err cant_retrieve_journal_size`
		local j_max_size=`echo "$(sed 's/K/*1024/;s/M/*1024*1024/' <<<"$JOURNAL_MAX_SIZE")" | bc -q`

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
	session_data_exported=t
	return 0
}

print_last_shown_episode_number() {
	echo
	[ $HEURISTICS_LEVEL -eq 0 ] && local ep_number_isnt_trustworthy=?
	local ep_number=${episode_number##*(0)}${ep_number_isnt_trustworthy:-}
	$LAST_EP_NUMBER_PRINTING_COMMAND < \
		<( echo -e "${LAST_EP_NUMBER_PRINTING_FORMAT//%n/$ep_number}" )
}

## Main algorithm starts here

if [ -v RESUME ]; then
	import_session_data || exit $?
else
	do_initial_search || exit $?
fi
screenshots_preprocessing || exit $?
# Just for emergency.
# Exit trap should be placed right here—after all the necessary data are
#   collected or imported. There is no point in altering the journal on exit,
#   if user declined to start watching something halfway.
exit_trap() { export_session_data; }
trap "exit_trap; trap - EXIT HUP INT QUIT KILL" EXIT HUP INT QUIT KILL
# A good place to check the $MODE.
until [ -v STOP ]; do
	watch || exit $?
	[ $MODE = episodes ] \
		&& [ "$LAST_EP_NUMBER_SHOW_AFTER" = player \
		  -o "$LAST_EP_NUMBER_SHOW_AFTER" = both ] \
		&& print_last_shown_episode_number
		[ -v STOP ] || {
			[ -v RUN_IN_CYCLE ] && {
				echo -en "Press $g<Space>$s to stop > "
				read -n1 -t ${INTERVAL:-3}
				# Avoiding [C to get to mpv’s input in case right arrow
				#   is still hold. If mpv reads them, it’ll try to interpret
				#   them as commands, and [ is usually bound to decrease speed
				#   by multiplying it on 0.9.
				[ "$REPLY" = $'\e' ] && read -sn2 rest && REPLY+="$rest"
				echo
				[ "$REPLY" = ' ' ] && STOP=t || IT_IS_NEXT_ITERATION=t
			}|| STOP=t
		}
done
screenshots_postprocessing && [ $MODE = episodes ] \
	&& [ "$LAST_EP_NUMBER_SHOW_AFTER" = screenshots \
	  -o "$LAST_EP_NUMBER_SHOW_AFTER" = both ] \
	&& print_last_shown_episode_number
export_session_data || exit $?
