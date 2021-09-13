#!/usr/bin/perl -w
# This plugin uses /proc/diskstats to collect disk I/O stats and output them in Graphite format
# See https://www.kernel.org/doc/Documentation/ABI/testing/procfs-diskstats
#
# Outputs four metrics per device:
#   reads: the number of reads completed successfully
#   read_time: the number of ms spent reading
#   writes: the number of writes completed successfully
#   write_time: the number of ms spent writing
# Each of these is measured since boot, so the numbers will reset to 0.

use Getopt::Long qw(:config no_auto_abbrev no_ignore_case);
use Pod::Usage;
use Sys::Hostname;
use List::Util qw(any);

my $scheme = hostname() . '.diskstats';
my @ignoredevices = ('^loop', 'p[0-9]+$');
my @includedevices;

GetOptions(
	'scheme|s=s' => \$scheme,
	'ignore-device|x=s' => \@ignoredevices,
	'include-device|i=s' => \@includedevices,
) or pod2usage(2);

my $now = time();
open(my $fh, '<', '/proc/diskstats') or die("Cannot read /proc/diskstats");

sub output {
	my ($name, $value) = @_;
	print "$scheme.$name $value $now\n";
}

while (my $line = <$fh>) {
	$line =~ s/^\s*//;
	my ($major, $minor, $device, $reads, $reads_merged, $reads_sectors, $read_time, $writes, $writes_merged, $writes_sectors, $write_time) = split(/\s+/, $line);

	next if @ignoredevices && any { $device =~ $_ } @ignoredevices;
	next if @includedevices && !any { $device =~ $_ } @includedevices;
		
	output("$device.reads", $reads);
	output("$device.read_time", $read_time);
	output("$device.writes", $writes);
	output("$device.write_time", $write_time);
}

close($fh);
