watch.sh
========

A [shell](http://www.gnu.org/software/bash/) wrapper for [mpv](http://mpv.io/)/[MPlayer](http://www.mplayerhq.hu/) to run videos easy via [CLI](http://en.wikipedia.org/wiki/Command-line_interface).

The main goal of this project was to access any video file in the depths of a certain folder by giving only a short keyword. And make as little movements as possible.

<p align="center">
<img src="https://raw.githubusercontent.com/wiki/deterenkelt/watchfromcli/img/main_repo_readme/1.png"/>
</p>

And this is it – the simplest command, that takes only one argument, a _keyword_.

<p align="center">
<img src="https://raw.githubusercontent.com/wiki/deterenkelt/watchfromcli/img/main_repo_readme/2.png"/>
</p>

First thing it does is looking for files and folders inside a _basepath_ (the only thing that must be provided, aside from the _keyword_). That’s how it looks after setting up an alias (described in the wiki).

<p align="center">
<img src="https://raw.githubusercontent.com/wiki/deterenkelt/watchfromcli/img/main_repo_readme/3.png"/>
</p>

It works not only with single video files, but also with folders having disk structure. For folders with episodes watch.sh can start a cycle, in which it will play one file after another through a short pause, in the time of which it can be stopped. The watching cycle can also be stopped by quitting the player, or even killing it – watch.sh recognizes when it quits normally or is closed in the middle of an episode. That helps to resume the cycle on the right episode.

<p align="center">
<img src="https://raw.githubusercontent.com/wiki/deterenkelt/watchfromcli/img/main_repo_readme/4.png"/>
</p>

watch.sh maintains a journal, where it stores session data. It provides information needed to resume the interrupted watching cycle.

<p align="center">
<img src="https://raw.githubusercontent.com/wiki/deterenkelt/watchfromcli/img/main_repo_readme/5.png"/>
</p>

Having a _keyword_ and being able to distinguish episode number sequences in file names enables this script to load exactly those subtitles and tracks, which are needed. This is a big step forward from the video players’ beloved paradigm ‘load by exact name or the whole bunch’.

If you’re already interested – learn more in the [wiki](https://github.com/deterenkelt/watchsh/wiki)!

N-no?.. Then how about…

<p align="center">
<img src="https://raw.githubusercontent.com/wiki/deterenkelt/watchfromcli/img/main_repo_readme/should be gif.png"/>
</p>

* storing screenshots to separate folders;
* compressing them with `pngcrush` to reduce the size of PNGs;
* or converting them to JPEGs with a given quality value;
* and running such jobs in `parallel` to utilize all available CPU cores;
* printing the last shown episode number in big ASCII-art (thanks to `figlet`);
* three levels of heuristics to guess the right sequence of episodes;
* ignoring disk structure and play BDMV or DVD like folders with episodes;

and, proabably, twice as much other options that tweak little things.

<p align="center">
<img src="https://raw.githubusercontent.com/wiki/deterenkelt/watchfromcli/img/main_repo_readme/example screen.png"><br/>
<i>Running the script in ‘novice’ mode.</i>
<p>

<p align="center">
<img src="https://raw.githubusercontent.com/wiki/deterenkelt/watchfromcli/img/main_repo_readme/23.jpg"><br/>
I hope you’ll like it.<br/><br/>
Visit the <a href="https://github.com/deterenkelt/watchsh/wiki">wiki</a>.
</p>
 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 

 



<p align="center">
<img src="https://raw.githubusercontent.com/wiki/deterenkelt/watchfromcli/img/main_repo_readme/y u no go to wiki.png"><br/>
Y U NO GO TO THE <a href="https://github.com/deterenkelt/watchsh/wiki">WIKI</a>?
</p>
