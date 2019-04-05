# Should be sourced.



# EXPECTS:
#     ~/.watch.sh/journal to exist and contain at least one \n (for sed).
# EXIT CODES:
#     0 if OK, ‘no_such_keyword_in_journal’, ‘not_enough_data_to_restore’.
import_session_data() {
	local current_lastmod
	[ -v NO_JOURNAL ] || {
		# Checking journal version
		local j_ver=`sed -nr '1 s/.*v([0-9]+)$/\1/p' $JOURNAL` start_line=3
		[[ "$j_ver" =~ ^[0-9]+$ ]] && [ $j_ver -ge $JOURNAL_MINVER ] || {
			warn "The journal version $j_ver is obsolete.
You can remove $JOURNAL and let watch.sh to create a new one."
		}
		[ "`stat --format='%s' $JOURNAL`" -gt 1 ] && {
			if [ "${KEYWORD:-}" ]; then
				# KEYWORD present, search among entries in the journal
				# We can’t pass exit code from sed to eval, since eval’s
				#   exit code is the result of what it _executes_, and it
				#   executes either an empty string, if sed found nothing
				#  (=instant 0), or some variable assignment VAR='value',
				#   that will most probably result in 0 return value.
				#   So add some assignment that will tell us we found nothing :D
				eval "`sed -n "/^KEYWORD='$(escape_for_sed_pattern "$KEYWORD")'/,/^$/ {
				               s/^declare/declare -g/; p; /^$/ Q0 }; $ Q1 # Force global namespace – we’re inside function." \
				       $JOURNAL 2>/dev/null || echo local no_such_keyword=t`"
			else
				# KEYWORD is not given, take 1st one from the journal
				# If this is the old style journal without header, start with 1st line.
				sed -rn '1s/^# watch.sh journal v[0-9]+$/&/;T;Q1' $JOURNAL && start_line=1
				eval "$(sed -n "$start_line,/^$/ { s/^declare/declare -g/; p } # Force global namespace – we’re inside function." \
				$JOURNAL 2>/dev/null || echo local no_such_keyword=t)"
			fi
			[ -v no_such_keyword ] && abort 'No such keyword.'

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
			[ "$MODE" = single ] && check_required_vars 'VIDEOFILE'
			if [ "$MODE" = episodes ]; then
				check_required_vars 'VIDEOFILES' 'VIDEO_NUMBER' 'EP_NUMBERS' 'INTERRUPTED' 'REMEMBER_SUB_AND_AUDIO_DELAY' 'LASTMOD'
			else
				unset RUN_IN_CYCLE  # --resume sets it by default.
			fi
		}
		[ -v not_enough_data ] && err "Not enough data to restore.
Couldn’t retrieve $not_found_vars from the journal.
This might be caused by a broken file, truncated entry at the end of the journal (though such entries shouldn’t exist) or a new update that changed the mechanism of file searching and thus, the list of required variables."
		# Yes, it could be just one variable, but with two names, its purpose
		#   is clearer, hence easier to understand at both stages. Moreover,
		#   INTERRUPTED can’t be used to launch ‘until’ cycle with ‘watch’
		#   function.
		[ "$INTERRUPTED" = t ] && RESUME_AND_REPLAY=t
		unset INTERRUPTED
		local var
		for var in 'FIXED_STRING' 'REMEMBER_SUB_AND_AUDIO_DELAY'; do
			[ "${!var}" = f ] && unset $var
		done
		[ "$MODE" = episodes ] && {
			# If the files in the folder were still downloading at the time
			# watching cycle has started, then on resume our file list is out
			# of date. We must force RUN_IN_CYCLE instead of regular
			# RESUME procedure.
			current_lastmod=$(stat -c %Y "$BASEPATH$FIRST_MATCH${SUBFOLDERS:-}")
			[[ "$current_lastmod" =~ ^[0-9]+$ ]] || err 'Cannot retrieve videofile’s directory last modification time.'
			[ $current_lastmod -gt "$LASTMOD" ] && {
				# We’re going to amend the --resume convenience,
				# so let’s at least provide the user with the number of
				# his last watched episode, in the hope, he started
				# watching something, before it downloaded completely,
				# from the beginning. Well, if he decided to download
				# some fifth episode first, while №1–4 weren’t finished,
				# he must know what he’s doing.
				SUGGESTED_NUMBER=$VIDEO_NUMBER
				unset RESUME RESUME_FROM_PREVIOUS MODE IT_IS_NEXT_ITERATION \
				      VIDEO_NUMBER FIRST_MATCH SUBFOLDERS VIDEOFILES \
				      EP_NUMBERS INTERRUPTED LASTMOD VIDEOFILE
				# This call must be the last, i.e. all the possible checks
				# and corrections must be made before it.
				do_initial_search
			}
		}
	}
	return 0
}


# SETS:
#     SESSION_DATA_EXPORTED – to prevent this function running twice.
# EXIT_CODES:
#     0 if OK, ‘cant_retrieve_journal_size’,
#    ‘cant_compute_journal_max_size’, ‘cant_truncate_journal’.
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
		data+="\nFIRST_MATCH='$(escape_for_sed_replacement "$FIRST_MATCH")'" # Remember? No slashes here, ‘&’ and ‘'’ only
		data+="\nSUBFOLDERS='$(escape_for_sed_replacement "$SUBFOLDERS")'"
		[ $MODE = single ] \
			&& data+="\nVIDEOFILE='$(escape_for_sed_replacement "$VIDEOFILE")'"
		[ $MODE = episodes ] && {

			# I did think about serialization of VIDITEM_* arrays into journal
			#   and operating on them in watch() instead of introducing its own
			#   personal variables, but a test snippet doing this with items
			#   containing ' and " in their names has shown that it’s better
			#   to restrain from that. Though the output of retrieval, i.e.
			#   evaling declare directives back, could be considered satisfying –
			#   nothing was lost – there were disadvantages, that held me from
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
			data+="\nLASTMOD=$(stat -c %Y "$BASEPATH$FIRST_MATCH${SUBFOLDERS:-}")"
		}
		# SCREENSHOT_DIR_ORIG is the original string passed via --screenshot-dir,
		# it should be used if we change SCREENSHOT_DIR to ‘.’ in screenshots_preprocessing().
		data+="\nSCREENSHOT_DIR='$(escape_for_sed_replacement "${SCREENSHOT_DIR_ORIG:-$SCREENSHOT_DIR}")'"
		[ -v TASKSET_CPULIST ] && data+="\nTASKSET_CPULIST='$TASKSET_CPULIST'"
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
		[[ "$j_size" =~ ^[0-9]+$ ]] || err 'Couldn’t retrieve journal size.'
		j_max_size=`echo "$(sed 's/K/*1024/;s/M/*1024*1024/' <<<"$JOURNAL_MAX_SIZE")" | bc -q`

		[[ "$j_max_size" =~ ^[0-9]+$ ]] || err 'Couldn’t compute journal maximum size.'
		[ $j_size -gt $j_max_size ] && {
			truncate --size=$JOURNAL_MAX_SIZE $JOURNAL || err 'Couldn’t truncate journal.'
			# TODO: Clean the stump that might have left at the end of the file
			# sed -i '/^$/,$ d' $JOURNAL # (this doesn’t work – sed is too greedy)
			# Though I’m not sure if the cleaning is really needed, simple tests
			# had shown that it may be fine as is, but more complicated ones must
			# be done.
		}
	}
	SESSION_DATA_EXPORTED=t
	return 0
}