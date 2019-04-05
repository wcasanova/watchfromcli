

# TAKES:
#    $1 – group index to check
#    $2 – bottom border for episode value
#   [$3] – top border for episode value
# USES:
#    group_occupied_numbers[@]
#    NOT_EPNUMBERS
# SETS:
#    EP – episode number that fits specified borders.
# RETURNS:
#    0 – if this is not a single group or a sinlge group which episode
#      number does reside within specified borders (what matters is
#      whether we can continue safely with current VIDITEM_EPNUMBER[]).
#    1 – if this is a single group and none of its possible episode
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


arrange_files_heu_lvl2() {
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
					echo -e "$header\n${header//[^ ]/–}"
					echo "$gr_index   $match   $gr_start   $gr_end   $gr_size   ${group_occupied_numbers[gr_index]}"
				}
				next_run=t
			done <<<"${group_matches[gr_index]}" | column -o ' ' -s '   ' -t  >>$dbg_file
		}
		# 1.–1.1.1. Is this group the initial one?
		[ $gr_index -eq 0 ] && {
			[ -v D ] && echo -e "\n\tThis is initial group (idx:0)." >>$dbg_file
			# Is this a single group by accident?
			[ $gr_size -eq 1 ] && {
				[ -v D ] && echo -e "\tThis is a single group (items:1)." >>$dbg_file
				[[ "${group_occupied_numbers[0]}" =~ ^[0-9]+$ ]] && {
					[ -v D ] && echo -e "\t\tLooks like this file has only one number: ${group_occupied_numbers[0]}, assigning it to VIDITEM_EPNUMBER[0]." >>$dbg_file
					VIDITEM_EPNUMBER[0]=${group_occupied_numbers[0]##0} # avoiding misinterpretation as octal
				}||{
					warn 'I can’t  guess episode number for the first group that is single – no basic data.\n    Choose what’ll become the first episode number:'
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
		# 2.–3. Does the group have gaps?
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
				[ $i -eq 0 ] && echo -e "    $header\n    ${header//[^ ]/–}"
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
					[ $j -eq 0 ] && echo -e "\n\n        $header\n        ${header//[^ ]/–}" && local header_put=t
					echo -e "        $j   ${groups_that_fill_entire_gap[j]%;*}   ${groups_that_fill_entire_gap[j]#*;}   YES"
				done | column -o ' ' -s '   ' -t  >>$dbg_file
				for ((j=0; j<${#groups_that_fill_gap_partly[@]}; j++)); do
					[ $j -eq 0 -a ! -v header_put ] && echo -e "    $header\n    ${header//[^ ]/–}"
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
				#   the closest case for the real life – when a directory contains
				#   hodgepodge, but the files represent one and only sequence.
				# With a minimal check, of course…

				# Resorting this array to bring first episodes of its
				#   items in order.
				# In bash, it’s okey to start from 1 – if there’s no such
				#   item, cycle won’t start, but in other languages…
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
				[ -v D ] && {
					echo -e "\t\tTrying to fill the gap from parts (resorted array):" >>$dbg_file
					header="Index   Group index   Episodes" # Episodes here ≠ group_matches[N]
					for ((j=0; j<${#groups_that_fill_gap_partly[@]}; j++)); do
						[ $j -eq 0 ] && echo -e "        $header\n        ${header//[^ ]/–}"
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
}