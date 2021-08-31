#!/usr/bin/perl -w
# Output disk usage metrics
# Based on https://github.com/sensu-plugins/sensu-plugins-disk-checks/blob/master/bin/metrics-disk-usage.rb

use Getopt::Long qw(:config no_auto_abbrev no_ignore_case);
use Pod::Usage;
use Sys::Hostname;
use List::Util qw(any);

my $scheme = hostname() . '.disk_usage';
my @ignore_mnt;
my @include_mnt;
my $flatten;
my $local;
my $block_size = 'M';

GetOptions(
	'scheme|s=s' => \$scheme,
	'ignore-mount|i=s' => \@ignore_mnt,
	'include-mount|I=s' => \@include_mnt,
	'flatten|f' => \$flatten,
	'local|l' => \$local,
	'block-size|B=s' => \$block_size,
) or pod2usage(2);

@ignore_mnt = split(/,/, join(',', @ignore_mnt));
@include_mnt = split(/,/, join(',', @include_mnt));

my @cli_options = ();
push(@cli_options, "-PB$block_size");
push(@cli_options, "-l") if $local;

my $delim = $flatten ? '_' : '.';

my $now = time();
open(my $fh, "df @cli_options|") or die("Cannot run df");

<$fh>; # Discard first line

while (my $line = <$fh>) {
	my ($filesystem, $blocks, $used, $avail, $used_p, $mnt) = split(/\s+/, $line);

	if ($mnt !~ /\/sys(\/|$)|\/dev(\/|$)|\/run(\/|$)/) {
		next if @ignore_mnt && any { $mnt =~ $_ } @ignore_mnt;
		next if @include_mnt && !any { $mnt =~ $_ } @include_mnt;

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

		print "$scheme.$mnt.used $used $now\n";
		print "$scheme.$mnt.avail $avail $now\n";
		print "$scheme.$mnt.used_percentage $used_p $now\n";
	}
}

close($fh);
