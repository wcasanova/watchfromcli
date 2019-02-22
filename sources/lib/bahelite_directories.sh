# Should be sourced.

#  bahelite_misc.sh
#  Functions to set paths to internal and user directories.
#  © deterenkelt 2019

#  Require bahelite.sh to be sourced first.
[ -v BAHELITE_VERSION ] || {
	echo 'Must be sourced from bahelite.sh.' >&2
	return 5
}
. "$BAHELITE_DIR/bahelite_messages.sh" || return 5

# Avoid sourcing twice
[ -v BAHELITE_MODULE_DIRECTORIES_VER ] && return 0
#  Declaring presence of this module for other modules.
BAHELITE_MODULE_DIRECTORIES_VER='1.0'


                       #  XDG directories  #

: ${XDG_CONFIG_HOME:=$HOME/.config}
: ${XDG_CACHE_HOME:=$HOME/.cache}
: ${XDG_DATA_HOME:=$HOME/.local/share}


 # Prepares config directory with respect to XDG
#  [$1] – script name, whose config directory will be used.
#         If unset, uses $MYNAME. (Useful for when there’s a script suite,
#         which should use same directory, or when one script is a testing
#         suite for another and should be able to retrieve other script’s
#         config directory).
#
prepare_confdir() {
	[ -v BAHELITE_CONFDIR_PREPARED ] && {
		info "Config directory is already prepared!"
		return 0
	}
	[ "${1:-}" ] \
		&& local own_subdir="$1" \
		|| local own_subdir="${MYNAME%.*}"
	[ -v CONFDIR ] || CONFDIR="$XDG_CONFIG_HOME/$own_subdir"

	bahelite_check_directory "$CONFDIR" 'Config'
	declare -g BAHELITE_CONFDIR_PREPARED=t
	return 0
}


 # Prepares cache directory with respect to XDG
#  [$1] – script name, whose cache directory will be used.
#         If unset, uses $MYNAME. (Useful for when there’s a script suite,
#         which should use same directory, or when one script is a testing
#         suite for another and should be able to retrieve other script’s
#         cache directory).
#
prepare_cachedir() {
	[ -v BAHELITE_CACHEDIR_PREPARED ] && {
		info "Cache directory is already prepared!"
		return 0
	}
	local own_subdir
	[ "${1:-}" ] \
		&& local own_subdir="$1" \
		|| local own_subdir="${MYNAME%.*}"
	[ -v CACHEDIR ] || CACHEDIR="$XDG_CACHE_HOME/$own_subdir"

	bahelite_check_directory "$CACHEDIR" 'Cache'
	declare -g BAHELITE_CACHEDIR_PREPARED=t
	return 0
}


 # Prepares data directory with respect to XDG
#  [$1] – script name, whose data directory will be used.
#         If unset, uses $MYNAME. (Useful for when there’s a script suite,
#         which should use same directory, or when one script is a testing
#         suite for another and should be able to retrieve other script’s
#         data directory).
#
prepare_datadir() {
	[ -v BAHELITE_DATADIR_PREPARED ] && {
		info "Data directory is already prepared!"
		return 0
	}
	[ "${1:-}" ] \
		&& local own_subdir="$1" \
		|| local own_subdir="${MYNAME%.*}"
	[ -v DATADIR ] || DATADIR="$XDG_DATA_HOME/$own_subdir"

	bahelite_check_directory "$DATADIR" 'Data'
	declare -g BAHELITE_DATADIR_PREPARED=t
	return 0
}


                      #  Internal subdirectories  #

 # Set LIBDIR or MODULESDIR
#  [$1] – script’s own subdirectory to search for (when it doesn’t match
#         the script name). Alike to $1 in prepare_cachedir() below.
#
set_libdir()         { set_required_dir LIBDIR         "$@"; }
set_modulesdir()     { set_required_dir MODULESDIR     "$@"; }
set_exampleconfdir() { set_required_dir EXAMPLECONFDIR "$@"; }
#
#  Actually sets LIBDIR and MODULESDIR globally
#   $1  – the variable, that must be set
#  [$2] – a custom subdirectory name, if it doesn’t match with the script
#         own name. Alike to $1 in prepare_cachedir() below.
#
set_required_dir() {
	local varname="$1" whats_the_dir  own_subdir  dir
	whats_the_dir="${varname,,}"
	whats_the_dir=${whats_the_dir%dir}  # LIBDIR → libdir → lib
	[ "${2:-}" ] \
		&& own_subdir="$2" \
		|| own_subdir="${MYNAME%.*}"
	for dir in "/usr/share/$own_subdir/$whats_the_dir" \
	           "/usr/local/share/$own_subdir/$whats_the_dir" \
	           "$MYDIR/$whats_the_dir"
	do
		[ -d "$dir" ] && { declare -g $varname="$dir"; break; }
	done
	[ -v "$varname" ] || err "Cannot find directory for $varname."
	return 0
}


 # Makes sure, that a directory exists and has R/W permissions.
#  $1 – path to the directory.
#  $2 – the purpose like “config” or “logging”. It is used only in the
#       error message.
#
bahelite_check_directory() {
	local dir="${1:-}" purpose="${2:-}"
	[ -v purpose ] && purpose="${purpose,,}"
	if [ -d "$dir" ]; then
		[ -r "$dir" ] \
			|| err "${purpose^} directory “$dir” isn’t readable."
		[ -w "$dir" ] \
			|| err "${purpose^} directory “$dir” isn’t writeable."
	else
		mkdir -p "$dir" || err "Couldn’t create $purpose directory “$dir”."
	fi
	return 0
}


return 0