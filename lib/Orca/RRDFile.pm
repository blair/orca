# Orca::RRDFile: Manage RRD file creation and updating.
#
# Copyright (C) 1998, 1999 Blair Zajac and Yahoo!, Inc.

package Orca::RRDFile;

use strict;
use Carp;
use RRDs;
use Orca::Constants qw($opt_verbose
          	       $ORCA_RRD_VERSION
                       $incorrect_number_of_args
                       @RRA_PDP_COUNTS
                       @RRA_ROW_COUNTS);
use Orca::Config    qw(%config_options
                       %config_groups
                       @config_plots);
use Orca::Utils     qw(recursive_mkdir);
use vars            qw($VERSION);

$VERSION = substr q$Revision: 0.01 $, 10;

# Use a blessed reference to an array as the storage for this class.
# Define these constant subroutines as indexes into the array.  If the
# order of these indexes change, make sure to rearrange the
# constructor in new.
sub I_RRD_FILENAME     () { 0 }
sub I_NAME             () { 1 }
sub I_NEW_DATA         () { 2 }
sub I_CREATED_IMAGES   () { 3 }
sub I_PLOT_REF         () { 4 }
sub I_INTERVAL         () { 5 }
sub I_RRD_VERSION      () { 6 }
sub I_CHOOSE_DATA_SUBS () { 7 }
sub I_RRD_UPDATE_TIME  () { 8 }

sub new {
  unless (@_ == 5) {
    confess "$0: Orca::RRDFile::new $incorrect_number_of_args";
  }

  my ($class,
      $group_name,
      $subgroup_name,
      $name,
      $plot_ref) = @_;

  # Remove any special characters from the unique name and do some
  # replacements.
  $name = &::escape_name($name);

  # Create the paths to the data directory.
  my $rrd_dir = $config_options{rrd_dir};
  if ($config_groups{$group_name}{sub_dir}) {
    $rrd_dir .= "/$subgroup_name";
    unless (-d $rrd_dir) {
      warn "$0: making directory `$rrd_dir'.\n";
      recursive_mkdir($rrd_dir);
    }
  }
  my $rrd_filename = "$rrd_dir/$name.rrd";

  # Create the new object.
  my $self = bless [
    $rrd_filename,
    $name,
    {},
    {},
    $plot_ref,
    int($config_groups{$group_name}{interval}+0.5),
    $ORCA_RRD_VERSION,
    {},
    -2
  ], $class;

  # See if the RRD file meets two requirements. The first is to see if
  # the last update time can be sucessfully read.  The second is to
  # see if the RRD has an DS named "Orca$ORCA_RRD_VERSION".  If
  # neither one of these is true, then create a brand new RRD is
  # created when data is first flushed to it.
  if (-e $rrd_filename) {
    my $update_time = RRDs::last $rrd_filename;
    if (my $error = RRDs::error) {
      warn "$0: RRDs::last error: `$rrd_filename' $error\n";
    } else {
      if (open(RRDFILE, "<$rrd_filename")) {
        my $version = '';
        while (<RRDFILE>) {
          if (/Orca(\d{8})/) {
            $version = $1;
            last;
          }
        }
        close(RRDFILE) or
          warn "$0: error in closing `$rrd_filename' for reading: $!\n";

        # Compare the version number of file to the required version.
        if (length($version)) {
          if ($version >= $ORCA_RRD_VERSION) {
            $self->[I_RRD_UPDATE_TIME] = $update_time;
            $self->[I_RRD_VERSION]     = $version;
          } else {
            warn "$0: old version $version RRD `$rrd_filename' found: will create new version $ORCA_RRD_VERSION file.\n";
          }
        } else {
          warn "$0: unknown version RRD `$rrd_filename' found: will create new version $ORCA_RRD_VERSION file.\n";
        }
      }
    }
  }

  $self;
}

sub version {
  $_[0]->[I_RRD_VERSION];
}

sub filename {
  $_[0]->[I_RRD_FILENAME];
}

sub name {
  $_[0]->[I_NAME];
}

sub rrd_update_time {
  $_[0]->[I_RRD_UPDATE_TIME];
}

sub add_image {
  my ($self, $image) = @_;
  $self->[I_CREATED_IMAGES]{$image->name} = $image;
  $self;
}

sub created_images {
  values %{$_[0]->[I_CREATED_IMAGES]};
}

# Queue a list of (time, value) data pairs.  Return the number of data
# pairs sucessfully queued.
# Call:   $self->(unix_epoch_time1, value1, unix_epoch_time2, value2, ...);
sub queue_data {
  my $self = shift;

  my $count = 0;
  my $rrd_update_time = $self->[I_RRD_UPDATE_TIME];
  while (@_ > 1) {
    my ($time, $value) = splice(@_, 0, 2);
    next if $time <= $rrd_update_time;
    $self->[I_NEW_DATA]{$time} = $value;
    ++$count;
  }

  $count;
}

sub flush_data {
  my $self = shift;

  # Get the times of the new data to put into the RRD file.
  my @times = sort { $a <=> $b } keys %{$self->[I_NEW_DATA]};

  return unless @times;

  my $rrd_filename = $self->[I_RRD_FILENAME];

  # Create the Orca data file if it needs to be created.
  if ($self->[I_RRD_UPDATE_TIME] == -2) {

    # Assume that a maximum of two time intervals are needed before a
    # data source value is set to unknown.
    my $interval = $self->[I_INTERVAL];
   
    my $data_source = "DS:Orca$ORCA_RRD_VERSION:" .
                      $self->[I_PLOT_REF]{data_type};
    $data_source   .= sprintf ":%d:", 2*$interval;
    $data_source   .= $self->[I_PLOT_REF]{data_min} . ':';
    $data_source   .= $self->[I_PLOT_REF]{data_max};
    my @options = ($rrd_filename,
                   '-b', $times[0]-1,
                   '-s', $interval,
                   $data_source);

    # Create the round robin archives.  Take special care to not
    # create two RRA's with the same number of primary data points.
    # This can happen if the interval is equal to one of the
    # consoldated intervals.
    my $count          = int($RRA_ROW_COUNTS[0]*300.0/$interval + 0.5);
    my @one_pdp_option = ("RRA:AVERAGE:0.5:1:$count");

    for (my $i=1; $i<@RRA_PDP_COUNTS; ++$i) {
      next if $interval > 300*$RRA_PDP_COUNTS[$i];
      my $rra_pdp_count = int($RRA_PDP_COUNTS[$i]*300.0/$interval + 0.5);
      if (@one_pdp_option and $rra_pdp_count != 1) {
        push(@options, @one_pdp_option);
      }
      @one_pdp_option = ();
      push(@options, "RRA:AVERAGE:0.5:$rra_pdp_count:$RRA_ROW_COUNTS[$i]");
    }

    # Now do the actual creation.
    if ($opt_verbose) {
      print "  Creating RRD `$rrd_filename'";
      if ($opt_verbose > 2) {
        print " with options ", join(' ', @options[1..$#options]);
      }
      print ".\n";
    }
    RRDs::create @options;

    if (my $error = RRDs::error) {
      warn "$0: RRDs::create error: `$rrd_filename' $error\n";
      return;
    }
  }

  # Flush all of the stored data into the RRD file.
  my @options;
  my $old_rrd_update_time = $self->[I_RRD_UPDATE_TIME];
  foreach my $time (@times) {
    push(@options, "$time:" . $self->[I_NEW_DATA]{$time});
  }
  RRDs::update $rrd_filename, @options;
  my $ok = 1;
  if (my $error = RRDs::error) {
    warn "$0: warning: cannot put data starting at ",
         scalar localtime($times[0]),
         " ($times[0]) into `$rrd_filename': $error\n";
    return 0;
  }

  # If there were no errors, then totally clear the hash to save
  # memory.
  undef $self->[I_NEW_DATA];
  $self->[I_NEW_DATA] = {};

  $self->[I_RRD_UPDATE_TIME] = $times[-1];

  1;
}

1;
