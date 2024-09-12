#!/usr/bin/perl -w
# Output disk usage metrics
# Based on https://github.com/sensu-plugins/sensu-plugins-disk-checks/blob/master/bin/metrics-disk-usage.rb

use Getopt::Long qw(:config no_auto_abbrev no_ignore_case);
use Pod::Usage;
use Sys::Hostname;
use List::Util qw(any);

my $scheme = hostname() . '.disk_usage';
my @fstype; # Only check fs type(s)
my @ignoretype; # Ignore fs type(s)
my @ignoremnt; # Ignore mount point(s)
my @includemnt; # Include only mount point(s)
my $ignorepathre; # Ignore mount point(s) matching regular expression
my @ignoreopt; # Ignore option(s)
my $ignorereadonly; # Ignore read-only filesystems
my $flatten;
my $local;
my $block_size = 'M';

GetOptions(
	'scheme|s=s' => \$scheme,
	'type|t=s' => \@fstype,
	'ignore-type|x=s' => \@ignoretype,
	'ignore-mount|ignore-mnt|i=s' => \@ignoremnt,
	'include-mount|include-mnt|I=s' => \@includemnt,
	'ignore-path-re|p=s' => \$ignorepathre,
	'ignore-opt|o=s' => \@ignoreopt,
	'ignore-readonly' => \$ignorereadonly,
	'flatten|f' => \$flatten,
	'local|l' => \$local,
	'block-size|B=s' => \$block_size,
) or pod2usage(2);

@fstype = split(/,/, join(',', @fstype));
@ignoretype = split(/,/, join(',', @ignoretype));
@ignoremnt = split(/,/, join(',', @ignoremnt));
@includemnt = split(/,/, join(',', @includemnt));
@ignoreopt = split(/,/, join(',', @ignoreopt));

my @cli_options = ();
push(@cli_options, "-B$block_size");
push(@cli_options, "-l") if $local;

my $delim = $flatten ? '_' : '.';

my @mounts = split(/\n/, `mount`);

my $now = time();
open(my $fh, "df @cli_options --output=target,fstype,used,avail,pcent,iused,iavail,ipcent|") or die("Cannot run df");

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

while (my $line = <$fh>) {
	my ($mnt, $type, $used, $avail, $used_p, $i_used, $i_avail, $i_used_p) = split(/\s+/, $line);

	my @options = mount_options($mnt, $type);

	next if @fstype && !any { $_ eq $type } @fstype;
	next if @ignoretype && any { $_ eq $type } @ignoretype;
	next if @ignoremnt && any { $mnt =~ $_ } @ignoremnt;
	next if $ignorepathre && $mnt =~ $ignorepathre;
	next if @ignoreopt && any { my $option = $_; return any { $_ eq $option } @options } @ignoreopt;
	next if $ignorereadonly && any { $_ eq 'ro' } @options;
	next if @includemnt && !any { $mnt =~ $_ } @includemnt;

	if ($flatten) {
		if ($mnt eq '/') {
			$mnt = 'root';
		} else {
			$mnt =~ s/^\///;
		}
	} elsif ($mnt eq '/') {
		$mnt = 'root';
	} else {
		$mnt =~ s/^\//root./;
	}

	$mnt =~ s/\//$delim/g;
	$used =~ s/[^0-9]//g;
	$avail =~ s/[^0-9]//g;
	$used_p =~ s/[^0-9]//g;
	$i_used =~ s/[^0-9]//g;
	$i_avail =~ s/[^0-9]//g;
	$i_used_p =~ s/[^0-9]//g;

	print "$scheme.$mnt.used $used $now\n";
	print "$scheme.$mnt.avail $avail $now\n";
	print "$scheme.$mnt.used_percentage $used_p $now\n" if length($used_p) > 0;
	print "$scheme.$mnt.i_used $i_used $now\n";
	print "$scheme.$mnt.i_avail $i_avail $now\n";
	print "$scheme.$mnt.i_used_percentage $i_used_p $now\n" if length($i_used_p) > 0;
}

close($fh);
