# Should be sourced.

#  bahelite_versioning.sh
#  Provides simple versioning in the form <major[.minor[.patch]]>.
#  Doesn’t work with versions longer than three numbers, e.g. “1.2.3.4”!
#  deterenkelt © 2018

# Require bahelite.sh to be sourced first.
[ -v BAHELITE_VERSION ] || {
	echo 'Must be sourced from bahelite.sh.' >&2
	return 5
}
. "$BAHELITE_DIR/bahelite_messages.sh" || return 5

# Avoid sourcing twice
[ -v BAHELITE_MODULE_VERSIONING_VER ] && return 0
#  Declaring presence of this module for other modules.
BAHELITE_MODULE_VERSIONING_VER='1.1.1'

# It is *highly* recommended to use “set -eE” in whatever script
# you’re going to source it from.

 # Call a dialog to update version in the specified file.
#  It’s supposed to be sourced from a pre-commit hook.
#  $1 – file name (absolute path) where the version needs to be changed.
#  $2 – variable name containing the version. Assignment to this variable
#       must occur in the code only once and be the only command on the line.
#
update_version() {
	xtrace_off && trap xtrace_on RETURN
	local file="$1" varname="$2" old_version new_version \
	      old_major old_minor old_patch \
	      major_nines minor_nines patch_nines \
	      new_major new_minor new_patch \
	      v v_val i xdialog_text which_is_newer
	[ -w "$file" ] || err "“$file”
		                   is not a writeable file."
	grep -qE "^\s*(declare\s+-r\s+|)$varname=" "$file" \
		|| err "Variable “$varname” assignment is nowhere to be found in file
		        “file”."
	[ "$(grep -cE "^\s*(declare\s+-r\s+|)$varname=" "$file")" = 1 ] \
		|| err "Variable “$varname” is assigned more than once in file
		        “file”."
	which Xdialog &>/dev/null || err 'Xdialog wasn’t found, but is required.'

	readarray -t old_version < <(
		# Possible version lines:
		# Column 0 in the file -> |version="1.22.333"
		#                         |   version=20180321
		#                         |       declare  -r version='1.22.333'
		sed -rn "s/^\s*(declare\s+-r\s+|)$varname=['\"]?([0-9\.]+)['\"]?\s*$/\2/
		         T
		         s/\./\n/g
		         p" \
		    "$file"
	)
	[ ${#old_version[@]} -le 3 ] \
		|| err "Old version splits to more than three parts: “${old_version[*]}”."
	old_major=${old_version[0]:-0}
	old_minor=${old_version[1]:-0}
	old_patch=${old_version[2]:-0}
	[[ "$old_major" =~ ^[0-9]+$ ]] \
		|| err "Major version is not a number: “$old_major”."
	[[ "$old_minor" =~ ^[0-9]+$ ]] \
		|| err "Minor version is not a number: “$old_minor”."
	[[ "$old_patch" =~ ^[0-9]+$ ]] \
		|| err "Patch version is not a number: “$old_patch”."
	# Xdialog spinboxes need padding or three-digit numbers and above
	# may not fit entirely. This is not just cosmetic.
	for v in  old_major  old_minor  old_patch; do
		declare -n v_val=$v
		for ((i=0; i<${#v_val}; i++)); do
			# Use as much digits as the part in the old_version had.
			local ${v}_nines+='9'
		done
		local ${v}_nines+='99'  # Add the actual padding.
	done
	xdialog_text='Set new version for file'
	xdialog_text+="\n${file##*/}"
	xdialog_text+="\n\nOld version: $old_major.$old_minor.$old_patch."
	errexit_off
	read -d '' new_major  new_minor  new_patch  < <(
			Xdialog --stdout \
			        --title "Set new version" \
			        --separator $'\n' \
			        --3spinsbox "Set new version for file\n" 400x170 \
	    		    0 "$major_nines" "$old_major" major \
	    	        0 "$minor_nines" "$old_minor" minor \
			        0 "$patch_nines" "$old_patch" patch \
			        ;\
			echo -e '\0'
			        # Fields: min max default label
	)
	errexit_on
	[ "$new_major" ] || err 'Aborted.'
	if [ $new_minor -ne 0  -a  $new_patch -ne 0 ]; then
		new_version="$new_major.$new_minor.$new_patch"
	elif [ $new_minor -ne 0 ]; then
		new_version="$new_major.$new_minor"
	else
		new_version="$new_major"
	fi
	unset old_version
	local old_version=$old_major.$old_minor.$old_patch
	which_is_newer=$(compare_versions "$old_version" "$new_version" )
	if [ "$which_is_newer" = "$old_version" ]; then
		xdialog_text="$old_version → $new_version"
		xdialog_text+="\nThe old version seems to be newer."
		xdialog_text+="\nStill write?"
		errexit_off
		Xdialog --stdout --title "Confirm new version" \
		        --ok-label Write --cancel-label Cancel \
		        --yesno "$xdialog_text" 400x110 \
			|| err 'Aborted.'
		errexit_on
	elif [ "$which_is_newer" = 'equal' ]; then
		xdialog_text="$old_version = $new_version"
		xdialog_text+="\nBoth versions are equal."
		xdialog_text+="\nStill write?"
		errexit_off
		Xdialog --stdout --title "Confirm new version" \
		        --ok-label Write --cancel-label Cancel \
		        --yesno "$xdialog_text" 400x110 \
			|| err 'Aborted.'
		errexit_on
	fi
	sed -ri "s/^(\s*(declare\s+-r\s+|))$varname=['\"]?[0-9\.]+['\"]?\s*$/\1$varname='$new_version'/" "$file"
	return 0
}

 # Returns 0, if the passed string is a valid version number,
#  e.g. “X”, “X.Y” or “X.Y.Z”. Returns 1 otherwise.
#  $1 – version string
#
is_version_valid() {
	xtrace_off && trap xtrace_on RETURN
	[[ "$1" =~ ^[0-9]{1,12}(\.[0-9]{1,12}){0,2}$ ]] \
		&& return 0 \
		|| return 1
}

 # Compares two versions, and returns either the bigger one or “equal”.
#    $1 – version string.
#    $2 – version string.
#
compare_versions() {
	xtrace_off && trap xtrace_on RETURN
	local i old_version="$1" new_version="$2"
	IFS='.' old_version=( $1 )
	IFS='.' new_version=( $2 )
	[ ${#new_version[@]} -ge ${#old_version[@]} ] \
		&& shortest_length=${#old_version[@]} \
		|| shortest_length=${#new_version[@]}
	# +2 is needed to compare implied digits, e.g. with 0 vs 0.0.1 the latter
	# should be considered bigger. The comparison shouldn’t end on the first
	# or the second digit and consider them equal.
	for ((i=0; i<shortest_length+2; i++)); do
		[[ "${old_version[i]:-}" =~ ^[0-9]+$ ]] || old_version[$i]=0
		[[ "${new_version[i]:-}" =~ ^[0-9]+$ ]] || new_version[$i]=0
		if [ ${new_version[i]} -gt ${old_version[i]} ]; then
			echo "$2"
			return 0
		elif [ ${old_version[i]} -gt ${new_version[i]} ]; then
			echo "$1"
			return 0
		fi
	done
	echo 'equal'
	return 0
}

return 0
