#! /usr/bin/perl -w

# $Id: killspike.pl.in,v 1.1.1.1 2002/02/26 10:21:19 oetiker Exp $
# $Source: /home/oetiker/data/cvs-repo/AABN-rrdtool/contrib/killspike/killspike.pl.in,v $

# This script will read an XML file produced by
#	rrdtool dump foo.rrd >in.xml
# and look at the $maxspike highest samples per datasource. It then finds
# the records with the most hits and ditches the data. The resulting file
# can be read back into the RRD database with the command
#	rrdtool restore out.xml foo.rrd
#
# The whole idea is to find and eradicate "spikes" caused by erroneous
# readings affecting entire records.
#
# This tool is not for the faint of heart, will require tweaking per case
# (even though that should just be picking values for cutoff and to a lesser
# extent, maxspike). It will cause data loss, for obvious reasons.
#
# THIS SOFTWARE IS DISTRIBUTED IN THE HOPE THAT IT IS USEFUL, AND COMES WITH
# NO WARRANTY. USE AT YOUR OWN RISK!
#
#			Bert Driehuis <driehuis@playbeing.org>

use strict;

my $maxspike = 25;	# How many top samples to consider per datasource
my $cutoff = 20;	# How many records to ditch
my $debug = 1;
my $file = "in.xml";
my $outfile = "out.xml";

my $nds = 0;
my @dsl = ();
my @dsi = ();
my @topindx = ();
my @botindx = ();
my @dsname = ();
my $i;
my $j;

# Count the number of data sources
open(IN, $file) || die;
while(<IN>) {
	if (/<name>\s*(\w+)\s*/) {
		$dsname[$nds] = $1;
		$nds++;
	}
}
close IN;

print "Found $nds datasources\n" if $debug;

# Set up the list of lists for the datasource data
for ($i = 0; $i < $nds; $i++) {
	my @dsdata = ();
	push @dsl, \@dsdata;
	my @dsindex = ();
	push @dsi, \@dsindex;
	my @top = ();
	push @topindx, \@top;
	my @bot = ();
	push @botindx, \@bot;
}

# Slurp all datasource fields into the @dsl Lol
my $recno = -1;
open(IN, $file) || die;
while(<IN>) {
	next if !/<row>/;
	$recno++;
	my @data = split(/ /);
	die "Malformed input" if $data[5] ne "<row><v>";
	die "Malformed record" if $data[5 + ($nds * 2)] ne "</v></row>\n";
	for ($i = 0; $i < $nds; $i++) {
		my $sample = $data[($i * 2) + 6];
		#print "$sample\n";
		push @{$dsl[$i]}, $sample;
	}
}
close IN;

# Set up a LoL with indexes, and ditch the values that represent NaN's
for ($i = 0; $i < $nds; $i++) {
	@{$dsi[$i]} = grep { ${$dsl[$i]}[$_] ne "NaN" } (0..$recno);
	print "$dsname[$i] has $#{$dsi[$i]} valid samples\n" if $debug;
}

sub sortit {
	${$dsl[$i]}[$a] <=> ${$dsl[$i]}[$b];
}
my %indexes;
for ($i = 0; $i < $nds; $i++) {
	next if ($#{$dsi[$i]} < $maxspike);
	@{$dsi[$i]} = sort sortit @{$dsi[$i]};
	@{$botindx[$i]} = @{$dsi[$i]};
	@{$topindx[$i]} = splice(@{$botindx[$i]}, -$maxspike);
	print "$dsname[$i] top $maxspike: ".join(' ', @{$topindx[$i]})."\n";
	for($j = 0; $j < $maxspike; $j++) {
		$indexes{${$topindx[$i]}[$j]} = 0 if
				!defined($indexes{${$topindx[$i]}[$j]});
		$indexes{${$topindx[$i]}[$j]}++;
		printf "%1.1e ", ${$dsl[$i]}[${$topindx[$i]}[$j]];
	}
	print "\n";
}

# Report on the hit rate of the records to be dumped, and a few for
# reference.
$j = 0;
my %ditch;
foreach $i (sort {$indexes{$b} <=> $indexes{$a}} keys %indexes) {
	print "Record index $i: $indexes{$i} hits\n";
	$ditch{$i} = 1 if $j < $cutoff;
	print "----------\n" if $j + 1 == $cutoff;
	last if $j++ > $maxspike;
}

# Okay, so we start ditching the records. You can always re-run the script
# if the results don't suit you after adjusting $cutoff or $maxspike.
$recno = -1;
open(IN, $file) || die;
open(OUT, ">$outfile") || die;
while(<IN>) {
	print OUT if !/<row>/;
	next if !/<row>/;
	$recno++;
	print OUT if !defined($ditch{$recno});
	next if !defined($ditch{$recno});
	my @data = split(/ /);
	for ($i = 0; $i < $nds; $i++) {
		$data[($i * 2) + 6] = "NaN";
	}
	print OUT join(' ', @data);
}
close IN;
close OUT;
