#! /usr/bin/env bash

# watch.sh
# A wrapper for mpv/MPlayer to run videos easy via CLI.
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
# GNU sed >= 4.2.1 (started developing with it)
# GNU grep >= 2.9 (started developing with it)
# GNU bash >= 4.2 (strongly)
# file >= 5.17 (output format of that utility has been changing,
#        watch.sh conforms with 5.17 since v20140807)
# util-linux >= 2.20 (for getopt that is required, and taskset
#        which may be of use, but is optional)
# mplayer, mplayer2 or mpv. Syntax was optimized
#   for the first and the latter.
#
# Works better with
# GNU parallel — to compress screenshots faster using all cores available
#       (or those available after restricting to those specified
#        to the -t or --taskset option.)
# figlet — to draw last seen episode number with big ASCII art numbers.
# pngcrush — helps to reduce PNG image size, if you prefer it over JPEG.
#       (players tend to save PNG in an unoptimized format, which makes
#        screenshots very large. pngcrush recompresses them without quality
#        loss.)
# pngtopam and cjpeg — are only needed for converting screenshots from PNG
#       (if you, for some reason use MPlayer, that can only save them to PNG)
#        to JPEG by the usage of --jpeg-compression. pngtopam is usually found
#        in the netpbm package and cjpeg in libjpeg-turbo.

# extglob for the sake of it, expand_aliases to make aliases available for
#   MPLAYER_COMMAND
shopt -s extglob expand_aliases
# Disable pathname expansion. * in expressions with find may lead to unforseen
#   consequences.
set -f

show_help() {
cat <<"EOF"
Simpliest form:
    watch.sh [optional arguments] -d basepath  keyword

Watching cycle start:
    watch.sh [optional arguments] -c -d basepath  keyword

Resuming watching cycle:
    watch.sh [optional arguments] -[r|R]  [keyword]

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

[ ${BASH_VERSINFO[0]:-0} -eq 4 ] &&
[ ${BASH_VERSINFO[1]:-0} -le 1 ] ||
[ ${BASH_VERSINFO[0]:-0} -le 3 ] && {
	echo "Bash v4.2 or higher required." >&2
	return 3 2>/dev/null || exit 3
}

[ "$BASH_SOURCE" != "$0" ] && {
	echo 'This script shouldn’t be sourced. See usage (-h).' >&2
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
			code=108; msg='Couldn’t create directory “$DEBUG_DIR”.';;
		getopt*)
			code=8;	msg='getopt returned an error while parsing command line. It was probably caused\n  by ';;&
		getopt_funcerr)
			msg+='the getopt() function error. If it’s not just an unrecognized option,\n  then see man 3 getopt.';;
		getopt_wrongparam)
			msg+='the parameters getopt wasn’t been able to parse correctly.';;
		getopt_internal)
			msg+='an internal error. Is there enough memory available?';;
		getopt_dumbme)
			msg+='the reason you shall probably know by yourself.';;
		opt_bashrc)
			code=9; msg='Option --bashrc takes an argument that has to be bash source file.';;
		opt_compat)
			code=10; msg='Option --compat requires an argument to be one of “mplayer”, “mplayer2” or “mpv-03x”.';;
		opt_basedir)
			code=11; msg="-d|--basedir: “$arg” is not a readable directory.";;
		opt_heulevel)
			code=12; msg="Option --heuristics-level requires an argument to be a number lower or equal to $MAX_HEURISTICS_LEVEL.";;
		opt_inputinvalid)
			code=13; msg='RESERVED';;
		opt_jentries)
			code=14; msg='Option -j|--list-journal takes\n  - a number between 1 and 65535;\n  - a single letter “a” or “all” to display all keywords.';;
		opt_journalsize)
			code=15; msg='Option --journal-max-size requires an argument to be a number of bytes that\n  may be followed by one of these suffixes: K M G to represent *2^10 once,\n  twice or three times.';;
		opt_jpegcompression)
			code=16; msg='Option --jpeg-compression takes an argument that has to be a number between 0 and 100.';;
		opt_lepshowafter)
			code=19; msg='Option --last-ep-show-after requires an argument to be one of\n  - player;\n  - screenshots;\n  - both.';;
		opt_limitsec)
			code=20; msg='RESERVED';;
		opt_taskset)
			code=26; msg='Option -t|--taskset-cpulist requires an argument to be a valid CPU list.\n See `man taskset` for the details.';;
		doushiyou)
			code=27; msg='DOUSHIYOU~?';;
		mpcmd_not_found)
			code=28; msg="No such binary or alias found: “$MPLAYER_COMMAND”.";;
		no_keyword)
			code=29; msg='No keyword given.';;
		no_matches)
			code=30; msg='No matches!';;
		empty_folder)
			# CHOSEN_ONE shall be set at the time of possibility of this error,
			#   so BASEPATH shouldn’t be an array already.
			code=31; msg="I couldn’t find any video files in
$BASEPATH${CHOSEN_ONE:-}${SUBFOLDERS:-}
Check your --subfolders pattern.";;
		chosen_one_is_unreadable)
			code=32; msg="“$CHOSEN_ONE” is not readable!";;
		user_declined_input)
			code=33; nomsg=t ;;
		heu2_nan)
			code=109; msg="Error on heuristics 2nd level: “${matches_as_numbers[j]}” and “${matches_as_numbers[k]}” must be numbers.";;
		scrdir_isnt_writeable)
			code=34; msg="No sufficient rights to write to “$screens_path”.";;
		cant_create_scrdir)
			code=35; msg="Couldn’t create directory “$screens_path”.";;
		cant_retrieve_from_journal)
			code=36; msg='Couldn’t retrieve data from journal.'
			[ "$KEYWORD" ] && msg+='\nThis was probably caused by a record at the end of journal and happened because\n  cleansing of broken entries is not implemented yet.';;
		nothing_to_restore)
			code=37; msg="Not enough data to restore.
Couldn’t rereive $not_found_vars from the journal.
This might be caused by the broken file, trancated entry at the end of the journal (though such entries shouldn’t exist) or a new update that changed the mechanism of file searching and the list of required variables.";;
		cant_retrieve_journal_size)
			code=38; msg='Couldn’t retrieve journal size.';;
		cant_compute_journal_maxsize)
			code=39; msg='Couldn’t compute journal maximum size.';;
		cant_truncate_journal)
			code=40; msg='Couldn’t truncate journal.';;
		aborted_by_user)
			code=41; msg='Aborted by user.';;
		opt_requires_an_arg)
			code=42; msg="Option “$option” requires an argument.";;
		*)
			code=107; msg='Unknown error.';;
	esac
    [ -v nomsg ] || echo -e "$msg" >&2
    echo $code
}

which getopt &>/dev/null || exit `err no_getopt`

# Checking util-linux version
read -d $"\n" major minor < <(getopt -V | sed -rn 's/^[^0-9]+([0-9]+)\.?([0-9]+)?.*/\1\n\2/p')
[[ "$major" =~ ^[0-9]+$ ]] && [[ "$minor" =~ ^[0-9]+$ ]] \
	&& [ $major -ge 2 ] && ( [ $major -gt 2 ] || \
	                         [ $major -eq 2 -a $minor -ge 20 ] ) || exit `err old_utillinux`

# Variables typed in caps can be either
# - bash built-ins;
# - those ones that set parameters from the options passed through the command line;
# - kinda global;
# - or are important for maintaining the watching cycle between runs.

VERSION="20141016"

MAX_HEURISTICS_LEVEL=2
HEURISTICS_LEVEL=0

JOURNAL=~/.watch.sh/journal
JOURNAL_MAX_SIZE="64K" # w/o suffix for bytes, K for KiB, M for MiB etc.
[ -d ~/.watch.sh ] || {
	mkdir -m755 ~/.watch.sh/ >/dev/null \
		|| exit `err homedir`
}

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
                       aAcCd:eEfhH:Ij::JlM:m:nNrRs:S:t:Tv \
             --longoptions \
match-all,\
no-aid,\
bashrc::,\
run-in-cycle,\
no-color,\
compat:,\
basedir:,basepath:,\
heuristics-level:,\
help,\
ignore-disks,\
list-journal::,\
no-journal,\
journal-max-size:,\
jpeg-compression::,\
last-ep,\
last-ep-command:,\
last-ep-format:,\
mplayer-command:,\
mplayer-opts:,\
my-increment:,\
my-decrement:,\
match-number,\
dvd-bd-nav,\
resume,\
resume-from-previous,\
subfolders:,\
screenshot-dir:,\
screenshot-dir-skel:,\
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
		-A|'--no-aid') # hide hints
			NO_AID=t
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
		-f) # Treat KEYWORD as a fixed string (-F for grep).
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
				echo 'E! figlet is not installed.
I will use ‘cat’ to print the last shown episode number!.' >&2
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
			[ "$2" ] && MPLAYER_OPTS="$MPLAYER_OPTS $2" && shift 2 || exit `err opt_requires_an_arg`
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
		# -q|'--be-quiet')
		# 	# BE_QUIET=t
		# 	exec >/dev/null 2>&1
		# 	;;
		-R|'--resume-from-previous')
			RESUME_FROM_PREVIOUS=t
			;&
		-r|'--resume')
			RESUME=t
			IT_IS_NEXT_ITERATION=t  # Would “THIS_IS…” be better?
			RUN_IN_CYCLE=t
			shift
			;;
		'--retarded')
			RETARDED=t
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

# This check must be here because -M itself is optional.
MPLAYER_COMMAND=${MPLAYER_COMMAND:=mpv}
which "$MPLAYER_COMMAND" &>/dev/null || {
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
	[ -v COMPAT ] && echo "I’ve guessed COMPAT mode for $COMPAT." >&2
}

# This is default. For the latest mpv.
dashes='--'
declare -A mp_keys=(
	[bd-protocol]='bd'
	[sub-file]='sub-file'
	[audio-file]='audio-file'
)

case "$COMPAT" in
	mplayer) # the original MPlayer
		dashes='-'
		mp_keys[bd-protocol]='br'
		mp_keys[sub-file]='sub'
		mp_keys[audio-file]='audiofile'
		;;
	mplayer2) # mplayer2
		mp_keys[bd-protocol]='br'
		mp_keys[sub-file]='sub'
		mp_keys[audio-file]='audiofile'
		;;
	mpv-03x)
		mp_keys[sub-file]='sub'
		mp_keys[audio-file]='audiofile'
		;;
esac

KEYWORD="$*"
[ -v RESUME ] || {
	[ "${KEYWORD/@(*[^.]|)\**/}" ] || {
		echo -e '\nI’ve found that you used * in the pattern for keyword, and the patterns should use “.*” style, not just “*”.' >&2
		read -p 'Are you sure you want to continue? [N/y] > '
		[[ "$REPLY" =~ ^[yY]$ ]] || exit `err aborted_by_user`
	}
	[ "$KEYWORD" ] || exit `err no_keyword`
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
[ -v NO_COLOR ] || {
	[ -v RETARDED ] && {
		# retarded console with white bg
		w='\e[00;30m'    # black
		g='\e[00;32m'    # green
		r='\e[00;31m'    # red
		s='\e[00m'    # stop
		u='\e[04;30m'    # underline black
	}||{ # normal colors
		w='\e[00;37m'    # white
		g='\e[00;32m'    # green
		r='\e[00;31m'    # red
		s='\e[00m'    # stop
		u='\e[04;37m'    # underline white
	}
}

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
#     CHOSEN_ONE — file or folder which reside directly in BASEPATH and which name
#                  does match KEYWORD
#     MODE — 'single', means that script will play _a file_ in BASEPATH
#            'episodes', this way depends on IGNORE_DISKS variable, but in common
#                         that means at the end of the collected path there are
#                         videofiles, probably episodes.
#                         If IGNORE_DISKS is set, then any disk structure ignored
#                         and all files of your choice will be available to play
#                         _independently_ of the fact do they have KEYWORD in
#                         their names or not. If IGNORE_DISKS is not set, script
#                         will continue searching files matching KEYWORD
#                         at the end of the path.
#            'dvd'|'bd',  give a directive to player to treat the stuff
#                         at the end of the path as a disk.

# EXIT CODES: 0 if ok;
#            “no_matches” in case no matches were found;
#            “empty_folder” if found a folder but nothing to play in it;
#            “chosen_one_is_unreadable” if couldn’t read file or folder.
do_initial_search() {
	[ -v D ] && dbg_file="$DEBUG_DIR/initial_search"
	unset MODE CHOSEN_ONE SUBFOLDERS
	list_videofiles  search_by_keyword  ${BASEPATH[1]:+preserve_basepath} || return $?
	[ ${#BASEPATH[@]} -eq 1 ] \
		&& local dirs=`find -L "$BASEPATH" -maxdepth 1 -type d $KEYWORD_FIND_PATTERNS -printf "%f\n"` \
		|| local dirs=`find -L "${BASEPATH[@]}" -maxdepth 1 -type d $KEYWORD_FIND_PATTERNS -printf "%H: %f\n"`
	unset newline #  DELETE ME?

	[ "$dirs" ] && [ "$VIDEOFILES" ] && newline="\n"
	local matches="`echo -e "$dirs${newline:-}$VIDEOFILES"`"

	if [ "$matches" ]; then
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
			[ `grep -cF "${BASEPATH[i]}" <<<"$matches"` \
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
		# CHOSEN_ONE that will be chosen from $matches, will never
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
		[ `wc -l <<<"$matches"` -gt 1 ] && {
			choose_from "$matches" || return $?
			CHOSEN_ONE="$selected_one"
			# Now there can be the case that there were matches with different
			#   path, and the BASEPATH chosen by user is yet to be defined.
			# export -f escape_for_sed
			[ ${#BASEPATH[@]} -gt 1 ] && for ((i=0; i<${#BASEPATH[@]}; i++)); do
				# No local directive here!
				m=$(sed -rn "s/^`escape_for_sed_pattern "${BASEPATH[i]}"`: //p;T;Q1" <<<"$CHOSEN_ONE") || {
					CHOSEN_ONE="$m"
					BASEPATH[0]="${BASEPATH[i]}"
					break
				}
			done
			# export -nf escape_for_sed
			[ 1 -eq 1 ] # Yes, I dislike if… else… fi this much.
		}|| CHOSEN_ONE="$matches"
		local temp=${BASEPATH[0]}
		unset BASEPATH
		BASEPATH="$temp"
	else
		return `err no_matches`
	fi

	[ -r "$BASEPATH$CHOSEN_ONE" ] && {
		if [ -d "$BASEPATH$CHOSEN_ONE" ]; then
			MODE='episodes'
			# Yep, it’s a directory. Trying to search subfolders.
			[ -v IGNORE_DISKS ] && EXPECTED_SUBFOLDERS+=" VIDEO_TS BDMV "
			unset same_path # important!
			check_for_subfolders || return $?
			[ -v IGNORE_DISKS ] || {
				[ "`find "$BASEPATH/$CHOSEN_ONE${SUBFOLDERS:-}" -type d -name "VIDEO_TS"`" ] \
					&& MODE='dvd'
				[ "`find "$BASEPATH/$CHOSEN_ONE${SUBFOLDERS:-}" -type d -name "BDMV"`" ] \
					&& MODE='bd'
			}
# FIXME: Here must be check for the count of VIDEOFILES found at the end of
#        the path (with SUBFOLDERS). If count==1, change mode to single and
#        correct paths for “single” case appropriately. If there are
#        videofiles and they look like episodes, i.e. containing numbers
#        like 01, 02…
			[ $MODE != dvd -a $MODE != bd ] && {
				list_videofiles || return $?
				[ "$VIDEOFILES" ] && {
					[ "`echo "$VIDEOFILES" | wc -l`" -eq 1 ] && {
						MODE=single
						videofile="$VIDEOFILES"
					}
					[ 1 -eq 1 ]
				}|| return `err empty_folder`
			}
		else
			videofile="$CHOSEN_ONE"
			unset CHOSEN_ONE
			MODE='single'
		fi
		[ 1 -eq 1 ]
	}|| return `err chosen_one_is_unreadable`
	return 0
}

# EXPECTS:
#     KEYWORD ($1 requirement) — set, non-empty string
#     BASEPATH — set, non-empty string or an array
#     CHOSEN_ONE — may be unset, if BASEPATH is an array
#     SUBFOLDERS — may be unset, if BASEPATH is an array
# TAKES:
#     $1 — whether or no search by the KEYWORD. This depends on the time this
#          function called, if the first time needed the keyword to define
#          CHOSEN_ONE, for example, then the second time assumes anything lying
#          there is wanted by default.
#     $2 — whether to preserve BASEPATH. This is an important thing at an early
#          stage when called first time from do_initial_search() and BASEPATH
#          is an array.
# P.S.: Be afraid—this function gave me very strange bugs not accepting second
#       parameter and pointing to the last line of the first subshell.
list_videofiles() {
	local result
	[ "$1" = search_by_keyword ] && local searchkeyword="$KEYWORD_FIND_PATTERNS"
	[ "$2" = preserve_basepath ] && local preserve_basepath=t
	# Single files residing directly in BASEPATH
	VIDEOFILES=`find -L "${BASEPATH[@]}${CHOSEN_ONE:-}${SUBFOLDERS:-}" \
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
#     CHOSEN_ONE — existed and readable directory
#     SUBFOLDERS — not set
#     EXPECTED_SUBFOLDERS — be correct
# SETS:
#     SUBFOLDERS — path between CHOSEN_ONE and actual filename to play (excepting them)
# EXIT CODES: 0 if ok, >0 if error occured in internal function calls.
check_for_subfolders() {
	FUNCNEST=12 # to avoid possible bug with a loop in symlinked dirs.
	[ "$BASEPATH$CHOSEN_ONE${SUBFOLDERS:-}" = "${same_path:-}" ] && {
		# IGNORE_DISKS is set and it is a bluray disk, but files for the
		#   list of episodes usually reside in BDMV/STREAM, unlike DVD do,
		#   where they’re directly in VIDEO_TS folder.
		[ "$SUBFOLDERS" -a -z "${SUBFOLDERS##*/BDMV/}" ] && SUBFOLDERS+='STREAM/'
		return 0
	}
	# not local!
	same_path="$BASEPATH$CHOSEN_ONE${SUBFOLDERS:-}"
	for word in ${EXPECTED_SUBFOLDERS:-}; do
		internal_dirs=`find -L "$BASEPATH$CHOSEN_ONE${SUBFOLDERS:-}" -mindepth 1 -maxdepth 1 -type d -iname "*${word}*" -printf "%f\n"`
		[ "$internal_dirs" ] && {
			[ `echo -e "$internal_dirs" | wc -l` -gt 1 ] && {
				choose_from "$internal_dirs" || return $?
				SUBFOLDERS+="/$selected_one/"
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
#     selected_one — set to the line from the $1 which number is $reply
# EXIT CODES: 0 if line(s) was(were) successfully picked,
#            “user_declined” in case of
#              - <Return> was hit (choice was declined);
#              - wrong number entered;
#              - not a number entered (prevented).
choose_from() {
	unset disable_heuristics print_screenshot_dir
	# [ ${FUNCNAME[1]} != watch ] && local disable_heuristics=t
	[ ${FUNCNAME[1]} = screenshots_preprocessing ] && local print_screenshot_dir=t
	LIST_TO_CHOOSE_FROM=`sort <<<"$1"`
	LIST_ITEMS_COUNT=`echo -e "$LIST_TO_CHOOSE_FROM" | wc -l`
	local cols=`tput cols`
	unset choice_made list_variants_available ROTATE_PATTERN_LIST mapfile_patterns MAPPAT_INDEX_OFFSET
	until [ -v choice_made ]; do
		# [ -v disable_heuristics ] || [ $HEURISTICS_LEVEL -eq 0 ] || {
		# Could it be replaced with && … &&?
		[ ${FUNCNAME[1]} != watch ] || [ $HEURISTICS_LEVEL -eq 0 ] || {
			dbg_file="$DEBUG_DIR/choose_from_[watch]"
			[ -v mapfile_patterns ] || create_patterns_for_the_list || return $?
			build_the_list || return $?
		}
		[ ${FUNCNAME[1]} = watch ] && VIDEOFILES="$LIST_TO_CHOOSE_FROM"
		# Showing current paths:
		# V: here is shown where the script looks for videofiles at this moment
		[ -v NO_AID ] || echo ' ↙ I currently look for videofiles here.'
		for ((i=0; i<${#BASEPATH[@]}; i++)); do
			local path_to_video="${BASEPATH[i]}${CHOSEN_ONE:-}${SUBFOLDERS:-}"
			local max_width=$(($cols-4))
			[ ${#path_to_video} -gt $max_width ] && path_to_video="…${path_to_video:0-$max_width:$max_width}"
			echo -e "${w}V: $path_to_video$s"
		done
		# C: current working directory (CWD), the directory in which the shell
		#    operates.
		[ -v NO_AID ] || echo ' ↙ The directory I’m currently in.'
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
		[ -v print_screenshot_dir ] && {
			local safe_screenshot_dir="$SCREENSHOT_DIR"
			[ ${#safe_screenshot_dir} -gt $max_width ] && ="…${safe_screenshot_dir:0-$max_width:$max_width}"
			[ -v NO_AID ] || echo ' ↙ Screenshot directory as it was passed.'
			echo "S: $safe_screenshot_dir"
		}
		[ -v NO_AID ] ||
		echo ' ↙ Pick a number from the list.'
		[ ${FUNCNAME[1]} = watch -a $HEURISTICS_LEVEL -gt 0 ] && {
			# The idea is providing a “new-list-to-choose-from” which would be
			#   an array, so we could highlight not a keyword and hypotetic(?)
			#   episode number, but a part of line that matched current pattern.
			local lcount=1 match
			unset used_matches
			[ -v D ] && {
				dbg_file="$DEBUG_DIR/choose_from_while_in_watch"
				declare -p mapfile_patterns mapfile_matches mapfile_matches_count | tee -a $dbg_file
			}
			for ((i=0; i<${#mapfile_patterns[@]}; i++)); do
				for ((j=0; j<${mapfile_matches_count[i]}; j++)); do
					pat_for_grep=${mapfile_patterns[i]%\[^0-9]\.\**}
					[ "$pat_for_grep" = "${mapfile_patterns[i]}" ] \
						&& pat_for_grep=${mapfile_patterns[i]#^\.\*\[^0-9]}
					unset new_match_found
					until [ -v new_match_found ]; do
						match=`sed -n $((j+1))p <<<"${mapfile_matches[i]}"`
						[ $i -eq 0 ] && break # matches of the 1st pattern are unique
						echo -e "$used_matches" | grep -qF "$match" \
							&& { [ $((++j)) -eq ${mapfile_matches_count[i]} ] && break 2 || [ 1 -eq 1 ]; } \
							|| local new_match_found=t
					done
					echo -en "${g}$lcount:${s}"
					[ -v D ] && echo -en "${g}$i:${s}"
					echo "$match" | grep -iG "$pat_for_grep" # BGE, basic regex
					used_matches="${used_matches:+$used_matches\n}$match"
					# We use mapfile_matches[i], because HEU LVL2 does sorting in place
					[ $((++lcount)) -gt $LIST_ITEMS_COUNT ] && break 2
				done
			done

			[ -v D ] && declare -p used_matches | tee -a $dbg_file
			# This is subject for testing. Since each filename that doesn’t
			#   conform to a known pattern must start a new sequence, there
			#   shouldn’t be any filenames “on their own”. But to be sure
			#   we won’t lost them if they’ve suddenly appeared…
			# used_matches=`echo -e "$used_matches"`
			unique_lines=`echo -e "${used_matches:+${used_matches}\n}$LIST_TO_CHOOSE_FROM" | sort | uniq -u`
			[ "$unique_lines" ] && {
				used_matches="${used_matches:+${used_matches}\n}$unique_lines"
				used_matches=`echo -e "$used_matches"`
				while read unique_line; do
					echo -en "${g}$((lcount++)):${s}"
					[ -v D ] && echo -en "${g}-:${s}"
					grep -iG "\($KEYWORD\|$\)" <<<"$unique_line"
				done < <(echo "$unique_lines")
				[ -v D ] && echo -e "\nThe new list contains line(s), which has(ve) no pattern.
unique_lines [--->\n$unique_lines\n<---]
This could happen if there was just a file with a unique name or some file has
  managed to appear more than once via another pattern, and another file became
  an outsider due to LIST_ITEMS_COUNT limit, then that’s a problem." >>$dbg_file
			}
			VIDEOFILES=`echo -e "$used_matches"`
			LIST_TO_CHOOSE_FROM="$VIDEOFILES"
			[ 1 -eq 1 ] # Yes, I hate ifs this much.
		}|| echo -e "$LIST_TO_CHOOSE_FROM" | grep -niG "\($KEYWORD\|$\)"

		unset another_view prompt_heuristics_up prompt_heuristics_down
		local prompt_numbers="Pick $g<number>$s"
		[ $HEURISTICS_LEVEL -gt 0 ] && [ -v list_variants_available ] \
			&& local another_view="View: $w[${MAPPAT_INDEX_OFFSET:=1}/${#mapfile_patterns[@]}]$s, $g<Tab>$s to alter, "
		[ $HEURISTICS_LEVEL -lt $MAX_HEURISTICS_LEVEL ] \
			&& local prompt_heuristics_up="$g<H>$s to raise heuristics level"
		[ $HEURISTICS_LEVEL -gt 0 ] && {
			unset hl comma
			[ ! -v prompt_heuristics_up ] && local hl=' heuristics level' || local comma=', '
			local prompt_heuristics_down="${comma:-}$g<h>$s to lower${hl:-}"
		}
		[ -v NO_AID ] || {
			local num_choosing_hint="[$MY_DECREMENT↓0-9↑$MY_INCREMENT] "
			echo ' ↙ Commands to rebuild the list in other way, if possible.'
		}
		local prompt_1st_line="${another_view:-}${prompt_heuristics_up}${prompt_heuristics_down}."
		local prompt_2nd_line="$prompt_numbers or hit $g<Return>$s to return ${num_choosing_hint}> "
		local prompt="${prompt_1st_line}\n${prompt_2nd_line}"
		echo -ne "$prompt"

		# `local` is poinless for these two, because big cycle and <TAB>.
		unset reply reply_is_ready
		local up=$'\e[A'        # Use C-v <key> to print its escape sequence.
		local down=$'\e[B'
		local backspace=$'\177'        # Octals work, too!
		until [ -v reply_is_ready ]; do
			# [ ${#reply} -gt 5 ] && reply=${reply:$((${#reply}-5))}
			[ ${#reply} -gt 5 ] && reply=${reply:0:5}
			read -n1 -p "$reply" -s char
			[ "$char" = $'\e' ] && {
				while read -n2 -s rest; do char+="$rest"; break; done
				[ 1 -eq 1 ]
			}
			[ $HEURISTICS_LEVEL -eq 0 ] || {
				[ "$char" = $'\t' ] && {
					[ -v list_variants_available ] && ROTATE_PATTERN_LIST=t
					echo && continue 2
				}
				[ "$char" = 'H' ] && {
					[ $HEURISTICS_LEVEL -lt $MAX_HEURISTICS_LEVEL ] &&
					let HEURISTICS_LEVEL++
					MAPPAT_INDEX_OFFSET=1
					echo && continue 2
				}
				[ "$char" = 'h' ] && {
					[ $HEURISTICS_LEVEL -gt 0 ] &&
					let HEURISTICS_LEVEL--
					MAPPAT_INDEX_OFFSET=1
					echo && continue 2
				}
			}

			[ "$char" ] && {
				if [ "$char" = "$backspace" ]; then
					[ ${#reply} -gt 0 ] && reply=${reply::-1}
				elif [ "$char" = "$up" -o "$char" = "$MY_INCREMENT" ]; then
					[ "$reply" ] || local reply=0
					[[ "$reply" =~ ^[0-9]+$ ]] \
						&& [ $reply -lt $LIST_ITEMS_COUNT ] \
						&& let reply++ || {
							[ $reply -gt $LIST_ITEMS_COUNT ] \
								&& reply=$LIST_ITEMS_COUNT
					}
				elif [ "$char" = "$down" -o "$char" = "$MY_DECREMENT" ]; then
					[ "$reply" ] || local reply=0
					[[ "$reply" =~ ^[0-9]+$ ]] \
						&& [ $reply -gt 1 ] && {
							[ $reply -gt $LIST_ITEMS_COUNT ] \
								&& reply=$LIST_ITEMS_COUNT \
								|| let reply--
					}
				else
					[[ "$char" =~ ^[0-9]$ ]] && reply="$reply$char"
				fi
				echo -ne "\r\e[K$prompt_2nd_line" # \K lear line
			}||{ reply_is_ready=t; echo; }
		done

		unset selected_one
		[ "$reply" ] && {
			[[ "$reply" =~ ^[0-9]+$ ]] && {
				[ $reply -le $LIST_ITEMS_COUNT ] && [ $reply -gt 0 ] \
					&& selected_one=`echo -e "$LIST_TO_CHOOSE_FROM" | sed -n "$reply p"` \
					|| echo "Number must be the number of the line." >&2
			}|| echo "“$reply” must be a number." >&2
		}
		[ -v selected_one ] && choice_made=t || return `err user_declined_input`
	done
return 0
}

# This function’s purpose is to create patterns of similarity among files
#   in a folder contents, so build_the_list() could build (and rebuild)
#   the list in accordance with the conception that we must line up
#   the list of episodes in the correct order.
create_patterns_for_the_list() {
	[ -v D ] && {
		dbg_file="$DEBUG_DIR/patterns"
		echo "$LIST_TO_CHOOSE_FROM" >"$DEBUG_DIR/patterns_ltcf"
	}
	unset mapfile_patterns mapfile_matches mapfile_matches_count
	# In origin this function was a part of another function where is was
	#   checking the list of possible candidates to $videofile variable
	#   (at the end of the “eval” in watch()), and those ones were really
	#   existed files. But now it’s part of “choose_from” function, so
	#   the list passing to it may be list of folders, subfolders, video,
	#   subtitle files et cetera.
	#
	# Just don’t believe ↙that “filename” is an actual filename. I just couldn’t
	#   imagine a more proper name.
	while read filename; do
		[ -v D ] && echo "FN: “$filename”." >>$dbg_file
		# Match current filename against known patterns
		[ -v mapfile_patterns ] && {
			for pattern in "${mapfile_patterns[@]}"; do
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
			[ "${MAPFILE[i]//[^0-9]/}" ] && {
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
				#   $LIST_TO_CHOOSE_FROM but with number substituted with
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
				#   number” — [^0-9]\?
				multinum_patterns=( "^$left_part[0-9]\+[^0-9].*$" \
					"^.*[^0-9][0-9]\+$right_part$" \
					"^[0-9]\+$right_part$" \
					"^$left_part[0-9]\+$right_part$" ) # Both parts — the last!
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

				# If either of left or right parts appear empty, this will cause
				#   the non-empty one and the pattern with both of them
				#  (whicht is supposed to be the last element) to be the same,
				#   causing a bug with duplication.
				[ -z "$left_part" -o -z "$right_part" ] && {
					unset inc_patterns[${#inc_patterns}]
					[ -v D ] && echo -e '\t Unsetting pattern with incremented number and both (left and right) parts
\t   of the filename in attempt to avoid pattern duplicate.' >>$dbg_file
				}

				for ((j=0; j<${#inc_patterns[@]}; j++)) do
				[ -v D ] && echo -en "\t\tInc. pattern: “${inc_patterns[j]}”.\n\t\t\tSequence found? " >>$dbg_file
				matches=$(echo "$LIST_TO_CHOOSE_FROM" | sed -n '/'"${inc_patterns[j]}"'/p' )
				[ "$matches" ] && {
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
					[[ "$matches_count" =~ ^[0-9]+$ ]] && [ $matches_count -gt 1 ] && {
						[ -v D ] && echo -en "\t\t\tUnique? " >>$dbg_file
						unset same_matches_found
						# Now check if any pattern already produced the same list of matches.
						for ((k=0; k<${#mapfile_matches[@]}; k++)); do
							[ "$matches" = "${mapfile_matches[k]}" ] && {
								same_matches_found=t
								[ -v D ] && echo 'No.' >>$dbg_file
								break
							}
						done
						[ -v same_matches_found ] || {
							[ -v D ] && echo -e "Yes.\nADD\t\t\tMultinum pattern: “${multinum_patterns[j]}”." >>$dbg_file
							# TODO: make some flag to define the situation when no number is present. # Er… how’s that?
							# I thouhgt about renaming these variables to fname_*, but  mapfile_* clearly points at the place of origin.
							mapfile_patterns[${#mapfile_patterns[@]}]="${multinum_patterns[j]}"
							mapfile_matches[${#mapfile_patterns[@]}-1]="$matches"
							mapfile_matches_count[${#mapfile_patterns[@]}-1]=$matches_count
						} # list of matches is unique
						[ 1 -eq 1 ] # yes I hate ifs this much.
					}||{ [ -v D ] && echo -e "\n#\t\t\tMULTINUM EXPRESSION FAILED!
\t\t\tSequence was found, but multinum pattern couldn’t find even two filenames.\n" >>$dbg_file; } # multinumber pattern found two or more matches
					[ 1 -eq 1 ] # yes I hate ifs this much.
				}||{ [ -v D ] && echo 'No.' >>$dbg_file; } # inc_pattern[j] found a sequence (non-empty match list)
				done # for j in inc_patterns[@]
				[ 1 -eq 1 ] # yes I hate ifs this much.
			}||{ [ -v D ] && echo 'No.' >>$dbg_file; }  # MAPFILE[i] is a number
		done # for i in MAPFILE[@]
	done  < <(echo "$LIST_TO_CHOOSE_FROM")  # $LIST_TO_CHOOSE_FROM _never_ has a '\n' here.
return 0
}

# EXPECTS:
#     - that you know why some characters should be escaped;
#     - that the output will be used in the subshell, i.e. $(…)
#       so don’t make assignings like
#           var1=`escape_for_sed_pattern "blablabla"`
#       but use subshell in place
#
# TAKES:
#     $1 – a string to escape.
# RETURNS: an escaped string.
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
	str=${str//\[/\\[} 	# …add round parentheses too?
	# str=${str//\]/\\]}
	# Just in case. There must be no slashes. If sed suddenly starts
	#   throw errors like
	#     sed: -e expression #1, char 84: extra characters after command
	#     sed: -e expression #1, char 77: unknown command: `o'
	#     sed: -e expression #1, char 102: Invalid range end
	#   especially when BASEPATH is an array, this may mean that folder paths
	#   have appeared in the pattern when they should not, because
	#   create_patterns_for_the_list() must only process _file names_ when
	#   MODE == episodes and choose_from() was called from watch().
	# P.S. Slashes are used in do_initial_search() when removing
	#   duplicates from d.
	str=${str//\//\\/}
	str=${str//\^/\\^}
	echo -ne "$str" # TODO: check for what purpose is -e here
}


build_the_list() {
	[ -v D ] && {
		dbg_file="$DEBUG_DIR/pattern_groups"
		declare -p mapfile_patterns mapfile_matches mapfile_matches_count >>$dbg_file
	}
	# If we have no patterns and therefore, no matches, that’s bad
	#   and we have to fallback, there’s no error produced since
	#   the list_to_choose_from still exist, so we just don’t touch it.
	[ ${#mapfile_patterns[@]} -eq 0 ] && {
		[ -v D ] && echo 'No patterns.' >>$dbg_file
		return 0
	}

	[ ${#mapfile_patterns[@]} -gt 1 ] \
		&& list_variants_available=${#mapfile_matches_count[@]}

	[ -v list_variants_available ] && {
		[ -v D ] && echo "List variants available: $list_variants_available." >>$dbg_file
		# There is >1 pattern, we can sort and rotate patterns.
		[ -v ROTATE_PATTERN_LIST ] && {
			[ -v D ] && echo 'ROTATING' >>$dbg_file
			# ┌─────────────────────>──────────┐
			# ^   TAB in menu rotates groups   v
			# └──────────<─────────────────────┘
			patterns_buffer="${mapfile_patterns[0]}"
			matches_buffer="${mapfile_matches[0]}"
			matches_count_buffer="${mapfile_matches_count[0]}"
			for ((i=1; i<${#mapfile_patterns[@]}; i++)); do
				mapfile_patterns[i-1]="${mapfile_patterns[i]}"
				mapfile_matches[i-1]="${mapfile_matches[i]}"
				mapfile_matches_count[i-1]="${mapfile_matches_count[i]}"
			done
			mapfile_patterns[${#mapfile_patterns[@]}-1]="$patterns_buffer"
			mapfile_matches[${#mapfile_patterns[@]}-1]="$matches_buffer"
			mapfile_matches_count[${#mapfile_patterns[@]}-1]="$matches_count_buffer"
			[ $((++MAPPAT_INDEX_OFFSET)) -gt ${#mapfile_patterns[@]} ] && MAPPAT_INDEX_OFFSET=1 # why not 0?
			[ -v D ] && declare -p MAPPAT_INDEX_OFFSET >>$dbg_file
			unset ROTATE_PATTERN_LIST
		}||{
			[ -v D ] && echo 'SORTING' >>$dbg_file
			# Do initial groups sorting.
			# Sort patterns descending by the number of matches OR
			#   lexicographically if numbers are equal
			for (( i=0; i<${#mapfile_patterns[@]}-1; i++)); do
				for (( j=$i+1; j<${#mapfile_patterns[@]}; j++)); do
					( [ ${mapfile_matches_count[i]} -lt ${mapfile_matches_count[j]} ] ||
						( [ ${mapfile_matches_count[i]} -eq ${mapfile_matches_count[j]} ] &&
							[[ "${mapfile_patterns[i]}" > "${mapfile_patterns[j]}" ]] ) ) && {
						# Biggest number of matches → to the top of the array.
						buffer="${mapfile_patterns[i]}"
						mapfile_patterns[i]="${mapfile_patterns[j]}"
						mapfile_patterns[j]="$buffer"
						buffer="${mapfile_matches[i]}"
						mapfile_matches[i]="${mapfile_matches[j]}"
						mapfile_matches[j]="$buffer"
						buffer="${mapfile_matches_count[i]}"
						mapfile_matches_count[i]="${mapfile_matches_count[j]}"
						mapfile_matches_count[j]="$buffer"
					}
				done
			done
			[ -v D ] && echo 'Sorted patterns:' >>$dbg_file
		}
	}
	[ -v D ] && {
		echo 'Some elements may span on multiple lines if they contain double quotes.
This is not a bug.' >>$dbg_file
		declare -p mapfile_patterns mapfile_matches mapfile_matches_count >>$dbg_file
	}

	# Resort all matches in each mapfile_matches[i] comparing numbers as numbers.
	[ $HEURISTICS_LEVEL -gt 1 ] && {
		[ -v D ] && echo -e '\n\nHEU LVL 2 start.' >>$dbg_file
		# Careful from here. This seems to build that way to work for both
		#   heuristic levels, so don’t accidentally put the cycle inside [ $HEU -gt 1 ]
		for ((i=0; i<${#mapfile_matches[@]}; i++)); do
			# Okay, we have them. But now it’s not much far away from the “sort” command.
			# Sort would find these numbers too (and put 1 after 10), we are a step forward
			#   only by finding a hint for a presence of sequence in those numbers.
			#   Now arrange these numbers to make them reflect this sequence.
			# Change pattern so it could grab found number in ([0-9]+).
			[ -v D ] && {
				echo -e "\tProcessing mapfile_matches[$i]\n\tList:" >>$dbg_file
				echo "${mapfile_matches[i]}" | sed 's/.*/\t\t“&”/g' >>$dbg_file
				echo -e "\tCount: ${mapfile_matches_count[i]}" >>$dbg_file
			}
			# Removing leading zeroes just to avoid possible misinterpretation as octal.
			subst_pattern=$(echo "${mapfile_patterns[i]}" | sed 's/\(\[0-9]\\+\)/0*\\([0-9]\\+\\)/' )
 			# We’re going to do a bubble sort against $matches_*, and that
			#   way we shall run this number extractor twice at every ite-
			#   ration to compare numbers, but creating a list of numbers
			#   and doing comparsion among them is 11 times faster.
			unset matches_as_array matches_as_numbers
			readarray -t matches_as_array < <(echo -e "${mapfile_matches[i]}")
			readarray -t matches_as_numbers < <(echo -e "${mapfile_matches[i]}" | sed -n "s/$subst_pattern/\1/p")
			[ -v D ] && declare -p matches_as_array matches_as_numbers >>$dbg_file
			unset mapfile_matches[i]
			for ((j=0; j<${#matches_as_array[@]}-1; j++)); do
				for ((k=$j+1; k<${#matches_as_array[@]}; k++)); do
					# Big numbers (of an episode) → to the end of the list
					[[ "${matches_as_numbers[j]}" =~ ^[0-9]+$
							&& "${matches_as_numbers[k]}" =~ ^[0-9]+$ ]] ||	return `err heu2_nan`
					[ ${matches_as_numbers[j]} -gt ${matches_as_numbers[k]} ] && {
						buffer="${matches_as_array[j]}"
						matches_as_array[j]="${matches_as_array[k]}"
						matches_as_array[k]="$buffer"
						buffer="${matches_as_numbers[j]}"
						matches_as_numbers[j]="${matches_as_numbers[k]}"
						matches_as_numbers[k]="$buffer"
					}
				done
				# Each j should be the smallest number from what’s left, i.e. 1, 2, 3…
				mapfile_matches[i]="${mapfile_matches[i]:+${mapfile_matches[i]}\n}${matches_as_array[j]}"
			done
			# We deleted the original item, remember? And now the last
			#  (and the biggest) match wasn’t added to the original array
			#   element back. Don’t be confused with a similar sort above,
			#   there was no deleteion of original mapfile elements!
			mapfile_matches[i]="${mapfile_matches[i]}\n${matches_as_array[j]}"
			mapfile_matches[i]=`echo -e "${mapfile_matches[i]}"` # `\n`
			[ -v D ] && {
				echo -e "\tList after resorting:" >>$dbg_file
				echo "${mapfile_matches[i]}" | sed 's/.*/\t\t“&”/g' >>$dbg_file
				echo -e "\tCount: ${mapfile_matches_count[i]}\n" >>$dbg_file
			}
		done
	}
	return 0
}

## Functions below this line do never execute during `do_initial_search`

# EXPECTS:
#     SCREENSHOT_DIR — be correct
#     KEYWORD — set, non-empty string
# SETS:
#     screens_path — path where pushd to, so MPlayer will store taken screenshots there.
# EXIT_CODES: 0 if ok,
#            “scrdir_isnt_writeable”, “cant_create_scrdir” in case
#             of insufficient rights to access $screens_path.
screenshots_preprocessing() {
	[ -v SCREENSHOT_DIR ] && {
		screens_path=`find -L "$SCREENSHOT_DIR" -maxdepth 1 -type d $KEYWORD_FIND_PATTERNS -printf "%f\n"`
		if [ "$screens_path" ]; then
			[ `echo "$screens_path" | wc -l` -gt 1 ] && {
				echo "Which directory to store screenshots in?"
				choose_from "$screens_path" &&
					screens_path="$SCREENSHOT_DIR/$selected_one" ||
					unset screens_path
			}|| screens_path="$SCREENSHOT_DIR/$screens_path"
		else
			echo -ne "No appropriate directory for screenshots found.\nType a long, correct name to create one or hit <Return> to skip > "
			read
			[ "$REPLY" ] && {
				screens_path="$SCREENSHOT_DIR/$REPLY"
				[ -d "$screens_path" ] && {
					[ -w "$screens_path" ] && [ -x "$screens_path" ] || return `err scrdir_isnt_writeable`
				}||{
					# eval is necessary for {} expansion in SCREENSHOT_DIR_SKEL
					eval mkdir -pm775 "${screens_path// /\ }/${SCREENSHOT_DIR_SKEL:+{${SCREENSHOT_DIR_SKEL// /\ }}}" || return `err cant_create_scrdir`
					# Keep escaping for the other special cahracters for later.
					# Now it will drag unescaping or eval’ing for all the further
					#   commands involving screens_path.
				}
			}|| unset screens_path
		fi
	}

	[ -v screens_path ] \
		&& pushd "$screens_path" >/dev/null \
		||{
			screens_path='.'
			echo "Current directory is about to hold screenshots."
		}
	watching_started=`date +%s`
	return 0
}

# EXPECTS:
#     MODE — set and be one of 'single', 'episodes' or 'dvd' strings.
#     IT_IS_NEXT_ITERATION — set only when execution is on the next iteration
#                            of `until` cycle, or it was resumed after
#                            interruption, i.e. RESUME, and therefore
#                            IT_IS_NEXT_ITERATION, is set.
#     RUN_IN_CYCLE — set only if script was called with -c or -r option.
#     INTRRUPTED — set if previous run of MPlayer was interrupted by <q>
#                  or <Esc>.
# SETS:
#     findpath — where to search for additional files (subtitles, audiotracks
#                etc.)
#     VIDEO_ITEM — line number from the list of VIDEOFILES.
#     videofile — videofile that will be playing, must be unset to play a disk
#                 as a disk.
#     episode_number — retrieved via EP_PATTERN applied to $videofile.
#     INTERRUPTED — used in “resume” case, means episode wasn’t watched till
#                   the end and must be re-played on resume.
#     stop — if MPlayer was interrupted by key, that stops the cycle too.
# RETURNS: 0 if ok, >0 if internal function call returned an error.
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
			if [ -v IT_IS_NEXT_ITERATION ]; then
				# If playback was interrupted, play last watched episode
				#   once again, otherwise increment episode number and play
				#   the next one otherwise.
				[ -v RESUME_AND_REPLAY ] || let VIDEO_ITEM++
				[ -v RESUME_FROM_PREVIOUS ] \
					&& [ $VIDEO_ITEM -gt 0 ] && let VIDEO_ITEM--
				unset RESUME_AND_REPLAY RESUME_FROM_PREVIOUS
				[ $VIDEO_ITEM -gt `echo -e "$VIDEOFILES" | wc -l` ] &&
				VIDEO_ITEM=1
				videofile=`echo -e "$VIDEOFILES" | sed -n "$VIDEO_ITEM p"`
			else
				# The beginning of watching cycle
				[ `echo "$VIDEOFILES" | wc -l` -gt 1 ] && {
					choose_from "$VIDEOFILES" || return $?
					videofile="$selected_one"
					VIDEO_ITEM=$reply
				}
			fi
			# Storing chosen pattern to EP_PATTERN
			#  (cycle has just started and the variable doesn’t exist yet).
			[ -v EP_PATTERN ] \
				|| EP_PATTERN=`sed -r 's/\[0-9]\\\\\+/\\\(&\\\)/' \
						               <<<${mapfile_patterns[0]}`
			episode_number=`sed -n "s/$EP_PATTERN/\1/p" <<<"$videofile"`
			[[ "$episode_number" =~ ^[0-9]+$ ]] || {
				echo 'Couldn’t get value for $episode_number. Reverting to $VIDEO_ITEM=='$VIDEO_ITEM >&2
				episode_number=$VIDEO_ITEM
			}
			;;
		dvd|bd)
			unset videofile
			if [ $MODE = dvd ]; then
				[ -v DVD_BD_NAV ] && local protocol=dvdnav || local protocol=dvd
				local device='dvd-device'
			else
				# bdnav is only supported by the mpv mplayer.
				[ -v DVD_BD_NAV ] && local protocol=bdnav || local protocol=${mp_keys[bd-protocol]}
				local device='bluray-device'
			fi

			if $MPLAYER_COMMAND ${dashes}profile help \
				|& grep -q "\<protocol.$protocol\>" ; then
				MPLAYER_OPTS=`echo "$MPLAYER_OPTS" \
				    | sed "s/${dashes}profile[= ]^\S+/&,protocol.$protocol/;T;Q1"`
				[ $? -eq 0 ] && \
					MPLAYER_OPTS+=" ${dashes}profile protocol.$protocol"
			else
				echo "Your $MPLAYER_COMMAND config doesn’t have profile “protocol.$protocol” set." >&2
			fi
			MPLAYER_OPTS+=" $protocol:// ${dashes}$device "
			;;
	esac

	## From now on, no more exits (except errors during the export to journal).

	[ $MODE = single -o $MODE = episodes ] && {
		[ "$SUBFOLDERS" ] || SUBFOLDERS='/'
		# Subtitles
		get_other_files "srt ass sub ssa" || return $?
		subtitles="$other_files_list"
		findpath="$BASEPATH${CHOSEN_ONE:-}${SUBFOLDERS:-}"
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
				subtitles="${dashes}${mp_keys[sub-file]} \"$subtitles\""
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
		tracks="${other_files_list}"
		[ "$tracks" ] && {
			[ -v COMPAT ] && {
				[ "`sed -n '$=' <<<"$other_files_list"`" -gt 1 ] \
					&& echo -e "${r}Multiple external tracks were found, but only the last one can be loaded.
Consider switching to the latest mpv if you want to load multiple tracks
  at once.${s}" >&2
				# tracks="${other_files_list// /\\\ }"
				tracks=`sed -n "$ s/.*/${dashes}${mp_keys[audio-file]} '$(escape_for_sed_replacement "$findpath")&'/p" <<<"$tracks"`
				[ 1 -eq 1 ]
			}|| tracks=`sed -r "s/.*/--audio-file='$(escape_for_sed_replacement "$findpath")&'/g" <<<"$tracks"`
		}
	} # MODE = single -o $MODE = episodes

# Path explanation
#
# <BASEPATH> <CHOSEN_ONE> [ <SUBFOLDERS> [videofile] ]
#             ^^^^^^^^^^                  ^^^^^^^^^
# The matched parts of the path may be ending ones.
# As of possible cases:
# 1. Single videofile in BASEPATH
# /home/video/  MononokeHime.mkv
# BASEPATH      videofile

# 2. Videofile inside of a folder found in BASEPATH
# /home/video/  Azumanga_Daioh      /           Azumanga_Daioh_01.mkv
# BASEPATH      CHOSEN_ONE          SUBFOLDERS  videofile

# 3. Videofile found inside of a subfolder under the folder found in BASEPATH
# /home/video/  Exosquad            /Season_1/  Exosquad_01.mkv
# BASEPATH      CHOSEN_ONE          SUBFOLDERS  videofile

# 4.a. The same goes for videofiles in VIDEO_TS folder, when option IGNORE_DISKS is set.
# /home/video/  Zeta_Project_Disk_1 /VIDEO_TS/  VTS_04_01.VOB
# BASEPATH      CHOSEN_ONE          SUBFOLDERS  videofile

# 4.b. If IGNORE_DISKS is not present, then the folder containing disk stuff
#      and matched KEYWORD becomes the path.
# /home/video/  Zeta_Project_Disk_1
# BASEPATH      CHOSEN_ONE

# NB: CHOSEN_ONE never has surrounding slashes. Neither in front nor behind.
#     videofile never has a slash in front of it.
	[ -v TASKSET_CPULIST ] && which taskset >/dev/null &&
	taskset_cmd="taskset --cpu-list $TASKSET_CPULIST"
# Spaces in filenames in $subtitles and $tracks may be lost w/o quotes here.
# TODO: Find out why altered DISPLAY breaks input to mplayer
# $MPLAYER_OPTS must be right before path because of protocol:// things
    eval  ${taskset_cmd:-} $MPLAYER_COMMAND  ${subtitles:-} ${tracks:-} \
		"$MPLAYER_OPTS" "\"$BASEPATH$CHOSEN_ONE${SUBFOLDERS:-}${videofile:-}\"" \
		| sed '$s/Quit/&/p;T;Q1' || {
			INTERRUPTED=t
			stop=t
		  }
	return 0
}

# EXPECTS:
#     findpath — where to search for additional files (subtitles, audiotracks etc.)
#     videofile – exact name match
#     KEYWORD — set, non-empty string
#     MATCH_NUMBER — set if called with -n, -a.
# TAKES:
#     $1 — non-empty string with a list of extensions to match agaist, must be
#          separated by space and contain no trailing space, like "abc def ghi"
# SETS:
#     other_files_list — list of files that reside in findpath, match by extension to what
#                was through $1 passed and all collected match_* rules
# RETURNS: 0 if ok, >0 if internal function call returned an error.
get_other_files() {
	matchext="$1"
	unset match_by_keyword_and_num match_by_num
	# W! This asterisk in the line below is under shell pathname expansion.
	ext=`echo "$matchext" | sed -r 's/\s/ -o /g; s^([a-zA-Z0-9_-]{3,})^-iname *.\1^g'`
	found_other_files=`find -L "$BASEPATH${CHOSEN_ONE:-}${SUBFOLDERS:-}" -maxdepth 1 -type f \( $ext \) -printf "%f\n"`
	match_by_name=`echo "$found_other_files" | grep -Fi "${videofile%.*}" | sort`
	other_files_list="$match_by_name" # exact name
	# TODO: This is the only place where KEYWORD is used as a fixed string.
	#       Need to replace KEYWORD with two variables
	#       KEYWORD_FOR_FIND with space substituted with “?” and
	#       KEYWORD_FOR_GREP with space replaced with “.”.
	#       Also either escape special symbols in KEYWORD, or somehow
	#       check UNICODE symbol class to be letter/hieroglyph.
	match_by_keyword=`echo "$found_other_files" | grep -i -${FIXED_STRING:-G} "$KEYWORD" | sort`
	[ -v D ] && {
		dbg_file="$DEBUG_DIR/other_files"
		declare -p ext found_other_files match_by_name >>$dbg_file
	}
	[ $MODE = episodes ] && {
		# This check may be not needed, but it’s safer to have it                    vvv     EP20v2    vvv
		match_by_keyword_and_num=`echo "$match_by_keyword" | grep -e "[^0-9a-oA-Oq-zQ-Z]$episode_number[^0-9a-uA-Uw-zW-Z]" | sort`
		other_files_list="${other_files_list:+${other_files_list}\n}$match_by_keyword_and_num"
		match_by_num=`echo "$found_other_files" | grep -e "[^0-9]$episode_number[^0-9]" | sort`
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
	[ -v MATCH_ALL -o -v MATCH_NUMBER ] && other_files_list="${other_files_list:+${other_files_list}\n}${match_by_num:-}"
	# Including files matching by keyword in search results requires MATCH_ALL
	#   to be set, because in case of lots of files matching that keyword many
	#   other unnecessary may be included (e.g. subtitles to 20 episodes). But,
	#   in case of the file is a single, in gives some confidence that there are
	#   not many other files, at least, not that much like in previous case.
	[ -v MATCH_ALL -o $MODE = single ] && other_files_list="${other_files_list:+${other_files_list}\n}$match_by_keyword"
	# Remove duplicates and empty lines
	other_files_list=`echo -e "$other_files_list" \
	                  | sed -nr 'G; s/\n/&&/; /^([[:print:]]*\n).*\n\1/d; s/\n//; h; P'`
	[ -v D ] && declare -p other_files_list >>$dbg_file
	return 0
}

# EXPECTS:
#     screens_path — if set, then we should be in screenshot directory
#                    and therefore, will be popd’d inside of the trap.
#     *.png — screenshots taken.
# RETURNS:  0 if the function processed screenshots, 1 if not. This is needed
#           to distinguish cases when it did the job and when it didn’t
#           to avoid printing last shown episode number twice.
screenshots_postprocessing() {
	# Seeking screenshots
	[ -v screens_path ] && {
		local new_screenshots=`find "$screens_path" -maxdepth 1 \
		                      -type f -iname "*.png" \
		                      -newermt @$watching_started -printf "%f\n"`
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
		[ "$new_screenshots" ] && {
			local result=0
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
				for shot in $new_screenshots; do
					${taskset_cmd:-} compress_screenshot "$shot"
				done
			fi
		}
	}
	return ${result:-1}
}

# EXIT CODES: 0 if OK, “cant_retrieve_from_journal”, “nothing_to_restore”.
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
						no_data=t
					}
				done
			}

			check_required_vars 'KEYWORD' 'KEYWORD_FIND_PATTERNS' 'MODE' 'BASEPATH'
			[ "$MODE" != single ] \
				&& check_required_vars 'CHOSEN_ONE' 'SUBFOLDERS' # it’s OK to check like that.
			[ "$MODE" = single ] \
				&& check_required_vars 'videofile'
			[ "$MODE" = episodes ] \
				&& check_required_vars 'VIDEOFILES' 'VIDEO_ITEM' 'EP_PATTERN' 'INTERRUPTED'
		}
		[ -v no_data ] && return `err nothing_to_restore`
		# Yes, it could be just one variable, but with two names, its purpose
		#   is clearer, hence easier to understand at both stages. Moreover,
		#   INTERRUPTED can’t be used to launch “until” cycle with “watch”
		#   function.
		[ "$INTERRUPTED" = yes ] && RESUME_AND_REPLAY=t
		unset INTERRUPTED
	}
	return 0

}

# TAKES: $1 string to prepare to be put in sed replacement string.
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
	echo -ne "$str"
}

# EXIT_CODES: 0 if OK, “cant_retrieve_journal_size”,
#            “cant_compute_journal_max_size”, “cant_truncate_journal”.
export_session_data() {
	[ -v NO_JOURNAL ] || {
		local data="KEYWORD='`escape_for_sed_replacement "$KEYWORD"`'"
		# [ -v T ] && data+="\nSTAMP=\\\"`date`\\\""
		data+="\nKEYWORD_FIND_PATTERNS='`escape_for_sed_replacement "$KEYWORD_FIND_PATTERNS"`'"
		[ -v FIXED_STRING ] && data+="\nFIXED_STRING='$FIXED_STRING'"
		data+="\nMODE='$MODE'"
		data+="\nBASEPATH='`escape_for_sed_replacement "$BASEPATH"`'"
		[ $MODE != single ] && {
			data+="\nCHOSEN_ONE='`escape_for_sed_replacement "$CHOSEN_ONE"`'" # only “&” and “'” actually
			[ "$SUBFOLDERS" ] && data+="\nSUBFOLDERS='${SUBFOLDERS//\//\\/}'"
		}
		[ $MODE = single ] \
			&& data+="\nvideofile='$(escape_for_sed_replacement "$videofile")'"
		[ $MODE = episodes ] && {
			# NB extra backslash in sed replacement. It’s there because sed called in a subshell.
			local videofiles_in_one_row="`echo -n "$(escape_for_sed_replacement "$VIDEOFILES")" | sed ':be N; s/\n/\\\n/g; b be'`"
			data+="\nVIDEOFILES='$videofiles_in_one_row'"
			data+="\nVIDEO_ITEM=$VIDEO_ITEM"
			# For what reason escape_for_sed_pattern was used here?
			#   was it just a mistake or not?
			data+="\nEP_PATTERN='$(escape_for_sed_replacement "${EP_PATTERN//\\/\\\\\\}")'"
			[ -v INTERRUPTED ] && data+="\nINTERRUPTED='yes'" || data+="\nINTERRUPTED='no'"
		}
		# removing old data
		sed -ri "/^KEYWORD='`escape_for_sed_pattern "$KEYWORD"`'/,/^$/ d" $JOURNAL
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
			# have shown that it may be fine as is, but more complicated ones must
			# be done.
		}
	}
	return 0
}

print_last_shown_episode_number() {
	local ep_number=${episode_number##*(0)}
	$LAST_EP_NUMBER_PRINTING_COMMAND < \
		<( echo -e "${LAST_EP_NUMBER_PRINTING_FORMAT//%n/$ep_number}" )
}

# Don’t forget to export data to the journal. It may be lost in case the machine
#   was shut down while the script was running and the video was on pause,
#   for example.
exit_trap() {
	export_session_data
}

## Main algorithm starts here

if [ -v RESUME ]; then
	import_session_data || exit $?
else
	do_initial_search || exit $?
fi
screenshots_preprocessing || exit $?
trap "exit_trap; trap - EXIT HUP INT QUIT KILL" EXIT HUP INT QUIT KILL
# $MODE can be checked here.
until [ -v stop ]; do
	watch || exit $?
	[ $MODE = episodes ] \
		&& [ "$LAST_EP_NUMBER_SHOW_AFTER" = player \
		  -o "$LAST_EP_NUMBER_SHOW_AFTER" = both ] \
		&& print_last_shown_episode_number
		[ -v stop ] || {
			[ -v RUN_IN_CYCLE ] && {
				echo -ne "Press $g<Space>$s to stop > "
				unset REPLY
				read -n1 -t3 ; echo
				[ "$REPLY" = ' ' ] && stop=t || IT_IS_NEXT_ITERATION=t
			}|| stop=t
		}
done
screenshots_postprocessing && [ $MODE = episodes ] \
	&& [ "$LAST_EP_NUMBER_SHOW_AFTER" = screenshots \
	  -o "$LAST_EP_NUMBER_SHOW_AFTER" = both ] \
	&& print_last_shown_episode_number
export_session_data || exit $?
exit 0
