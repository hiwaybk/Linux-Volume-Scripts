#!/bin/sh

# Package creation script created based off info from:
#   http://ubuntuforums.org/showthread.php?t=910717

####
#### Make sure we're running in the correct directory.
####

cd `dirname "${0}"`

####
#### Pull some settings from README.md
####

SETTINGS=`cat README.md`
SETTINGS=`echo "${SETTINGS}" | grep '^<!---'`
SETTINGS=`echo "${SETTINGS}" | sed -e 's/^<!--- *//' -e 's/ *--->$//'`
eval "${SETTINGS}"

####
#### Set the package name
####

PACKAGE="${Project}"
VERSION="${MajorVersion}.${MinorVersion}-${PackageVersion}"
NAME="${PACKAGE}_${VERSION}"

####
#### Create the file structure for the package
####

mkdir -p "${NAME}/usr/local/bin"
mkdir -p "${NAME}/DEBIAN"

####
#### Create the package control file
####

CONTROL="${NAME}/DEBIAN/control"
echo "Package: ${PACKAGE}" > "${CONTROL}"
echo "Version: ${VERSION}" >> "${CONTROL}"
echo "Section: base" >> "${CONTROL}"
echo "Priority: optional" >> "${CONTROL}"
echo "Architecture: i386" >> "${CONTROL}"
echo "Depends: ${Depends}" >> "${CONTROL}"
echo "Maintainer: ${MaintainerName} <${MaintainerEmail}>" >> "${CONTROL}"
echo "Description: ${Description}" >> "${CONTROL}"
cat README.md | grep '^> ' | sed -e 's/^> / /' >> "${CONTROL}"

####
#### 
####

dpkg-deb --build "${NAME}" && rm -rf "${NAME}"
