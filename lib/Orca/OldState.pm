# Orca::OldState: Keep state information between invocations of Orca.
#
# Copyright (C) 1998-1999 Blair Zajac and Yahoo!, Inc.
# Copyright (C) 1999-2002 Blair Zajac.

package Orca::OldState;

use strict;
use Carp;
use Orca::Constants     qw($opt_verbose
                           $INCORRECT_NUMBER_OF_ARGS);
use Orca::SourceFileIDs qw(@sfile_fids);
use vars                qw(@EXPORT_OK @ISA $VERSION);

@ISA     = qw(Exporter);
$VERSION = substr q$Revision: 0.01 $, 10;

# Create one global state object for the whole program.
use vars          qw($orca_old_state);
@EXPORT_OK      = qw($orca_old_state load_old_state save_old_state);
$orca_old_state = {};

# If this string appears in the beginning of the first column
# description name, then it signifies that the text following the
# string is the filename that contains a column description that this
# particular file should use.
my $refer_to_filename_marker = 'USETHISFILE';

# This loads the old source file state information.
sub load_old_state {
  unless (@_ == 1) {
    confess "$0: Orca::OldState::load_old_state $INCORRECT_NUMBER_OF_ARGS";
  }

  my $state_file = shift;

  unless (open(STATE, $state_file)) {
    warn "$0: warning: cannot open state file `$state_file' for reading: $!\n";
    return;
  }

  print "Loading state from `$state_file'.\n" if $opt_verbose;

  # Get the first line which contains the hash key name.  Check that
  # the first field is _filename.
  my $line = <STATE>;
  defined($line) or return;
  chomp($line);
  my @keys = split(' ', $line);
  unless ($keys[0] eq '_filename') {
    warn "$0: warning: ignoring state file `$state_file': incorrect first field.\n";
    return;
  }

  my %file_column_descriptions;

  while (<STATE>) {
    my @line = split;
    if (@line != 3 && @line < 8) {
      warn "$0: incorrect number of elements on line $. of `$state_file'.\n";
      next;
    }

    my $filename  = shift(@line);
    my @stat_info;
    if (@line == 2) {
      @stat_info = (@line, -1, -1, -1, -1, undef);
    } else {
      @stat_info = splice(@line, 0, 6);
      if ($line[0] =~ s/^$refer_to_filename_marker//o) {
        push(@stat_info, $file_column_descriptions{$line[0]});
      } else {
        $file_column_descriptions{$filename} = \@line;
        push(@stat_info, \@line);
      }
    }
    $orca_old_state->{$filename} = \@stat_info;
  }

  close(STATE) or
    warn "$0: warning: cannot close `$state_file' for reading: $!\n";

  1;
}

# Write the state information for the source data files.
sub save_old_state {
  unless (@_ == 2) {
    confess "$0: Orca::OldState::save_old_state $INCORRECT_NUMBER_OF_ARGS";
  }

  my ($state_file, $state_ref) = @_;

  print "Saving state into `$state_file'.\n" if $opt_verbose;

  if (open(STATE, "> $state_file.tmp")) {

    print STATE "_filename _last_data_time _last_read_time\n";

    my %file_column_descriptions;

    foreach my $fid (keys %$state_ref) {
      my $object_ref = $state_ref->{$fid};
      my $filename   = $sfile_fids[$fid];
      print STATE
        "$filename ",
        $object_ref->[&Orca::SourceFile::I_LAST_DATA_TIME], ' ',
        $object_ref->[&Orca::SourceFile::I_LAST_READ_TIME], ' ',
        $object_ref->[&Orca::DataFile::I_FILE_DEV], ' ',
        $object_ref->[&Orca::DataFile::I_FILE_INO], ' ',
        $object_ref->[&Orca::DataFile::I_FILE_SIZE], ' ',
        $object_ref->[&Orca::DataFile::I_FILE_MTIME];
        my $column_ref = $object_ref->[&Orca::SourceFile::I_COLUMN_DESCRIPTION];
        if (my $f = $file_column_descriptions{"$column_ref"}) {
          print STATE " $refer_to_filename_marker$f\n";
        } else {
          print STATE " @$column_ref\n";
          $file_column_descriptions{"$column_ref"} = $filename;
        }
    }

    if (close(STATE)) {
      unless (rename("$state_file.tmp", $state_file)) {
        my $print_warning = 1;
        if (-e $state_file) {
          if (unlink($state_file)) {
            $print_warning = !rename("$state_file.tmp", $state_file);
          } else {
            $print_warning = 0;
            warn "$0: warning: cannot unlink old `$state_file': $!\n";
          }
        }
        if ($print_warning) {
          warn "$0: warning: cannot rename `$state_file.tmp' to `$state_file': $!\n";
        }
      }
    } else {
      warn "$0: warning: cannot close `$state_file' for writing: $!\n";
    }
  } else {
    warn "$0: warning: cannot open state file `$state_file.tmp' for writing: $!\n";
  }
}

1;
