#!/usr/bin/perl

$DEBUG = 0;

#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -x
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -b
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -d 1 -l kellybvol
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -d 10 -l md11
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -d 1 -l sdc

use Data::Dumper;
use Getopt::Std;

sub help($) {
	my $MSG = shift;
	print qq{\n};
	print $MSG . qq{\n\n};
	print $OPTIONS . qq{\n\n};
	exit 1;
}

sub checkArg($$$) {
	my $opt = shift;
	my $varRef = shift;
	my $hashRef = shift;
	if (exists $hashRef->{$opt}) {
		if (defined $hashRef->{$opt}) {
			$$varRef = $hashRef->{$opt};
		} else {
			help(qq{Option '$opt' requires an argument.});
		}
	}
}

sub convertBytes($) {
    my $size = shift();

    if ($size > 1099511627776) {	#   TiB: 1024 GiB
        return sprintf("%.2f TiB", $size / 1099511627776);
    } elsif ($size > 1073741824) {	#   GiB: 1024 MiB
        return sprintf("%.2f GiB", $size / 1073741824);
    } elsif ($size > 1048576) {		#   MiB: 1024 KiB
        return sprintf("%.2f MiB", $size / 1048576);
    } elsif ($size > 1024) {		#   KiB: 1024 B
        return sprintf("%.2f KiB", $size / 1024);
    } else {						#   bytes
        return "$size byte" . ($size == 1 ? "" : "s");
    }
}

sub getDiskDevices() {
    print qq{getDiskDevices: Starting...\n} if $DEBUG;
    my %devices;
    my @fields;
    open(PARTITIONS, "/proc/partitions") or die;
    while (my $chunk = <PARTITIONS>) {
        foreach my $line (split(/[\n\r]+/, $chunk)) {
            my %device;
            print Data::Dumper->Dump([$line], ['getDiskDevices: line from /proc/partitions']) if ($DEBUG > 8);
            $line =~ s/^\s*(.*?)\s*$/\1/;
            my @line = split(/\s+/, $line);
            print Data::Dumper->Dump([\@line], ['getDiskDevices: line from /proc/partitions']) if ($DEBUG > 7);
            if (@fields) {
                foreach my $field (@fields) {
                    $device{$field} = shift(@line);
                }
                print Data::Dumper->Dump([\%device], ['getDiskDevices: device']) if ($DEBUG > 6);
                if ($device{'name'} =~ /^(sd[a-z]+)(\d+)$/) {
                    $devices{$1}{'partitions'}{$1 . $2} = \%device;
                } else {
                    $devices{$device{'name'}} = \%device;
                }
            } else {
                @fields = @line;
                print Data::Dumper->Dump([\@fields], ['getDiskDevices: fields']) if ($DEBUG > 6);
            }
        }
    }
    print Data::Dumper->Dump([\%devices], ['getDiskDevices: devices']) if ($DEBUG > 5);
    return %devices;
}

sub getDiskSmartInfo(%) {
    print qq{getDiskSmartInfo: Starting...\n} if $DEBUG;
    my %devices = @_;
    print Data::Dumper->Dump([\%devices], ['getDiskSmartInfo: devices']) if ($DEBUG > 8);
    foreach my $device (sort keys %devices) {
        print qq{getDiskSmartInfo: checking $device\n} if ($DEBUG > 5);
        next unless $devices{$device}{'major'} == 8; # Linux SCSI disks (SATA)
        print qq{getDiskSmartInfo: found physical disk device: $device\n} if ($DEBUG > 5);
        my $cmd = qq{sudo smartctl --info /dev/} . $device;
        print qq{getDiskSmartInfo: running: $cmd\n} if ($DEBUG > 6);
        my %info;
        open(SMARTCTL, $cmd . " 2>&1 |") or die;
        while (my $chunk = <SMARTCTL>) {
            foreach my $line (split(/[\n\r]+/, $chunk)) {
                print "getDiskSmartInfo: smartctl: " . $line . "\n" if ($DEBUG > 7);
                next unless ($line =~ /Model Family|Device Model|Serial Number/);
                if ($line =~ /Model Family:\s+(.*)$/) {
                    $info{'type'} = $1;
                    print "getDiskSmartInfo: smartctl: type -> " . $1 . "\n" if ($DEBUG > 6);
                } elsif ($line =~ /Device Model:\s+(.*)$/) {
                    $info{'model'} = $1;
                    print "getDiskSmartInfo: smartctl: model -> " . $1 . "\n" if ($DEBUG > 6);
                } elsif ($line =~ /Serial Number:\s+(.*)$/) {
                    $info{'serial'} = $1;
                    print "getDiskSmartInfo: smartctl: serial -> " . $1 . "\n" if ($DEBUG > 6);
                }
            }
        }
        print Data::Dumper->Dump([\%info], ['getDiskSmartInfo: info']) if ($DEBUG > 5);
        $devices{$device}{'smart'} = \%info;
    }
    return %devices;
}

sub getDiskPartedInfo(%) {
    print qq{getDiskPartedInfo: Starting...\n} if $DEBUG;
    my %devices = @_;
    print Data::Dumper->Dump([\%devices], ['getDiskPartedInfo: devices']) if ($DEBUG > 8);
    foreach my $device (sort keys %devices) {
        print qq{getDiskPartedInfo: checking $device\n} if ($DEBUG > 5);
        next unless $devices{$device}{'major'} == 8; # Linux SCSI disks (SATA)
        print qq{getDiskPartedInfo: found physical disk device: $device\n} if ($DEBUG > 5);
        my $cmd = qq{sudo parted -m /dev/} . $device . qq{ unit s print};
        print qq{getDiskPartedInfo: running: $cmd\n} if ($DEBUG > 6);
        my %info;
        open(PARTED, $cmd . " 2>&1 |") or die;
        while (my $chunk = <PARTED>) {
            foreach my $line (split(/[\n\r]+/, $chunk)) {
                print "getDiskPartedInfo: PARTED: " . $line . "\n" if ($DEBUG > 6);
                next unless ($line =~ /:/);
                if ($line =~ m,/dev/$device:(.*)$,) {
                    my @info = split(/:/, $1);
                    $devices{$device}{'parted'}{'size'} = $info[0];
                    $devices{$device}{'parted'}{'type'} = $info[1];
                    $devices{$device}{'parted'}{'sectorSizeLogical'} = $info[2];
                    $devices{$device}{'parted'}{'sectorSizePhysical'} = $info[3];
                    $devices{$device}{'parted'}{'partitionTable'} = $info[4];
                    $devices{$device}{'parted'}{'model'} = $info[5];
                } elsif ($line =~ m,(\d+):(.*);$,) {
                    my $partition = $1;
                    my @info = split(/:/, $2);
                    $devices{$device}{'partitions'}{$device . $partition}{'parted'}{'start'} = $info[0];
                    $devices{$device}{'partitions'}{$device . $partition}{'parted'}{'end'} = $info[1];
                    $devices{$device}{'partitions'}{$device . $partition}{'parted'}{'size'} = $info[2];
                    $devices{$device}{'partitions'}{$device . $partition}{'parted'}{'fs'} = $info[3];
                    $devices{$device}{'partitions'}{$device . $partition}{'parted'}{'name'} = $info[4];
                    $devices{$device}{'partitions'}{$device . $partition}{'parted'}{'flags'} = $info[5];
                }
                my $sectors = $devices{$device}{'parted'}{'size'};
                my $sectorsize = $devices{$device}{'parted'}{'sectorSizeLogical'};
                $sectors =~ s/s$//;
                $devices{$device}{'parted'}{'Capacity'} = convertBytes($sectors * $sectorsize);
             }
         }
        print Data::Dumper->Dump([\%info], ['getDiskPartedInfo: info']) if ($DEBUG > 5);
    }
    return %devices;
}

sub getMdDeviceInfo(%) {
    print qq{getMdDeviceInfo: Starting...\n} if $DEBUG;
    my %devices = @_;
    print Data::Dumper->Dump([\%devices], ['getMdDeviceInfo: devices']) if ($DEBUG > 8);
    foreach my $device (sort keys %devices) {
        print qq{getMdDeviceInfo: checking $device\n} if ($DEBUG > 5);
        next unless $devices{$device}{'major'} == 8; # Linux SCSI (SATA) devices
        print qq{getMdDeviceInfo: found physical disk device: $device\n} if ($DEBUG > 5);
        next unless (defined $devices{$device}{'partitions'});
        foreach my $partition (sort keys %{$devices{$device}{'partitions'}}) {
            my $cmd = qq{sudo mdadm --examine /dev/} . $partition;
            print qq{getMdDeviceInfo: running: $cmd\n} if ($DEBUG > 6);
            my %info;
            open(MDADM, $cmd . " 2>&1 |") or die;
            while (my $chunk = <MDADM>) {
                foreach my $line (split(/[\n\r]+/, $chunk)) {
                    print "getMdDeviceInfo: mdadm: " . $line . "\n" if ($DEBUG > 7);
                    if ($line =~ /^ *(.*) : (.*)$/) {
                        $info{$1} = $2;
                    }
                }
            }
            print Data::Dumper->Dump([\%info], ['getMdDeviceInfo: info']) if ($DEBUG > 5);
            $devices{$device}{'partitions'}{$partition}{'mdadm'} = \%info;
        }
    }
    return %devices;
}

sub getMdArrayInfo(%) {
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -d 10 -x
    print qq{getMdArrayInfo: Starting...\n} if $DEBUG;
    my %devices = @_;
    print Data::Dumper->Dump([\%devices], ['getMdArrayInfo: devices']) if ($DEBUG > 8);
     foreach my $device (sort keys %devices) {
         print qq{getMdArrayInfo: checking $device\n} if ($DEBUG > 5);
         next unless $devices{$device}{'major'} == 9; # Linux MD devices
         print qq{getMdArrayInfo: found a MD device: $device\n} if ($DEBUG > 5);
         my $cmd = qq{sudo mdadm --detail /dev/} . $device;
         print qq{getMdArrayInfo: running: $cmd\n} if ($DEBUG > 6);
         my %info;
         open(MDADM, $cmd . " 2>&1 |") or die;
         while (my $chunk = <MDADM>) {
             foreach my $line (split(/[\n\r]+/, $chunk)) {
                print "getMdArrayInfo: mdadm: " . $line . "\n" if ($DEBUG > 9);
                next if ($line =~ /^\/dev\//);
                if ($line =~ /^ *(.*) : (.*)$/) {
                    $info{$1} = $2;
	                print "getMdArrayInfo: key: " . $1 . "; value: " . $1 . "\n" if ($DEBUG > 7);
                } else {
                    $line =~ s/^\s*(.*?)\s*$/$1/;
                    my @line = split(/\s+/, $line);
                    my $drive = shift @line;
	                print "getMdArrayInfo: drive: " . $drive . "; values: " . join("|", @line) . "\n" if ($DEBUG > 7);
                    if ($drive ne 'Number') {
                        $info{'drives'}{$drive}{'major'} = shift @line;
                        $info{'drives'}{$drive}{'minor'} = shift @line;
                        $info{'drives'}{$drive}{'raiddevice'} = shift @line;
                        my $disk = pop(@line);
                        $disk =~ s,^/dev/,,;
                        $info{'drives'}{$drive}{'disk'} = $disk;
                        $info{'drives'}{$drive}{'state'} = \@line;
                    }
                }
            }
        }
        print Data::Dumper->Dump([\%info], ['getMdArrayInfo: info']) if ($DEBUG > 5);
        $devices{$device}{'mdadm'} = \%info;
    }
    return %devices;
}

sub getLVMdisks() {
    print qq{getLVMdisks: Starting...\n} if $DEBUG;
    my %LVM2;
    my $cmd = qq{sudo lvs -o+devices --noheadings --nameprefixes --aligned --separator '|'};
    print qq{getLVMdisks: Running: $cmd\n} if ($DEBUG > 5);
    foreach my $line (split(/[\n\r]+/, qx{$cmd})) {
        my %volInfo;
        $line =~ s/^\s*(.*?)\s*$/$1/;
        print "getLVMdisks line: " . $line . "\n" if ($DEBUG > 8);
        foreach my $item (split(/\|/, $line)) {
            print "getLVMdisks item: " . $item . "\n" if ($DEBUG > 8);
            my ($key, $value) = split(/=/, $item);
            $value =~ s/^'(.*)'$/$1/;
            print qq{getLVMdisks value: "} . $key . qq{" = "} . $value . qq{"\n} if ($DEBUG > 8);
            $volInfo{$key} = $value;
        }
        print Data::Dumper->Dump([\%volInfo], ['getLVMdisks: volInfo']) if ($DEBUG > 7);
        my $vg = $volInfo{'LVM2_VG_NAME'};
        my $lv = $volInfo{'LVM2_LV_NAME'};
        if (! exists $LVM2{$vg}{$lv}) {
            $LVM2{$vg}{$lv} = \%volInfo;
        } else {
            foreach my $key (keys %{$LVM2{$vg}{$lv}}) {
                if (! exists $LVM2{$vg}{$lv}{$key}) {
                    $LVM2{$vg}{$lv}{$key} = $volInfo{$key};
                } else {
                    if ($LVM2{$vg}{$lv}{$key} ne $volInfo{$key}) {
                        $LVM2{$vg}{$lv}{$key} .= qq{,} . $volInfo{$key};
                    }
                }
            }
        }
    }
    foreach my $vg (keys %LVM2) {
        foreach my $lv (keys %{$LVM2{$vg}}) {
            my %disks;
            foreach my $device (split(/,/, $LVM2{$vg}{$lv}{'LVM2_DEVICES'})) {
                my $disk = $device;
                $disk =~ s/\(\d+\)$//;
                $disk =~ s,^/dev/,,;
                $disks{$disk}++;
            }
            my @disks = sort keys %disks;
            $LVM2{$vg}{$lv}{'disks'} = \@disks;
        }
    }
    print Data::Dumper->Dump([\%LVM2], ['getLVMdisks: LVM2']) if ($DEBUG > 6);
    return %LVM2;
}

sub getDeviceInfo($$$) {
    print qq{getDeviceInfo: Starting... ($DEBUG)\n} if $DEBUG;
    my $disk = shift;
    my $devicesRef = shift;
    my %devices = %{$devicesRef};
    my $lvmRef = shift;
    my %lvm = %{$lvmRef};
    print qq{getDeviceInfo: Getting info for disk: } . $disk . qq{\n} if $DEBUG;
    my %diskinfo;
    foreach my $dg (sort keys %lvm) {
        if (exists $lvm{$dg}{$disk}) {
            %diskinfo = %{$lvm{$dg}{$disk}};
        } elsif (exists $devices{$disk}) {
            %diskinfo = %{$devices{$disk}};
        }
    }
    return %diskinfo;
}

sub returnDiskDevices($) {
    print qq{returnDiskDevices: Starting... ($DEBUG)\n} if $DEBUG;
    my $devicesRef = shift;
    my %devices = %{$devicesRef};

    my %disks;

    foreach my $device (sort keys %devices) {
        print qq{returnDiskDevices: checking $device.\n} if ($DEBUG > 2);
        if (exists $devices{$device}{'major'}) {
            print qq{returnDiskDevices: major device number is } . $devices{$device}{'major'} . qq{\n} if ($DEBUG > 2);
            if ($devices{$device}{'major'} == 8) {
                print qq{returnDiskDevices: It's a disk!\n} if ($DEBUG > 2);
                push (@{$disks{$device}{'subdevices'}}, $device);
                if (exists $devices{$device}{'partitions'}) {
                    push (@{$disks{$device}->{'subdevices'}}, keys %{$devices{$device}->{'partitions'}});
                }
            }
        }
    }

    print Data::Dumper->Dump([\%disks], ['returnDiskDevices: disks']) if ($DEBUG > 1);
    return %disks;
}

sub findMetaDevices($$) {
    print qq{returnMetaDevices: Starting... ($DEBUG)\n} if $DEBUG;
    my $partitionsRef = shift;
    my $devicesRef = shift;

    my @partitions = @{$partitionsRef};
    my %devices = %{$devicesRef};

    print qq{returnMetaDevices: Finding meta-devices with these members:\n\t} . join("\n\t", @partitions) . "\n" if $DEBUG;
	my %metaDevices;

    foreach my $device (sort keys %devices) {
        print qq{returnMetaDevices: checking $device.\n} if ($DEBUG > 2);
        if (exists $devices{$device}{'mdadm'}) {
            print qq{returnMetaDevices: device } . $device . qq{ is a meta-device\n} if ($DEBUG > 2);
	        if (exists $devices{$device}{'mdadm'}{'drives'}) {
	        	foreach $drive (sort keys %{$devices{$device}{'mdadm'}{'drives'}}) {
		            print qq{returnMetaDevices: checking member } . $drive . qq{ of } . $device . qq{\n} if ($DEBUG > 2);
	        		my $member = $devices{$device}{'mdadm'}{'drives'}{$drive}{'disk'};
	        		if (grep(/$member/, @partitions)) {
			            print qq{returnMetaDevices: found matching member } . $member . qq{ of } . $device . qq{\n} if ($DEBUG > 2);
	        			$metaDevices{$device}++;
	        		}
	        	}
            }
        }
    }

	my @metaDevices = sort keys %metaDevices;

    print Data::Dumper->Dump([\@metaDevices], ['returnMetaDevices: metaDevices']) if ($DEBUG > 1);
    return @metaDevices;
}

sub findLVMvolumes($$) {
    print qq{findLVMvolumes: Starting... ($DEBUG)\n} if $DEBUG;
    my $devicesRef = shift;
    my $lvmRef = shift;

    my @devices = @{$devicesRef};
    my %lvm = %{$lvmRef};

    print qq{findLVMvolumes: Finding LVM volumes with these devices:\n\t} . join("\n\t", @devices) . "\n" if $DEBUG;
	my %volumes;

    foreach my $group (sort keys %lvm) {
		print qq{findLVMvolumes: checking volume group $group.\n} if ($DEBUG > 2);
	    foreach my $volume (sort keys %{$lvm{$group}}) {
			print qq{findLVMvolumes: checking volume $volume.\n} if ($DEBUG > 2);
		    foreach my $disk (sort @{$lvm{$group}{$volume}{'disks'}}) {
				print qq{findLVMvolumes: checking volume $volume disk $disk.\n} if ($DEBUG > 2);
	        	if (grep(/$disk/, @devices)) {
			    	print qq{findLVMvolumes: found matching disk } . $disk . qq{ of } . $volume . qq{\n} if ($DEBUG > 2);
	        		$volumes{$group}{$volume}++;
	        	}
	        }
        }
     }

    print Data::Dumper->Dump([\%volumes], ['findLVMvolumes: volumes']) if ($DEBUG > 1);
    return %volumes;
}

sub getBackupSummary($$) {
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -d 3 -b
    print qq{getBackupSummary: Starting... ($DEBUG)\n} if $DEBUG;
    my $devicesRef = shift;
    my %devices = %{$devicesRef};
    my $lvmRef = shift;
    my %lvm = %{$lvmRef};
    my %backupInfo;

    my %disks = returnDiskDevices(\%devices);
    foreach my $disk (keys %disks) {
        print qq{getBackupSummary: checking disk $disk.\n} if ($DEBUG > 1);

        my @checkedDevices = ();

        if (exists $disks{$disk}{'subdevices'}) {
	        my @devices2check = sort @{ $disks{$disk}{'subdevices'} };
			while (my $subdevice = shift(@devices2check)) {
				next if ($subdevice eq $disk);
            	print qq{getBackupSummary: checking subdevice $subdevice.\n} if ($DEBUG > 1);
            	push(@checkedDevices, $subdevice);
            }
		}
        $backupInfo{$disk}{'subdevices'} = \@checkedDevices;
        my @partitions = ($disk, @{$backupInfo{$disk}{'subdevices'}});
        my @metaDevices = findMetaDevices(\@partitions, \%devices);
        $backupInfo{$disk}{'metadevices'} = \@metaDevices;
        my @devices = ($disk, @{$backupInfo{$disk}{'subdevices'}}, @{$backupInfo{$disk}{'metadevices'}});
        my %volumes = findLVMvolumes(\@devices, \%lvm);
        $backupInfo{$disk}{'volumes'} = \%volumes;
    }

    return %backupInfo;
}

sub printBackupSummary($$$) {
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -d 3 -b
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -b
    print qq{printBackupSummary: Starting... ($DEBUG)\n} if $DEBUG;
    my $backupInfoRef = shift;
    my %backupInfo = %{$backupInfoRef};
    my $devicesRef = shift;
    my %devices = %{$devicesRef};
    my $lvmRef = shift;
    my %lvm = %{$lvmRef};
    print Data::Dumper->Dump([\%devices], ['devices']) if ($DEBUG);
    print Data::Dumper->Dump([\%lvm], ['lvm']) if ($DEBUG);
    print Data::Dumper->Dump([\%backupInfo], ['backupInfo']) if ($DEBUG);
    my $format = "%-20s %s\n";
    foreach my $device (sort keys %backupInfo) {
		printf($format, "Drive:", $devices{$device}{'smart'}{'type'});
		printf($format, "Model:", $devices{$device}{'smart'}{'model'});
		printf($format, "Serial:", $devices{$device}{'smart'}{'serial'});
		printf($format, "Size:",
			$devices{$device}{'parted'}{'size'}
			. " ("
			. $devices{$device}{'parted'}{'Capacity'}
			. ")"
		);
		printf($format, "Sector Size:",
			$devices{$device}{'parted'}{'sectorSizePhysical'}
			. " (physical) / "
			. $devices{$device}{'parted'}{'sectorSizeLogical'}
			. " (logical) "
		);
		printf($format, "Partition Type:",
			$devices{$device}{'parted'}{'partitionTable'}
			. " (currently attached as "
			. $devices{$device}{'parted'}{'type'}
			. " disk "
			. $device
			. ")"
		);
		foreach my $partition (sort keys %{$devices{$device}{'partitions'}}) {
			printf($format, "Partition " . $partition . ":",
				$devices{$device}{'partitions'}{$partition}{'parted'}{'start'}
				. " to "
				. $devices{$device}{'partitions'}{$partition}{'parted'}{'end'}
				. " = "
				. $devices{$device}{'partitions'}{$partition}{'parted'}{'size'}
				. " ("
				. $devices{$device}{'partitions'}{$partition}{'parted'}{'name'}
				. ")"
			);
		}
		foreach my $metaDevice (sort @{$backupInfo{$device}{'metadevices'}}) {
			printf($format, "MD device " . $metaDevice . ":",
				$devices{$metaDevice}{'mdadm'}{'Raid Level'}
				. " with "
				. $devices{$metaDevice}{'mdadm'}{'Raid Devices'}
				. " devices ("
				. $devices{$metaDevice}{'mdadm'}{'Active Devices'}
				. " active)"
			);
		}
		foreach my $volumeGroup (sort keys %{$backupInfo{$device}{'volumes'}}) {
			foreach my $volume (sort keys %{$backupInfo{$device}{'volumes'}{$volumeGroup}}) {
				printf($format, "LVM Volume:", $volume . " in " . $volumeGroup);
			}
		}
    	print "\n" x 2;
    }
}

sub printBackupLog($$$) {
#   /home/kellyb/Dropbox/Files/Code/Github/Linux-Volume-Scripts/bks_show_disks.pl -d 3 -e
    print qq{printBackupLog: Starting... ($DEBUG)\n} if $DEBUG;
    my $backupInfoRef = shift;
    my %backupInfo = %{$backupInfoRef};
    my $devicesRef = shift;
    my %devices = %{$devicesRef};
    my $lvmRef = shift;
    my %lvm = %{$lvmRef};
    print Data::Dumper->Dump([\%devices], ['devices']) if ($DEBUG);
    print Data::Dumper->Dump([\%lvm], ['lvm']) if ($DEBUG);
    print Data::Dumper->Dump([\%backupInfo], ['backupInfo']) if ($DEBUG);

    my @output_fields = (
        'Serial',
        'MD',
        'Location',
        'Drive',
        'Size',
        'Notes'
    );
    my $output_format = "%-20s %-5s %-10s %-25s %-10s %s\n";

    my %entry_log;
    foreach my $device (sort keys %backupInfo) {
        my %entry;

        my @volumes;
		foreach my $volumeGroup (sort keys %{$backupInfo{$device}{'volumes'}}) {
			foreach my $volume (sort keys %{$backupInfo{$device}{'volumes'}{$volumeGroup}}) {
			    push(@volumes, qq{$volumeGroup / $volume});
			}
		}

        $entry{'Serial'} = $devices{$device}{'smart'}{'serial'};
        $entry{'MD'} = join(", ", sort grep(!/^md(0|10)$/, @{$backupInfo{$device}{'metadevices'}}));
        $entry{'Location'} = $device;
        $entry{'Drive'} = $devices{$device}{'smart'}{'model'};
        $entry{'Size'} = $devices{$device}{'parted'}{'Capacity'};
        $entry{'Notes'} = join("; ", @volumes);

        print Data::Dumper->Dump([\%entry], ['printBackupLog: entry']) if ($DEBUG);
        $entry_log{$device} = \%entry;
    }
    print Data::Dumper->Dump([\%entry_log], ['printBackupLog: entry_log']) if ($DEBUG);

    printf($output_format, @output_fields);
    foreach my $device (sort keys %entry_log) {
        my %entry = %{$entry_log{$device}};
		printf($output_format,
		    $entry{'Serial'},
		    $entry{'MD'},
		    $entry{'Location'},
		    $entry{'Drive'},
		    $entry{'Size'},
		    $entry{'Notes'}
		);
    }

}

sub checkArrays($) {
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -d 3 -c
    print qq{checkArrays: Starting... ($DEBUG)\n} if $DEBUG;
    my $devicesRef = shift;
    my %devices = %{$devicesRef};
    print Data::Dumper->Dump([\%devices], ['devices']) if ($DEBUG);
    my %mdDeviceUUIDs;
    my %diskDeviceUUIDs;
    foreach my $device (sort keys %devices) {
	    print qq{checkArrays: Checking device $device\n} if $DEBUG;
	    if (exists $devices{$device}{'mdadm'}) {
	    	print qq{checkArrays: Device $device is an md device!\n} if $DEBUG;
		    if (exists $devices{$device}{'mdadm'}{'UUID'}) {
		    	my $UUID = $devices{$device}{'mdadm'}{'UUID'};
		    	print qq{checkArrays: Device $device has UUID of} . $UUID . qq{!\n} if $DEBUG;
		    	if ($devices{$device}{'major'} == 8) {
		    		$diskDeviceUUIDs{$device} = $UUID;
		    	} elsif ($devices{$device}{'major'} == 9) {
		    		$mdDeviceUUIDs{$device} = $UUID;
		    	}
		    }
	    }
	    if (exists $devices{$device}{'partitions'}) {
	    	print qq{checkArrays: Device $device has partitions!\n} if $DEBUG;
	    	foreach my $partition (sort keys %{$devices{$device}{'partitions'}}) {
			    print qq{checkArrays: Checking device $device\n} if $DEBUG;
			    if (exists $devices{$device}{'partitions'}{$partition}{'mdadm'}) {
			    	print qq{checkArrays: Device $partition is an md device!\n} if $DEBUG;
				    if (exists $devices{$device}{'partitions'}{$partition}{'mdadm'}{'Array UUID'}) {
				    	my $UUID = $devices{$device}{'partitions'}{$partition}{'mdadm'}{'Array UUID'};
				    	print qq{checkArrays: Device $partition has UUID of $UUID\n} if $DEBUG;
		    			$diskDeviceUUIDs{$partition} = $UUID;
				    }
				    if (exists $devices{$device}{'partitions'}{$partition}{'mdadm'}{'UUID'}) {
				    	my $UUID =  $devices{$device}{'partitions'}{$partition}{'mdadm'}{'UUID'};
				    	print qq{checkArrays: Device $partition has UUID of } . $UUID . qq{!\n} if $DEBUG;
		    			$diskDeviceUUIDs{$partition} = $UUID;
				    }
				}
	    	}
	    }
    }
    print Data::Dumper->Dump([\%mdDeviceUUIDs], ['mdDeviceUUIDs']) if ($DEBUG);
    print Data::Dumper->Dump([\%diskDeviceUUIDs], ['diskDeviceUUIDs']) if ($DEBUG);
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -d 3 -c
    foreach my $mdDevice (sort keys %mdDeviceUUIDs) {
    	foreach my $index (sort keys %{$devices{$mdDevice}{'mdadm'}{'drives'}}) {
    		my $component = $devices{$mdDevice}{'mdadm'}{'drives'}{$index}{'disk'};
    		if ($mdDeviceUUIDs{$mdDevice} eq $diskDeviceUUIDs{$component}) {
				print qq{checkArrays: Device $mdDevice has component $component\n} if $DEBUG;
				delete $diskDeviceUUIDs{$component};
    		} else {
				print qq{checkArrays: Device $mdDevice is missing component "$component"\n} if $DEBUG;
    		}
    	}
    }
    foreach my $device (sort keys %diskDeviceUUIDs) {
    	foreach my $mdDevice (sort keys %mdDeviceUUIDs) {
    		if ($diskDeviceUUIDs{$device} == $mdDeviceUUIDs{$mdDevice}) {
    			print qq{checkArrays: Device $device is missing from array $mdDevice\n} if $DEBUG;
    			print qq{mdadm --manage /dev/$mdDevice --add /dev/$device\n};
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -c
    		}
    	}
    }
    print Data::Dumper->Dump([\%diskDeviceUUIDs], ['diskDeviceUUIDs']) if ($DEBUG);
}

sub calculatepartitionNameData($$) {
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -d 3 -n
    print qq{calculatepartitionNameData: Starting... ($DEBUG)\n} if $DEBUG;
    my $devicesRef = shift;
    my %devices = %{$devicesRef};
    my $lvmRef = shift;
    my %lvm = %{$lvmRef};

    my %partitionNameData;

    foreach my $device (sort keys %devices) {
        print qq{calculatepartitionNameData: checking $device\n} if ($DEBUG > 5);
        next unless defined $devices{$device}{'mdadm'};
        if (defined $partitionNameData{$device}{'md_name'}) {
	        $partitionNameData{$device}{'md_name'} = $devices{$device}{'mdadm'}{'Name'};
	        $partitionNameData{$device}{'md_name'} =~ s/ .*$//;
	    } else {
	        $partitionNameData{$device}{'md_name'} = $device;
	    }
    }
	print Data::Dumper->Dump([\%partitionNameData], ['partitionNameData']) if ($DEBUG);

	my %arrays;
	foreach my $diskGroup (sort keys %lvm) {
		foreach my $volume (sort keys %{$lvm{$diskGroup}}) {
		    print qq{calculatepartitionNameData: Processing volume $volume in volume group $diskGroup...\n} if $DEBUG;
		    next if ($volume =~ /^swap/);
		    my @volumesArrays = @{$lvm{$diskGroup}{$volume}{'disks'}};
			print Data::Dumper->Dump([\@volumesArrays], ['volumesArrays']) if ($DEBUG);
			foreach my $array (@volumesArrays) {
				$arrays{$array}{$diskGroup}{$volume}++;
			}
		}
	}
	print Data::Dumper->Dump([\%arrays], ['calculatepartitionNameData: arrays']) if ($DEBUG);

	foreach my $array (keys %arrays) {
		my @vgvols;
		foreach my $volumeGroup (keys %{$arrays{$array}}) {
			#push(@vgvols, $volumeGroup . "-" . join("_", keys %{$arrays{$array}{$volumeGroup}}));
			push(@vgvols, join("_", keys %{$arrays{$array}{$volumeGroup}}));
		}
		$partitionNameData{$array}{'lvm_name'} = join("/", @vgvols);
	}
	print Data::Dumper->Dump([\%partitionNameData], ['calculatepartitionNameData: partitionNameData']) if ($DEBUG);

 	foreach my $array (keys %partitionNameData) {
	    print qq{calculatepartitionNameData: Looking for members of array $array...\n} if $DEBUG;
 		my @array_partitions;
 		foreach my $arrayMember (keys %{$devices{$array}{'mdadm'}{'drives'}}) {
		    print qq{calculatepartitionNameData: Looking for array $array member $arrayMember...\n} if $DEBUG;
 			push(@array_partitions, $devices{$array}{'mdadm'}{'drives'}{$arrayMember}{'disk'});
 		}
		$partitionNameData{$array}{'members'} = \@array_partitions;
 	}
	print Data::Dumper->Dump([\%partitionNameData], ['partitionNameData']) if ($DEBUG);

	my %partitionNames;
 	foreach my $array (keys %partitionNameData) {
 		my $partition_name = join('/', $partitionNameData{$array}{'md_name'}, $partitionNameData{$array}{'lvm_name'});
		$partition_name =~ s,^/*(.*?)/*$,$1,;
		if ($partition_name eq 'md10') {
		    $partition_name = "md10/DiskInfo";
		} elsif ($partition_name eq 'md0') {
		    $partition_name = "md0/boot";
		}
		foreach my $partition (sort @{$partitionNameData{$array}{'members'}}) {
			$partitionNames{$partition} = $partition_name;
		}
	}
	print Data::Dumper->Dump([\%partitionNames], ['partitionNames']) if ($DEBUG);

	my @cmds;
	foreach my $array (sort keys %partitionNames) {
		print qq{calculatepartitionNameData: Finding disk for array $array...\n} if ($DEBUG > 2);
		foreach my $device (keys %devices) {
			print qq{calculatepartitionNameData: Checking device $device...\n} if ($DEBUG > 3);
			next unless defined $devices{$device}{'partitions'};
			foreach my $partition (keys %{$devices{$device}{'partitions'}}) {
				print qq{calculatepartitionNameData: Checking partition $partition...\n} if ($DEBUG > 4);
				next unless ($partition eq $array);
				$part_no = $partition;
				$part_no =~ s/^$device//;
				print qq{calculatepartitionNameData: Partition number is $part_no...\n} if ($DEBUG > 4);
				push (@cmds, sprintf (qq{sudo parted /dev/%s name %d %s}, $device, $part_no, $partitionNames{$array}));
			}
		}
	}
	print Data::Dumper->Dump([\@cmds], ['cmds']) if ($DEBUG);

#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -d 3 -n
#   /home/kellyb/Documents/Code/GIT/Linux-Volume-Scripts/show_disks.pl -n

    return @cmds;
}

sub main() {}
print qq{MAIN CODE: Starting...\n} if $DEBUG;

# Define options
($OPTIONS = <<END_OPTIONS) =~ s/^[^\S\n]+//gm;
    -b              Print backup summaries for each disk
    -e              Print backup log entries for each disk
    -c              Check all arrays for completeness
    -n              Name all partitions (beta)
    -l <device>     List info for device
    -x              Dump all data in Perl hash format
    -d #            Debuging level
    -h              Print this help
END_OPTIONS

# Process command line arguments
getopts("hd:xl:becn", \%opts);

# Process debug argument
checkArg("d", \$DEBUG, \%opts);
$DEBUG += 0;
print qq{MAIN CODE: DEBUG is now: $DEBUG\n} if $DEBUG;
print Data::Dumper->Dump([\%opts], ['opts']) if $DEBUG;

# Process other arguments which require values
checkArg("l", \$LISTDISK, \%opts);

# Process help if requested
if ($opts{'h'}) {
  print qq{\n} . $OPTIONS . qq{\n};
  exit 0;
}

my %devices = getDiskDevices();
%devices = getDiskSmartInfo(%devices);
%devices = getDiskPartedInfo(%devices);
%devices = getMdDeviceInfo(%devices);
%devices = getMdArrayInfo(%devices);

my %lvm = getLVMdisks();

if ( ($opts{'x'}) or ($DEBUG) ) {
    print qq{MAIN CODE: Dumping Devices...\n};
    print Data::Dumper->Dump([\%devices], ['devices']);
    print qq{MAIN CODE: Dumping LVM...\n};
    print Data::Dumper->Dump([\%lvm], ['lvm']);
}

if ($opts{'c'}) {
    print qq{MAIN CODE: Checking all MD devices...\n} if $DEBUG;
    checkArrays(\%devices);
} elsif ($opts{'n'}) {
    print qq{MAIN CODE: Naming partitions...\n} if $DEBUG;
    my @cmds = calculatepartitionNameData(\%devices, \%lvm);
    print Data::Dumper->Dump([\@cmds], ['cmds']) if ($DEBUG);
    print qq{\n# Running the following should update your partition names:\n\n};
    print join("\n", @cmds) . "\n\n";
} elsif ($opts{'b'}) {
    print qq{MAIN CODE: Printing device backup summaries...\n} if $DEBUG;
    my %backupSummary = getBackupSummary(\%devices, \%lvm);
    print Data::Dumper->Dump([\%backupSummary], ['backupSummary']) if ($DEBUG);
	printBackupSummary(\%backupSummary, \%devices, \%lvm);
} elsif ($opts{'e'}) {
    print qq{MAIN CODE: Printing device backup log entries...\n} if $DEBUG;
    my %backupSummary = getBackupSummary(\%devices, \%lvm);
    print Data::Dumper->Dump([\%backupSummary], ['backupSummary']) if ($DEBUG);
	printBackupLog(\%backupSummary, \%devices, \%lvm);
} elsif ($opts{'l'}) {
    print qq{MAIN CODE: Listing Device: } . $opts{'l'} . qq{\n} if $DEBUG;
    my %info = getDeviceInfo($LISTDISK, \%devices, \%lvm);
    print Data::Dumper->Dump([\%info], ['info']); # if ($DEBUG);
}
