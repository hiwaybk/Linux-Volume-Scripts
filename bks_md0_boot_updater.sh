#!/bin/sh

DEBUG=0

DISKINFO=/boot/DiskInfo

DISKS=`cat /proc/partitions | awk '{print $4}' | sort | grep sd.$`
test "${DEBUG}" -gt 0 && echo Disks: ${DISKS}

watch_rebuild() {
    DEVICE="/dev/${1}"
    if [ -b "${DEVICE}" ]; then
        RECOVERING=1
    else
        RECOVERING=0
    fi
    while [ "${RECOVERING}" -gt 0 ]; do
        clear
        RECOVERING=`sudo mdadm --detail "${DEVICE}" | grep 'State :' | grep recovering | wc -l`
        date
        echo ""
        echo ""
        cat /proc/mdstat
        sleep 2
    done

}

#### #### #### ####
#### Recover MD0
#### #### #### ####

for DISK in ${DISKS}; do
	BOOT=`sudo parted /dev/${DISK} unit gb print | egrep '(boot|md0)' | awk '{print $1}'`
	test "${BOOT}" -gt 0 && BOOT="${DISK}${BOOT}"
	MD0_ALL_PARTS="${MD0_ALL_PARTS} ${BOOT}"
done
test "${DEBUG}" -gt 0 && echo MD0_ALL_PARTS: ${MD0_ALL_PARTS}

MD0_CURRENT=`sudo mdadm --detail /dev/md0 | grep /dev/sd | cut -d/ -f3 | sort`
test "${DEBUG}" -gt 0 && echo MD0_CURRENT: ${MD0_CURRENT}

MD0_PARTS=`echo ${MD0_ALL_PARTS} | cut -d' ' -f-2`
test "${DEBUG}" -gt 0 && echo MD0_PARTS: ${MD0_PARTS}

MD0_SPARES=`echo ${MD0_ALL_PARTS} | cut -d' ' -f3-`
test "${DEBUG}" -gt 0 && echo MD0_SPARES: ${MD0_SPARES}

#MIRRORS=`sudo mdadm --detail /dev/md0 | grep /dev/sd.2 | wc -l`
MIRRORS=`echo ${MD0_PARTS} ${MD0_SPARES} | tr ' ' '\n' | wc -l`
test "${DEBUG}" -gt 0 && echo MIRRORS: ${MIRRORS}

for x in ${MD0_PARTS} ${MD0_SPARES}; do
	sudo mdadm --manage /dev/md0 --add /dev/${x}
done

sudo mdadm --grow /dev/md0 --raid-devices="${MIRRORS}"

watch_rebuild "md0"

for x in ${MD0_SPARES}; do
	sudo mdadm --manage /dev/md0 --fail /dev/${x}
done

for x in ${MD0_SPARES}; do
	sudo mdadm --manage /dev/md0 --remove /dev/${x}
done

sudo mdadm --grow /dev/md0 --raid-devices=2

sudo dpkg-reconfigure grub-pc

sudo update-grub

#for DISK in ${DISKS}; do
#	if [ `echo ${MD0_ALL_PARTS} | grep ${DISK} | wc -l` -gt 0 ]; then
#		sudo grub-install /dev/${DISK}
#	fi
#done

for x in ${MD0_SPARES}; do
	sudo mdadm --manage /dev/md0 --add /dev/${x}
done

sudo mdadm --grow /dev/md0 --raid-devices="${MIRRORS}"

watch_rebuild "md0"

#### #### #### ####
#### Recover MD10
#### #### #### ####

for DISK in ${DISKS}; do
    INFODISKS=`sudo parted /dev/${DISK} unit gb print | egrep -i '(DiskInfo|md10)' | awk '{print $1}'`
    test "${INFODISKS}" && test "${INFODISKS}" -gt 0 && INFODISKS="${DISK}${INFODISKS}"
    MD10_ALL_PARTS="${MD10_ALL_PARTS} ${INFODISKS}"
done
test "${DEBUG}" -gt 0 && echo MD10_ALL_PARTS: ${MD10_ALL_PARTS}

MIRRORS=`echo ${MD10_ALL_PARTS} | tr ' ' '\n' | wc -l`
test "${DEBUG}" -gt 0 && echo MIRRORS: ${MIRRORS}

for x in ${MD10_ALL_PARTS}; do
	sudo mdadm --manage /dev/md10 --add /dev/${x}
done

sudo mdadm --grow /dev/md10 --raid-devices="${MIRRORS}"

watch_rebuild "m1d0"

#### #### #### ####
#### Rename partitions
#### #### #### ####

bks_show_disks.pl | sort | sh -x

echo ""; echo ""; echo ""
date
echo ""; echo ""; echo ""
cat /proc/mdstat

#### #### #### ####
#### Save Disk Info
#### #### #### ####

bks_show_disks.pl -b | sudo tee "${DISKINFO}/Summary.txt" > /dev/null

for DISK in $DISKS; do
	sudo smartctl -x /dev/$DISK | sudo tee "${DISKINFO}/SmartCTL-${DISK}.txt" > /dev/null
	sudo parted /dev/$DISK unit s print | sudo tee "${DISKINFO}/Parted-${DISK}.txt" > /dev/null
done
