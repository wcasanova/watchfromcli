# Should be sourced.

#  bahelite.sh
#  Bash helper library for Linux to create more robust shell scripts.
#  © deterenkelt 2018–2019
#  https://github.com/deterenkelt/Bahelite
#
#  This work is based on the Bash Helper Library for Large Scripts,
#  that I’ve been initially developing for Lifestream LLC in 2016. It was
#  licensed under GPL v3.
#
 # Bahelite is free software; you can redistribute it and/or modify it
#    under the terms of the GNU General Public License as published
#    by the Free Software Foundation; either version 3 of the License,
#    or (at your option) any later version.
#  Bahelite is distributed in the hope that it will be useful, but without
#    any warranty; without even the implied warranty of merchantability
#    or fitness for a particular purpose. See the GNU General Public License
#    for more details.


 # Bahelite doesn’t enable or disable any shell options, it leaves to the prog-
#    rammer to choose an optimal set. Bahelite may only temporarily enable or
#    disable shell options – but only temporarily.
#  It is *highly* recommended to use “set -feEu” in the main script, and if
#    you add -T to that, thus making the line “set -feEuT”, Bahelite will be
#    able to catch more bash errors.
#
 # The exit codes:
#    1 – is not used. It is the generic code, with which main script may
#        exit, if the programmer forgets to place his exits and returns pro-
#        perly. Let these mistakes be exposed.
#    2 – is not used. Bash exits with this code, when it catches an interpre-
#        ter or a syntax error. Such errors may happen in the main script.
#    3 – Bahelite exits with this code, if the system runs an incompatible
#        version of the Bash interpreter.
#    4 – Bahelite uses this code for all internal errors, i.e. related to the
#        inner mechanics of this library, like checking for the minimal depen-
#        dencies, loading modules, on an unsolicited attempt to source the main
#        script (instead of executing it). In each case a detailed message
#        starting with “Bahelite error:” is printed to stderr.
#    5 – any error happening in the main script after Bahelite is loaded.
#        You are strongly advised to use err() from bahelite_messages.sh
#        instead of something like { echo 'An error happened!' >&2; exit 5; }.
#        To use custom error codes, use ERROR_CODES (see bahelite_messages.sh).
#    6 – an abort sanctioned by the one who runs the main script. Since an
#        early quit means, that the run was not successful (as the program
#        didn’t have a chance to complete whatever it was made for), and on
#        the other hand it’s not like the program is broken (what a regular
#        error would indicate), the exit code must be distinctive from both
#        the “clear exit” with code 0 and “regular error” with code 5.
#    7–125 – free for the main script.
#    126–165 – not used by Bahelite and must not be used in the main script:
#        this range belongs to the interpreter.
#    166–254 – free for the main script.
#    255 – not used by Bahelite and must not be used in the main script:
#        this code may be triggered by more than one reason, which makes it
#        ambiguous.
#
#  Notes
#  1. Codes 5 and 6 are used only if the error_handling module is included
#    (it is included by default).
#  2. The usage of codes 1–6, 126–165, 255 is prohibited in ERROR_CODES,
#     if you decide to use it for the custom type-specific error codes.
#    (See bahelite_messages.sh for details.)



 # Require bash v4.3 for declare -n.
#          bash v4.4 for the fixed typeset -p behaviour, ${param@x} operators,
#                    SIGINT respecting builtins and interceptable by traps,
#                    BASH_SUBSHELL that is updated for process substitution.
#
if	((    ${BASH_VERSINFO[0]:-0} <= 3
	   || (
	            ${BASH_VERSINFO[0]:-0} == 4
	        &&  ${BASH_VERSINFO[1]:-0} <  4
	      )
	))
then
	echo -e "Bahelite error: bash v4.4 or higher required." >&2
	#  so that it would work for both sourced and executed scripts
	return 3 2>/dev/null ||	exit 3
fi

 # Scripts usually shouldn’t be sourced. And so that your main script wouldn’t
#  be sourced by an accident, Bahelite checks, that the main script is called
#  as an executable. To allow the usage of Bahelite in a sourcable script,
#  set BAHELITE_LET_MAIN_SCRIPT_BE_SOURCED to any value.
#
if	[ ! -v BAHELITE_LET_MAIN_SCRIPT_BE_SOURCED ] \
	&& [ "${BASH_SOURCE[-1]}" != "$0" ]
then
	echo -e "Bahelite error: ${BASH_SOURCE[-1]} shouldn’t be sourced." >&2
	return 4
fi


                #  Cleaning the environment before start  #

 # Wipe user functions from the environment
#  This is done by default, because of the custom things, that often
#    exist in ~/.bashrc or exported from some higher, earlier shell. Being
#    supposed to only simplify the work in terminal, such functions may –
#    and often will – complicate things for a script.
#  To keep the functions exported to us in this scope, that is, the scope
#    where this very script currently execues, define BAHELITE_KEEP_ENV_FUNCS
#    variable before sourcing bahelite.sh. Keep in mind, that outer functions
#    may lead to an unexpected behaviour.
#
if [ ! -v BAHELITE_KEEP_ENV_FUNCS ]; then
	#  This wipes every function, which name doesn’t start with an underscore
	#  (those that start with “_” or “__” are internal functions mostly
	#  related to completion)
	unset -f $(declare -F | sed -rn 's/^declare\s\S+\s([^_]*+)$/\1/p')
fi
#
#
 # env in shebang will not recognise -i, so an internal respawn is needed
#  in order to run the script in a clean environment. Be aware, env -i
#  literally WIPES the environment – you won’t find $HOME or $USER any more.
#
if [ -v BAHELITE_TOTAL_ENV_CLEAN ]; then
	[ ! -v BAHELITE_ENV_CLEANED ] && {
		exec /usr/bin/env -i BAHELITE_ENV_CLEANED=t bash "$0" "$@"
		exit $?
	}
fi
declare -r BAHELITE_VARLIST_BEFORE_STARTUP="$(compgen -A variable)"


                    #  Checking basic dependencies  #

 # Dependency checking goes in three stages:
#  - basic dependencies (you are here). It’s those, that allow internal
#    mechanisms of Bahelite to work. Passing this stage guarantees only
#    that Bahelite has the necessary minimum to work and it can proceed
#    to loading modules and doing more complex stuff.
#  - module dependency checking. Sourcing the modules doesn’t need anything
#    but the source command – at least it shouldn’t require any outside
#    utils. The programmer is supposed to run check_required_utils (see the
#    definition below in this file) when he thinks everything would be ready,
#    and then the dependencies specified by the modules will be checked along
#    the main script dependencies.
#  - main script dependency checking. See check_required_utils below again.
#
if [ "$(type -t sed)" != 'file' ]; then
	echo 'Bahelite error: sed is not installed.' >&2
	do_exit=t

elif [ "$(type -t grep)" != 'file' ]; then
	echo 'Bahelite error: grep is not installed.' >&2
	do_exit=t

elif [ "$(type -t getopt)" != 'file' ]; then
	echo 'Bahelite error: util-linux is not installed.' >&2
	do_exit=t

elif [ "$(type -t yes)" != 'file' ]; then
	echo 'Bahelite error: coreutils is not installed.' >&2
	do_exit=t
fi
#  This is to accumulate messages, so that if more than one utility would be
#  missing, the messages would appear at once.
[ -v do_exit ] && exit 4 || unset do_exit

sed_version=$(sed --version | sed -n '1p')
grep -q 'GNU sed' <<<"$sed_version" || {
	echo 'Bahelite error: sed must be GNU sed.' >&2
	exit 4
}
grep_version=$(grep --version | sed -n '1p')
grep -q 'GNU grep' <<<"$grep_version" || {
	echo 'Bahelite error: grep must be GNU grep.' >&2
	exit 4
}

#  ex: sed (GNU sed) 4.5
if [[ "$sed_version" =~ ^sed.*\ ([0-9]+)(\.([0-9]+)|)(\.([0-9]+)|)$ ]]; then
	if	((    ${BASH_REMATCH[1]} <= 3
		   || (      ${BASH_REMATCH[1]:-0} == 4
		         &&  ${BASH_REMATCH[3]:-0} <= 2
		         &&  ${BASH_REMATCH[5]:-0} <  1
		      )
		))
	then
		echo -e "Bahelite error: sed v4.2.1 or higher required." >&2
		exit 4
	fi
else
	echo 'Bahelite error: cannot determine sed version.' >&2
	exit 4
fi

#  ex: grep (GNU grep) 3.1
if [[ "$grep_version" =~ ^grep.*\ ([0-9]+)(\.([0-9]+)|)(\.([0-9]+)|)$ ]]; then
	if	((    ${BASH_REMATCH[1]} <= 1
		   || (      ${BASH_REMATCH[1]:-0} == 2
		         &&  ${BASH_REMATCH[3]:-0} <  9
		      )
		))
	then
		echo -e "Bahelite error: grep v2.9 or higher required." >&2
		exit 4
	fi
else
	echo 'Bahelite error: cannot determine grep version.' >&2
	exit 4
fi

#  ex: getopt from util-linux 2.32
getopt_version="$(getopt --version | sed -n '1p')"
if [[ "$getopt_version" =~ ^getopt.*util-linux.*\ ([0-9]+)(\.([0-9]+)|)(\.([0-9]+)|)$ ]]; then
	if	((    ${BASH_REMATCH[1]} <= 1
		   || (      ${BASH_REMATCH[1]:-0} == 2
		         &&  ${BASH_REMATCH[3]:-0} <  20
		      )
		))
	then
		echo -e "Bahelite error: util-linux v2.20 or higher required." >&2
		exit 4
	fi
else
	echo 'Bahelite error: cannot determine util-linux version.' >&2
	exit 4
fi

#  ex: yes (GNU coreutils) 8.29
yes_version="$(yes --version | sed -n '1p')"
if [[ "$yes_version" =~ ^yes.*coreutils.*\ ([0-9]+)(\.([0-9]+)|)(\.([0-9]+)|)$ ]]; then
	if	((  ${BASH_REMATCH[1]} < 8  ))
	then
		echo -e "Bahelite error: coreutils v8.0 or higher required." >&2
		exit 4
	fi
else
	echo 'Bahelite error: cannot determine coreutils version.' >&2
	exit 4
fi

unset  sed_version  grep_version  getopt_version  yes_version



                        #  Initial settings  #

BAHELITE_VERSION="2.19"
#  $0 == -bash if the script is sourced.
[ -f "$0" ] && {
	MYNAME=${0##*/}
	MYNAME_NOEXT=${MYNAME%.*}
	#  Sourced scripts cannot operate on the main script’s $0,
	#  as it is changed for them to “bash”.
	MYNAME_AS_IN_DOLLARZERO="$0"
	MYPATH=$(realpath --logical "$0")
	MYDIR=${MYPATH%/*}
	#  Used for desktop notifications in bahelite_messages_to_desktop.sh
	#  and in the title for dialog windows in bahelite_dialog.sh
	[ -v MY_DISPLAY_NAME ] || {
		#  Not forcing lowercase, as there may be intended
		#  caps, like in abbreviations.
		MY_DISPLAY_NAME="${MYNAME_NOEXT^}"
	}
	BAHELITE_DIR=${BASH_SOURCE[0]%/*}  # The directory of this file.
	ORIG_BASHPID=$BASHPID
	ORIG_PPID=$PPID
}

CMDLINE="$0 $@"
ARGS=("$@")
if [ -v TERM_COLS  -a  -v TERM_LINES ]; then
	declare -x TERM_COLS
	declare -x TERM_LINES
elif [ -v COLUMNS  -a  -v LINES ]; then
	declare -nx TERM_COLS=COLUMNS
	declare -nx TERM_LINES=LINES
else
	declare -x TERM_COLS=80
	declare -x TERM_LINES=25
fi



 # The directory for temporary files
#  It’s used by Bahelite and the main script. bahelite_on_exit will remove
#    this directory, unless you set BAHELITE_DONT_CLEAR_TMPDIR or an error
#    would be caught.
#  If using /tmp is for some reason undesirable, for example, if the main
#    script creates very large files, you may want to create one under user’s
#    $HOME or somewhere else. For that, define TMPDIR=$HOME/.cache/ before
#    sourcing bahelite.sh, and TMPDIR will be set to something like
#    $HOME/.cache/my-prog.XXXXXXXXX/.
#  You can also pass TMPDIR through the environment. This is useful, when you
#    run one script from within another, and they both use Bahelite. By passing
#    TMPDIR to the inside script, you can tell it to use the same TMPDIR as
#    the main script does. With this you simplify the debugging and minimise
#    file clutter.
#
[ -v TMPDIR ] && {
	[ -d "${TMPDIR:-}" ] || {
		echo "Bahelite warning: no such directory: “$TMPDIR”, will use /tmp." >&2
		unset TMPDIR
	}
}
TMPDIR=$(mktemp --tmpdir=${TMPDIR:-/tmp/}  -d ${MYNAME%*.sh}.XXXXXXXXXX  )
#  bahelite_on_exit trap shouldn’t remove TMPDIR, if the exit occurs
#  within a subshell
(( BASH_SUBSHELL > 0 )) && BAHELITE_DONT_CLEAR_TMPDIR=t

declare -rx  MYNAME  MYNAME_NOEXT  MYNAME_AS_IN_DOLLARZERO  MYPATH  MYDIR  \
             MY_DISPLAY_NAME  BAHELITE_VERSION  BAHELITE_DIR  CMDLINE  ARGS  \
             TMPDIR  BAHELITE_LOCAL_TMPDIR  ORIG_BASHPID  ORIG_PPID


 # By default Bahelite turns off xtrace for its internal functions.
#  set BAHELITE_SHOW_UP_IN_XTRACE after sourcing bahelite.sh
#  to view full xtrace output.
#
# BAHELITE_SHOW_UP_IN_XTRACE=t


 # Lists of utilities, the lack of which must trigger an error.
#  For internal dependencies of bahelite.sh and bahelite_*.sh.
#  Long name to make it distinctive from the REQUIRED_UTILS, which is
#    the facility for the mother script.
#  Historically, this array was separated from REQUIRED_UTILS to avoid acci-
#    dental redefinition in the mother script instead of extension. It would
#    be good to set this array readonly at the end of the bahelite.sh execu-
#    tion, but it’s not possible, because modules must remain optional – 
#    the mother script may want to include additional modules after receiving
#    certain options, e.g. make checking for updates optional and include
#    bahelite_github.sh only when the option is set.
#  NO NEED TO ADD sed, grep and any of the coreutils or util-linux binaries!
#
declare -ax BAHELITE_INTERNALLY_REQUIRED_UTILS=()
#
#
 # Holds a short info on which package a missing binary may be found in.
#
declare -Ax BAHELITE_INTERNALLY_REQUIRED_UTILS_HINTS=()
#
#
 # User list for required utils
#  Ex. REQUIRED_LIST=( mimetype ffmpeg )
#  This list is initially empty to separate internally required utils from
#    the dependencies of the main script itself. If that would be a single
#    list, users could accidently wipe it with = instead of addition to it
#    with +=.
#  NO NEED TO ADD sed, grep and any of the coreutils or util-linux binaries!
#
declare -ax REQUIRED_UTILS=()
#
#
 # Holds descriptions for missing utils: which packages they can be found in,
#  which versions were used for development etc. A hint is printed when
#  a corresponding utility in REQUIRED_UTILS is not found.
#  Syntax: REQUIRED_UTILS_HINTS=( [prog1]='Prog1 can be found in Package1.' )
#  (Hints are not required, this array may be left empty.)
#
declare -Ax REQUIRED_UTILS_HINTS=()
#
#
 # In the future, add an array that would hold function names, that should
#  run sophisticated checks over the binaries, e.g. query their version,
#  or that grep is GNU grep and not BSD grep.
#
#declare -A REQUIRED_UTILS_CHECKFUNCS=()



                             #  Modules  #

bahelite_load_module() {
	local module_name="$1"
	local module_file="$BAHELITE_DIR/bahelite_$module_name.sh"
	[ -r "$module_file" ]  || {
		echo "Bahelite error: cannot find module “$module_name”." >&2
		return 4
	}
	#  As we are currently in a function scope, the “source” command
	#  will make all declare calls local. To define global variables
	#  “declare -g” must be used in all modules!
	source "$module_file"  || {
		echo "Bahelite error: cannot load module “$module_name”." >&2
		return 4
	}
	return 0
}
export -f bahelite_load_module


bahelite_verify_error_code() {
	local error_code=$1
	if	[[ "$error_code" =~ ^[0-9]{1,3}$ ]]  \
		&&  ((
		            (       $error_code >= 7
		                &&  $error_code <= 125
		            )

		        ||  (       $error_code >= 166
		                &&  $error_code <= 254
		            )
		    ))
	then
		return 0
	else
		return 1
	fi
}
export -f bahelite_verify_error_code


#  Required modules
bahelite_load_module 'util_overrides' || exit $?
bahelite_load_module 'messages' || exit $?
if [ -v BAHELITE_CHERRYPICK_MODULES ]; then
	for module_name in "${BAHELITE_CHERRYPICK_MODULES[@]}"; do
		bahelite_load_module "$module_name" || exit $?
	done
else
	bahelite_noglob_off
	for bahelite_module in "$BAHELITE_DIR"/bahelite_*.sh; do
		module_name=${bahelite_module##*/}
		module_name=${module_name#bahelite_}
		module_name=${module_name%.sh}
		bahelite_load_module "$module_name" || exit $?
	done
	bahelite_noglob_on
fi
unset  module_name  bahelite_module


 # Dependency checking
#  Call this function after extending REQUIRED_UTILS in the main script.
#  See also “Checking basic dependencies” above.
#
check_required_utils() {
	local  util  missing_utils req_utils=()
	req_utils=$(printf "%s\n" ${BAHELITE_INTERNALLY_REQUIRED_UTILS[@]} \
	                          ${REQUIRED_UTILS[@]} \
	                | sort -u  )
	for util in ${req_utils[@]}; do
		which "$util" &>/dev/null || {
			missing_utils="${missing_utils:+$missing_utils, }“$util”"
			if [ "${REQUIRED_UTILS_HINTS[$util]:-}" ]; then
				warn "$util was not found on this system!
				      ${REQUIRED_UTILS_HINTS[$util]}"
			elif [ "${BAHELITE_INTERNALLY_REQUIRED_UTILS_HINTS[$util]:-}" ]; then
				warn "$util was not found on this system!
				      ${BAHELITE_INTERNALLY_REQUIRED_UTILS_HINTS[$util]}"
			else
				warn "$util was not found on this system!"
			fi
		}
	done
	[ "${missing_utils:-}" ] && ierr 'no util' "$missing_utils"
	return 0
}
export -f check_required_utils

[ -v ERROR_CODES ] && [ ${#ERROR_CODES[*]} -ne 0 ] && {
	for key in ${!ERROR_CODES[*]}; do
		bahelite_verify_error_code "${ERROR_CODES[key]}" || {
			echo "Bahelite error: Invalid exit code in ERROR_CODES[$key]:" >&2
			echo "should be a number in range 7…125 or 166…254 inclusively." >&2
			invalid_code=t
		}
	done
	[ -v invalid_code ] && exit 4
}
unset  key  invalid_code


 # Before the main script starts, gather variables. In case of an error
#  this list would be compared to the other, created before exiting,
#  and the diff will be placed in "$LOGDIR/variables"
#
declare -r BAHELITE_VARLIST_AFTER_STARTUP="$(compgen -A variable)"

return 0