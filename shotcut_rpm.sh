#!/bin/sh -e

NAME="$(basename $0)"
CWD="$(pwd)"
TMP_PATH="/tmp/.shotcut.$$"
SHOTCUT_VERSION=""

if [ "$(which rpmbuild)" == "" ]; then
	printf "Unable to find rpmbuild, please use yum or zypper to install the package\n" >&2
	exit 1
fi
if [ "$(which curl)" == "" ]; then
	printf "Unable to find curl, please use yum or zypper to install the package\n" >&2
	exit 1
fi

usage() {
	cat << EOF
$NAME: Shotcut RPM package generator tool

Usage: $NAME [OPTIONS]

        -h          Show help

Example:
       $NAME

EOF
}

shotcut_set_version() {
	local app_version=
	local tmp_file="/tmp/.version.$$"

	printf "Retrieving latest Shotcut version from Github ... "
	curl -sk -X GET 'https://api.github.com/repos/mltframework/shotcut/releases/latest' -o $tmp_file >/dev/null 2>&1
	app_version=$(sed -n 's/.*\"\(tag_name\)\": \"\(.*\)\"\,/\2/p' $tmp_file 2>/dev/null | sed 's/v//g')
	rm -f $tmp_file >/dev/null 2>&1
	printf "$app_version\n"

	SHOTCUT_VERSION=$app_version
}

shotcut_set_release() {
	local new_version="$1"
	local old_version=""
	local release=""

	if [ -r "${CWD}/.version" ]; then
		old_version="$(cat ${CWD}/.version)"
	else
		echo "$new_version" > ${CWD}/.version
	fi

	if [ -r "${CWD}/.release" ]; then
		release=$(cat ${CWD}/.release)
	else
		release=0
	fi

	if [ "$new_version" == "$old_version" ]; then
		release=$(($release + 1))
	else
		release=0
	fi

	echo "$new_version" > ${CWD}/.version
	echo "$release" > ${CWD}/.release

	RPM_REVISION=$release
}

while getopts "h" opt; do
	case "$opt" in
		h)
			usage
			exit 0
		;;
	esac
done

shotcut_set_version
shotcut_set_release "${SHOTCUT_VERSION}"

if [ "${SHOTCUT_VERSION}" == "" ]; then
	printf "Unable to determine version, something went wrong... \n" >&2
	exit 1
fi

SHOTCUT_PATH="/opt/shotcut"
SHOTCUT_ALT_VERSION="$(echo ${SHOTCUT_VERSION}.02 | tr -d '.')"
PACKAGE_NAME="shotcut-linux-x86_64-${SHOTCUT_ALT_VERSION}.tar.bz2"
PACKAGE_URL="https://github.com/mltframework/shotcut/releases/download/v${SHOTCUT_VERSION}/${PACKAGE_NAME}"
RPM_ARCH="x86_64"
RPM_PACKAGE_NAME="shotcut"
RPM_PACKAGE="${RPM_PACKAGE_NAME}-${SHOTCUT_VERSION}-${RPM_REVISION}.${RPM_ARCH}.rpm"
RPM_BUILD_PATH="${TMP_PATH}/rpmbuild"

mkdir -p ${TMP_PATH}
mkdir -p ${RPM_BUILD_PATH}/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} || exit 1

printf "Downloading ${PACKAGE_NAME}: "
rc=$(curl -skL -X GET "${PACKAGE_URL}" -o "${RPM_BUILD_PATH}/SOURCES/${PACKAGE_NAME}" -w '%{http_code}')
if [ "$rc" -eq 200 ]; then
	printf "done\n"
else
	printf "failed\n"
	exit 1
fi

printf "Generating ${RPM_PACKAGE_NAME}.spec ...\n"
cat << EOF > ${RPM_BUILD_PATH}/SPECS/${RPM_PACKAGE_NAME}.spec
%define           _topdir         ${RPM_BUILD_PATH}
Name:             ${RPM_PACKAGE_NAME}
Version:          ${SHOTCUT_VERSION}
Release:          ${RPM_REVISION}
Summary:          Shotcut is a free, open source, cross-platform video editor.
License:          GPL-3.0
Vendor:           Shotcut
URL:              https://www.shotcut.org
BugURL:           https://github.com/mltframework/shotcut/issues
ExcludeArch:      noarch
Source:           ${PACKAGE_NAME}
Requires(post):   coreutils shared-mime-info desktop-file-utils
Requires(postun): shared-mime-info desktop-file-utils
AutoReqProv:      no
%if 0%{?suse_version}
Requires:         libXss1
%else
Requires:         libXScrnSaver
%endif
Packager:         Robert Milasan <robert@linux-source.org>

%description
Shotcut is a free, open source, cross-platform video editor for Windows, Mac and Linux.
Major features include support for a wide range of formats; no import required meaning native timeline editing; 
Blackmagic Design support for input and preview monitoring; and resolution support to 4k.

%prep
%setup -n Shotcut

%build

%install
mkdir -p \$RPM_BUILD_ROOT/${SHOTCUT_PATH}
cp -afR Shotcut.app/* \$RPM_BUILD_ROOT/${SHOTCUT_PATH}
mkdir -p \$RPM_BUILD_ROOT/usr/bin
ln -sf ${SHOTCUT_PATH}/shotcut \$RPM_BUILD_ROOT/usr/bin/shotcut

mkdir -p \$RPM_BUILD_ROOT/usr/share/applications
install -m 644 Shotcut.app/share/applications/org.shotcut.Shotcut.desktop \$RPM_BUILD_ROOT/usr/share/applications/org.shotcut.Shotcut.desktop
mkdir -p \$RPM_BUILD_ROOT/usr/share/icons/hicolor/64x64/apps
install -m 644 Shotcut.app/share/icons/hicolor/64x64/apps/org.shotcut.Shotcut.png \$RPM_BUILD_ROOT/usr/share/icons/hicolor/64x64/apps/org.shotcut.Shotcut.png
mkdir -p \$RPM_BUILD_ROOT/usr/share/metainfo
install -m 644 Shotcut.app/share/metainfo/org.shotcut.Shotcut.appdata.xml \$RPM_BUILD_ROOT/usr/share/metainfo/org.shotcut.Shotcut.appdata.xml
mkdir -p \$RPM_BUILD_ROOT/usr/share/mime/packages
install -m 644 Shotcut.app/share/mime/packages/org.shotcut.Shotcut.xml \$RPM_BUILD_ROOT/usr/share/mime/packages/org.shotcut.Shotcut.xml

%post
if test -x /usr/bin/update-mime-database; then
  /usr/bin/update-mime-database "/usr/share/mime" || true
fi
if test -x /usr/bin/update-desktop-database; then
  /usr/bin/update-desktop-database --quiet "/usr/share/applications" || true
fi
if test -x /usr/bin/gtk-update-icon-cache; then
  /usr/bin/gtk-update-icon-cache --quiet --force "/usr/share/icons/hicolor" || true
fi
exit 0

%postun
if [ \$1 -eq 0 ]; then
  if test -x /usr/bin/gtk-update-icon-cache; then
    /usr/bin/gtk-update-icon-cache --quiet --force "/usr/share/icons/hicolor" || true
  fi
fi
if [ \$1 -eq 0 ]; then
  if test -x /usr/bin/update-desktop-database; then
    /usr/bin/update-desktop-database --quiet "/usr/share/applications" || true
  fi
fi
if [ \$1 -eq 0 ]; then
  if test -x /usr/bin/update-mime-database; then
    /usr/bin/update-mime-database "/usr/share/mime" || true
  fi
fi
exit 0

%clean
rm -rfv \$RPM_BUILD_ROOT

%files
%defattr(0644, root, root, 0755)
%dir $SHOTCUT_PATH
$SHOTCUT_PATH/*
%attr(755,root,root) $SHOTCUT_PATH/shotcut
%attr(755,root,root) $SHOTCUT_PATH/ffmpeg
%attr(755,root,root) $SHOTCUT_PATH/ffplay
%attr(755,root,root) $SHOTCUT_PATH/ffprobe
%attr(755,root,root) $SHOTCUT_PATH/melt
%attr(755,root,root) $SHOTCUT_PATH/qmelt
%attr(755,root,root) $SHOTCUT_PATH/source-me
%attr(755,root,root) $SHOTCUT_PATH/bin/*
/usr/bin/shotcut
/usr/share/applications/org.shotcut.Shotcut.desktop
/usr/share/icons/hicolor/64x64/apps/org.shotcut.Shotcut.png
/usr/share/metainfo/org.shotcut.Shotcut.appdata.xml
/usr/share/mime/packages/org.shotcut.Shotcut.xml
EOF

printf "Generating RPM package: ${RPM_PACKAGE}\n"
( cd ${RPM_BUILD_PATH}/SPECS
  rpmbuild -bb --quiet --target=${RPM_ARCH} ${RPM_PACKAGE_NAME}.spec 2>/dev/null
)

if [ -r "${RPM_BUILD_PATH}/RPMS/${RPM_ARCH}/${RPM_PACKAGE}" ]; then
	cp -af ${RPM_BUILD_PATH}/RPMS/${RPM_ARCH}/${RPM_PACKAGE} ${CWD}/${RPM_PACKAGE}
  	printf "Package generated: ${CWD}/${RPM_PACKAGE}\n"
else
	printf "Failed to generate RPM package\n" >&2
	exit 1
fi

rm -fr ${TMP_PATH}
