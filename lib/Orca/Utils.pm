# Orca::Utils: Small utility subroutines.
#
# Copyright (C) 1998, 1999 Blair Zajac and Yahoo!, Inc.

package Orca::Utils;

use strict;
use Carp;
use Exporter;
use Orca::Constants     qw($incorrect_number_of_args);
use Orca::SourceFileIDs qw(new_fids);
use vars qw(@EXPORT_OK @ISA $VERSION);

@EXPORT_OK = qw(gcd perl_glob recursive_mkdir unique);
@ISA       = qw(Exporter);
$VERSION   = substr q$Revision: 0.01 $, 10;

# Return the greatest common divisor.
sub gcd {
  unless (@_ == 2) {
    confess "$0: Orca::Utils::gcd $incorrect_number_of_args";
  }
  my ($m, $n) = @_;
  if ($n > $m) {
    my $tmp = $n;
    $n = $m;
    $m = $tmp;
  }
  while (my $r = $m % $n) {
    $m = $n;
    $n = $r;
  }
  $n;
}

# Find all files matching a particular Perl regular expression and
# return file ids.
sub perl_glob {
  my $regexp = shift;

  # perl_glob gets called recursively.  To tell if we're being called by
  # perl_glob, look for the existence of two arguments, where the second
  # one if the current directory to open for matching.
  my $current_dir = @_ ? $_[0] : '.';

  # Remove all multiple /'s, since they will confuse perl_glob.
  $regexp =~ s:/{2,}:/:g;

  # If the regular expression begins with a /, then remove it from the
  # regular expression and set the current directory to /.
  $current_dir = '/' if $regexp =~ s:^/::;

  # Get the first file path element from the regular expression to
  # match.
  my @regexp_elements = split(m:/:, $regexp);
  my $first_regexp    = shift(@regexp_elements);

  # Find all of the files in the current directory that match the
  # first regular expression.
  unless (opendir(GLOB_DIR, "$current_dir")) {
    warn "$0: error: cannot opendir `$current_dir': $!\n";
    return ();
  }

  my @matches = grep { /^$first_regexp$/ } readdir(GLOB_DIR);

  closedir(GLOB_DIR) or
    warn "$0: warning: cannot closedir `$current_dir': $!\n";

  # If the last path element is being used as the regular expression,
  # then just return the list of matching files with the current
  # directory prepended.
  unless (@regexp_elements) {
    @matches = grep { -f $_ and -r _ } map { "$current_dir/$_" } @matches;
    return @_ ? @matches : new_fids(@matches);
  }

  # Otherwise we need to look into the directories below the current
  # directory.  Also create the next regular expression to use that is
  # made up of the remaining file path elements.  Make sure not to
  # process any directories named `..'.
  my @results;
  my $new_regexp = join('/', @regexp_elements);
  foreach my $new_dir (grep { $_ ne '..' and -d "$current_dir/$_" } @matches) {
    my $new_current = "$current_dir/$new_dir";
    $new_current =~ s:/{2,}:/:g;
    push(@results, perl_glob($new_regexp, $new_current));
  }

  return @_ ? @results : new_fids(@results);
}

# Given a directory name, attempt to make all necessary directories.
sub recursive_mkdir {
  my $dir = shift;

  # Remove extra /'s.
  $dir =~ s:/{2,}:/:g;

  my $path;
  if ($dir =~ m:^/:) {
    $path = '/';
  } else {
    $path = './';
  }

  my @elements = split(/\//, $dir);
  foreach my $element (@elements) {
    $path = "$path/$element";
    next if -d $path;
    unless (mkdir($path, 0755)) {
      die "$0: error: unable to create `$path': $!\n";
    }
  }
}

# Return a list of the unique elements of a list in the same order as
# they appear in the input list.
sub unique {
  my %a;
  my @unique;
  foreach my $element (@_) {
    unless (exists $a{$element}) {
      push(@unique, $element);
      $a{$element} = 1;
    }
  }
  @unique;
}

1;
