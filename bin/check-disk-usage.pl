#!/usr/bin/perl -w
# Check disk usage
# Based on https://github.com/sensu-plugins/sensu-plugins-disk-checks/blob/master/bin/check-disk-usage.rb

use Getopt::Long qw(:config no_auto_abbrev no_ignore_case);
use Pod::Usage;
use Sys::Hostname;
use List::Util qw(any);

my @fstype; # Only check fs type(s)
my @ignoretype; # Ignore fs type(s)
my @ignoremnt; # Ignore mount point(s)
my @includemnt; # Include only mount point(s)
my $ignorepathre; # Ignore mount point(s) matching regular expression
my @ignoreopt; # Ignore option(s)
my $ignorereadonly; # Ignore read-only filesystems
my $ignore_reserved; # Ignore bytes reserved for privileged processes
my $bwarn = 85; # Warn if PERCENT or more of disk full
my $bcrit = 95; # Critical if PERCENT or more of disk full
my $iwarn = 85; # Warn if PERCENT or more of inodes used
my $icrit = 95; # Critical if PERCENT or more of inodes used
my $magic = 1.0; # Magic factor to adjust warn/crit thresholds. Example: .9
my $normal = 20; # Levels are not adapted for filesystems of exactly this size, where levels are reduced for smaller filesystems and raised for larger filesystems.
my $minimum = 100; # Minimum size to adjust (in GB)

GetOptions(
	't=s' => \@fstype,
	'x=s' => \@ignoretype,
	'i=s' => \@ignoremnt,
	'I=s' => \@includemnt,
	'p=s' => \$ignorepathre,
	'o=s' => \@ignoreopt,
	'ignore-readonly' => \$ignorereadonly,
	'ignore-reserved|r' => \$ignore_reserved,
	'w=i' => \$bwarn,
	'c=i' => \$bcrit,
	'W=i' => \$iwarn,
	'K=i' => \$icrit,
	'm=f' => \$magic,
	'n=f' => \$normal,
	'l=f' => \$minimum,
) or pod2usage(2);

@fstype = split(/,/, join(',', @fstype));
@ignoretype = split(/,/, join(',', @ignoretype));
@ignoremnt = split(/,/, join(',', @ignoremnt));
@includemnt = split(/,/, join(',', @includemnt));
@ignoreopt = split(/,/, join(',', @ignoreopt));

my @mounts = split(/\n/, `mount`);

my $now = time();
open(my $fh, "df -BG --output=target,fstype,used,pcent,size,ipcent|") or die("Cannot run df");

<$fh>; # Discard first line

sub mount_options {
	my ($mnt, $type) = @_;
	foreach my $mount_line (@mounts) {
		if ($mount_line =~ /$mnt type $type \((.*)\)/) {
			return split(/,/, $1);
		}
	}
	return undef;
}

# Adjust the percentages based on volume size
sub adj_percent {
	my ($size, $percent) = @_;
	my $hsize = $size / $normal;
	my $felt = $hsize ** $magic;
	my $scale = $felt / $hsize;
	return 100 - ((100 - $percent) * $scale);
}

my @crit_fs = ();
my @warn_fs = ();

while (my $line = <$fh>) {
	my ($mnt, $type, $used, $percent_b, $size, $percent_i) = split(/\s+/, $line);

	my @options = mount_options($mnt, $type);

	next if @fstype && !any { $_ eq $type } @fstype;
	next if @ignoretype && any { $_ eq $type } @ignoretype;
	next if @ignoremnt && any { $mnt =~ $_ } @ignoremnt;
	next if $ignorepathre && $mnt =~ $ignorepathre;
	next if @ignoreopt && any { my $option = $_; return any { $_ eq $option } @options } @ignoreopt;
	next if $ignorereadonly && any { $_ eq 'ro' } @options;
	next if @includemnt && !any { $mnt =~ $_ } @includemnt;

	next if $type eq 'devfs';

	$percent_i =~ s/[^0-9]//g;

	if (length $percent_i > 0) {
		if ($percent_i >= $icrit) {
			push(@crit_fs, "$mnt $percent_i% inode usage");
		} elsif ($percent_i >= $iwarn) {
			push(@warn_fs, "$mnt $percent_i% inode usage");
		}
	}

	my $size_i = $size;
	$size_i =~ s/[^0-9]//g;
	$percent_b =~ s/[^0-9]//g;

	my $actual_bcrit;
	my $actual_bwarn;
	if ($size_i < $minimum) {
		$actual_bcrit = $bcrit;
		$actual_bwarn = $bwarn;
	} else {
		$actual_bcrit = adj_percent($size_i, $bcrit);
		$actual_bwarn = adj_percent($size_i, $bwarn);
	}

	if ($percent_b >= $bcrit) {
		push(@crit_fs, "$mnt $percent_b% bytes usage ($used/$size)");
	} elsif ($percent_b >= $bwarn) {
		push(@warn_fs, "$mnt $percent_b% bytes usage ($used/$size)");
	}
}

close($fh);

if (@crit_fs) {
	print join(', ', (@crit_fs, @warn_fs));
	print "\n";
	exit 2;
} elsif (@warn_fs) {
	print join(', ', (@crit_fs, @warn_fs));
	print "\n";
	exit 1;
} else {
	print "All disk usage under $bwarn% and inode usage under $iwarn%\n";
	exit 0;
}
