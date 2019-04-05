# EXPECTS:
#     USE_1ST (in the future)
#     NO_COLOR
# TAKES:
#     $1 – list of strings
# SETS:
#     CHOSEN_ITEM – set to the line from the $1 which number is $CHOSEN_NUMBER
#     CHOSEN_NUMBER – number of the $CHOSEN_ITEM in the list. Will become
#         the VIDEO_NUMBER.
# RETURNS:
#     0 if line(s) was(were) successfully picked,
#    >0 some utility failed or the result of internal function call.
# EXIT CODES:
#    ‘user_declined’ in case of
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
		#  retarded BASEPATH may be either a variable or an array here.
		[[ "${BASEPATH@a}" =~ .*a.* ]]  \
			&& local _basepath_quantity=${#BASEPATH[@]} \
			|| local _basepath_quantity=1
		for ((i=0; i<_basepath_quantity; i++)); do
			local path_to_video="${BASEPATH[i]}${FIRST_MATCH:-}${SUBFOLDERS:-}"
			local max_width=$(($cols-4))
			[ ${#path_to_video} -gt $max_width ] && path_to_video="…${path_to_video:0-$max_width:$max_width}"
			echo -e "${__w}V: $path_to_video${__s}"
		done
		# C: current working directory (CWD), the directory in which the shell
		#    operates.
		[ -v NO_HINTS ] || echo ' ↙ The directory screenshots will go to.'
		local cwd="$PWD"
		[ ${#cwd} -gt $max_width ] && cwd="…${cwd:0-$max_width:$max_width}"
		echo -e "C: $cwd"  | grep -iG "\($KEYWORD\|$\)"
		# S: screenshot directory as provided via -S option (see above),
		#    it shows only in case this call of ‘choose_from’ came from
		#    ‘set_screenshot_subdir’, so the user could see the actual
		#    folder where screenshots will be saved to. This is important
		#    because of two things
		#    - portable hard drive;
		#    - very bad directory guessing, because it’s done by only matching
		#      the given keyword, e.g. I’m going to watch ‘Daria’, and type just
		#      ‘dar’ as a keyword, because it’s enough to find it in the current
		#      BASEPATH on my netbook, but I’m going to save screenshots on
		#      my portable hard drive where in SCREENSHOT_DIR a folder named
		#      ‘darker_then_black’ is already present, so script will choose it
		#      without asking, because of keyword matched the part of
		#      folder name. In most cases keyword would match correctly, so
		#      asking about ‘are you glad with the folder I’ve chosen for you?’
		#      would be annoying, so we just highlight the keyword, so the user
		#      can abort script executing and run it again with a more proper
		#      keyword.
		[ ${FUNCNAME[1]} = set_screenshot_subdir ] && {
			local safe_screenshot_dir="$SCREENSHOT_DIR"
			[ ${#safe_screenshot_dir} -gt $max_width ] \
				&& safe_screenshot_dir="…${safe_screenshot_dir:0-$max_width:$max_width}"
			[ -v NO_HINTS ] || echo ' ↙ Screenshot directory as it was passed.'
			echo "S: $safe_screenshot_dir"
		}
		[ -v NO_HINTS ] || echo ' ↙ Pick a number from the list.'
		[ ${FUNCNAME[1]} = watch ] && {
			[ -v SUGGESTED_NUMBER ] && local use_suggested_number=t
			[ $HEURISTICS_LEVEL -ne 0 ] && {
				[ -v D ] && dbg_file="$DEBUG_DIR/choose_from_[watch]"
				[ -v group_patterns ] || create_groups_for_the_list || return $? # L1 HEU
				arrange_groups || return $?                                      # L1 HEU
				build_the_list || return $?                                      # L1/L2 HEU
			}|| local use_simple_list=t
		}|| local use_simple_list=t
		[ -v use_simple_list ] \
			&&	echo -e "$LIST_TO_CHOOSE_FROM" \
					| grep -n --colour=always -i -G  "\($KEYWORD\|$\)"

		unset  another_view  prompt_heuristics
		[ ${FUNCNAME[1]} = watch -a "${MODE:-}" = episodes ] && {
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
			local num_choosing_hint="[${MY_DECREMENT:-}↓0-9↑${MY_INCREMENT:-}] "
			echo ' ↙ Commands to rebuild the list in other way, if possible.'
		}
		local prompt_1st_line="${another_view:-}${prompt_heuristics:-}${g}<?>${s} hints."
		[ ${FUNCNAME[1]} = set_screenshot_subdir ] \
			&& local prompt_2nd_line="Pick line $g<number>$s or press $g<Enter>$s to skip ${num_choosing_hint:-}> " \
			|| local prompt_2nd_line="Pick line $g<number>$s and press $g<Enter>$s to confirm ${num_choosing_hint:-}> "
		local prompt="${prompt_1st_line:+$prompt_1st_line\n}${prompt_2nd_line}"
		echo -en "$prompt"

		# local is poinless for the second one, because big cycle and <TAB>.
		unset input input_is_ready
		[ -v use_suggested_number ] && {
			input=$SUGGESTED_NUMBER
			unset SUGGESTED_NUMBER
		}
		# Use C-v <key> to print its escape sequence. P.S. Octals work, too!
		local up=$'\e[A' down=$'\e[B' backspace=$'\177' F1=$'\e[11~' # F1 requires another read to catch 4th char, wat do? ;_;
		until [ -v input_is_ready ]; do
			[ -v input ] && [ ${#input} -gt 30 ] && input=${input:0:30}
			read -sn1 -p "${input:-}"
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
					"$up"|"${MY_INCREMENT:-disregard it}")
						[ "$input" ] || input=0
						[[ "$input" =~ ^[0-9]+$ ]] \
							&& [ $input -lt $LIST_ITEMS_COUNT ] \
							&& let input++ || {
							[ $input -gt $LIST_ITEMS_COUNT ] \
								&& input=$LIST_ITEMS_COUNT
						}
						;;
					"$down"|"${MY_DECREMENT:-disregard it}")
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
				[[ "${input:-}" =~ ^[0-9]+$ || ! "${input:-}" ]] && {
					input_is_ready=t
				}||{
					MANUAL_REARRANGEMENT="${input:-}"
					continue 2
				}
			}
		done

		unset CHOSEN_ITEM  # may be left from some previous call
		[ "${input:-}" ] && {
			[[ "${input:-}" =~ ^[0-9]+$ ]] && {
				[ $input -le $LIST_ITEMS_COUNT ] && [ $input -gt 0 ] \
					&& CHOSEN_ITEM=`echo -e "$LIST_TO_CHOOSE_FROM" | sed -n "$input p"` \
					|| warn "Number must be a correct line number, from 1 to $LIST_ITEMS_COUNT." # copypaste, C-v etc.
			}|| warn "‘${input:-}’ must be a number."
		}
		[ -v CHOSEN_ITEM ] && CHOSEN_NUMBER="$input" || abort 'Cancelled.'
	done
	return 0
}