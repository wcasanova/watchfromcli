# Makefile for building packages for watch.sh
SHELL := /usr/bin/env bash
PN := watchsh
DATE := $(shell date +%s)
PV := $(shell LC_TIME=C date --date='@${DATE}' +%Y%m%d)
P := ${PN}-${PV}
HUMAN_DATE := $(shell LC_TIME=C date --date='@${DATE}' +'%B %-d, %Y')
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
# REV := -1
PF := ${PN}-${PV}${REV}

clean:
	-@rm -rf ${PN}*.tar.gz *~ &>/dev/null

prepare:
	sed -i 's/^VERSION=.*$$/VERSION="${PV}"/' sources/watch.sh
	sed -i '1 s/^.TH watch\.sh 1 "[^"]*"/.TH watch.sh 1 "${HUMAN_DATE}"/' sources/watch.sh.1
	read -p 'Have you written RELEASE_NOTES? [N/y] > '; [[ "$$REPLY" =~ ^[yY]$$ ]] \
		|| { echo -e "Please write.\nAborted by user." >&2; exit 3; }
	sed -ri '1 s/^.*(\[.*)$$/===] ${HUMAN_DATE} \1/' sources/RELEASE_NOTES
	$$EDITOR sources/RELEASE_NOTES
	mkdir ${P}
	cp sources/* ${P}
	@read -d $$"\n" maj min <<< $$(tar --version | sed -nr '1s/.*\s([0-9]+)\.([0-9]+).*$$/\1\n\2/p'); \
		[[ "$$maj" =~ ^[0-9]+$$ && "$$min" =~ ^[0-9]+$$ ]] \
			&& ( [ $$maj -eq 1 -a $$min -ge 27 ] || [ $$maj -gt 1 ] ) \
			|| { echo -e "This version of tar doesn’t support --exclude-backups yes.\nThat is not okay." >&2; exit 4; }
	fakeroot tar czf ${TARBALL} --exclude-backups ${P}
	@rm -rf ${P}


ebuild: prepare
	cp gentoo/${PN}.ebuild ${P}.ebuild

deb: prepare
	-@rm -rf ${PN}*.deb ${PN}*.changes &>/dev/null
	cp ${TARBALL} ${TARBALL_ORIG}
	tar xf ${TARBALL_ORIG}
	cd ${P} \
		&& cp -R ../debian ./ \
		&& echo 9 > debian/compat \
		&& echo -e "${PN} (${PV}${REV}) unstable; urgency=low\n\n  * WHY\n\n -- ${DEBFULLNAME} <${DEBEMAIL}>  ${DEB_CHANGELOG_DATE}\n" > debian/changelog \
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
	$$EDITOR fedora/${PN}.spec
	cp fedora/${PN}.spec ~/rpmbuild/SPECS/
	cp ${TARBALL} ~/rpmbuild/SOURCES/
	cd ~/rpmbuild \
		&& rpmbuild -ba SPECS/${PN}.spec

all: ebuild deb rpm
