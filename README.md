# Linux_Volume_Scripts
<!--- Project=Linux-Volume-Scripts --->
<!--- MajorVersion=0 --->
<!--- MinorVersion=6 --->
<!--- PackageVersion=2 --->
<!--- MaintainerName="Brian Kelly" --->
<!--- MaintainerEmail=Github@Brian.Kelly.name --->
<!--- Depends="perl (>= 5.14.2), mdadm (>= 3.2.5), lvm2 (>= 2.02.66), smartmontools (>= 6.5+svn4324)" --->
<!--- Description="Scripts to help manage LVM on software RAID (level 1)" --->

Scripts for managing LVM volumes on software RAID

> This is my collection of scripts for managing my disk volumes (using
> LVM2 on RAID1 software mirrors).

# ChangeLog
* Version 0.6
  1. Updated debugging
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
