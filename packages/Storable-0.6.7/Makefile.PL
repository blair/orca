# $Id: Makefile.PL,v 0.6 1998/06/04 16:08:18 ram Exp $
#
#  Copyright (c) 1995-1998, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# $Log: Makefile.PL,v $
# Revision 0.6  1998/06/04 16:08:18  ram
# Baseline for first beta release.
#

use ExtUtils::MakeMaker;
use Config;

WriteMakefile(
    'NAME'			=> 'Storable',
    'DISTNAME'		=> "Storable",
    'VERSION_FROM'	=> 'Storable.pm',
    'dist'			=> { SUFFIX => 'gz', COMPRESS => 'gzip -f' },
    'clean'			=> {'FILES' => '*%'},
);

