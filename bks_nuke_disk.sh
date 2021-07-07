#!/bin/bash

#---  VARS  --------------------------------------------------------------------
#   DESCRIPTION:  Set necessary variables
#-------------------------------------------------------------------------------
VARS_STORAGE=/tmp/zero_disk_vars.txt
SOURCE=/dev/zero
TEMP=/tmp/`basename $0`.$$.tmp
WEBHOOK_FILENAME="/etc/default/slack_webhook" # File with single line: SLACK_WEBHOOK='http://xxx'

if [ -r "${WEBHOOK_FILENAME}" ]; then
    source "${WEBHOOK_FILENAME}"
else
    SLACK_WEBHOOK=''
fi


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  die
#   DESCRIPTION:  Echo errors to stderr.
#-------------------------------------------------------------------------------
die() {
    ERROR="${1}"
    printf "${ERROR}\n" 1>&2;
    exit 1;
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  info
#   DESCRIPTION:  Echo information to stdout.
#-------------------------------------------------------------------------------
info() {
    #printf "${GC} *  INFO${EC}: %s\n" "$@";
    printf "${GC} *${EC} %s\n" "$@";
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  warn
#   DESCRIPTION:  Echo warning informations to stdout.
#-------------------------------------------------------------------------------
warn() {
    printf "${YC} *  WARN${EC}: %s\n" "$@";
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __strip_duplicates
#   DESCRIPTION:  Strip duplicate strings
#-------------------------------------------------------------------------------
__strip_duplicates() {
    echo $@ | tr -s '[:space:]' '\n' | awk '!x[$0]++'
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __function_defined
#   DESCRIPTION:  Checks if a function is defined within this scripts scope
#    PARAMETERS:  function name
#       RETURNS:  0 or 1 as in defined or not defined
#-------------------------------------------------------------------------------
__function_defined() {
    FUNC_NAME=$1
    if [ "$(command -v $FUNC_NAME)x" != "x" ]; then
        #info "Found function $FUNC_NAME"
        return 0
    fi
    debug "$FUNC_NAME not found...."
    return 1
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __prompt_user
#   DESCRIPTION:  Prompt the user for input
#    PARAMETERS:  Prompt to display to user
#       RETURNS:  User input
#-------------------------------------------------------------------------------
__prompt_user() {
    VAR="${1}"
    PROMPT="${2}"
    DEFAULT="${3}"
    SECURE="${4}"

    echo -n "${PROMPT}"
    if [ "${DEFAULT}" ]; then
        if [ "${SECURE}" ]; then
            echo -n " ["
            echo -n "${DEFAULT}" | sed -r 's/./*/g'
            echo -n "]"
        else
            echo -n " [${DEFAULT}]"
        fi
    fi
    echo -n ": "
    test "${SECURE}" && stty -echo
    read ANSWER
    if [ "${SECURE}" ]; then
        stty echo
        echo "${ANSWER}" | sed -r 's/./*/g'
    fi


    if [ "${ANSWER}" ]; then
        eval "$VAR='${ANSWER}'"
    else
        eval "$VAR='${DEFAULT}'"
    fi

}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __saveVars
#   DESCRIPTION:  Save variables entered by the user
#-------------------------------------------------------------------------------
__saveVars() {
    set | grep ^SETUP_ > "${VARS_STORAGE}"
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __readVars
#   DESCRIPTION:  Read variables entered by the user
#-------------------------------------------------------------------------------
__readVars() {
    test -r "${VARS_STORAGE}" && source "${VARS_STORAGE}"
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __listDrives
#   DESCRIPTION:  List disks from /proc/partitions
#-------------------------------------------------------------------------------
__listDrives() {
    cat /proc/partitions | awk '/sd.$/ {print $4}' | sort
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __listDrivesDetails
#   DESCRIPTION:  List disks from /proc/partitions with details
#-------------------------------------------------------------------------------
__listDrivesDetails() {
	LSHWDISKS="/tmp/lshw_disks-$$.tmp"
	sudo lshw -class disk 2>/dev/null >"${LSHWDISKS}"
    for DEV in `cat /proc/partitions | awk '/sd.$/ {print $4}' | sort`; do
        echo ""
        echo "Disk: $DEV"
        cat "${LSHWDISKS}" \
        | awk "/${DEV}/" RS='*' ORS="\n" \
        | grep : \
        | egrep '^       (product|vendor|serial|size):'
    done | more
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __drive_info_lshw
#   DESCRIPTION:  Output lshw info for a disk
#-------------------------------------------------------------------------------
__drive_info_lshw() {
    DEVICE="${1}"
    sudo lshw -class disk 2>/dev/null | awk "/${DEVICE}/" RS='*' ORS="\n" | grep :
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __lshw_drive_parted
#   DESCRIPTION:  Output parted info for a disk
#-------------------------------------------------------------------------------
__lshw_drive_parted() {
    DEVICE="${1}"
    sudo parted $DEVICE unit gb print < /dev/null
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __lshw_drive_size
#   DESCRIPTION:  Output size for a disk
#-------------------------------------------------------------------------------
__lshw_drive_size() {
    DISK="${1}"
    SIZE=`cat /proc/partitions | grep "${DISK}$" | awk '{print $3}'`
    SIZE=`expr "${SIZE}" / 1024`
    SIZE=`expr "${SIZE}" / 1024`
    SIZE=`expr "${SIZE}" + 1`
    SIZE="${SIZE}g"
    if [ "${SIZE}" = "g" ]; then
        die "Can't find size for '${DISK}'"
    fi
    echo "${SIZE}"
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __lshw_drive_size_kb
#   DESCRIPTION:  Output size for a disk
#-------------------------------------------------------------------------------
__lshw_drive_size_kb() {
    DISK="${1}"
    SIZE=`cat /proc/partitions | grep "${DISK}$" | awk '{print $3}'`
    if [ "${SIZE}" = "" ]; then
        die "Can't find size for '${DISK}'"
    fi
    echo "${SIZE}"
}


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  __slack_hostalert
#   DESCRIPTION:  Post a message to Slack on the Mozart HostAlert channel
#-------------------------------------------------------------------------------

__slack_hostalert() {
    FILE="${1}"
    if [ "${SLACK_WEBHOOK}" ]; then
        if [ -r "${FILE}" ]; then
            DATA=`
                echo '{"text":"'
                echo 'Disk Information:\n\n'
                cat "${FILE}" | sed -E ':a;N;$!ba;s/\r{0,1}\n/\n/g'
                echo '"}'
            `
            curl -X POST -H 'Content-type: application/json' --data "${DATA}" "${SLACK_WEBHOOK}"
        fi
    fi
}


#---  MAIN CODE ----------------------------------------------------------------
#          NAME:  Main code
#   DESCRIPTION:  Select a drive
#-------------------------------------------------------------------------------

__readVars

# Pompt the user for a drive
echo ""
echo "Available drives:"
__listDrivesDetails

echo ""
__prompt_user DRIVE "Please enter the drive to wipe" ""

DRIVE=`__listDrives | grep -i "^${DRIVE}$"`
TARGET="/dev/${DRIVE}"

# Check that the user selected a drive
if [ \! "${DRIVE}" ]; then
    die "No drive selected."
fi

# Check the drive's device file
if [ \! -b "${TARGET}" ]; then
    die "Device ${TARGET} is not a block device."
fi

#---  MAIN CODE ----------------------------------------------------------------
#          NAME:  Main code
#   DESCRIPTION:  Prompt users
#-------------------------------------------------------------------------------

clear

__drive_info_lshw "${DRIVE}" > "${TEMP}"
echo "" >> "${TEMP}"
__lshw_drive_parted "${TARGET}" >> "${TEMP}"

cat "${TEMP}"

echo ""
echo "Checking for typical disk useage..."

cat /proc/mdstat | grep -i "${DRIVE}"
sudo pvs | grep -i "${DRIVE}"
mount | grep -i "${DRIVE}"

echo "Check complete."

if [ "${SLACK_WEBHOOK}" ]; then
    echo ""
    __prompt_user SLACK "Send data to Slack" "Yes"
    SLACK=`echo "${SLACK}n" | cut -c-1 | tr 'Y' 'y'`
fi

if [ "${SLACK}" = 'y' ]; then
    __slack_hostalert "${TEMP}"
    echo ""
fi

echo ""
__prompt_user CONTINUE "Continue with this drive" "No"
CONTINUE=`echo "${CONTINUE}n" | cut -c-1 | tr 'Y' 'y'`

if [ "${CONTINUE}" = 'y' ]; then
    SIZE=`__lshw_drive_size "${DRIVE}"`
else
    echo ""
    exit 0
fi

echo ""
__prompt_user WIPELVM "Wipe LVM data from partitons" "No"
WIPELVM=`echo "${WIPELVM}n" | cut -c-1 | tr 'Y' 'y'`

echo ""
__prompt_user WIPEMDADM "Wipe MDADM data from partitons" "No"
WIPEMDADM=`echo "${WIPEMDADM}n" | cut -c-1 | tr 'Y' 'y'`

echo ""
__prompt_user ZEROALL "Write zeros to the entire drive" "No"
ZEROALL=`echo "${ZEROALL}n" | cut -c-1 | tr 'Y' 'y'`

if [ "${ZEROALL}" != 'y' ]; then
    echo ""
    __prompt_user ZEROPART "Write zeros to the start of each partition" "No"
    ZEROPART=`echo "${ZEROPART}n" | cut -c-1 | tr 'Y' 'y'`
fi

echo ""
__prompt_user REPARTITION "Create new partition table" "No"
REPARTITION=`echo "${REPARTITION}n" | cut -c-1 | tr 'Y' 'y'`


#---  MAIN CODE ----------------------------------------------------------------
#          NAME:  Main code
#   DESCRIPTION:  Wipe current partitions and info
#-------------------------------------------------------------------------------

SIZE=`__lshw_drive_size "${DRIVE}"`

if [ "${WIPELVM}" = 'y' ]; then
    echo ""
    echo "Wiping LVM data...."
    for PART in `cat /proc/partitions | awk '{print $4}' | grep "^${DRIVE}."`; do
        sudo pvcreate "/dev/${PART}"
        sudo pvremove "/dev/${PART}"
    done
    echo "Done."
fi

if [ "${WIPEMDADM}" = 'y' ]; then
    echo ""
    echo "Wiping MD data...."
    for PART in `cat /proc/partitions | awk '{print $4}' | grep "^${DRIVE}."`; do
        sudo mdadm --zero-superblock "/dev/${PART}"
    done
    echo "Done."
fi

if [ "${ZEROPART}" = 'y' ]; then
    echo ""
    echo "Wiping partitions...."
    for PART in `cat /proc/partitions | awk '{print $4}' | grep "^${DRIVE}."`; do
        SKIP_KB=`__lshw_drive_size_kb "${DRIVE}"`
        SKIP_KB=`expr "${SKIP_KB}" - 10`
        sudo dd if="${SOURCE}" bs=4096 count=11 skip="${SKIP_KB}" of="${TARGET}"
    done
    echo "Done."
fi

if [ "${ZEROALL}" = 'y' ]; then
    sudo dd if="${SOURCE}" | pv -s "${SIZE}" | sudo dd of="${TARGET}" bs=8M
    echo "Done."
fi

if [ "${REPARTITION}" = 'y' ]; then

    if [ "${ZEROPART}" = 'y' ]; then
        echo ""
        echo "Wiping start of disk...."
        sudo dd if="${SOURCE}" bs=512 count=2048 of="${TARGET}"
    fi

        sudo parted --script --align optimal -- "${TARGET}" \
                mklabel gpt \
                mkpart GRUB 1MiB 2Mib \
                set 1 bios_grub on \
                mkpart 'DiskInfo' 2MiB 100MiB \
                mkpart 'Blank_for_/boot' 100MiB 900MiB \
                set 3 raid on \
                set 3 boot on \
                mkpart 'Blank_for_LVM' 900MiB 100% \
                set 4 raid on

    sleep 5

    if [ "${WIPELVM}" = 'y' ]; then
        echo ""
        echo "Wiping LVM data from new partitions...."
        for PART in `cat /proc/partitions | awk '{print $4}' | grep "^${DRIVE}."`; do
            sudo pvcreate "/dev/${PART}"
            sudo pvremove "/dev/${PART}"
        done
        echo "Done."
    fi

    if [ "${WIPEMDADM}" = 'y' ]; then
        echo ""
        echo "Wiping MD data from new partitions...."
        for PART in `cat /proc/partitions | awk '{print $4}' | grep "^${DRIVE}."`; do
            sudo mdadm --zero-superblock "/dev/${PART}"
        done
        echo "Done."
    fi

    echo ""
    echo "Zero'ing new partitions...."
    for PART in `cat /proc/partitions | awk '{print $4}' | grep "^${DRIVE}."`; do
        sudo dd if="${SOURCE}" bs=4096 count=256 of="/dev/${PART}"
    done

fi


#---  MAIN CODE ----------------------------------------------------------------
#          NAME:  Main code
#   DESCRIPTION:  Done
#-------------------------------------------------------------------------------

__drive_info_lshw "${DRIVE}" > "${TEMP}"
echo "" >> "${TEMP}"
__lshw_drive_parted "${TARGET}" >> "${TEMP}"

if [ "${SLACK}" = 'y' ]; then
    __slack_hostalert "${TEMP}"
    echo ""
fi

echo ""
echo ""
echo ""
echo "+-------+"
echo "| Done! |"
echo "+-------+"
echo ""
echo ""
echo ""

cat "${TEMP}"

