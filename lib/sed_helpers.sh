# EXPECTS:
#   - that you know why some characters should be escaped;
#   - that the output will be used in a subshell, i.e. $(…)
#     so don’t make assignings like
#       var1=`escape_for_sed_pattern "blablabla"`
#     but use a subshell in place.
# TAKES:
#     $1 – a string to escape.
# RETURNS:
#     An escaped string.
escape_for_sed_pattern() {
	# Add second parameter to set number of additional escapes so it
	#   would escape properly a string that would be able to undergo eval?
	local str="$1"
	# Really not sure how many backslashes needed to escape
	#   slash and backslash itself, think one is alright.
	str=${str//\\/\\} # must be first
	str=${str//\./\\.}
	str=${str//\$/\\$}
	str=${str//\*/\\*}
	# Your syntax checker may fail here,
	#   and indentaion may also be fucked up, but it’s ok.
	str=${str//\[/\\[}   # …add round parentheses too?
	# str=${str//\]/\\]}
	# Just in case. There must be no slashes. If sed suddenly starts
	#   throw errors like
	#     sed: -e expression #1, char 84: extra characters after command
	#     sed: -e expression #1, char 77: unknown command: `o'
	#     sed: -e expression #1, char 102: Invalid range end
	#   especially when BASEPATH is an array, this may mean that folder paths
	#   have appeared in the pattern when they should not, because
	#   create_groups_for_the_list() must only process _file names_ when
	#   MODE == episodes and choose_from() was called from watch().
	# P.S. Slashes are used in do_initial_search() when removing
	#   duplicates from d.
	str=${str//\//\\/}
	str=${str//\^/\\^}
	echo -en "$str" # TODO: check for what purpose is -e here
}


# TAKES:
#     $1 – string to prepare to be put in sed replacement string.
escape_for_sed_replacement() {
	# local str="$1" # as it was before 20140915
	# to cover issue with ' in file names, when it goes through the journal
	# NB  suited for export_session_data, for being read through eval in
	#     import_session_data
	local str=${1//\\/\\\\} # must be first
	str=${str//\'/\'\"\'\"\'} # glue: var='bla bl'a bla'  →  var='bla bl'"'"'a bla'
	str=${str//&/\\&}
	str=${str//\//\\/}
	# str=${str//\"/\\\"} # Just for the case if a bug will appear
	echo -en "$str"
}