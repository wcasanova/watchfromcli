# EXPECTS:
#     SCREENSHOT_DIR – if set, then we should be in screenshot directory
#         and therefore, will be popd’d later inside of the trap.
#     *.png – screenshots taken.
# RETURNS:
#     0 if the function processed screenshots, 1 if not. This is needed
#     to distinguish cases when it did the job and when it didn’t to avoid
#     printing last shown episode number twice.
# screenshots_postprocessing() {
# 	local new_screenshots=()
# 	# Seeking screenshots
# 	[ -d "$SCREENSHOT_DIR" ] && {
# 		compress_screenshot() {
# 			local shot="$1"
# 			[ -v pngcrush ] && {
# 				# In place overwriting wasn’t supposed to run under parallel.
# 				# Should check how to run optipng some day.
# 				pngcrush -reduce "$shot" "/tmp/$shot"
# 				mv "/tmp/$shot" "$shot"
# 			}
# 			[ -v JPEG_COMPRESSION ] && [ -v pngtopbm ] && [ -v cjpeg ] && {
# 				$pngtopbm "$shot" 2>/dev/null \
# 					| cjpeg -quality $JPEG_COMPRESSION \
# 					        -progressive \
# 					        -outfile "${shot%.*}.jpg" \
# 					        &>/dev/null
# 				rm "$shot"
# 			}
# 		}

# 		while IFS= read -r -d ''; do
# 			new_screenshots+=("$REPLY")
# 		done < <(find "$SCREENSHOT_DIR" -maxdepth 1 \
# 		              -type f -iname "*.png" \
# 		              -newermt @$screendir_timestamp \
# 		              -print0)
# 		[ ${#new_screenshots[@]} -ne 0 ] && {
# 			if which parallel &>/dev/null; then
# 				# Exporting the function doing the job to the environment,
# 				#   so it would be available in the subshell. Also doing `which`
# 				#   here, so the function wouldn’t call it each time.
# 				export -f compress_screenshot
# 				export JPEG_COMPRESSION # if unset, then not exported
# 				which pngcrush &>/dev/null && export pngcrush=t
# 				# pngtopnm is old binary and as far as I know it is removed
# 				#   from the upstream package, but symlinked to pngtopam in
# 				#   many distributives. Except debean >_>
# 				which pngtopnm &>/dev/null && export pngtopbm=pngtopnm
# 				# Modern distrubutives won’t use symlink, Debean won’t get
# 				#   an inexisting binary.
# 				which pngtopam &>/dev/null && export pngtopbm=pngtopam
# 				which cjpeg &>/dev/null && export cjpeg=t
# 				${taskset_cmd:-} parallel --eta compress_screenshot ::: "${new_screenshots[@]}"
# 				export -nf compress_screenshot
# 			else
# 				cpu_cores=$(nproc)
# 				[[ "$cpu_cores" =~ ^[0-9]+$  &&  "$cpu_cores" -gt 1 ]] \
# 					&& warn 'No parallel was found. Using 1 CPU core.'
# 				for shot in $new_screenshots; do
# 					${taskset_cmd:-} compress_screenshot "$shot"
# 				done
# 			fi
# 		}
# 	}
# 	return $((1-0${new_screenshots:+1}))
# }