# migrate_to_orcallator: migrate from a percollator named installation to
# an orcallator named install.
#
# Copyright (C) 1999 Blair Zajac and GeoCities, Inc.

use strict;
use File::Find;

$| = 1;

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
  $new_name =~ s/percent/\200/g;
  $new_name =~ s/percollator/orcallator/g;
  $new_name =~ s/percol/orcallator/g;
  $new_name =~ s/perc/orcallator/g;
  $new_name =~ s/\200/percent/g;
  if ($old_name ne $new_name) {
    print "Renaming $File::Find::dir/$old_name\n";
    rename("$File::Find::dir/$old_name", "$File::Find::dir/$new_name") or
      warn "$0: cannot rename `$File::Find::dir/$old_name': $!\n";
  }
}
