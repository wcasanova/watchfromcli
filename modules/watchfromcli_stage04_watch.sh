# EXPECTS:
#     MODE – set and be one of 'single', 'episodes' or 'dvd' strings.
#     IT_IS_NEXT_ITERATION – set only when execution is on the next iteration
#         of `until` cycle, or it was resumed after interruption, i.e. RESUME,
#         and therefore IT_IS_NEXT_ITERATION, is set.
#     RUN_IN_CYCLE – set only if script was called with -c or -r option.
#     RESUME_AND_REPLAY (aka INTERRUPTED) – set if previous run of the player
#         in resumed session was interrupted in the middle of playing a file
#         by <q>, <Esc>, SIGKILL etc.
# SETS:
#     findpath – where to search for additional files (subtitles, audiotracks
#         etc.)
#     VIDEO_NUMBER – line number from the list of VIDEOFILES.
#     VIDEOFILE – videofile that will be playing, must be unset to play a disk
#         as a disk.
#     CLEAN_EP_NUMBER – EP_NUMBER[VIDEO_NUMBER-1] with L and ? removed.
#         Used in search for other files.
#     INTERRUPTED – used in ‘resume’ case, means episode wasn’t watched till
#         the end and must be replayed on resume.
#     STOP – if the player was interrupted by key, that stops the cycle too.
# RETURNS:
#     0 if ok, >0 if internal function call returned an error.
watch() {
	case $MODE in
		single)
			[ -v LOOP ] && MPLAYER_OPTS+=( "--loop-file=inf" )
			;;
		episodes)
			MATCH_NUMBER=t
			# Add check for -L option limiting the number of
			#   sequentially playing files to LIMIT_SEQUNCE.
			# Add check to stop cycle when last episode finished?
			#   -e for ‘stop at the end’?
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
				}||{  # Eeeeh? One videofile in episodes mode?
					[ -v RUN_IN_CYCLE ] && {
						warn 'Cannot start watching cycle: only one video file.'
						unset RUN_IN_CYCLE
					}
					# Just in case the rules for single videofiles may be bypassed
					warn 'There was only 1 file for episodes mode. Please report a bug.'
				}
			fi
			CLEAN_EP_NUMBER=${EP_NUMBERS[VIDEO_NUMBER-1]#L}
			CLEAN_EP_NUMBER=${CLEAN_EP_NUMBER%\?}
			[ -v SUB_DELAY ]  \
				&& MPLAYER_OPTS+=( "$dashes${mp_opts[sub-delay]}=$SUB_DELAY" )
			[ -v AUDIO_DELAY ]  \
				&& MPLAYER_OPTS+=( "$dashes${mp_opts[audio-delay]}=$AUDIO_DELAY" )
			[ -v REMEMBER_SUB_AND_AUDIO_DELAY ]  \
				&& MPLAYER_OPTS+=( "--write-filename-in-watch-later-config" )
			;;
		dvd|bd)
			local device protocol
			unset VIDEOFILE
			if [ $MODE = dvd ]; then
				[ -v DVD_BD_NAV ] && protocol=dvdnav || protocol=dvd
				[ -v COMPAT ] && device="${dashes}dvd-device"
			else
				# bdnav is only supported by the mpv mplayer.
				[ -v DVD_BD_NAV ] && protocol=bdnav || protocol=${mp_opts[bd-protocol]}
				[ -v COMPAT ] && device="${dashes}bluray-device"
			fi

			# Replace it with MPLAYER_OPTS+=" ${dashes}profile protocol.$protocol"
			#   when rejecting mplayer and mplayer2.
			# if $MPLAYER_COMMAND ${dashes}profile help \
			# 	|& grep -q "\<protocol.$protocol\>" ; then
			# 	MPLAYER_OPTS=`echo "$MPLAYER_OPTS" \
			# 	    | sed "s/${dashes}profile[= ]^\S+/&,protocol.$protocol/;T;Q1"`
			# 	[ $? -eq 0 ] && \
			# 		MPLAYER_OPTS+=( "${dashes}profile" "protocol.$protocol" )
			# else
			# 	info "$MPLAYER_COMMAND config doesn’t have profile ‘protocol.$protocol’ set."
			# fi
			MPLAYER_OPTS+=( "$protocol://" "${device:-}" )
			;;
	esac

	## From now on, no more exits (except errors during the export to journal).
	[ $MODE = single -o $MODE = episodes ] && {
		[ "$SUBFOLDERS" ] || SUBFOLDERS='/'
		# Subtitles
		set_related_files_list "srt ass sub ssa" || return $?
		subtitles="$RELATED_FILES_LIST"
		findpath="$BASEPATH${FIRST_MATCH:-}${SUBFOLDERS:-}"
		[ "$subtitles" ] && {
			if [ -v COMPAT ]; then
				#  Subtitles in one line, --sub file1,file2,…fileN
				#  Because MPlayer’s syntax for subtitles is "-sub file1,file2"
				#    we must escape commas in path and file names.
				findpath="${findpath//,/\\\,}"
				subtitles="${subtitles//,/\,}"
				subtitles=$(echo "$subtitles" \
					| sed -r " # Here we combine all subtitles in one line.
					           # Padding 1st sub file with path.
					               1s/^/$(escape_for_sed_replacement "$findpath")/
					               :loop  # For every next line
					           # Append its line to pattern space
					           # …and replace newline between those lines with a comma
					           # …and path that goes for the second file (after \n).
					               N; s/\n/,$(escape_for_sed_replacement "$findpath")/
					           # Successful replace → goto loop.
					               t loop  ")
				subtitles="${dashes}${mp_opts[sub-file]} \"$subtitles\""
			else
				#  Each subtitle file passed with the key --sub file1 --sub file2 etc.
				# subtitles=`echo "$subtitles" | sed -r "s/.*/--sub-file='$(escape_for_sed_replacement "$findpath")&'/g"` # '…'"$findpath"'…'
				subtitles="--sub-file=${findpath@Q}"  # '…'"$findpath"'…'
				#  $subtitles is supposedly a newline-separated list, so there
				#  should probably be something like
				# while read -r ; do
				# 	new_subtitles+=( "--sub_file=${REPLY@Q}" )
				# done
				#  And then in the mpv command it should simply expand as
				#  an array "${new_subtitles[@]}"
			fi
		}
		# Soundtracks
		# NB: old format of passing files via comma is broken in latest MPlayer,
		#     only one file can be passed through -audiofile. Multiple -audiofile
		#     options are ignored except the last one. The same goes for mpv-0.3.x
		#     but it was fixed in git version, where multilpe -audio-file options
		#     are allowed and work.
		set_related_files_list "mka dst ac3" || return $?
		tracks="${RELATED_FILES_LIST}"
		[ "$tracks" ] && {
			if  [ -v COMPAT ];  then
				[ "`sed -n '$=' <<<"$RELATED_FILES_LIST"`" -gt 1 ] \
					&& warn 'Multiple external tracks were found, but only the last one can be loaded.
Consider switching to the latest mpv if you want to load multiple tracks
  at once.'
				# tracks="${RELATED_FILES_LIST// /\\\ }"
				tracks=`sed -n "$ s/.*/${dashes}${mp_opts[audio-file]} '$(escape_for_sed_replacement "$findpath")&'/p" <<<"$tracks"`
			else
				tracks=`sed -r "s/.*/--audio-file='$(escape_for_sed_replacement "$findpath")&'/g" <<<"$tracks"`
			fi
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
	[ -v TASKSET_CPULIST ] \
		&& which taskset >/dev/null \
		&& taskset_cmd="taskset --cpu-list $TASKSET_CPULIST"
	[ -v IONICE_OPTS ] \
		&& which ionice >/dev/null \
		&& ionice_cmd="ionice $IONICE_OPTS"
	# $MPLAYER_OPTS must be right before path because of protocol:// things
	# --msg-level=all=info because coproc will make mpv spam its status line.
	#   It is also used to distinguish the mpv instance that runs
	#   the video from those that encode webms (see below).

	{ coproc  \
		{
			#  To know, if mpv finished playing the file or it was interrupted,
			#  we must catch its last line of the output and parse it. This
			#  is bound to several difficulties:
			#
			#  1. The line in the mpv output that is interesting to us, is the
			#     last one, however, as mpv output goes, there is just no
			#     telling which line is last until the output finishes.
			#     This means, that the program should either have a buffering
			#     input, or there will be no output at all while mpv will not
			#     quit playing the video and its output will be piped to that
			#     program.
			#
			#  2. As working with the last line is undesirable, each line
			#     must be compared. However, if the line wouldn’t match, this
			#     shouldn’t be the signal to quit with a negative result.
			#     A negative result should be when the last line would be
			#     telling about an interruption (mpv process terminated or
			#     received a key to quit.)
			#
			#  3. With grep it is impossible to preserve all lines of the out-
			#     put for sure: if the lines would be printed with hacking the
			#     -C(ontext) option, like -C 9999, then somelines of the mpv
			#     output may be cut, because mpv may spam to console a lot and
			#     exceed that number.
			#     If grep would be given a regular expression like “Exiting...
			#     OR $”, where `$` stands for the end of line, then it simply
			#     will match against every single line.
			#
			#  4. In the end, the solution is using sed, but it is somewhat
			#     tricky: first I’ll explain how this works and then I’ll tell,
			#     why it cannot be done another way.
			#
			#     a) mpv output is piped to sed;
			#     b) sed compares each line to “Exiting... ”
			#     c) if the line would match, sed runs the commands in curly
			#        braces on that line;
			#     d) the first command in the curly braces attempts a replace-
			#        ment. The pattern in this replacement is set to match
			#        for the way when the video finishes to play by itself,
			#        or naturally (user fastforwarded it);
			#     e) the result of the replacement then serves as a boolean
			#        variable for the “T” command – it gets “true” (and does
			#        an action), when the replacement wasn’t successful;
			#     f) The action of the “T” command is to jump to the end of the
			#        sed expression, making it stop processing the current line
			#        and proceed to load the next line and start the expression
			#        from the step b);
			#     e) In case when the replacement in the curly braces *is*
			#        successful, the “T” command doesn’t activate, and the
			#        execution pipeline goes to the next command, that is, “Q1”.
			#     f) “Q1” tells sed to quit *immediately,* sed interrupts
			#        itself, reads no more lines and quits with a return code
			#        specified after the “Q”.
			#
			#     So, the result of sed is inverted: when the mpv quits with
			#     “End of file”, the replacement works, sed quits with code 1,
			#     which *negative.* And when mpv is interrupted, the output
			#     would have “Quit” (or “Some errors happened”), the replace-
			#     ment in curly braces will not happen, the “T” command will
			#     make sed ignore the line and it will eventually quit by
			#     itself with a code 0, *positive*.
			#
			#     This has to be made so, because of two reasons:
			#     - first, the string in the mpv output, that reports about
			#       an uninterrupted is known to be one, while strings that
			#       report about terminated may vary. (So the sed result
			#       cannot be “inverted back” by changing the pattern in the
			#       replacement to the opposite.)
			#     - second, the approach with two quit commands, which seems
			#       more logical, will not work:
			#          sed … {s/End of file/&/p; t ex0; p; Q1; :ex0 p; Q0}
			#       With this command, closing mpv in the middle of playback
			#       doesn’t make sed catch the command for some reason. It just
			#       never quits through the Q1 route. Why? A good question.
			#
			#  So that everything would work as intended, this sed command
			#  with an internally inverted return code has to be used. The
			#  code is then inverted to what it should be with an “!” before
			#  the eval command. Then the “wait” command some lines below
			#  will be conveying this return code and a negative result
			#  (with an exception for code 127), will mean that mpv was inter-
			#  rupted, and a positive one (with code 0) will mean, that mpv
			#  finished playback in a natural way and watchfromcli may
			#  proceed to load the next file, if RUN_IN_CYCLE is set.
			#
			! {
				#  env must be used to clear the environemnt from Bahelite
				#    variables – or they will prevent other programs, that run
				#    from within mpv, to run properly (mpv inherits this envi-
				#    ronment).
				#  eval, that was here before, will not work inside env
				#    (and it would obviously be stupid to put it outside), so
				#    it had to be removed. The removal of eval may break things
				#    like external subtitles or some video files, because
				#    the paths were modified to maintain escapes to run within
				#    eval.
				#  This was indeed bad to use eval at all, but this script has
				#    originated from the year 2013, when there was no such
				#    nice bash features like name references (declare -n) and
				#    input escapes in the built-in substitution (e.g. ${var@Q}).
				#
				env ${ionice_cmd:-} ${taskset_cmd:-}  \
				    $MPLAYER_COMMAND  \
				        --msg-level=all=info  \
				        ${NO_AUTOSUB:-}  \
				        ${subtitles:-}  \
				        ${tracks:-}  \
				        "${MPLAYER_OPTS[@]}"  \
				        "${path_to_videofile}"  \
				    |& sed '/^Exiting\.\.\./ {s/End of file/&/p; T; Q1}'
			  }
		} >&3
	} 3>&1 # let mpv’s output flow to the stdout.

	local mpvsed_pipe_pid=$!
	[ -v D ] && {
		echo "mpvsed_pipe_pid = $mpvsed_pipe_pid" >>$dbg_file
		ps -C mpv -ww -o session=,command= >>$dbg_file
	}

	## inotifywait is supposed to catch changes user makes via mpv interface,
	##  i.e. change sub/audio delays, so it might be better to use mpv_pid instead.
	##  I leave it here just in case that coproc shell won’t be closing in time again,
	##  making inotifywait wait for the hanging shell …or sed in it. See bug #6.
	# until [[ "$mpv_pid" =~ ^[0-9]+$ ]]; do
	# 	# Do not run convert_script right away when the window apeared, let it check
	# 	#   for the main mpv instance first!
	# 	local mpv_pid=`pgrep --session $PPID -xf '^mpv --msg-level.*'`  # NB --msg-level
	# 	sleep 1
	# done

	[ -v REMEMBER_SUB_AND_AUDIO_DELAY ] && [ ! -v COMPAT -a "$MODE" = episodes ] && {
		if which inotifywait pkill &>/dev/null; then
			local config
			if [ -r "$HOME/.mpv/watch_later" ]; then
				local  watch_later="$HOME/.mpv/watch_later"

			elif [ -r "$HOME/.config/mpv/watch_later" ]; then
				local  watch_later="$HOME/.config/mpv/watch_later"
			else
				err "Cannot find watch_later directory neither in ~/.mpv nor in ~/.mpv/config."
			fi
			local inotifywait_cmd="inotifywait -q --monitor --format %f -e modify $watch_later"
			(
				# Wait for inotifywait to spawn
				while ! pgrep --session $PPID \
				              -xf "$inotifywait_cmd" \
				              &>/dev/null
				do
					sleep 1
				done
				# Wait for mpv to close (mpv_pid could be used instead, but at this time
				#   it’d be kinda superfluous).
				while [ -e /proc/$mpvsed_pipe_pid ]; do sleep 1; done
				[ -v D ] && {
					echo "Trying to kill ‘$inotifywait_cmd’ with session id $PPID." >>$dbg_file
					pstree -ap $PPID >>$dbg_file
				}
				# SIGPIPE to suppress the message.
				pkill -13 --session $PPID -xf "$inotifywait_cmd"  \
					|| true
			) &
			while IFS= read -r config; do
				if [ "`sed -nr '1s/^#\s(.*)$/\1/p' "$watch_later/$config"`" -ef "$path_to_videofile" ];  then
					# The user must have run write_watch_later_config from mpv.
					# Would it be good to sleep here for 3 seconds and not spam
					#   about found delays while the user shifts them to, say,
					#   from zero to 20000, or it may lead to confusion?
					[ -v D ] && echo "$config changed in $watch_later\!" >>$dbg_file
					local _sub_delay="`sed -nr 's/^sub-delay=(.*)$/\1/p' "$watch_later/$config"`"
					#                                         v-----------may be unset
					[ "$_sub_delay" ] && [ "$_sub_delay" != "${SUB_DELAY:-}" ] && {
						SUB_DELAY="$_sub_delay"
						info "${0##*/}: remembering sub-delay=$SUB_DELAY"
					}
					local _audio_delay="`sed -nr 's/^audio-delay=(.*)$/\1/p' "$watch_later/$config"`"
					#                                             v-----------may be unset
					[ "$_audio_delay" ] && [ "$_audio_delay" != "$AUDIO_DELAY" ] && {
						AUDIO_DELAY="$_audio_delay"
						info "${0##*/}: remembering audio-delay=$AUDIO_DELAY"
					}
				else [ -v D ] && echo 'Something changed, but that wasn’t our file.' >>$dbg_file;  fi
			done < <($inotifywait_cmd || true)
		else
			warn 'For --remember-sub-and-audio-delay inotifywait and pkill are required!'
		fi
	}

	wait $mpvsed_pipe_pid || {
		(( $? == 127 )) && err '“wait” command error.'
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
#     findpath – where to search for additional files (subtitles, audiotracks etc.)
#     VIDEOFILE – exact name match
#     KEYWORD – set, non-empty string
#     MATCH_NUMBER – set if called with -n, -a.
# TAKES:
#     $1 – non-empty string with a list of extensions to match agaist, must be
#         separated by space and contain no trailing space, like "abc def ghi"
# SETS:
#     RELATED_FILES_LIST – list of files that reside in findpath, match by extension to what
#         was through $1 passed and all collected match_* rules
# RETURNS:
#     0 if ok, >0 if internal function call returned an error.
set_related_files_list() {
	local matchext="$1"
	unset match_by_keyword_and_num match_by_num
	# W! This asterisk in the line below is under shell pathname expansion.
	local ext=`echo "$matchext" | sed -r 's/\s/ -o /g; s^([a-zA-Z0-9_-]{3,})^-iname *.\1^g'`
	local found_other_files=`find -L "$BASEPATH${FIRST_MATCH:-}${SUBFOLDERS:-}" -maxdepth 1 -type f \( $ext \) -printf "%f\n"`
	local match_by_name=`echo "$found_other_files" | grep -Fi "${VIDEOFILE%.*}" | sort`
	RELATED_FILES_LIST="$match_by_name" # exact name
	# TODO: This is the only place where KEYWORD is used as a fixed string.
	#       Need to replace KEYWORD with two variables
	#       KEYWORD_FOR_FIND with space substituted with ‘?’ and
	#       KEYWORD_FOR_GREP with space replaced with ‘.’.
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
		local match_by_keyword_and_num=`echo "$match_by_keyword" | grep -E "[^0-9a-oA-Oq-zQ-Z]0*$CLEAN_EP_NUMBER[^0-9a-uA-Uw-zW-Z]" | sort`
		# That’s no good                                                    ^^^^^^^^^^^^^^^^^^                  ^^^^^^^^^^^^^^^^^^
		# Shoulda check whether the group_number_at_the_beginning[VIDEO_NUMBER-1] or group_number_at_the_end[VIDEO_NUMBER-1] were set.
		RELATED_FILES_LIST="${RELATED_FILES_LIST:+${RELATED_FILES_LIST}\n}$match_by_keyword_and_num"
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
		&& RELATED_FILES_LIST="${RELATED_FILES_LIST:+${RELATED_FILES_LIST}\n}${match_by_num:-}"
	# Including files matching by keyword in search results requires MATCH_ALL
	#   to be set, because in case of lots of files matching that keyword many
	#   other unnecessary may be included (e.g. subtitles to 20 episodes). But,
	#   in case of the file is a single, in gives some confidence that there are
	#   not many other files, at least, not that much like in previous case.
	[ -v MATCH_ALL -o $MODE = single ] \
		&& RELATED_FILES_LIST="${RELATED_FILES_LIST:+${RELATED_FILES_LIST}\n}$match_by_keyword"
	# Remove duplicates and empty lines
	RELATED_FILES_LIST=`echo -e "$RELATED_FILES_LIST" \
	                  | sed -nr 'G; s/\n/&&/; /^([[:print:]]*\n).*\n\1/d; s/\n//; h; P'`
	[ -v D ] && declare -p RELATED_FILES_LIST >>$dbg_file
	return 0
}
