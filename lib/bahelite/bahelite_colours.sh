# Should be sourced.

#  bahelite_colours.sh
#  Defines character sequences, that control font colour and style
#  in terminal. They can be used with “echo -e”.
#  © deterenkelt 2018–2019

#  Require bahelite.sh to be sourced first.
[ -v BAHELITE_VERSION ] || {
	echo "Bahelite error on loading module ${BASH_SOURCE##*/}:"  >&2
	echo "load the core module (bahelite.sh) first."  >&2
	return 4
}

#  Avoid sourcing twice
[ -v BAHELITE_MODULE_COLOURS_VER ] && return 0
#  Declaring presence of this module for other modules.
declare -grx BAHELITE_MODULE_COLOURS_VER='1.2'



 # Controlling sequences
#
#  Colours for messages
declare -grx __k='\e[30m'  __bla='\e[30m'  __black='\e[30m'
declare -grx               __blk='\e[30m'
declare -grx __r='\e[31m'  __red='\e[31m'
declare -grx __g='\e[32m'  __gre='\e[32m'  __green='\e[32m'
declare -grx               __grn='\e[32m'
declare -grx __y='\e[33m'  __yel='\e[33m'  __yellow='\e[33m'
declare -grx               __ylw='\e[33m'
declare -grx __b='\e[34m'  __blu='\e[34m'  __blue='\e[34m'
declare -grx __m='\e[35m'  __mag='\e[35m'  __magenta='\e[35m'
declare -grx               __mgn='\e[35m'
declare -grx               __mgt='\e[35m'
declare -grx __c='\e[36m'  __cya='\e[36m'  __cyan='\e[36m'
declare -grx               __cyn='\e[36m'
declare -grx __w='\e[37m'  __whi='\e[37m'  __white='\e[37m'
declare -grx               __wht='\e[37m'
#
#  Style control sequences
#  Blink is usually disabled in terminals
#  Bright/bold style depends on the way terminal does it.
declare -grx __s='\e[0m'  __sto='\e[0m'  __stop='\e[0m'
declare -grx              __stp='\e[0m'
declare -grx __o='\e[1m'  __bri='\e[1m'  __bright='\e[1m'
declare -grx              __brt='\e[1m'
declare -grx              __bol='\e[1m'  __bold='\e[1m'
declare -grx              __bld='\e[1m'
declare -grx __d='\e[2m'  __dim='\e[2m'
declare -grx __l='\e[3m'  __bli='\e[3m'  __blink='\e[3m'
declare -grx              __bln='\e[3m'
declare -grx __u='\e[4m'  __und='\e[4m'  __underline='\e[4m'
declare -grx __i='\e[7m'  __inv='\e[7m'  __invert_bg_fg='\e[7m'
declare -grx __h='\e[8m'  __hid='\e[8m'  __hidden='\e[8m'
#
#  Sequences that reset style and colour
declare -grx __bri_rst='\e[21m'  __bright_reset='\e[21m'  # reset bold/bright,
declare -grx __brt_rst='\e[21m'
declare -grx __bol_rst='\e[21m'  __bold_reset='\e[21m'
declare -grx __bld_rst='\e[21m'
declare -grx __fg_rst='\e[39m'  __fg_reset='\e[39m'  # reset fg to its default
#
#
#  Extra
declare -grx __clearline='\r\e[K'


 # Strip colours from the string
#  Useful for when the message should go somewhere where terminal control
#  sequences wouldn’t be recognised.
#
strip_colors()  { strip_colours "$@"; }
strip_colours() {
	bahelite_xtrace_off  &&  trap bahelite_xtrace_on RETURN
	local c str="$1"  c_val
	for c in   __k  __r  __g  __y  __b  __m  __c  __w  \
	          __s  __o  __d  __l  __u  __i  __h  \
	         __bri_rst  __fg_rst
	do
	    declare -n c_val=$c
	    str=${str//${c_val//\\/\\\\}/}
	done
	echo -n "$str"

	# Doesn’t work as good.
	#sed -r 's/[[:cntrl:]]\[[0-9]{1,3}[mKG]//g' <<<"$1"
	return 0
}
export -f strip_colours



return 0