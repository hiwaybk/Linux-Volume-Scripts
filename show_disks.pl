#!/usr/bin/perl

$DEBUG = 0;

use Data::Dumper;

sub getDiskDevices() {
    my @devices;
    open(PARTITIONS, "/proc/partitions") or die;
    while (my $chunk = <PARTITIONS>) {
        foreach my $line (split(/[\n\r]+/, $chunk)) {
            print Data::Dumper->Dump([$line], ['line from /proc/partitions']) if $DEBUG;
            my @line = unpack("A4 A9 A11 A80", $line);
            print Data::Dumper->Dump([\@line], ['line from /proc/partitions']) if ($DEBUG > 2);
            if (@line[0] == 8) {
                (my $device) = ($line[3] =~ /^\s*([^\s]+)/);
                print Data::Dumper->Dump([$device], ['device from /proc/partitions']) if $DEBUG;
                push(@devices, $device);
            }
        }
    }
    return sort @devices;
}

sub getPartitions() {
    my @partitions;
    foreach my $device (getDiskDevices()) {
        push(@partitions, $device) if ($device =~ /\d$/);
        print Data::Dumper->Dump([$device], ['device from getPartitions()']) if $DEBUG;
    }
    return sort @partitions;
}

sub getDisks() {
    my @disks;
    foreach my $device (getDiskDevices()) {
        push(@disks, $device) unless ($device =~ /\d$/);
        print Data::Dumper->Dump([$device], ['device from getPartitions()']) if $DEBUG;
    }
    return sort @disks;
}

sub getMdDeviceUUID($) {
    my $device = shift;
    #     UUID=`sudo mdadm --detail /dev/$ARRAY | grep UUID | cut -d: -f2-`
    $cmd = "sudo mdadm --detail /dev/$device";
    print Data::Dumper->Dump([$cmd], ['cmd']) if $DEBUG;
    open(MDADM, $cmd . "|") or die qq{Can't run: $cmd: $!};
    while (my $chunk = <MDADM>) {
        foreach my $line (split(/[\n\r]+/, $chunk)) {
            print Data::Dumper->Dump([$line], ['line from $cmd']) if $DEBUG;
            next unless ($line =~ /\s*UUID\s:\s+(.*)$/);
            return $1;
        }
    }
}

sub getMdDeviceArrayUUID($) {
    my $device = shift;
    #     UUID=`sudo mdadm --detail /dev/$ARRAY | grep UUID | cut -d: -f2-`
    $cmd = "sudo mdadm --examine /dev/$device";
    print Data::Dumper->Dump([$cmd], ['cmd']) if $DEBUG;
    open(MDADM, $cmd . " 2>&1 |") or die qq{Can't run: $cmd: $!};
    my $pattern = "Array UUID";
    while (my $chunk = <MDADM>) {
        foreach my $line (split(/[\n\r]+/, $chunk)) {
            print Data::Dumper->Dump([$line], ['line from $cmd']) if $DEBUG;
            $pattern = "UUID" if ($line =~ /Version : 0.90.00/);
            next unless ($line =~ /$pattern\s:\s+(.*)$/);
            print Data::Dumper->Dump([$1], ['UUID']) if $DEBUG;
            return $1;
        }
    }
}

sub getMdUuidDevices() {
    my %UUIDs;
    my @devices = getDiskDevices();
    foreach my $device (@devices) {
        my $UUID = getMdDeviceArrayUUID($device);
        if ($UUID) {
            my @memberDevices = @{$UUIDs{$UUID}};
            push(@memberDevices, $device);
            $UUIDs{$UUID} = [ sort @memberDevices ];
        }
    }
    print Data::Dumper->Dump([\%UUIDs], ['%UUIDs']) if $DEBUG;
    return %UUIDs;
}

sub getMdDevices() {
    my %UUIDs = getMdUuidDevices();
    my %raidDevices;
    open(MDSTAT, "/proc/mdstat") or die;
    while (my $chunk = <MDSTAT>) {
        foreach my $line (split(/[\n\r]+/, $chunk)) {

            print "/proc/mdstat: " . $line . "\n" if $DEBUG;
            next if ($line =~ /^Personalities :/);
            next unless $line =~ /^md\d+ :/;
            (my $md, my $componentList) = split(/\s*:\s*/, $line);
            $deviceUUID = getMdDeviceUUID($md);
            $raidDevices{$md}{'uuid'} = getMdDeviceUUID($md);
            if (exists $UUIDs{$deviceUUID}) {
                $raidDevices{$md}{'components'}{'discovered'} = $UUIDs{$deviceUUID};
            }
            my @componentList = split(/\s+/, $componentList);
            my @components;
            foreach my $component (@componentList) {
                # md21 : active raid1 sdh3[3](W) sde3[4](W) sdd3[2]
                $component =~ s/\[.*$//;
                print $md . " -> " . $component . "\n" if $DEBUG;
                next if ($component =~ /active/);
                next if ($component =~ /raid1/);
                push(@components, $component);
            }
            $raidDevices{$md}{'components'}{'active'} = [ sort @components ];
            my @partitions = ( @{$raidDevices{$md}{'components'}{'active'}}, @{$raidDevices{$md}{'components'}{'discovered'}});
            my %drives;
            foreach my $partition (sort @partitions) {
                my $drive = $partition;
                $drive =~ s/\d+$//;
                $drives{$drive}++;
            }
            $raidDevices{$md}{'components'}{'drives'} = [ sort keys %drives ];
        }
    }
    print Data::Dumper->Dump([\%raidDevices], ['%raidDevices']) if $DEBUG;
    return %raidDevices;

}

sub compareArrayRef($$) {
    my $ref1 = shift;
    my $ref2 = shift;
    my @a = @{$ref1};
    my @b = @{$ref2};

    %a = map { $_ => 1 } @a;
    %b = map { $_ => 1 } @b;
    print Data::Dumper->Dump([\%a], ['compareArrayRef %a']) if $DEBUG;
    print Data::Dumper->Dump([\%b], ['compareArrayRef %b']) if $DEBUG;

    my %results;
    foreach my $item (sort keys %a) {
        if (exists $b{$item}) {
            delete $b{$item};
        } else {
            $results{'array 1'}{$item}++;
        }
    }
    foreach my $item (sort keys %b) {
        $results{'array 2'}{$item}++;
    }

    print Data::Dumper->Dump([\%results], ['compareArrayRef %results']) if $DEBUG;
    return %results;
}

sub getCheckMdDevices(%) {
    my %arrays = @_;
    print Data::Dumper->Dump([\%arrays], ['getCheckMdDevices %arrays']) if $DEBUG;
    foreach my $array (sort keys %arrays) {
        print Data::Dumper->Dump([$array], ['array']) if $DEBUG;
        my @active = @{$arrays{$array}{'components'}{'active'}};
        print Data::Dumper->Dump([\@active], ['getCheckMdDevices @active']) if $DEBUG;
        my @discovered = @{$arrays{$array}{'components'}{'discovered'}};
        print Data::Dumper->Dump([\@discovered], ['getCheckMdDevices @discovered']) if $DEBUG;
        if (compareArrayRef(\@active, \@discovered)) {
            print qq{Array $array is bad!\n};
            my %discovered;
            foreach my $device (@discovered) {
                $discovered{$device}++;
            }
            foreach my $device (@active) {
                if (exists $discovered{$device}) {
                    delete $discovered{$device};
                    print qq{\t$device seems OK.\n};
                } else {
                    print qq{\t$device is in the array, but no partition found!\n};
                }
            }
            foreach my $device (keys %discovered) {
                print qq{\t$device should probably be in $array.\n};
                print qq{\t\tmdadm --manage /dev/$array --write-mostly --add /dev/$device\n};
            }
        }
        print Data::Dumper->Dump([$flag], ['getCheckMdDevices $flag']) if $DEBUG;

    }
}


sub getLVMdisks() {
    my %volumeInfo;
    foreach my $row (split(/[\n\r]+/, qx{sudo lvs -o+devices --noheadings --nameprefixes --aligned --separator '|'})) {
        print "lvs: " . $row . "\n" if $DEBUG;
        my $line = $row;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        my @row = split(/\s*\|\s*/, $line);
        my %LVM2;
        foreach my $info (@row) {
             print "lvs found: " . $info . "\n" if $DEBUG > 10;
             $cmd = $info;
             $cmd =~ s/^/\$LVM2{'/;
             $cmd =~ s/=/'}=/;
             $cmd =~ s/$/;/;
             print "cmd: " . $cmd . "\n" if $DEBUG > 10;
             eval($cmd);
        }
        if ( $LVM2{'LVM2_DEVICES'} =~ /\/dev\/(.+)\((\d+)\)/ ) {
            $LVM2{'LVM2_DEVICE'} = $1;
            $LVM2{'LVM2_DEVICE_OFFSET'} = $2;
        }
        print Data::Dumper->Dump([\%LVM2], ['LVM2']) if $DEBUG;

        $volgroup = $LVM2{'LVM2_VG_NAME'};
        $volume = $LVM2{'LVM2_LV_NAME'};
        my $blocks = $LVM2{'LVM2_DEVICES'};
        delete $LVM2{'LVM2_VG_NAME'} if exists $LVM2{'LVM2_VG_NAME'};
        delete $LVM2{'LVM2_LV_NAME'} if exists $LVM2{'LVM2_LV_NAME'};
        delete $LVM2{'LVM2_DEVICES'} if exists $LVM2{'LVM2_DEVICES'};
        $volumeInfo{$volgroup}{$volume}{'extents'}{$blocks} = { %LVM2 };
    }
    foreach my $volgroup (sort keys %volumeInfo) {
        my %volumes = %{$volumeInfo{$volgroup}};
        foreach my $volume (sort keys %volumes) {
            my %disks;
            my %extents = %{$volumes{$volume}{'extents'}};
            foreach my $blocks (sort keys %extents) {
                my $disk = $extents{$blocks}{'LVM2_DEVICE'};
                $disks{$disk}++;
            }
            $volumeInfo{$volgroup}{$volume}{'disks'} = [ sort keys %disks ];
        }
    }
    return %volumeInfo;
}

my %raidDevices = getMdDevices();
my %lvmDisks = getLVMdisks();

foreach my $volgroup (sort keys %lvmDisks) {
    print qq{Volume Group: $volgroup\n};
    my %volumes = %{$lvmDisks{$volgroup}};
    foreach my $volume (sort keys %volumes) {
        print qq{\tVolume Name: $volume\n};
        my @lvmDisks = @{$volumes{$volume}{'disks'}};
        my @disks;
        foreach my $lvmDisk (@lvmDisks) {
            print qq{\tArray Name: $lvmDisk\n};
            if (exists $raidDevices{$lvmDisk}) {
                my @raidDisks = @{$raidDevices{$lvmDisk}{'components'}{'drives'}};
                foreach my $disk (@raidDisks) {
                    push(@disks, $disk);
                }
            } else {
                push(@disks, $lvmDisk);
            }
        }
        print qq{\t\tPhysical disks:\n\t\t\t};
        print join("\n\t\t\t", @disks);
        print "\n";
    }
}

getCheckMdDevices(%raidDevices);

__END__

sub getDiskInfo($) {
    my $device = shift;
    my $cmd = qq{sudo smartctl --info $device};
    my %info;
    open(SMARTCTL, $cmd . "2>&1 |") or die;
    while (my $chunk = <SMARTCTL>) {
        foreach my $line (split(/[\n\r]+/, $chunk)) {
            print "smartctl: " . $line . "\n" if $DEBUG;
            next unless ($line =~ /Model Family|Device Model|Serial Number/);
            if ($line =~ /Model Family:\s+(.*)$/) {
                $info{'type'} = $1;
                print "smartctl: type -> " . $1 . "\n" if $DEBUG;
            } elsif ($line =~ /Device Model:\s+(.*)$/) {
                $info{'model'} = $1;
                print "smartctl: model -> " . $1 . "\n" if $DEBUG;
            } elsif ($line =~ /Serial Number:\s+(.*)$/) {
                $info{'serial'} = $1;
                print "smartctl: serial -> " . $1 . "\n" if $DEBUG;
            }
        }
    }
    return %info;
}



my %lvm = getLVMdisks();
print Data::Dumper->Dump([\%lvm], ['lvm']) if $DEBUG;

foreach my $volgroup (sort keys %lvm) {
    print "\n\n" . "Volume Group " . $volgroup . "\n";
    foreach my $volume (sort keys %{$lvm{$volgroup}}) {
        next if ($volume eq "swapvol");
        print "Volume " . $volume . "...\n";
        foreach my $array (sort keys %{$lvm{$volgroup}{$volume}}) {
            print "... has " . $lvm{$volgroup}{$volume}{$array}{'count'} . " chunk(s) on array " . $array . " which is on disk(s):\n";
            foreach my $disk (sort keys %{$lvm{$volgroup}{$volume}{$array}{'components'}}) {
                print "\t" . $disk;
                foreach my $item (qw{type model serial}) {
                    #print qq{\n\t\t} . $item . qq{: "} . $lvm{$volgroup}{$volume}{$array}{'components'}{$disk}{$item} . qq{"};
                    printf(qq{\n\t\t%-7s %s}, $item . ":", $lvm{$volgroup}{$volume}{$array}{'components'}{$disk}{$item});
                }
                print qq{\n};
            }
        }
        print qq{\n};
        print qq{\n};
    }
}

# foreach my $vol (sort keys %lvm) {
#     print "The volume " . $vol . "is on the array(s):\n";
#     my @raid = sort keys %{$lvm{$vol}};
#     foreach my $raid (@raid) {
#         print "\t" . $raid . " (pieces: " . $lvm{$vol}{$raid}{'count'} . ") which is on the disk(s):\n";
#         foreach my $device (@{$raid{$raid}}) {
#             print "\t\t" . $device . "\n";
#         }
#     }
# }

__END__


my $first_row = 0;
my %volumes;
my %raiddevices;

print Dumper(\%volumes) if $DEBUG;
print Dumper(\%raiddevices) if $DEBUG;

my @raiddevices = keys %raiddevices;

my %mdstat;
open(MDSTAT, "/proc/mdstat") or die;
while (my $chunk = <MDSTAT>) {
	foreach my $line (split(/[\n\r]/, $chunk)) {
		next if ($line =~ /^\s/);
		next unless ($line =~ /active/);
		print "MDSTAT: " . $line . "\n" if ($DEBUG);
		(my $array, my $components) = split(/\s*:\s*/, $line);
		print "Array: " . $array . "\n" if ($DEBUG);
		print "Components: " . $components . "\n" if ($DEBUG);
		foreach my $component (split(/\s+/, $components)) {
			next unless ($component =~ /\[/);
			$component =~ s/\[.*$//;
			print "Component: " . $component . "\n" if ($DEBUG);
			if (defined($mdstat{$array})) {
				$mdstat{$array} .= "|" . $component;
			} else {
				$mdstat{$array} = $component;
			}
		}
	}
}
print Dumper(\%mdstat) if $DEBUG;

#cat /proc/mdstat | grep md21 | tr ' ' '\n' | grep '\[' | cut -d '[' -f1

#md12 : active raid1 sdg3[3](W) sdb3[2]
#      2926318848 blocks super 1.2 [2/2] [UU]
#      bitmap: 0/22 pages [0KB], 65536KB chunk


foreach my $volume (sort keys %volumes) {
	print qq{Volume "$volume" has};
	my @segments = ();
	foreach my $disk (sort keys $volumes{$volume}) {
		my $segmentCount  = $volumes{$volume}{$disk};
		push(@segments, sprintf (qq{ %d segment%s on disk %s}, $segmentCount, $segmentCount > 1 ? "s": "", $disk));
	}
	print join(", and ", @segments) . qq{.\n};
}


