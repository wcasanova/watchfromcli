# Should be sourced.

#  bahelite_directories.sh
#  Functions to set paths to internal and user directories.
#  © deterenkelt 2019

#  Require bahelite.sh to be sourced first.
[ -v BAHELITE_VERSION ] || {
	echo "Bahelite error on loading module ${BASH_SOURCE##*/}:"  >&2
	echo "load the core module (bahelite.sh) first."  >&2
	return 4
}

#  Avoid sourcing twice
[ -v BAHELITE_MODULE_DIRECTORIES_VER ] && return 0
#  Declaring presence of this module for other modules.
declare -grx BAHELITE_MODULE_DIRECTORIES_VER='1.1.7'



                     #  Paths within user’s $HOME  #

[ -v XDG_CONFIG_HOME ]  \
	|| declare -gx  XDG_CONFIG_HOME="$HOME/.config"
[ -v XDG_CACHE_HOME ]  \
	|| declare -gx  XDG_CACHE_HOME="$HOME/.cache"
[ -v XDG_DATA_HOME ]  \
	|| declare -gx  XDG_DATA_HOME="$HOME/.local/share"


 # Creates the directory for storing configuration files.
#    If CONFDIR isn’t already set in the environment, a subdirectory would be
#    created under XDG_CONFIG_HOME.
#  [$1] – subdirectory name. If not set, ${MYNAME%.*} will be used
#         (i.e. the main script file name without an extension).
#
#         Setting $1 manually may help when you have a bunch (a family)
#         of scripts, but want them to use single config directory.
#         E.g. if you have my-script.sh and my-script-something-else.sh,
#         the config directory would probably called “my-script”, so
#         in my-script.sh use “prepare_confdir”
#         in my-script-something-else use “prepare_confdir 'my-script'”
#
prepare_confdir() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -gx CONFDIR
	local own_subdir
	if [ -v CONFDIR ]; then
		info 'CONFDIR is already set!'
	else
		[ "${1:-}" ] \
			&& own_subdir="$1" \
			|| own_subdir="${MYNAME%.*}"
		CONFDIR="$XDG_CONFIG_HOME/$own_subdir"
	fi
	__check_directory "$CONFDIR" 'Config'
	return 0
}
#  No export: init stage function.


 # Creates the directory for storing cache files (logging module also uses it).
#    If CACHEDIR isn’t already set in the environment, a subdirectory would be
#    created under XDG_CACHE_HOME.
#  [$1] – subdirectory name. If not set, ${MYNAME%.*} will be used
#         (i.e. the main script file name without an extension).
#
#         See also the comment to prepare_confdir() above.
#
prepare_cachedir() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -gx CACHEDIR
	local own_subdir
	if [ -v CACHEDIR ]; then
		info 'CACHEDIR is already set!'
	else
		[ "${1:-}" ] \
			&& own_subdir="$1" \
			|| own_subdir="${MYNAME%.*}"
		CACHEDIR="$XDG_CACHE_HOME/$own_subdir"
	fi
	__check_directory "$CACHEDIR" 'Cache'
	return 0
}
#  No export: init stage function.


 # Creates the directory for storing persistent extra files.
#    If DATADIR isn’t already set in the environment, a subdirectory would be
#    created under XDG_DATA_HOME.
#  [$1] – subdirectory name. If not set, ${MYNAME%.*} will be used
#         (i.e. the main script file name without an extension).
#
#         See also the comment to prepare_confdir() above.
#
prepare_datadir() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	declare -gx DATADIR
	local own_subdir
	if [ -v DATADIR ]; then
		info 'DATADIR is already set!'
	else
		[ "${1:-}" ] \
			&& own_subdir="$1" \
			|| own_subdir="${MYNAME%.*}"
		DATADIR="$XDG_DATA_HOME/$own_subdir"
	fi
	__check_directory "$DATADIR" 'Data'
	return 0
}
#  No export: init stage function.



                      #   System directories   #

 # These are the directories being the part of the source code.
#  Bahelite supports two ways of finding them, depending on how
#  the source is installed:
#
#  - IF THE SOURCE REMAINS A SOLID PIECE, e.g. it is downloaded by the user
#    (or cloned with some version control system) somewhere under his own
#    $HOME, the source directories are searched in the same directory, where
#    the main script (the mother script for bahelite) itself resides.
#
#  - IF THE SOURCE IS SPLIT, because a package manager (or a Linux enthusiast)
#    utilised some Makefile, then the subdirectories are searched depending on
#    where the executable file – the main script – resides, and on the purpose
#    of the subdirectory. Where each subdirectory is search, read below.
#
#  Bahelite tries to intellectually determine, whether the installation is
#    a solid, standalone or it is split across the root filesystem. For that
#    MYDIR is tested to be /usr/local/bin or /usr/bin, and if it appears to be
#    one of them, BAHELITE_SPLIT_INSTALLATION is set. See the code at the bot-
#    tom of this file.
#  This variable prevents search for source subdirectories in MYDIR. In the
#    case when a user might install the main program both ways – with a pack-
#    age manager and locally, then calling the executable from the local in-
#    stallation should not look into system directories, and stay in MYDIR
#    instead. And vice versa, a split installation will not try to find
#    source subdirectories in $PATH, around the executable.
#
#
#                 Possible paths for source subdirectories
#
#                    SOLID INSTALLATION     SPLIT INSTALLATION
#                    (all in MYDIR)         (separated across filesystem)
#
#            LIBDIR¹ ./lib                        /usr/lib/${MYNAME%.*}
#                                           /usr/local/lib/${MYNAME%.*}
#
#        MODULESDIR² ./modules                    /usr/lib/${MYNAME%.*}
#                                           /usr/local/lib/${MYNAME%.*}
#
#    EXAMPLECONFDIR³ ./exampleconf          /usr/share/${MYNAME%.*}/exampleconf
#                                           /usr/local/share/${MYNAME%.*}/exampleconf
#
#    Notes
#    1. Note, that in the OS the “lib” directory is a common one, so a subdi-
#       rectory is created. the files from the lib in the source code go to
#                    <usr prefix>/lib/${MYNAME%.sh},
#           not into <usr prefix>/lib/${MYNAME%.sh}/lib !
#    2. Modules are essentially libraries too. The division on libs and modu-
#       les in the split installation only reflects the way of keeping files
#       in the source code, where libraries may be third-party and better to
#       be kept separately because of their licence or the ease of updating
#       them, while modules are just parts of the main script separated into
#       their own physical files. If the main script would be distributed
#       as is, merging modules into libs would require a post-unpack hook
#       in the archive or a post-clone hook in the repository, what isn’t
#       conceivable.
#    3. EXAMPLECONFDIR can be any extra directory, e.g. RESDIR or MY_SPECIAL_
#       DATA_DIR.
#    4. Plural forms are possible:
#         - for the solid type of installation both “lib” and “libs” are accep-
#           table, as well as “module and modules”, “exampleconf” and “example-
#           confs”;
#         - for the split type of installation only the extra files may have
#           plural forms (the common “lib” directory belongs to OS).
#       The provided alias functions: set_libdir(), set_modulesdir() etc. set
#       variables in their specific form: LIBDIR, MODULESDIR (not LIBSDIR,
#       MODULEDIR), but you may call set_source_dir() with the variables named
#       to your taste, the underlying function __set_source_dir() will recog-
#       nise both lib/libs and module/modules and will direct it properly
#       in the case of split installation.
#    5. The author doesn’t believe, that somebody would use Bahelite for essen-
#       tial system software, hence the basic directories like /bin and /lib
#       are never searched.


 # Helpers for setting the most common source subdirectories.
#
set_libdir() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	__set_source_dir LIBDIR "$@"
}
set_modulesdir() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	__set_source_dir MODULESDIR "$@"
}
set_defconfdir() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	__set_source_dir DEFCONFDIR "$@"
}
set_metaconfdir() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	__set_source_dir METACONFDIR "$@"
}
set_resdir() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	__set_source_dir RESDIR "$@"
}
set_sourcedir() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	__set_source_dir "$@"
}
#
#
 # Finds paths for the subdirectories of the source code and sets these
#  paths to global variables.
#  $1  – subdirectory name and also the name of the global variable, that will
#        hold the path. I.e. you give the variable name, and the subdirectory
#        name is found by making it lowercase and stripping “dir” from the end.
# [$2] – a custom subdirectory name to use in place of $MYNAME
#        Alike to $1 in prepare_cachedir() above.
#
__set_source_dir() {
	local varname="${1^^}"  own_subdir="${2:-$MYNAME}"  dir  possible_paths=()
	local whats_the_dir="${varname,,}"   #  LIBDIR → libdir
	whats_the_dir=${whats_the_dir%dir}   #           libdir → lib
	own_subdir=${own_subdir%.*}          #  my-prog.sh → my-prog
	if [ -v BAHELITE_SPLIT_INSTALLATION ]; then
		case "$whats_the_dir" in
			lib|module)
			;&
			libs|modules)
				possible_paths+=(
					"$BAHELITE_USRDIR_PREFIX/lib/$own_subdir"
				)
				;;
			*)
				possible_paths+=(
					"$BAHELITE_USRDIR_PREFIX/share/$own_subdir/$whats_the_dir"
					"$BAHELITE_USRDIR_PREFIX/share/$own_subdir/${whats_the_dir}s"
				)
				;;
		esac
	else
		possible_paths=(
			"$MYDIR/$whats_the_dir"
			"$MYDIR/${whats_the_dir}s"
		)
	fi
	for dir in "${possible_paths[@]}"; do
		[ -d "$dir" ] && {
			[ -v BAHELITE_MODULES_ARE_VERBOSE ] \
				&& info "$FUNCNAME: setting $varname to “$dir”"
			declare -gx $varname="$dir"
			break
		}
	done
	[ -v "$varname" ] || err "Cannot find directory for $varname."
	return 0
}
#  No export: init stage functions.


 # Makes sure, that a directory exists and has R/W permissions.
#  $1 – path to the directory.
#  $2 – the purpose like “config” or “logging”. It is used only in the
#       error message.
#
__check_directory() {
	#  Internal! No xtrace_off/on needed!
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
#  No export: init stage function.



 # For the use in __set_source_dir().
#
[[ "$MYDIR" =~ (/usr/bin|/usr/local/bin) ]] && {
	declare -gr BAHELITE_SPLIT_INSTALLATION=t
	declare -gr BAHELITE_USRDIR_PREFIX=${BASH_REMATCH[1]%/bin}
}

return 0