# This -*- perl -*- script writes the Makefile for this package.

use strict;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
  'NAME'		=> 'Math::Interpolate',
  'VERSION_FROM'	=> 'lib/Math/Interpolate.pm', # finds $VERSION
);
