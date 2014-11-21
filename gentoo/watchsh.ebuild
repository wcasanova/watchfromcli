# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI="5"
inherit eutils

SLOT="0"
DESCRIPTION="A shell wrapper for mpv/MPlayer to watch videos easy via CLI."
HOMEPAGE="https://github.com/deterenkelt/watchsh"
SRC_URI="https://github.com/deterenkelt/watchsh/archive/v${PV}.tar.gz -> ${P}.tar.gz"
LICENSE="GPL-3"
MERGE_TYPE="binary"
KEYWORDS="~*"

IUSE="convtojpeg +figlet +parallel +pngcrush +remember-delays toilet"

RDEPEND="|| ( media-video/mpv media-video/mplayer2 media-video/mplayer )
         >=sys-apps/grep-2.9
         >=sys-apps/sed-4.2.1
         >=sys-apps/util-linux-2.20
         >=app-shells/bash-4.2
         net-misc/wget
         remember-delays? ( media-video/mpv
                            sys-fs/inotify-tools
                            sys-process/procps )
         convtojpeg? ( media-libs/netpbm
                       media-libs/libjpeg-turbo )
         figlet? ( app-misc/figlet )
         parallel? ( sys-process/parallel )
         pngcrush? ( media-gfx/pngcrush )
         toilet? ( app-misc/toilet )
         xdg-open? ( x11-misc/xdg-utils )"

src_prepare() {
	epatch_user
}

src_install() {
	mkdir -p ${D}/usr/{bin,share/{doc/${PN},man/man1}}
	cd sources
	emake DESTDIR="${D}" install || die "make install failed"
}
