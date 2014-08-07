# Makefile for building packages for watch.sh
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
	-@rm -rf ${PN}* *~ &>/dev/null

prepare: clean
	sed -i 's/^VERSION=.*$$/VERSION="${PV}"/' sources/watch.sh 
	sed -i '1 s/^.TH watch\.sh 1 "[^"]*"/.TH watch.sh 1 "${HUMAN_DATE}"/' sources/watch.sh.1
# W! You supposed to write a new header and notes before running make
	sed -ri '1 s/^.*(\[.*)$$/===] ${HUMAN_DATE} \1/' sources/RELEASE_NOTES
	$$EDITOR sources/RELEASE_NOTES
	mkdir ${P}
	cp sources/* ${P}
# W! --exclude backups appeared only in tar-1.27
	fakeroot tar czf ${TARBALL} --exclude-backups ${P}
	@rm -rf ${P}


ebuild: prepare
	cp gentoo/${PN}.ebuild ${P}.ebuild

deb: prepare
	cp ${TARBALL} ${TARBALL_ORIG}
	tar xf ${TARBALL_ORIG}
	cd ${P} \
		&& cp -R ../debian ./ \
		&& echo 9 > debian/compat \
		&& echo "${PN} (${PV}${REV}) unstable; urgency=low\n\n  *\n\n -- ${DEBFULLNAME} <${DEBEMAIL}>  ${DEB_CHANGELOG_DATE}\n" > debian/changelog \
		&& $$EDITOR debian/changelog \
		&& dpkg-buildpackage -A -k9F0D2DC6 -pgpg2
	cd ../
	rm -rf ${P} ${TARBALL_ORIG}

rpm: prepare
	-@rm -rf ~/rpmbuild
	rpmdev-setuptree
	sed -ri "s/^(Name:).*$$/\1 ${PN}/" fedora/${PN}.spec
	sed -ri "s/^(Version:).*$$/\1 ${PV}/" fedora/${PN}.spec
	sed -ri "s/^%changelog$$/&\n* ${RPM_CHANGELOG_DATE} ${MAINTAINER} <${MAINTAINER_EMAIL}> ${PV}${REVISION}\n- \n/" fedora/${PN}.spec
	$$EDITOR fedora/${PN}.spec
	cp fedora/${PN}.spec ~/rpmbuild/SPECS/
	cp ${TARBALL} ~/rpmbuild/SOURCES/
	cd ~/rpmbuild \
		&& rpmbuild -ba SPECS/${PN}.spec

all: ebuild deb rpm
