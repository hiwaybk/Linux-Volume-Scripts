#!/bin/sh

# Package creation script created based off info from:
#   http://ubuntuforums.org/showthread.php?t=910717

####
#### Make sure we're running in the correct directory.
####

cd `dirname "${0}"`/..

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
#### Remove any old packages...
####

if [ `ls -1 ${PACKAGE}*.deb 2>/dev/null | wc -l` -gt 0 ]; then
    for x in ${PACKAGE}*.deb; do
        rm -rf $x
        if [ -d .git ]; then
            git rm $x
        fi
    done
fi

####
#### Create the file structure for the package
####

mkdir -p "${NAME}/DEBIAN"

####
#### Create the package control file
####

CONTROL="${NAME}/DEBIAN/control"
echo "Package: ${PACKAGE}" > "${CONTROL}"
echo "Version: ${VERSION}" >> "${CONTROL}"
echo "Section: base" >> "${CONTROL}"
echo "Priority: optional" >> "${CONTROL}"
echo "Architecture: all" >> "${CONTROL}"
echo "Depends: ${Depends}" >> "${CONTROL}"
echo "Maintainer: ${MaintainerName} <${MaintainerEmail}>" >> "${CONTROL}"
echo "Description: ${Description}" >> "${CONTROL}"
cat README.md | grep '^> ' | sed -e 's/^> / /' >> "${CONTROL}"

####
#### Let's put some stuff into the file structure...
####

mkdir -p "${NAME}/usr/local/scripts"
cp bks_show_disks.pl "${NAME}/usr/local/scripts"
cp bks_md0_boot_updater.sh "${NAME}/usr/local/scripts"
cp bks_nuke_disk.sh "${NAME}/usr/local/scripts"

####
#### Let's put some stuff into the control directory...
####

for SCRIPT in postinst prerm; do
    test -r "package_scripts/${SCRIPT}" \
    && cp "package_scripts/${SCRIPT}" "${NAME}/DEBIAN"
done

####
#### Make the package (finally)!
####

dpkg-deb --build "${NAME}" && rm -rf "${NAME}"

####
#### If this is a Git repository, add the package & show the current status
####
if [ -d .git ]; then
    git add "${NAME}"*
    git status
fi
