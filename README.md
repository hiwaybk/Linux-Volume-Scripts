# Linux_Volume_Scripts
<!--- Project=Linux-Volume-Scripts --->
<!--- MajorVersion=0 --->
<!--- MinorVersion=11 --->
<!--- PackageVersion=0 --->
<!--- MaintainerName="Brian Kelly" --->
<!--- MaintainerEmail=Github@Brian.Kelly.name --->
<!--- Depends="perl (>= 5.14.2), mdadm (>= 3.2.5), lvm2 (>= 2.02.66), smartmontools (>= 6.2+svn3841-1.2ubu)" --->
<!--- Description="Scripts to help manage LVM on software RAID (level 1)" --->

Scripts for managing LVM volumes on software RAID

> This is my collection of scripts for managing my disk volumes (using
> LVM2 on RAID1 software mirrors).

> bks_md0_boot_updater.sh
> bks_nuke_disk.sh
> bks_show_disks.pl


# ChangeLog
* Version 0.11
  1. Updated bks_md0_boot_updater.sh to call bks_show_disks.pl properly
* Version 0.10
  1. Added bks_nuke_disk.sh script
* Version 0.9
  1. Fixed test for "DiskInfo" partitions
* Version 0.8
  1. Added -e option to bks_show_disks.pl to output an summery of all disks
* Version 0.7
  1. Renamed show_disks.pl to bks_show_disks.pl
  2. Added bks_md0_boot_updater.sh
* Version 0.6
  1. Updated debugging
  2. Updated packaging to only require smartmontools version 6.4+svn4214-1
* Version 0.5
  1. Corrected use of Perl pointers / hashes
  2. Included SmartMonTools dependency 
* Version 0.4
  1. Added option (-n) to output GNU Parted commands to name disk partitions based on MD device / LVM volume(s)
* Version 0.3
  1. Added preliminary functionality for a check option (-c) to verify all components in an array exist
* Version 0.2
  1. Added backup option (-b) to print backup summaries

--[Brian Kelly](https://github.com/hiwaybk)
