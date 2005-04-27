#! /usr/bin/perl
#
# rrdlastds - report the latest DS values from the RRA with
# the shortest time resolution
#
# steve rader
# <rader@wiscnet.net>
# Jan 8th, 2000
#
# $Id: rrdlastds.pl.in,v 1.1.1.1 2002/02/26 10:21:19 oetiker Exp $
#

#makes things work when run without install
use lib qw( ../../perl-shared/blib/lib ../../perl-shared/blib/arch );
# this is for after install
use lib qw( /usr/local/rrdtool-1.0.50/lib/perl ../lib/perl );

use RRDs;

%scale_symbols = qw( -18 a -15 f -12 p -9 n -6 u -3 m 
  3 k 6 M 9 G 12 T 15 P 18 E );

#----------------------------------------

while ( $ARGV[0] =~ /^-/ ) {
  switch: {
    if ( $ARGV[0] eq '--autoscale' || $ARGV[0] =~ /^-a/ ) {
      $scale = 1;
      last switch;
    }
    if ( $ARGV[0] eq '--conversion' || $ARGV[0] =~ /^-c/ ) {
      shift @ARGV;
      $conversion = $ARGV[0];
      if ( $conversion !~ /^\d+$|^\d+\.\d+$|^\.\d+$/ ) {
        print "rrdlastds: bad conversion factor \"$conversion\"\n";
        exit 1;
      }
      last switch;
    }
    if ( $ARGV[0] eq '--label' || $ARGV[0] =~ /^-l/ ) {
      shift @ARGV;
      $label = $ARGV[0];
      last switch;
    }
    if ( $ARGV[0] eq '--start' || $ARGV[0] =~ /^-s/ ) {
      shift @ARGV;
      $start = $ARGV[0]; 
      if ( $start =~ /^\d+$/ ) {
        $end = $start+1;
      } else {
        $end = "${start}+1sec";
      }
      last switch;
    }
    if ( $ARGV[0] eq '--verbose' || $ARGV[0] =~ /^-v/ ) {
      $verbose = 1;
      last switch;
    }
    if ( $ARGV[0] eq '--debug' || $ARGV[0] =~ /^-d/ ) {
      $debug = 1;
      last switch;
    }
    print "rrdlastds: unknown option \"$ARGV[0]\"\n";
    exit 1;
  }
  shift @ARGV;
}

if ( $#ARGV != 0 ) {
  print <<_EOT_;
usage: rrdlastds [-v] [-a] [-c num] [-l label] [-s stamp] some.rrd
  -v        print the start and end times (also --verbose)
  -a        autoscale DS values (also --autoscale)
  -c num    convert DS values by "num" (also --conversion)
  -l label  label DS values with "label" (also --label)
  -s time   report about DS values at the time "time" (also --start)

  The -s option supports the traditional "seconds since the Unix epoch"
  and the AT-STYLE time specification (see man rrdfetch)
_EOT_
  exit 1;
}

if ( ! -f "$ARGV[0]" ) {
  print "rrdlastds: can't find \"$ARGV[0]\"\n";
  exit 1;
} 

#----------------------------------------

if ( $start ) {
  @fetch = ("$ARGV[0]", "-s", "$start", "-e", "$end", "AVERAGE");
} else {
  @fetch = ("$ARGV[0]", "-s", "-1sec", "AVERAGE");
}
if ( $debug ) {
  print "rrdfetch ", join(' ',@fetch), "\n";
}

($start,$step,$names,$data) = RRDs::fetch @fetch;

if ( $error = RRDs::error ) {
  print "rrdlastds: rrdtool fetch failed: \"$error\"\n";
  exit 1;
}

#----------------------------------------

if ( $debug ) {
  $d_start = $start;
  print "Start:       ", scalar localtime($d_start), " ($d_start)\n";
  print "Step size:   $step seconds\n";
  print "DS names:    ", join (", ", @$names)."\n";
  print "Data points: ", $#$data + 1, "\n";
  print "Data:\n";
  foreach $line (@$data) {
    print "  ", scalar localtime($d_start), " ($d_start) ";
    $d_start += $step;
    foreach $val (@$line) {
      printf "%12.1f ", $val;
    }
    print "\n";
  }
  print "\n";
}
   
#----------------------------------------

if ( $verbose ) {
  print scalar localtime($start), ' through ', 
    scalar localtime($start+$step), "\naverage";
} else {
  print scalar localtime($start);
}

$line = $$data[0];
for $i (0 .. $#$names) {
  if ( $conversion ) {
    $$line[$i] = $$line[$i] * $conversion;
  }
  if ( $scale ) {
    ($val, $units) = autoscale($$line[$i]);
  } else {
    $val = $$line[$i];
  }
  printf "  %.2f$units$label %s", $val, $$names[$i];
}
print "\n";

exit 0;

#==================================================================

sub autoscale {
  local($value) = @_;
  local($floor, $mag, $index, $symbol, $new_value);

  if ( $value =~ /^\s*[0]+\s*$/ || 
       $value =~ /^\s*[0]+.[0]+\s*$/ || 
       $value =~ /^\s*NaN\s*$/ ) {
    return $value, ' ';
  }

  $floor = &floor($value);
  $mag = int($floor/3);
  $index = $mag * 3;
  $symbol = $scale_symbols{$index};
  $new_value = $value / (10 ** $index);
  return $new_value, " $symbol";
}

#------------------------------------------------------------------

sub floor {
  local($value) = @_;
  local($i) = 0;

  if ( $value > 1.0 ) {
    # scale downward...
    while ( $value > 10.0 ) {
      $i++;
      $value /= 10.0;
    }
  } else {
    while ( $value < 10.0 ) {
      $i--;
      $value *= 10.0;
    }
  }
  return $i;
}

