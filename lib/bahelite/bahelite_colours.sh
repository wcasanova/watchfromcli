# Should be sourced.

#  bahelite_colours.sh
#  Defines character sequences, that control font colour and style
#  in terminal. They can be used with “echo -e”.
#  © deterenkelt 2018–2019

#  Require bahelite.sh to be sourced first.
[ -v BAHELITE_VERSION ] || {
	echo 'Must be sourced from bahelite.sh.' >&2
	return 5
}

#  Avoid sourcing twice
[ -v BAHELITE_MODULE_COLOURS_VER ] && return 0
#  Declaring presence of this module for other modules.
BAHELITE_MODULE_COLOURS_VER='1.1'

 # Controlling sequences
#
#  Colours for messages
export __k='\e[30m'  __bla='\e[30m'  __black='\e[30m'    # former __bk
export               __blk='\e[30m'                      # ——»——
export __r='\e[31m'  __red='\e[31m'                      # former __r
export __g='\e[32m'  __gre='\e[32m'  __green='\e[32m'    # former __g
export               __grn='\e[32m'                      # ——»——
export __y='\e[33m'  __yel='\e[33m'  __yellow='\e[33m'   # former __y
export               __ylw='\e[33m'                      # ——»——
export __b='\e[34m'  __blu='\e[34m'  __blue='\e[34m'     # former __bl
export __m='\e[35m'  __mag='\e[35m'  __magenta='\e[35m'  # former __ma
export               __mgn='\e[35m'                      # ——»——
export               __mgt='\e[35m'                      # ——»——
export __c='\e[36m'  __cya='\e[36m'  __cyan='\e[36m'     # former __cy
export               __cyn='\e[36m'                      # ——»——
export __w='\e[37m'  __whi='\e[37m'  __white='\e[37m'    # former __wh
export               __wht='\e[37m'                      # ——»——
#
#  Style control sequences
#  Blink is usually disabled in terminals
#  Bright/bold style depends on the way terminal does it.
export __s='\e[0m'  __sto='\e[0m'  __stop='\e[0m'           # former __s
export              __stp='\e[0m'                           # ——»——
export __o='\e[1m'  __bri='\e[1m'  __bright='\e[1m'         # former __b
export              __brt='\e[1m'                           # ——»——
export              __bol='\e[1m'  __bold='\e[1m'           # ——»——
export              __bld='\e[1m'                           # ——»——
export __d='\e[2m'  __dim='\e[2m'                           # former __dim
export __l='\e[3m'  __bli='\e[3m'  __blink='\e[3m'          # former __blink
export              __bln='\e[3m'                           # ——»——
export __u='\e[4m'  __und='\e[4m'  __underline='\e[4m'      # former __u
export __i='\e[7m'  __inv='\e[7m'  __invert_bg_fg='\e[7m'   # former __inv
export __h='\e[8m'  __hid='\e[8m'  __hidden='\e[8m'         # former __hid
#
#  Sequences that reset style and colour
export __bri_rst='\e[21m'  __bright_reset='\e[21m'  # reset bold/bright,
export __brt_rst='\e[21m'                           # former __rb
export __bol_rst='\e[21m'  __bold_reset='\e[21m'
export __bld_rst='\e[21m'
export __fg_rst='\e[39m'  __fg_reset='\e[39m'  # reset fg to its default
#                                              # colour, former __d
#
#  Extra
export __clearline='\r\e[K'


 # Strip colours from the string
#  Useful for when the message should go somewhere where terminal control
#  sequences wouldn’t be recognised.
#
strip_colours() {
	xtrace_off && trap xtrace_on RETURN
	local c str="$1"  c_val
	for c in   __k  __r  __g  __y  __b  __m  __c  __w  \
	          __s  __o  __d  __l  __u  __i  __h  \
	         __bri_rst  __fg_rst
	do
	    declare -n c_val=$c
	    str=${str//${c_val//\\/\\\\}/}
	done
	echo "$str"

	# Doesn’t work as good.
	#sed -r 's/[[:cntrl:]]\[[0-9]{1,3}[mKG]//g' <<<"$1"
	return 0
}


return 0