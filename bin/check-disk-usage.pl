#!/usr/bin/perl -w
# Check disk usage
# Based on https://github.com/sensu-plugins/sensu-plugins-disk-checks/blob/master/bin/check-disk-usage.rb

use Getopt::Long qw(:config no_auto_abbrev no_ignore_case);
use Pod::Usage;
use Sys::Hostname;
use List::Util qw(any);
use POSIX qw/floor/;

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
my $magic = 1.0; # Magic factor to adjust warn/crit thresholds [0.0 - 1.0]. Raises the warning and critical levels for disks of size greater than `normal`, and lowers for smaller.
my $normal = 20; # Size of filesystem (in GB) that is not adapted by the `magic` factor.
my $minimum = 100; # Minimum size of filesystem to adjust using `normal` and `magic (in GB)

GetOptions(
	'type|t=s' => \@fstype,
	'ignore-type|x=s' => \@ignoretype,
	'ignore-mnt|i=s' => \@ignoremnt,
	'include-mnt|I=s' => \@includemnt,
	'ignore-path-re|p=s' => \$ignorepathre,
	'ignore-opt|o=s' => \@ignoreopt,
	'ignore-readonly' => \$ignorereadonly,
	'ignore-reserved|r' => \$ignore_reserved,
	'w=i' => \$bwarn,
	'c=i' => \$bcrit,
	'W=i' => \$iwarn,
	'K=i' => \$icrit,
	'magic|m=f' => \$magic,
	'normal|n=f' => \$normal,
	'minimum|l=f' => \$minimum,
) or pod2usage(2);

@fstype = split(/,/, join(',', @fstype));
@ignoretype = split(/,/, join(',', @ignoretype));
@ignoremnt = split(/,/, join(',', @ignoremnt));
@includemnt = split(/,/, join(',', @includemnt));
@ignoreopt = split(/,/, join(',', @ignoreopt));

my @mounts = split(/\n/, `mount`);

my $now = time();
open(my $fh, "df -BG --output=target,fstype,used,pcent,size,iused,ipcent,itotal|") or die("Cannot run df");

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
	return floor(100 - ((100 - $percent) * $scale));
}

my @crit_fs = ();
my @warn_fs = ();
my @info_fs = ();

while (my $line = <$fh>) {
	my ($mnt, $type, $used, $used_p, $size, $i_used, $i_used_p, $i_size) = split(/\s+/, $line);

	my @options = mount_options($mnt, $type);

	next if @fstype && !any { $_ eq $type } @fstype;
	next if @ignoretype && any { $_ eq $type } @ignoretype;
	next if @ignoremnt && any { $mnt =~ $_ } @ignoremnt;
	next if $ignorepathre && $mnt =~ $ignorepathre;
	next if @ignoreopt && any { my $option = $_; return any { $_ eq $option } @options } @ignoreopt;
	next if $ignorereadonly && any { $_ eq 'ro' } @options;
	next if @includemnt && !any { $mnt =~ $_ } @includemnt;

	next if $type eq 'devfs';

	$i_used_p =~ s/[^0-9]//g;

	if (length $i_used_p > 0) {
		if ($i_used_p >= $icrit) {
			push(@crit_fs, "$mnt $i_used_p% inode usage >= $icrit ($i_used/$i_size)");
		} elsif ($i_used_p >= $iwarn) {
			push(@warn_fs, "$mnt $i_used_p% inode usage >= $iwarn ($i_used/$i_size)");
		} else {
			push(@info_fs, "$mnt $i_used_p% inode usage < $iwarn% ($i_used/$i_size)")
		}
	}

	my $size_i = $size;
	$size_i =~ s/[^0-9]//g;
	$used_p =~ s/[^0-9]//g;

	my $actual_bcrit;
	my $actual_bwarn;
	if ($size_i < $minimum) {
		$actual_bcrit = $bcrit;
		$actual_bwarn = $bwarn;
	} else {
		$actual_bcrit = adj_percent($size_i, $bcrit);
		$actual_bwarn = adj_percent($size_i, $bwarn);
	}

	if ($used_p >= $actual_bcrit) {
		push(@crit_fs, "$mnt $used_p% bytes usage >= $actual_bcrit% ($used/$size)");
	} elsif ($used_p >= $actual_bwarn) {
		push(@warn_fs, "$mnt $used_p% bytes usage >= $actual_bwarn% ($used/$size)");
	} else {
		push(@info_fs, "$mnt $used_p% bytes usage < $actual_bwarn% ($used/$size)");
	}
}

close($fh);

if (@crit_fs) {
	print join("\n", (@crit_fs, @warn_fs));
	print "\n";
	exit 2;
} elsif (@warn_fs) {
	print join("\n", @warn_fs);
	print "\n";
	exit 1;
} else {
	print join("\n", @info_fs);
	print "\n";
	exit 0;
}
