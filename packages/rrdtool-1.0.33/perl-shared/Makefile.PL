use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

# Specify the location of the archive containing PIC compiled object files.
my $librrd = -f "../src/.libs/librrd_private.a" ? '../src/.libs/librrd_private.a' : '../src/.libs/librrd_private.al'  ;

WriteMakefile(
    'NAME'         => 'RRDs',
    'VERSION_FROM' => 'RRDs.pm', # finds $VERSION
    'OPTIMIZE'     => '-g',
    'INC'          => '-I../src -I../gd1.3',
    # where to look for the necessary libraries 
    # Perl will figure out which one is valid
    'depend'	   => {'RRDs.c' => $librrd},
    'dynamic_lib'  => {'OTHERLDFLAGS' => "$librrd -lm"},
    'realclean'    => {FILES => 't/demo?.rrd t/demo?.gif' }
);
