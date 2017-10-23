_watchsh() {
	local cur prev words cword split
	_init_completion -s -n : || return

	[[ ${cur} == -* ]] && {
		COMPREPLY=( $(compgen -W "-a --match-all --allow-autosub -c --run-in-cycle -C --no-color --check-for-update --compat -d --basedir --basepath --group-indicator --heuristics-level -h --help -H -I --ignore-disks --interval --ionice-opts -J --no-journal --journal-max-size --jpeg-compression -L --limit-watching-to -l --loop --last-ep --last-ep-command --last-ep-format --last-ep-show-after --last-item-mark -M --mplayer-command -m --mplayer-opts --my-increment --my-decrement -n --match-number -N --dvd-bd-nav --not-episodes --remember-sub-and-audio-delay -R --resume-from-previous -r --resume -s --subfolders -S --screenshot-dir --screenshot-dir-skel --taskset-opts -u -v --version" -- ${cur}) )
		return 0
	}
	case $prev in
		--bashrc)
			_filedir
			;;
		--compat)
			COMPREPLY=(mplayer mplayer2 mpv-03x)
			;;
		-d|--basedir|--basepath)
			_filedir -d
			;;
		-r|--resume|-R|--resume-from-previous)
			# Separate -r and -R.
			# -r is for quick remembering — 12 keys
			# -R is for deep search. Full journal + episodes
			COMPREPLY=(`sed -nr "s/^KEYWORD='($cur.*)'/\1/p" ~/.watch.sh/journal | head -n 12`)
			return
			;;
		-S|--screenshot-dir)
			_filedir -d
			;;
	esac
}

complete -o nosort -F _watchsh watch.sh
