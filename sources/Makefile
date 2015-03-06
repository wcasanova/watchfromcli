prefix := /usr
bindir := ${prefix}/bin
sharedir := ${prefix}/share
mandir := ${sharedir}/man
man1dir := ${mandir}/man1
docdir := ${sharedir}/doc/watchsh
bashcompdir= := ${sharedir}/bash-completion

build:
# nothing to build

install:
	install -m 0755 watch.sh ${DESTDIR}${bindir}
	install -m 0644 watch.sh.1 ${DESTDIR}${man1dir}
	install -m 0644 RELEASE_NOTES ${DESTDIR}${docdir}
	install -m 0644 bash_completion.sh ${DESTDIR}${bashcompdir}/watchsh
