                         #  Forming groups  #

# A ‘group’ is nothing more, but its index.
# Data of each record are contained in group_* arrays elements having
#   corresponding index. No variable should be named with prefix ‘group_’
#   unless it is supposed to contain the actual group data of some sort
#  (certain functions operating on groups use this prefix for automatization,
#   because it would be a pain to rewrite all these keys every now and then if
#   something changes).

# TAKES:
#     $1 – pattern
#     $2 – matches
#     $3 – matches_count
group_create() {
	local _gr_p_index \
	      _gr_m_index \
	      _gr_m_count_index
	[ -v group_patterns ] \
		&& _gr_p_index=${#group_patterns[@]} \
		|| _gr_p_index=0
	[ -v group_matches ] \
		&& _gr_m_index=$(( ${#group_patterns[@]} - 1 )) \
		|| _gr_m_index=0
	[ -v group_matches_count ] \
		&& _gr_m_count_index=$(( ${#group_patterns[@]} - 1 )) \
		|| _gr_m_count_index=0

	group_patterns[_gr_p_index]=$1
	group_matches[_gr_m_index]=$2
	group_matches_count[_gr_m_count_index]=$3

	# group_occupied_numbers[] is to be filled later on, when we’ll know
	#   which episodes will be left to each group.
}

# TAKES:
#     $1 – source group index
#     $2 – destination group index
group_copy() {
	local group
	for group in ${!group_@}; do
		local group1=$group[$1]
		local group2=$group[$2]
		eval $group2=\""${!group1}"\"
	done
}

# TAKES:
#     $1 – index to delete from group_* arrays.
group_delete() {
	local group
	for group in ${!group_@}; do unset $group[$1]; done
}

# TAKES:
#     $1 – index of the group A
#     $2 – index of the group B
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
		[ -v D ] && echo "FN: ‘$filename’." >>$dbg_file
		# Match current filename against known patterns
		[ -v group_patterns ] && {
			for pattern in "${group_patterns[@]}"; do
				# if pattern does match, drop that filename
				echo "$filename" | sed 's/'"$pattern"'/&/;T;Q1' >/dev/null || {
					[ -v D ] && echo -e "\tMatches against pattern: ‘$pattern’.\nDROP.\n" >>$dbg_file
					continue 2
				}
			done
		}
		# Splitting the string "$filename" by ‘numbers’ and ‘not numbers’
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
				echo -en "\n\t$i: ‘$filename’\n\t" >>$dbg_file
				for ((j=0; j<$(( ${#i}+ ${#left_part} +3 )); j++)); do
					echo -n ' ' >>$dbg_file
				done
				for ((j=0; j<${#MAPFILE[i]}; j++)); do
					echo -n '^' >>$dbg_file
				done
				echo -en "\n\tLeft part: ‘$left_part’.\n\tRight part: ‘$right_part.’
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
				[ -v D ] && echo -e "\tInc. number: ‘$inc_num’." >>$dbg_file

				# Incremental patterns: to match the current line of
				#   $LIST_TO_CHOOSE_FROM with number substituted with
				#   an incremented one to define a sequence presence.
				# There was a trouble with sed being ungreedy while matching
				#   what is supposed to be an episode number. The \b for
				#   boundary helped for some time, but then filenames having
				#   episode number surrounded with underscores (‘_’) appeared,
				#   and, because \b matches letters, digits and underscores
				#   as a single word, this caused patterns to fail on such
				#   names. That’s why \b was replaced by a ‘possible non-
				#   number’ – [^0-9]\?. It should be replaced with pre-condition
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
				# Both parts – the last!
				inc_patterns[2]="^$left_part$inc_num$right_part$"
				multinum_patterns[2]="^$left_part\([0-9]\+\)$right_part$"
				# If you noticed that the two last elements of both arrays with
				#   regular expressions are redundant. That’s because I’ve rea-
				#   lized only at this point, that sed capabilities are not
				#   enough.
				# Below, in the ‘watch’ function, at the end of the ‘episodes’
				#   case, one of the patterns above this text will be applied to
				#   a file name in attempt to acquire episode number. And there
				#   is the rub: sed behaves non-greedy when it searches for
				#   ([0-9]+) and that makes first digits of the number to fall
				#   out of the \1 match. The first thing I did was to add boun-
				#   dary separators \b around the regex matching the number,
				#   but then sed appeared to include not only alphanumeric
				#   characters, BUT DIGITS AND THE UNDERSCORE SIGN, TOO, i.e.
				#   in file name ‘Durarara_01_2F4B8D2.mkv’ there’s only one word
				#   boundary (except the beginning and the end of the line) –
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
				[ -v D ] && echo -en "\t\tInc. pattern: ‘${inc_patterns[j]}’.\n\t\t\tSequence found? " >>$dbg_file
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
						[ -v group_matches ] && {
							for ((k=0; k<${#group_matches[@]}; k++)); do
								[ "$matches" = "${group_matches[k]}" ] && {
									same_matches_found=t
									[ -v D ] && echo 'No.' >>$dbg_file
									break
								}
							done
						}  # or catch [ -v same_matches_found ] too?
						[ -v same_matches_found ] || {
							[ -v D ] && echo -e "Yes.\nADD\t\t\tMultinum pattern: ‘${multinum_patterns[j]}’." >>$dbg_file
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




                        #  Arranging groups  #


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
		if [ -v ROTATE_PATTERN_LIST ]; then
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
		else
			[ -v D ] && echo 'SORTING' >>$dbg_file
			# Do initial groups sorting.
			# Sort patterns descending by the number of matches OR
			#   lexicographically if numbers are equal
			for (( i=0; i<${#group_patterns[@]}-1; i++)); do
				for (( j=$i+1; j<${#group_patterns[@]}; j++)); do
					# Biggest number of matches → to the top of the array.
					(
						[ ${group_matches_count[i]} -lt ${group_matches_count[j]:--9999} ] \
						||	(
								[ ${group_matches_count[i]} -eq ${group_matches_count[j]:--9999} ] \
								&& [[ "${group_patterns[i]}" > "${group_patterns[j]}" ]] \
							)
					) && {
						group_swap $i $j
					}
				done
			done
			[ -v D ] && echo 'Sorted patterns:' >>$dbg_file
		fi
	}
	[ -v D ] && {
		echo 'Some elements may span on multiple lines if they contain double quotes.
This is not a bug.' >>$dbg_file
		declare -p group_patterns group_matches group_matches_count >>$dbg_file
	}
	return 0
}