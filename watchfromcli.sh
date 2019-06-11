#! /usr/bin/env bash

#  watchfromcli.sh
#  A shell wrapper for mpv to launch videos easy via CLI.
#  © deterenkelt 2013–2019

 # This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License as published
#  by the Free Software Foundation; either version 3 of the License,
#  or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but without any warranty; without even the implied warranty
#  of merchantability or fitness for a particular purpose.
#  See the GNU General Public License for more details.


# Requires
# GNU sed >= 4.2.1 (started developing with it).
# GNU grep >= 2.9 (started developing with it).
# GNU bash >= 4.4 (strongly).
# mimetype >= 0.28
# util-linux >= 2.20 (for getopt that is required, and taskset
#        which may be of use, but is optional).
# mplayer, mplayer2 or mpv.
#
# Works better with
# GNU parallel – to compress screenshots faster using all cores available
#       (or those available after restricting to those specified
#        to the -t or --taskset option).
# figlet – to draw last seen episode number with big ASCII art numbers.
# pngcrush – helps to reduce PNG image size, if you prefer it over JPEG.
#       (players tend to save PNG in an unoptimized format, which makes
#        screenshots very large. pngcrush recompresses them without quality
#        loss).
# pngtopam and cjpeg – are only needed for converting screenshots from PNG
#       (if you, for some reason use MPlayer, that can only save them to PNG)
#        to JPEG by the usage of --jpeg-compression. pngtopam is usually found
#        in the netpbm package and cjpeg in libjpeg-turbo.
# inotifywait, ps and pkill – for SUB_DELAY, is of use only with mpv.
#        The first belongs to intotify-tools and the latter – to procps package.


# extglob for the sake of it, expand_aliases to make aliases available for
#   MPLAYER_COMMAND
shopt -s extglob expand_aliases
set -feEuT

BAHELITE_CHERRYPICK_MODULES=(
	error_handling
	logging
	misc
)
. "$(dirname "$(realpath --logical "$0")")/lib/bahelite/bahelite.sh"
prepare_cachedir
start_logging

show_help() {
	cat <<-"EOF"
	Simplest form:
	    watch.sh [optional arguments] -d <basepath>  <keyword>

	To start watching cycle:
	    watch.sh [optional arguments] -c -d <basepath>  <keyword>

	To resume watching cycle:
	    watch.sh [optional arguments] <-r|-R>  [keyword]

	Open wiki <link>
	Send issues to Github <link>
	EOF
	exit 0
}


show_version() {
	cat <<-EOF
	watchfromcli.sh $VERSION
	© deterenkelt 2013–2019.
	License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
	This is free software: you are free to change and redistribute it.
	There is NO WARRANTY, to the extent permitted by law.
	EOF
	exit 0
}


cd "$PWD" 2>/dev/null || err 'Cannot run – current directory is removed.'



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

VERSION="20190611"

JOURNAL=~/.watch.sh/journal
JOURNAL_MAX_SIZE="64K" # w/o suffix for bytes, K for KiB, M for MiB et al.
JOURNAL_MINVER='20180409'

[ -d ~/.watch.sh ] || {
	mkdir -m755 ~/.watch.sh/ >/dev/null \
		|| err "Couldn’t create directory ~/.watch.sh."
}



GROUP_INDICATOR='┌│└⋅' # upper part/middle part/lower part/single

# If any of these patterns is met in a filename, which episode number
#   can’t be guessed, then it and all numbers met further can’t be
#   taken as a presumed episode number.
# Patterns are to be given to bash with enabled extglob. To be precise,
#   they’ll be used in an expression like this:
#   "${var%${NOT_EPNUMBERS[i]}*}"
NOT_EPNUMBERS=("240p" "360p" "480p" "720p" "1280??(?)?(?)720" "1080p" "1920??(?)?(?)1080" "@(h|H|h.|H.|x)264" "10?bit")

NO_AUTOSUB='--sub-auto=no'

# DEBUG MODE
# No function aggregator for debug messages because test [ -v D ]
#   is faster than function call (there would be lots of them).
# Also [ -v D ] is more visually distinguishable. descartes.jpg
[ -v D ] && {
	DEBUG_DIR="$HOME/.watch.sh/debug"
	[ -d "$DEBUG_DIR" ] && rm -rf "$DEBUG_DIR"
	mkdir -m755 "$DEBUG_DIR" >/dev/null || err "Couldn’t create directory ‘$DEBUG_DIR’."
	for i in "$0" "$@"; do echo "\"$i\"" >>"$DEBUG_DIR/cmdline"; done
	vars="`set -o posix; set`"
}

set_libdir
#  Escaping for pattern and replacement.
. "$LIBDIR/sed_helpers.sh"
#  To be removed, when the entire code is reviewed and remade for Bahelite.
. "$LIBDIR/misc_helpers.sh"
set_modulesdir
set +f
for module in "$MODULESDIR"/watchfromcli_*.sh ; do
	. "$module" || err "Couldn’t source module $module."
done
set -f


is_this_the_last_item() {
	# If [ $MODE = bd ] then VIDEO* vars will be empty
	[    ${VIDEO_NUMBER:- 1} -eq ${VIDEOFILES_COUNT:- -1} \
      -o ${VIDEO_NUMBER:- 1} -eq ${EXIT_AFTER_THIS_EPISODE:- -1} ]
}

print_last_shown_episode_number() {
	echo
#	declare -p EP_NUMBERS
	local ep_number=${EP_NUMBERS[VIDEO_NUMBER-1]##*(0)}
	is_this_the_last_item && local last_item_finishing_mark=$LAST_ITEM_MARK
	$LAST_EP_NUMBER_PRINTING_COMMAND < \
		<( echo -e "${LAST_EP_NUMBER_PRINTING_FORMAT//%n/$ep_number}${last_item_finishing_mark:-}" )
}



                   #  Main algorithm starts here  #

process_args "${ARGS[@]}"
if [ -v RESUME ]; then
	import_session_data
else
	do_initial_search
fi
set_screenshot_subdir
# Exit trap should be here – after all the necessary data are collected or
#   imported. There is no point in altering the journal on exit, if user
#   declined to start watching something halfway.
on_exit() { export_session_data || exit $?; }


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

# screenshots_postprocessing && [ $MODE = episodes ] \
	# && [    "$LAST_EP_NUMBER_SHOW_AFTER" = screenshots    \
	     # -o "$LAST_EP_NUMBER_SHOW_AFTER" = both        ]  \
	# && print_last_shown_episode_number


echo
exit 0

# IDEAS
# ————————
# Add ED/OP as something equal to episode numbers in terms of sequences?
# Make a true check for multiple manual rearrangements expression.
# Create journal header to contain version for compatibility check.
# And integration with MyAnimeList. (Would be a pain with cases like Tekyuu (see below))
# Write modular localization.
# Rewrite it with C++.
#
# I’ve given it much thought, but still can’t decide, whether I should reduce heuristics levels down to two,
#   i.e. ‘enabled’ and ‘disabled’. On the one hand, this is how it’s meant to be – user either uses full-featured
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
#
# There are cases such as Teekyuu when all the episode can be marked sequentially, i.e. each new season continues
#   numbering insteadof starting from 01, 02… etc. Should the script try to find this case, if number of subtitle
#   files matches the number in the first group (simplest case?) But it may work bad in really messed up folders,
#   which would involve HEU2… when it will be finished.

# WAT DONE
# ————————

# TODO
# ————————
#
#   1. Check that in every damn find clause brackets are escaped.
#      Fucking find ignores ? * and lone [ and ] in -name "pattern",
#      but if said pattern will contain both [ and ], find will think
#      it’s time to enable GLOB pattern matching. Re⋅tar⋅da⋅tion.
#
#
#
# Add pstree to deps in deb and rpm.
# The purpose of this update is^W shoud have been to make HEU1 better (actual sorting by number included) and to make HEU2
#   ready for use, so this program would put on title ‘version 1.0’ with dignity.
# GROUP_INDICATOR must be 4 unique chars! Or not? Try to combine an array which would contain indices of groups
#   and start/end indices of the elements in VIDITEM_FILE[@], so we could use them instead of GI_*. // GI_*
#   must be unique in that case, and that may be inconvenient for the user and will require another cycle
#   for checking his own GROUP_INDICATOR.
# Group placed at the top, however, will still persist, and the topmost will be used for complementing in HEU2.
