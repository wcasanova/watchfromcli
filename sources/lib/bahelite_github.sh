# Should be sourced.

#  bahelite_github.sh
#  Functions to check for the latest release page on github.com.
#  © deterenkelt 2018–2019

# Require bahelite.sh to be sourced first.
[ -v BAHELITE_VERSION ] || {
	echo 'Must be sourced from bahelite.sh.' >&2
	return 5
}
. "$BAHELITE_DIR/bahelite_messages.sh" || return 5
. "$BAHELITE_DIR/bahelite_versioning.sh" || return 5

# Avoid sourcing twice
[ -v BAHELITE_MODULE_GITHUB_VER ] && return 0
#  Declaring presence of this module for other modules.
BAHELITE_MODULE_GITHUB_VER='1.0.6'
BAHELITE_INTERNALLY_REQUIRED_UTILS+=(date stat ps wget xdg-open)
BAHELITE_INTERNALLY_REQUIRED_UTILS_HINTS+=(
	[ps]='ps is a part of procps-ng.
	http://procps-ng.sourceforge.net/
	https://gitlab.com/procps-ng/procps'
	[xdg-open]='xdg-open belongs to xdg-utils
	https://www.freedesktop.org/wiki/Software/xdg-utils/'
)

 # Default interval, that check_for_new_release() will use to look
#  for a new release. You can redefine it after sourcing bahelite.sh
#
NEW_RELEASE_CHECK_INTERVAL=21  # each N days


 # Confirms, that updater_timestamp exists.
#  The timestamp is used to maintain the specified interval between checks.
#  Can be overriden after sourcing bahelite.sh.
#
bahelite_create_updater_timestamp() {
	#  Default path, where release check timestamp should be placed.
	declare -g RELEASE_CHECK_TIMESTAMP="${CACHEDIR:-$MYDIR}/updater_timestamp"
	[ -f "$RELEASE_CHECK_TIMESTAMP" ] || touch "$RELEASE_CHECK_TIMESTAMP"
	return 0
}


 # Downloads “Releases” page of a github repo and compares the version
#  of the latest release to the current version of the program.
#  This function compares version with compare_versions(), so it also
#  works only with maximum three-numbered versions (X, X.Y or X.Y.Z)
#
#  TAKES
#    $1  – github user name (as in the URL)
#    $2  – github repo name (as in the URL)
#    $3  – version string to compare with the latest release.
#   [$4] – URL to release notes.
#   [$5] – what to do with the URL to release notes:
#          - “ask_to_open” – use console (Bahelite’s menu) or desktop (Xdialog)
#            dialog to ask the user, if he wants to open release notes
#            in his browser.
#          - “open” – don’t ask the user, always open.
#          - “print” – never ask, never open, just print the URL to stdout.
#
#  RETURNS
#    0 if there’s a new release, 1 if not, 5 in case of error in retrieving
#    or parsing input.
#
check_for_new_release() {
	xtrace_off && trap xtrace_on RETURN
	bahelite_create_updater_timestamp
	local days_since_last_check=$((
		(    $(date +%s)
		   - $(stat -L --format %Y "$RELEASE_CHECK_TIMESTAMP")
		) / 60 / 60 / 24                                        ,1 ))
	[ $days_since_last_check -lt $NEW_RELEASE_CHECK_INTERVAL ] \
		&& return 1
	local user="$1" repo="$2" our_ver="$3" relnotes_url="${4:-}" \
	      relnotes_action="${5:-}"  latest_release_ver  \
	      which_is_newer  message  open_relnotes_url
	is_version_valid "$our_ver" || {
		warn "Our version “$our_ver” is not a valid string."
		return 5
	}
	latest_release_ver=$(
		wget -O- https://github.com/$user/$repo/releases/latest \
			|& sed -rn "s=^.*/$user/$repo/tree/v([0-9\.]+).*$=\1=p;T;Q"
	) ||:
	is_version_valid "$latest_release_ver" || {
		warn "Latest release version “$latest_release_ver” is not a valid string."
		return 5
	}
	touch "$RELEASE_CHECK_TIMESTAMP"
	which_is_newer=$(compare_versions "$our_ver" "$latest_release_ver")

	if [ "$which_is_newer" = "$latest_release_ver" ]; then
		info-ns "${__bri}v$latest_release_ver is available!${__s}"
		[ "$relnotes_url" ] && {
			case "$relnotes_action" in
				ask_to_open)
					# message="Would you like to read release notes\n"
					# message+="for v$latest_release_ver on Github?"
					#  If our shell has a terminal…
					#  (literally: it is a foreground process)
					#  P.S. no, both [[ "$-" =~ ^.*i.*$ ]] and [ -t 0 ]
					#       do not work here.
					# if [[ "$(ps -o stat= -p $$)" =~ ^.*\+.*$ ]]; then
					# 	menu "${message//\\n/}" Yes No
					# 	[ "$CHOSEN" = Yes ] && open_relnotes_url=t
					# else
					# 	which Xdialog &>/dev/null && {
					# 		local dialog=Xdialog
					# 		errexit_off
					# 		$dialog --stdout \
					# 	            --ok-label Open \
					# 	            --cancel-label No \
					# 	            --yesno "$message" 400x110 \
					# 			&& open_relnotes_url=t
					# 		errexit_on
					# 	}
					# fi
					;;
				open)
					open_relnotes_url=t
					;;
				print)
					info "You can read, what’s new in the new version here:
					      $relnotes_url"
					;;
				*)
					#  Do nothing.
					;;
			esac
			[ -v open_relnotes_url ] && xdg-open "$relnotes_url"
		}
	else
		info 'This version is the latest available.'
		return 1
	fi
	return 0
}


return 0