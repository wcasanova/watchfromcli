
# SETS:
#     VIDITEM_* – arrays for manipulation while doing heuristics.
#         NB All these arrays start from zero, while line numbers in
#         selection dialog and VIDEO_NUMBER starting from 1.
# TAKES:
#     $1 – filename
#     $2 – group id (for pattern) # wait, where do we need the pattern?..
#     $3 – episode number OR supposed episode number OR line number
#          Ex. "1"           Ex. "1?"                   Ex. "L1"
#         (temporarily may comprise of space-separated numbers)
viditem_create() {
	local filename=${1:-} group_id=${2:-} proto_ep_number=${3:-}  \
	      viditem_file_idx  viditem_gid_idx  viditem_epnumber_idx
	proto_ep_number=${proto_ep_number##0}
	# If HEU LVL == 0, constructed in choose_from().
	[ -v VIDITEM_FILE ] \
		&& viditem_file_idx=${#VIDITEM_FILE[@]} \
		|| viditem_file_idx=0
	VIDITEM_FILE[viditem_file_idx]=$filename
	# Global, but used only within build_the_list() scope in order
	#   to make us able to build the list with accordance to groups when
	#   lowering heuristics level.
	# Doesn’t go to journal – caps is used for conformance with viditem_*().
	[ -v VIDITEM_GID ] \
		&& viditem_gid_idx=${#VIDITEM_GID[@]} \
		|| viditem_gid_idx=0
	VIDITEM_GID[viditem_gid_idx]=$group_id
	# Global. If HEU LVL == 0, filled with L# in choose_from().
	# Removing leading zeroes to avoid misinterpretation as octal.
	[ -v VIDITEM_EPNUMBER ] \
		&& viditem_epnumber_idx=${#VIDITEM_EPNUMBER[@]} \
		|| viditem_epnumber_idx=0
	VIDITEM_EPNUMBER[viditem_epnumber_idx]=$proto_ep_number
	return 0
}


# TAKES:
#     $1 – source viditem index
#     $2 – destination viditem index
viditem_copy() {
	local viditem
	for viditem in ${!VIDITEM_@}; do
		local viditem1=$viditem[$1]
		local viditem2=$viditem[$2]
		eval $viditem2=\""${!viditem1}"\"
	done
}


# TAKES:
#     $1 – index to delete from VIDITEM_* arrays
viditem_delete() {
	local viditem
	for viditem in ${!VIDITEM_@}; do unset $viditem[$1]; done
}


# TAKES:
#     $1 – index of the viditem A
#     $2 – index of the viditem B
viditem_swap() {
	local buffer_index=${#VIDITEM_FILE[@]}
	viditem_copy $1 $buffer_index
	viditem_copy $2 $1
	viditem_copy $buffer_index $2
	viditem_delete $buffer_index
}


# USES:
#     queue_* – arrays that specify queue. Because there are batch jobs
#         in manual rearrangement as well as in HEU2.
# ALTERS:
#     VIDITEM_* – alter the order of items.
# RETURNS:
#     0 – if OK;
#     3 – illegal queue construct, immediate return;
#     42 – queue is 2big4ahuman to read the debug output (only when D is set).
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
			[ $i -eq 0 ] && echo -e "\n$header\n${header//[^ ]/–}"
			echo "$i   ${VIDITEM_FILE[i]}   ${VIDITEM_GID[i]}   ${VIDITEM_EPNUMBER[i]}"
		done | column -o ' ' -s '   ' -t  >>$dbg_file
		echo -e "" >>$dbg_file
		header="Index   Start/end/dest"
		for ((i=0; i<${#queue_start[@]}; i++)); do
			[ $i -eq 0 ] && echo -e "$header\n${header//[^ ]/–}"
			echo "$i   ${queue_start[i]}/${queue_end[i]}/${queue_dest[i]}"
		done | column -o ' ' -s '   ' -t  >>$dbg_file
		echo -e '^Queue is running on VIDITEM indices.\n' >>$dbg_file
	}

	# We’ll have to create arrays of actual items instead of relying upon
	#   where the group starts and where ends – such groups may be split
	#   after iterations. So, instead of groups – indices of what will be
	#   moving. Eval is because we can’t into arrays of arrays here.
	for ((i=0; i<${#queue_dest[@]}; i++)); do
		for ((j=queue_start[i]; j<queue_end[i]+1; j++)); do
			eval queue_items_$i[\${#queue_items_$i[@]}]=$j
			[ -v D ] && eval info \""queue_items_$i=( \${queue_items_$i[@]} )"\"
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
		[ -v D ] && info "_queue_items=( ${_queue_items[@]} )"
		# [ -v T ] && [ $i -eq $iter ] && set -x
		unset buf
		for ((j=0; j<${#_queue_items[@]}; j++)); do
			buf[${#buf[@]}]=${_arr[_queue_items[j]]}
			local _temp_index="${_queue_items[j]}"
			local _temp_value="${_arr[_queue_items[j]]]}"
			[ -v D ] && echo "${di}Unsetting _arr[$_temp_index] = $_temp_value." >>$dbg_file
			unset _arr[_queue_items[j]] # removing source lines from the array
		done
		# [ -v T ] && [ $i -eq $iter ] && { set +x; declare -p buf; }
		[ -v D ] && {
			echo -n "$di" >> $dbg_file && declare -p buf >>$dbg_file
			[ $(( ${queue_dest[i]} + ${#_queue_items[@]} )) -gt ${#_old_arr[@]} ] \
				&& info '' 'Possible error: ${queue_dest[i]} + ${#_queue_items[@]} are out of range (${#_old_arr[@]}).\n'
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
			[ -v D ] && info "Destination was shifted by -$((${#_queue_items[@]}-1))"
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
					info "Destination place! Placing the buffer:"
					dil_inc
				}
				for ((k=0; k<${#buf[@]}; k++)); do
					_new_arr[${#_new_arr[@]}]=${buf[k]}
					[ -v D ] && info "_new_arr[$((${#_new_arr[@]}-1))] = ${buf[k]}"
				done
				buffer_placed=t
				[ -v D ] && dil_dec
			}
			_new_arr[${#_new_arr[@]}]=$item_index
			[ -v D ] && info "_new_arr[$((${#_new_arr[@]}-1))] = $item_index"
		done
		# [ -v T ] && [ $i -eq $iter ] && set +x
		[ -v buffer_placed ] || {
			warn "やべっ！ Buffer wasn’t placed possibly because of illegal move, stopping the queue.\n  No changes were made."
			return 3
		}

		[ -v D ] && {
			info "Rearrangements for queue $i complete."
			dput_declare '' _old_arr '' _new_arr ''
			info "Brigning subsequent queue items into correspondence with current order:"
			dil_inc
		}
		# [ -v T ] && exit
		for ((j=i+1; j<${#queue_dest[@]}; j++)); do
			# [ -v T ] && [ $i -eq $iter ] && echo j = $j
			eval _queue_items=(\${queue_items_$j[@]})
			[ -v D ] && {
				info "Adjusting queue item $j."
				dil_inc
				dput_declare _queue_items
				info "Walking the _queue_items:"
				dil_inc
			}
			unset dest_j_found
			for ((k=0; k<${#_queue_items[@]}; k++)); do
				[ -v D ] && info "Searching for item = ${_queue_items[k]} (idx:$k):" && dil_inc
				for ((l=0; l<${#_new_arr[@]}; l++)); do
					# [ -v T ] && [ $i -eq $iter ] && set -x
					[ ! -v dest_j_found -a  ${_new_arr[l]} -eq ${queue_dest[j]} ] && {
						[ -v D ] && info "Looks lile _new_arr[$l] is our destination: ${queue_dest[j]}."
						queue_dest[j]=$l
						local dest_j_found=t
					}
					# [ -v T ] && [ $i -eq $iter ] && set +x
					[ ${_new_arr[l]} -eq ${_queue_items[k]} ] && {
						eval queue_items_$j[k]=$l
						[ -v D ] && {
							info "Looks like _new_arr[$l]=${_new_arr[l]} is also equal to the item in _queue_items[$k]!"
							info "Setting queue_items_$j (←the true one) to $l."
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
#     $1 – start line
#     $2 – end line
#     $3 – destination line
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
		#   in the buffer, i.e. the 3rd line, before, and only after –
		#   the destination, what was the 4th line.
		# Since it makes the operation obscure to the user, we put
		#   the destination before what is in the buffer in that case, so
		#   it would act like the user expects it to.
#queue_put_dest_line_first[${#queue_start[@]}-1]=t # t or unset
#}
}

# TAKES:
#     $1 – index to delete from queue_* arrays
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


build_the_list() {
	local i j k header manual_rearrangement_was_in_effect \
		total_items_count=$LIST_ITEMS_COUNT # because choose_from() may be called again from here
	[ -v D ] && {
		dbg_file=$DEBUG_DIR/build_the_list
		echo -e 'Building the list. # View me with `less -S`.\nManual reararngement, end of HEU1, HEU2.\n\nInitial data:' >>$dbg_file
		header="Index   Pattern   Matches   Matches count"
		for ((i=0; i<${#group_patterns[@]}; i++)); do
			[ $i -eq 0 ] && echo -e "$header\n${header//[^ ]/–}"
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

	if [ -v MANUAL_REARRANGEMENT ]; then
		readarray -t <<<"`echo -e ${MANUAL_REARRANGEMENT//,/\\\n}`"
		[ -v D ] && echo -e "Manual rearrangement requested.\nRaw MAPFILE: ‘$MAPFILE’." >>$dbg_file
		unset MANUAL_REARRANGEMENT
		for ((i=0; i<${#MAPFILE[@]}; i++)); do
			[ -v D ] && echo -e "\tPiece $i: ‘${MAPFILE[i]}’." >>$dbg_file
			[[ "${MAPFILE[i]}" =~ ^[0-9]+(-[0-9]+)?\>[0-9]+$ ]] || {
				warn "‘${MAPFILE[i]}’ is not a valid rearrangement instruction."
				warn "The format is: ‘10>1’, ‘9-11>2’, ‘1-3>5,7-8>1,…’."
				return 0
			}
			local start="${MAPFILE[i]%>*}" \
			      end="${MAPFILE[i]%>*}" \
			      dest="${MAPFILE[i]#*>}"
			local start="${start%-*}" \
			      end="${end#*-}"
			[ $start -gt $total_items_count ] && {
				warn "‘${MAPFILE[i]}’: start value must be lower than $total_items_count."
				return 0
			}
			[ $end -lt $start ] && {
				warn "‘${MAPFILE[i]}’: end value must be lower than start value."
				return 0
			}
			[ $dest -gt $total_items_count ] && {
				warn "‘${MAPFILE[i]}’: destination value must be lower than $total_items_count."
				return 0
			}
			[ $start -eq $dest ] && {
				warn "‘${MAPFILE[i]}’: what’s the point in this?.."
				return 0
			}
			[ -v D ] && echo -e "\tAdding queue start/end/dest: $start $end $dest." >>$dbg_file
			queue_create $start $end $dest
		done
		test_queue_for_intersections || return $?
		rearrange_list_items && manual_rearrangement_was_in_effect=t || return $?
	else
	    # First run of this function should start here (no manual rearrangement was requested).
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
			for ((j=0; j<${group_matches_count[i]:-0}; j++)); do
				unset new_match_found
				until [ -v new_match_found ]; do
					match=`sed -n $((j+1))p <<<"${group_matches[i]}"`
					[ $i -eq 0 ] && break # matches of the 1st pattern are unique
					new_match_found=t
					for ((k=0; k<$total_items_count; k++)); do
						[ "${VIDITEM_FILE[k]:-}" = "$match" ] && unset new_match_found
					done
					[ -v new_match_found ] || {
						# If there are no new matches, it will simply accumulate until j reaches its limit
						[ $((++j)) -eq ${group_matches_count[i]} ] && break 2 # Yes, it works. Think!
					}
				done
				# ‘extracted number’, what is supposed to be an ‘episode number’.
				# (For HEU1 just ‘Line No. N’)
				[ ${group_matches_count[i]:--9999} -eq 1 ] && {
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
				[ $i -eq 0 ] && echo -e "$header\n${header//[^ ]/–}"
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
		#   simply forget about groups and rebuilds the list by numbers–this would
		#   only mess the order if it has several actual sequences, like
		#     - Animu EP XX [hash].mkv
		#     - Animu extra XX [hash].mkv
		#     - Animu OVA XX [hash].mkv
		#   Groups are respected and only so called holes are filled in them, before,
		#   after and  between them. So the actual sort between the group members
		#   should be done before it.

		# Okay, we have groups and arranged them. But currenlty it’s not much
		#   far away from the ‘sort’ command, that would find these numbers too
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
				[ $i -eq 0 ] && echo -e "$header\n${header//[^ ]/–}"
				[ $_prev_viditem_gid -ne ${VIDITEM_GID[i]} ] \
					&& echo "$i   ${list_indicators[i]}   ${VIDITEM_FILE[i]}   ${VIDITEM_GID[i]}   ${VIDITEM_EPNUMBER[i]}   ${group_occupied_numbers[VIDITEM_GID[i]]}" \
					|| echo "$i   ${list_indicators[i]}   ${VIDITEM_FILE[i]}   ${VIDITEM_GID[i]}   ${VIDITEM_EPNUMBER[i]}   "
				_prev_viditem_gid=${VIDITEM_GID[i]}
			done | column -o ' ' -s '   ' -t  >>$dbg_file
			echo -e '\nHEU LVL 1 ends.' >>$dbg_file
		}

		# Level 2 heuristics.
		[ $HEURISTICS_LEVEL -eq 2 ]  \
			&& arrange_files_heu_lvl2
	fi   # if [ -v MANUAL_REARRANGEMENT ]

	# Fixing leftover L# numbers that possibly may be skewed now.
	for ((i=0; i<${#VIDITEM_EPNUMBER[@]}; i++)); do
		[ "${VIDITEM_EPNUMBER[i]/L*/}" ] || VIDITEM_EPNUMBER[i]=L$((i+1))
	done

	[ -v D ] && {
		echo -e "\n\nResulting VIDITEM_* arrays:" >>$dbg_file
		header="Index   File   GID   Episode number"
		for ((i=0; i<total_items_count; i++)); do
			[ $i -eq 0 ] && echo -e "$header\n${header//[^ ]/–}"
			echo "$i   ${VIDITEM_FILE[i]}   ${VIDITEM_GID[i]}   ${VIDITEM_EPNUMBER[i]}"
		done | column -o ' ' -s '   ' -t  >>$dbg_file
		echo -e "\n\n\n    ----- Exiting from build_the_list ------------------------------------------\n\n\n" >>$dbg_file
	}

	# Composing new LIST_TO_CHOOSE_FROM to return to choose_from()
	unset LIST_TO_CHOOSE_FROM
	for ((i=0; i<total_items_count; i++)); do
	   printf "${g}%*d:${s}" ${#total_items_count} $((i+1))
		[ -v manual_rearrangement_was_in_effect -o $HEURISTICS_LEVEL -gt 1 ] \
			|| echo -en "${list_indicators[i]:-}"
		local pattern=${pat_for_grep[${VIDITEM_GID[i]:-0}]}
		# If the match is unique, i.e. pattern is equal to the match itself,
		#   restrain grep from highlighting the whole string.
		[ $HEURISTICS_LEVEL -lt 2 ] && {
			[ "`grep -oG "$pattern"<<<"${VIDITEM_FILE[i]}"`" = "${VIDITEM_FILE[i]}" ] \
				&& echo "${VIDITEM_FILE[i]}" | grep --colour=always -iG "\($KEYWORD\|${VIDITEM_EPNUMBER[i]}\)" \
				|| echo "${VIDITEM_FILE[i]}" | grep --colour=always -iG "$pattern"
			:
		}|| echo "${VIDITEM_FILE[i]}"
		LIST_TO_CHOOSE_FROM="${LIST_TO_CHOOSE_FROM:+$LIST_TO_CHOOSE_FROM\n}${VIDITEM_FILE[i]}"
	done
	return 0
}