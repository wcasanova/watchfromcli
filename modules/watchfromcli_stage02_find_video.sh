# EXPECTS:
#     KEYWORD – set, non-empty string
#     BASEPATH – set, non-empty string or an array
#     IGNORE_DISKS
#     EXPECTED_SUBFOLDERS
# SETS:
#     FIRST_MATCH – file or folder which reside directly in BASEPATH and which
#          name does match KEYWORD
#     MODE – 'single' means that script will play a single file. I’m not sure
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
#     ‘no_matches’ in case no matches were found;
#     ‘empty_folder’ if found a folder but nothing to play in it;
#     ‘chosen_one_is_unreadable’ if couldn’t read file or folder.
do_initial_search() {
	[ -v D ] && dbg_file="$DEBUG_DIR/initial_search"
	unset MODE FIRST_MATCH SUBFOLDERS
	EXPECTED_SUBFOLDERS="${EXPECTED_SUBFOLDERS//%keyword/$KEYWORD}"
	# Pattern split for find
	[ -v FIXED_STRING ] && {
		# Perform escaping of | . * in the pattern for grep -G?
		KEYWORD_FIND_PATTERNS="-iname \"*$KEYWORD*\""
	}||{
		KEYWORD_FIND_PATTERNS=`
		sed -r 's/([^\])"/\1\\"/g                       # Escape unescaped "
		        s/([^\])\.\*/\1*/g                      #    .* → * ;                   \.* → \.*
		        s/^/\\\\( -iname "*/; s/$/*" \\\\)/     # ^… …$ → \( -iname "*… …*" \)
		        s/([^\])\|/\1*" -o -iname "*/g          #     | → *" -o -iname "* ;      \| → \|
		       ' <<<"$KEYWORD"`
		KEYWORD_FIND_PATTERNS=`eval echo "$KEYWORD_FIND_PATTERNS"`
	}
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
				#   in the ‘V:’ list in choose_from()
				local old_bp_count=${#BASEPATH[@]}
				for ((j=1; j<old_bp_count; j++)); do unset BASEPATH[$j]; done
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
		#   that sed expression with ‘primary’ and ‘slave’ basepath,
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

		else
			FIRST_MATCH="$matches"
		fi
		local temp=${BASEPATH[0]}
		unset BASEPATH
		BASEPATH="$temp"
	}|| err 'No matches!'

	if  [ -r "$BASEPATH$FIRST_MATCH" ];  then
		if  [ -d "$BASEPATH$FIRST_MATCH" ];  then
			MODE='episodes'
			# Yep, it’s a directory. Trying to search subfolders.
			[ -v IGNORE_DISKS ] && EXPECTED_SUBFOLDERS+=" VIDEO_TS BDMV "
			unset same_path # important!
			check_for_subfolders || return $?
			[ "`find -L "$BASEPATH/$FIRST_MATCH${SUBFOLDERS:-}" -type d -name "VIDEO_TS"`" ] \
				&& { [ -v IGNORE_DISKS ] && INTERVAL=0 || MODE='dvd'; }
			[ "`find -L "$BASEPATH/$FIRST_MATCH${SUBFOLDERS:-}" -type d -name "BDMV"`" ] \
				&& { [ -v IGNORE_DISKS ] && INTERVAL=0 ||  MODE='bd'; }
# FIXME: Here must be check for the count of VIDEOFILES found at the end of
#        the path (with SUBFOLDERS). If count==1, change mode to single and
#        correct paths for ‘single’ case appropriately. If there are
#        videofiles and they look like episodes, i.e. containing numbers
#        like 01, 02…
			[ $MODE != dvd -a $MODE != bd ] && {
				list_videofiles || return $?
				if  [ "$VIDEOFILES" ];  then
					[ "`echo "$VIDEOFILES" | wc -l`" -eq 1 ] && {
						MODE=single
						VIDEOFILE="$VIDEOFILES"
					}
				else
					#  FIRST_MATCH shall be set at the time of possibility of this error,
					#  so BASEPATH shouldn’t be an array already.
					err "I couldn’t find any video files in $BASEPATH${FIRST_MATCH:-}${SUBFOLDERS:+$SUBFOLDERS\nConsider checking your --subfolders pattern.}"
				fi
			}
		else
			VIDEOFILE="$FIRST_MATCH"
			unset FIRST_MATCH
			MODE='single'
		fi
	else
		err "‘$FIRST_MATCH’ is not readable!"
	fi
	return 0
}

# EXPECTS:
#     KEYWORD ($1 requirement) – set, non-empty string
#     BASEPATH – set, non-empty string or an array
#     FIRST_MATCH – may be unset, if BASEPATH is an array
#     SUBFOLDERS – may be unset, if BASEPATH is an array
# TAKES:
#     $1 – whether or no search by the KEYWORD. This depends on the time this
#          function called, if the first time needed the keyword to define
#          FIRST_MATCH, for example, then the second time assumes anything lying
#          there is wanted by default.
#     $2 – whether to preserve BASEPATH. This is an important thing at an early
#          stage when called first time from do_initial_search() and BASEPATH
#          is an array.
# P.S. Be afraid – this function gave me very strange bugs not accepting second
#      parameter and pointing to the last line of the first subshell.
list_videofiles() {
	local result
	[ "${1:-}" = search_by_keyword ] && local searchkeyword="$KEYWORD_FIND_PATTERNS"
	[ "${2:-}" = preserve_basepath ] && local preserve_basepath=t
	# Single files residing directly in BASEPATH
	VIDEOFILES=`find -L "${BASEPATH[@]}${FIRST_MATCH:-}${SUBFOLDERS:-}" \
	                    -maxdepth 1 -type f ${searchkeyword:-} \
	                    -exec mimetype -iL {} \; 2>/dev/null`
	result=$?;
	[ -v D ] && declare -p VIDEOFILES >>$dbg_file
	# exec known to fail when it’s not important.That’s probably
	#   due to invalid symbolic links in the folder with videofiles.
	# [ $result -gt 0 ] && return $result
	if [ -v preserve_basepath ]; then
		# colon (‘:’) may be in a file name
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
#     BASEPATH – set, non-empty string
#     FIRST_MATCH – an existent and readable directory
#     EXPECTED_SUBFOLDERS – be a simple plaintext list of words,
#         except %keyword.
# SETS:
#     SUBFOLDERS – path between FIRST_MATCH and actual filename to play.
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