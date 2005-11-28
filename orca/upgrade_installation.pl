# upgrade_installation: Upgrade and rename any files to the latest
# installation of Orca:
#
# 1) Migrate from a percollator named installation to orcallator.
# 2) Rename all files with * in them to _times_.
#
# $HeadURL$
# $LastChangedRevision$
# $LastChangedDate$
# $LastChangedBy$
#
# Copyright (C) 1999 Blair Zajac and GeoCities, Inc.
# Copyright (C) 1999-2005 Blair Zajac.
#
# This file is part of Orca.
#
# Orca is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# Orca is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
# License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Orca in the COPYING-GPL file; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
# 02111-1307 USA

use strict;
use File::Find;

$| = 1;

# Check if there is an argument -n, in which case the rename will be
# shown but not done.
my $rename = 1;
if (@ARGV and $ARGV[0] eq '-n') {
  $rename = 0;
  shift;
}

# Take a list of directories and rename every file in the directory using
# the following translation in the following order:
#   percollator -> orcallator
#   percol      -> orcallator
#   perc        -> orcallator
# Protect the word percent from this conversion.
foreach my $dir (@ARGV) {
  finddepth(\&rename, $dir) if -d $dir;
}

sub rename {
  my $old_name = $_;
  my $new_name = $_;
  $new_name =~ s:percent:\200:g;
  $new_name =~ s:percollator:orcallator:g;
  $new_name =~ s:percol:orcallator:g;
  $new_name =~ s:perc:orcallator:g;
  $new_name =~ s:_{2,}:_:g;
  $new_name =~ s:\200:percent:g;

  # This name change was released between 0.23 and 0.24.
  $new_name =~ s:\*:_times_:g;

  # These are the final 0.24 names.
  $new_name =~ s:_percent([\W_]):_pct$1:g;
  $new_name =~ s:_number([\W_]):_num$1:g;
  $new_name =~ s:_times([\W_]):_X$1:g;

  # Be careful not to rename filenames exactly named orcallator or orca.
  $new_name =~ s:orcallator_:o_:g;
  $new_name =~ s:orca_:o_:g;

  if ($old_name ne $new_name) {
    print "$File::Find::name -> $new_name\n";
    if ($rename) {
      rename($old_name, $new_name) or
        warn "$0: cannot rename $old_name: $!\n";
    }
  }
}
