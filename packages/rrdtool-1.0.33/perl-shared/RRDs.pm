package RRDs;

use strict;
use vars qw(@ISA $VERSION);

@ISA = qw(DynaLoader);

require DynaLoader;

$VERSION = 1.000131;

bootstrap RRDs $VERSION;

1;
__END__

=head1 NAME

RRDs - Access rrdtool as a shared module

=head1 SYNOPSIS

  use RRDs;
  RRDs::error
  RRDs::last ...
  RRDs::create ...
  RRDs::update ...
  RRDs::graph ...
  RRDs::fetch ...
  RRDs::tune ...

=head1 DESCRIPTION

=head2 Calling Sequence

This module accesses rrdtool functionality directly from within perl. The
arguments to the functions listed in the SYNOPSIS are explained in the regular
rrdtool documentation. The commandline call

 rrdtool update mydemo.rrd N:12:13

gets turned into

 RRDs::update ("mydemo.rrd", "N:12:13");

=head2 Error Handling

The RRD functions will not abort your program even when they can not make
sense out of the arguments you fed them. There are two ways to determine if
an error has occured.

First the every function will return the value -1 if an error occured.
Second, the function RRDs::error can be called to get the error message
from the last function call. If RRDs::error does not return an error
then the previous function has completed its task succesfully.

 use RRDs;
 RRDs::update ("mydemo.rrd","N:12:13");
 my $ERR=RRDs::error;
 die "ERROR while updating mydemo.rrd: $ERR\n" if $ERR;

=head2 Return Values

The functions RRDs::last, RRDs::graph and RRDs::fetch return their
findings.

RRDs::last returns a single INTEGER representing the last update time.

 $lastupdate = RRDs::last ...

RRDs::graph returns an pointer to an ARRAY containing the x-size and y-size of the
created gif and results of the PRINT arguments.

 ($averages,$xsize,$ysize) = RRDs::graph ...
 print "Gifsize: ${xsize}x${ysize}\n";
 print "Averages: ", (join ", ", @$averages);

RRDs::fetch is the most complex of the pack regarding return values. There are
4 values. Two normal integers, a pointer to an array and a pointer to a
array of pointers.

  my ($start,$step,$names,$data) = RRDs::fetch ... 
  print "Start:       ", scalar localtime($start), " ($start)\n";
  print "Step size:   $step seconds\n";
  print "DS names:    ", join (", ", @$names)."\n";
  print "Data points: ", $#$data + 1, "\n";
  print "Data:\n";
  foreach my $line (@$data) {
    print "  ", scalar localtime($start), " ($start) ";
    $start += $step;
    foreach my $val (@$line) {
      printf "%12.1f ", $val;
    }
    print "\n";
  }

See the examples directory for more ways to use this extension.

=head1 AUTHOR

Tobias Oetiker <oeitker@ee.ethy.ch>

=cut
