#! /usr/bin/perl
#
# Log 2 RRD.  This script translates a MRTG 2.x log file
# into a RRD archive.  The original version was written by
# Wrolf Courtney <wrolf@concentric.net> and
# Russ Wright <wright@LBL.Gov> with an early test version
# of RRDTOOL (mrtg-19980526.08) and has been modified to match
# the parameters of rrdtool version 99.23 by Alan Lichty at
# Electric Lightwave, Inc. <alichty@eli.net>.
#
# this script optimized for being called up by another script
# that cycles through a list of routers and invokes this for each
# interface.  It can be run just as easily from a command line for
# small numbers of logfiles.
#
# The RRD we create looks like the following:  Note
# that we have to use type GAUGE in order to have RRDTOOL
# populate the new rr archive correctly.  Otherwise RRDTOOL will try 
# to interpet the data as new octet counts instead of existing
# data rate averages.
#
# DS:GAUGE:86400:U:U	        # in counter
# DS:GAUGE:86400:U:U	        # out counter
# RRA:AVERAGE:0.5:1:600	        # 5 minute samples
# RRA:MAX:0.5:1:600		# 5 minute samples
# RRA:AVERAGE:0.5:6:600	        # 30 minute samples
# RRA:MAX:0.5:6:600		# 30 minute samples
# RRA:AVERAGE:0.5:24:600	        # 2 hour samples
# RRA:MAX:0.5:24:600		# 2 hour samples
# RRA:AVERAGE:0.5:288:732	# 1 day samples
# RRA:MAX:0.5:288:732            # 1 day samples
#
# 

use English;
use strict;

require "ctime.pl";

use RRDs;

my $DEBUG=0;

&main;

sub main {

    my($inBytes, $outBytes);
    my($lastRunDate, $firstRunDate);
    my($i, $dataFile, $firstRun);
    my($oldestRun, $lastRun);
    my($curTime, $oldestTime, $totRec);
    my($avgIn, $avgOut, $maxIn, $maxOut);
    my(@lines, @finalRecs);
    my($RRD, $START, $destDir, $dsType);

#
# get the logfile name to process
# the default is to strip out the .log extension and create
# a new file with the extension .rrd
#

    $dataFile=$ARGV[0];

    $destDir = $ARGV[1];

#
# strip off .log from file name - complain and die if no .log
# in the filename
#

    if ($dataFile =~ /(.*)\.log$/) {
	$RRD = "$1";
    }

    if ($RRD eq "") {
	printf("Usage: log2rrd [log file] [destination dir]\n");
	exit;
    }

#
# strip out path info (if present) to get at just the filename
#

    if ($RRD =~ /(.*)\/(.*)$/){
	$RRD = "$2";
    }

#
# add the destination path (if present) and .rrd suffix
#

    if ($destDir){
	$RRD = "$destDir/$RRD.rrd";

    }else{
	$RRD = "$RRD.rrd";
    }

    open(IN,"$dataFile") || die ("Couldn't open $dataFile");

#
# Get first line - has most current sample
#

    $_ = <IN>;
    chop;
    ($lastRun, $inBytes, $outBytes) = split;
    $lastRunDate = &ctime($lastRun);
    chop $lastRunDate;

    $firstRun = $lastRun;
    $i=2;

#
# start w/line 2 and read them into the lines array
# (2nd line is in position 2)
#
    while (<IN>) {
	chop;
	$lines[$i++] = $_;
	($curTime) = split;
	if ($curTime < $firstRun) {
	    $firstRun = $curTime;
	}
    }
    close(IN);

#
#  Let's say source start time is 5 minutes before 1st sample
#

    $START=$firstRun - 300;
    print STDERR "\$START = $START\n" if $DEBUG>1;

    $firstRunDate = &ctime($firstRun);
    chop $firstRunDate;

    printf("Data from $firstRunDate\n       to $lastRunDate\n") if $DEBUG>0;

    $oldestTime=$lastRun;
#
# OK- sort through the data and put it in a new array.
# This gives us a chance to find errors in the log files and
# handles any overlap of data (there shouldn't be any)
#
# NOTE: We start w/ record # 3, not #2 since #2 could be partial
#

    for ($i=3; $i <= 2533; $i++) {

	($curTime, $avgIn, $avgOut, $maxIn, $maxOut) = split(/\s+/, $lines[$i]);

	if ($curTime < $oldestTime) {

#
# only add data if older than anything already in array
# this should always be true, just checking
#

	    $oldestTime = $curTime;
	    $finalRecs[$totRec++]=$lines[$i];
	}
    }


    PopulateRRD($totRec, $RRD, $START, \@finalRecs);

#
# if you know that most of your MRTG logfiles are using
# counter data, uncomment the following lines to automatically
# run rrdtune and change the data type.
#
#    my(@tuneparams) = ("$RRD", "-d", "ds0:COUNTER", "-d", "ds1:COUNTER");
#    RRDs::tune(@tuneparams);


}

sub PopulateRRD {

    my($totRec, $RRD, $START, $finalRecs) = @_;
    my($i, $curTime, $avgIn, $avgOut, $maxIn, $maxOut);
    my($saveReal, $line);
    my($createret, $updret);

    print "* Creating RRD $RRD\n\n" if $DEBUG>0;

#
# We'll create RRAs for both AVG and MAX. MAX isn't currently filled but 
# may be later
#

    RRDs::create ("$RRD", "-b", $START, "-s", 300,
    "DS:ds0:GAUGE:86400:U:U",
    "DS:ds1:GAUGE:86400:U:U",
    "RRA:AVERAGE:0.5:1:600",
    "RRA:MAX:0.5:1:600",
    "RRA:AVERAGE:0.5:6:600",
    "RRA:MAX:0.5:6:600",
    "RRA:AVERAGE:0.5:24:600",
    "RRA:MAX:0.5:24:600",
    "RRA:AVERAGE:0.5:288:600",
    "RRA:MAX:0.5:288:600");

    if (my $error = RRDs::error()) {
	print "Cannot create $RRD: $error\n";
    }


    print "* Adding entries to $RRD\n\n" if $DEBUG>0;

    for ($i=$totRec - 1; $i >= 0; $i--) {

	($curTime, $avgIn, $avgOut, $maxIn, $maxOut) = split(/\s+/, @$finalRecs[$i]);

        RRDs::update ("$RRD", "$curTime:$avgIn:$avgOut");

	if (my $error = RRDs::error()) {
	    print "Cannot update $RRD: $error\n";
	}

  
# NOTE: Need to add checking on RRDread and include the Max values
# print status every now and then
#	print $i if $i % 25 && $DEBUG>0;
#	print "$i\n";

    }

}
