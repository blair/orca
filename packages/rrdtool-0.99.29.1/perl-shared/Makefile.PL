use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'         => 'RRDs',
    'VERSION_FROM' => 'RRDs.pm', # finds $VERSION
    'OPTIMIZE'     => '-g',
    'INC'          => '-I../src/',
    # where to look for the necessary libraries 
    # Perl will figure out which one is valid
    'LIBS'         => [ '-L../src -lrrd  -L../gd1.2 -lgd -lm' ],
    'realclean'    => {FILES => 't/demo?.rrd t/demo?.gif' }
);
