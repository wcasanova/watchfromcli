# Makefile for building packages for watch.sh
SHELL := /usr/bin/env bash
LANG := C
export LANG
PN := watchsh
DATE := $(shell date +%s)
PV := $(shell LC_TIME=C date --date='@${DATE}' +%Y%m%d)
P := ${PN}-${PV}
HUMAN_DATE := $(shell LC_TIME=C date --date='@${DATE}' +'%-d %B %Y')
TARBALL := ${P}.tar.gz
TARBALL_ORIG := ${PN}_${PV}.orig.tar.gz
MAINTAINER := deterenkelt
MAINTAINER_EMAIL := deterenkelt.github@gmail.com
DEBFULLNAME := ${MAINTAINER}
DEBEMAIL := ${MAINTAINER_EMAIL}
export DEBFULLNAME
export DEBEMAIL
DEB_CHANGELOG_DATE := $(shell LC_TIME=C date --date='@${DATE}' -R)
RPM_CHANGELOG_DATE := $(shell LC_TIME=C date --date='@${DATE}' +'%a %b %_d %Y')
#REV := -1
PF := ${PN}-${PV}${REV}

clean:
	-@rm -rf ${P} ${PN}*.tar.gz *~ &>/dev/null

prepare: clean
	sed -i 's/^VERSION=.*$$/VERSION="${PV}"/' sources/watch.sh
	sed -i '1 s/^.TH watch\.sh 1 "[^"]*"/.TH watch.sh 1 "${HUMAN_DATE}"/' sources/watch.sh.1
	opts=( $$( sed -rn "/^\s*case \"\\\$$option\" in/,/esac/ { /^\t\t\S+\)$$/ {s/\s//g; s/\)//; s/'//g; s/\|/\n/g; /^(--|\*)$$/d; p} }" ./sources/watch.sh ) ) \
		&& _opts="$${opts[@]}" && sed -ri "s/compgen -W \".*\"/compgen -W \"$$_opts\"/" sources/bash_completion.sh
	read -p 'Have you written RELEASE_NOTES? [N/y] > '; [[ "$$REPLY" =~ ^[yY]$$ ]] \
		|| { echo -e "Please write.\nAborted by user." >&2; exit 3; }
#   This is to not touch the file if it wasn’t modified, so Emacs wouldn’t ask
#     about rereading it from the disk.
	sed -r '1 s/^.*(\[.*)$$/===] ${HUMAN_DATE} \1/' sources/RELEASE_NOTES >/tmp/RELEASE_NOTES
	diff sources/RELEASE_NOTES /tmp/RELEASE_NOTES  \
		|| mv /tmp/RELEASE_NOTES sources/RELEASE_NOTES
	$$EDITOR sources/RELEASE_NOTES
	mkdir ${P}
	cp sources/* ${P}
	@read -d $$"\n" maj min <<< $$(tar --version | sed -nr '1s/.*\s([0-9]+)\.([0-9]+).*$$/\1\n\2/p'); \
		[[ "$$maj" =~ ^[0-9]+$$ && "$$min" =~ ^[0-9]+$$ ]] \
			&& ( [ $$maj -eq 1 -a $$min -ge 27 ] || [ $$maj -gt 1 ] ) \
			|| { echo -e "This version of tar doesn’t support --exclude-backups.\nThat is not okay." >&2; exit 4; }
	fakeroot tar czf ${TARBALL} --exclude-backups ${P}
	@rm -rf ${P}

# ebuild will work only when it will be able to download the archive,
#   and it won’t appear until the commit (with debs and rpms) is uploaded.
ebuild:
	cp gentoo/${PN}.ebuild ../deter/media-video/watchsh/${P}.ebuild
	cd ../deter/media-video/watchsh \
		&& ebuild ${P}.ebuild digest \
		&& git add . \
		&& [ "`git status -s`" ] \
		&& git commit -m "Added ${P}.ebuild." \
		&& git push

# Work on copy for debian is necessary because otherwise it will try
#   to alter ownership on NFS and fail.
deb:
	cp ${TARBALL} ${TARBALL_ORIG}
	tar xf ${TARBALL_ORIG}
	cd ${P} \
		&& cp -R ../debian ./ \
		&& echo 9 > debian/compat \
		&& echo -e "${PN} (${PV}${REV}) unstable; urgency=low\n\n  * NUISANCE\n\n -- ${DEBFULLNAME} <${DEBEMAIL}>  ${DEB_CHANGELOG_DATE}\n" > debian/changelog \
		&& dpkg-buildpackage -A -k9F0D2DC6 -pgpg2
#		&& $$EDITOR debian/changelog \ #↑↑
	cd ../
	rm -rf ${P} ${TARBALL_ORIG}

rpm:
	-@rm -rf ${PN}*.rpm ~/rpmbuild &>/dev/null
	rpmdev-setuptree
	sed -ri "s/^(Name:).*$$/\1 ${PN}/" fedora/${PN}.spec
	sed -ri "s/^(Version:).*$$/\1 ${PV}/" fedora/${PN}.spec
#	sed -ri "s/^%changelog$$/&\n* ${RPM_CHANGELOG_DATE} ${MAINTAINER} <${MAINTAINER_EMAIL}> ${PV}${REVISION}\n- \n/" fedora/${PN}.spec
#	$$EDITOR fedora/${PN}.spec
	cp fedora/${PN}.spec ~/rpmbuild/SPECS/
	cp ${TARBALL} ~/rpmbuild/SOURCES/
	cd ~/rpmbuild \
		&& rpmbuild -ba SPECS/${PN}.spec

# deb_and_rpm: prepare
# # vm-* aliases can be found in the bashrc/home.sh of the “dotfiles” repo nearby.
# # Don’t forget that ssh requires -t or "RequestTTY force". Also -X for pinentry.
# #   Also timeout, which I set to three minutes.
# 	ps axu |& grep -v grep | grep -q "qemu.*debean" || { vm-d.sh; sleep 60; }
# 	ps axu |& grep -v grep | grep -q "qemu.*feedawra" || { vm-f.sh; sleep 60; }
# 	ssh vmdebean "grep -q 'watch.sh' /proc/mounts && { \
# 		export LC_ALL=C; \
# 		export EDITOR='nano -w'; \
# 		[ -d /tmp/decrypted ] || scp -r home:/tmp/decrypted /tmp/; \
# 		ln -sf /tmp/decrypted/.gnupg ~/.gnupg; \
# 		rm -rf ~/watch.sh.local; \
# 		cd ~/watch.sh/; \
# 		rm -rf *.deb *.orig.tar.gz *.changes &>/dev/null; \
# 		cp -Ra ~/watch.sh ~/watch.sh.local; \
# 		cd ~/watch.sh.local; \
# 		make deb && cp -a ./*{deb,changes} ../watch.sh/; \
# 		: ; \
# 	}||{ echo 'ERROR: ~/watch.sh is not mounted.' >&2; exit 3; }" \
# 	&& ssh vmfeedawra "grep -q 'watch.sh' /proc/mounts && { \
# 		export LC_ALL=C; \
# 		export EDITOR='nano -w'; \
# 		cd ~/watch.sh/; \
# 		make rpm && { \
# 			cp -a /home/d/rpmbuild/RPMS/noarch/* ~/watch.sh/; \
# 			cp -a /home/d/rpmbuild/SRPMS/* ~/watch.sh/; \
# 		} ; \
# 		: ; \
# 	}||{ echo 'ERROR: ~/watch.sh is not mounted.' >&2; exit 3; }" \
# 	&& for m in vmdebean vmfeedawra; do ssh root@$$m "init 0"; done

upload:
	git status
	@read -n1 -p 'Confirm changes and continue? [Y/n] > '; [[ ! "$$REPLY" =~ ^[Nn]$$ ]] || exit 3
	git add --all .
	git commit -m "Version bump to ${PV}."
# This assumes we’re on the ‘dev’ branch
	git checkout master
	git merge dev
# Just in case I may need to --amend
	read -n1 -p 'Tag and push? [Y/n] > '; [[ ! "$$REPLY" =~ ^[Nn]$$ ]] || exit 3
	git tag v${PV}${REV}
	git push
	git push --tags
	git checkout dev
	git merge master

# +deb_and_rpm
all: prepare upload ebuild

# all = prepare → deb_and_rpm
help:
	echo 'all = prepare → upload → ebuild'
