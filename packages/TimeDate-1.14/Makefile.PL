# This -*- perl -*- script makes the Makefile
# $Id: //depot/TimeDate/Makefile.PL#4 $

#--- Distribution section ---

$DISTNAME = 'TimeDate';
$VERSION  = "1.10";

#--- Write the Makefile

BEGIN { require 5.002 }

use ExtUtils::MakeMaker;

my @ppd;

if ($] >= 5.00503) {
  @ppd = (
    AUTHOR    => 'Graham Barr <gbarr@pobox.com>',
    ABSTRACT  => 'Formatting and Parsing of Time and Date'
  );
}

sub MY::postamble {

  return '' unless $] >= 5.00503;

<<'ESQ';

dist : ppd

ESQ
}

WriteMakefile(
	VERSION   => $VERSION,
	NAME      => $DISTNAME,
	@ppd
);


