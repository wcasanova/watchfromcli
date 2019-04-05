
# Respect the environment.
[ -v d ] || d='\e[39m'    # default fg
[ -v r ] || r='\e[31m'    # red
[ -v g ] || g='\e[32m'    # green
[ -v y ] || y='\e[33m'    # yellow
[ -v s ] || s='\e[0m'    # stop
[ -v b ] || b='\e[1m'    # bright/bold
[ -v rb ] || rb='\e[21m'    # reset bold/bright
[ -v u ] || u='\e[4m'    # underlined


dil=0 # debug indentation level
di='' # debug indentation


#    [$1] – number of times to increment dil.
dil_inc() {
	local z count=$1
	count=${count:-1}
	for ((z=0; z<count; z++)); do let dil++; done
	di=; for ((z=0; z<dil; z++)); do di+=$'\t'; done
}

# TAKES:
#    [$1] – number of times to decrement dil.
dil_dec() {
	local z count=$1
	count=${count:-1}
	for ((z=0; z<count; z++)); do let dil--; done
	di=; for ((z=0; z<dil; z++)); do di+=$'\t'; done
}

# TAKES:
#    $@ – a set of arguments which can be variable names for declare to print
#         to the logfile or empty/newline strings to put there an empty line.
#         '' is simply shorter to type than $'\n'.
dput_declare() {
	local var
	for var in "$@"; do
		[ "$var" = '' -o "$var" = $'\n' ] \
			&& echo >>$dbg_file \
			|| { echo -n "$di" >>$dbg_file && declare -p $var >>$dbg_file; }
	done
}


