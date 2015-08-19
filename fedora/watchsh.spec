Name: watchsh
Version: 20150819
Release: 1%{?dist}
Summary: A meta package for a wrapper for mpv/MPlayer to run videos easy via CLI.

License: GPLv3
URL: http://github.com/deterenkelt/watchsh
Group: Applications/Multimedia
BuildArch: noarch
Requires: watchsh-base, parallel, figlet, pngcrush, libjpeg-turbo-utils, netpbm-progs, inotify-tools, procps-ng, psmisc, xdg-utils

%description
%{summary}


# Core subpackage.

%package base
Summary: A shell wrapper for mpv/MPlayer to run videos easy via CLI.
Group: Applications/Multimedia
Source0: %{name}-%{version}.tar.gz
Requires: mpv, bash >= 4.2, sed >= 4.2.1, grep >= 2.9, file >= 5.17, util-linux >= 2.20, wget

%description base
watch.sh is written to simplify access to video files and play videos easily.
It allows playing single files, DVD/BD folders and folders with episodes
of TV series. For the former and the latter ones it can also find external
subtitles and tracks, applying heuristic algorithms to include files with
names that may strongly differ from the names of corresponding video files,
and that frees you from the job of picking appropriate subtitles manually.

This script can also help you deal with organization taken screenshots,
placing them right into the folder named after video and compressing them
after you stop watching it.

For the folder with episodes watch.sh can track your watching progress,
allowing to run episodes one after another without creating a playlist,
but remembering the episode number you quit watching today, so you could
easily resume watching the folder later.

...and many other accompanying things that make life even lazier.

%prep
%setup -q

%build

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p %{buildroot}/usr/{bin,share/{doc/%{name},man/man1,bash-completion}}
%make_install

%files base
%defattr(-,root,root,-)
%{_bindir}/watch.sh
%{_mandir}/man1/watch.sh.1.gz
%{_docdir}/%{name}/RELEASE_NOTES
%{_datadir}/bash-completion/watchsh

%clean
rm -rf $RPM_BUILD_ROOT

%changelog
* Tue Jun 24 2014 deterenkelt <deterenkelt.github@gmail.com> 20140624
- First decent release.
