# Orca::ImageFile: Manage the creation of PNG or GIF plot files.
#
# Copyright (C) 1998-1999 Blair Zajac and Yahoo!, Inc.
# Copyright (C) 1999-2004 Blair Zajac.

package Orca::ImageFile;

use strict;
use Carp;
use RRDs;
use Orca::Constants qw($opt_generate_gifs
                       $opt_verbose
                       $IMAGE_SUFFIX
                       @IMAGE_PLOT_TYPES
                       @IMAGE_PDP_COUNTS
                       @IMAGE_TIME_SPAN
                       $MAX_PLOT_TYPE_LENGTH
                       $INCORRECT_NUMBER_OF_ARGS);
use Orca::Config    qw(%config_global
                       @config_groups
                       @config_plots);
use Orca::Utils     qw(name_to_fsname recursive_mkdir);

use vars            qw($VERSION);

$VERSION = substr q$Revision: 0.01 $, 10;

# Use a blessed reference to an array as the storage for this class.
# Define these constant subroutines as indexes into the array.  If
# the order of these indexes change, make sure to rearrange the
# constructor in new.
sub I_GROUP_INDEX      () {  0 }
sub I_SUBGROUP_NAME    () {  1 }
sub I_NO_SUBGROUP_NAME () {  2 }
sub I_NAME             () {  3 }
sub I_IMAGE_BASENAME   () {  4 }
sub I_ALL_RRD_REF      () {  5 }
sub I_MY_RRD_LIST      () {  6 }
sub I_PLOT_REF         () {  7 }
sub I_IMAGE_HEIGHT     () {  8 }
sub I_IMAGE_WIDTH      () {  9 }
sub I_GRAPH_OPTIONS    () { 10 }
sub I_UPDATE_TIME_BASE () { 11 }
sub I_PLOT_AGE_BASE    () { I_UPDATE_TIME_BASE + @IMAGE_PLOT_TYPES }
sub I_PLOT_LEGEND_BASE () { I_PLOT_AGE_BASE + @IMAGE_PLOT_TYPES }

sub new {
  unless (@_ == 8) {
    confess "$0: Orca::ImageFile::new $INCORRECT_NUMBER_OF_ARGS";
  }

  my ($class,
      $group_index,
      $subgroup_name,
      $name,
      $no_subgroup_name,
      $plot_ref,
      $rrd_data_files_ref,
      $my_rrds_ref) = @_;

  unless (@$my_rrds_ref) {
    confess "$0: Orca::ImageFile::new passed empty \@rrds_ref reference.\n";
  }
  unless ($name) {
    confess "$0: Orca::ImageFile::new passed empty \$name.\n";
  }

  # Remove any special characters from the unique name and do some
  # replacements.  Leave space at the end of the name to append a
  # string of the form '-daily.png' and optionally '.meta' if the
  # configuration file specifies that images should be expired.
  my $max_length = $MAX_PLOT_TYPE_LENGTH + 2 + length($IMAGE_SUFFIX);
  if ($config_global{expire_images}) {
    $max_length += 5;
  }
  $name = name_to_fsname($name, $max_length);

  # Create the paths to the html directory and subdirectories.
  my $html_dir     = "$config_global{html_dir}/$subgroup_name";

  # Create the html_dir directories if necessary.
  unless (-d $html_dir) {
    warn "$0: making directory '$html_dir'.\n";
    recursive_mkdir($html_dir);
  }
  my $image_basename = "$html_dir/$name";

  # Create the new object.
  my $self = bless [
    $group_index,
    $subgroup_name,
    $no_subgroup_name,
    $name,
    $image_basename,
    $rrd_data_files_ref,
    [ &::unique(@$my_rrds_ref) ],
    $plot_ref,
    0,
    0,
    []
  ], $class;

  my $plot_end_time = $self->plot_end_time;
  my $interval      = int($config_groups[$group_index]{interval}+0.5);
  for (my $i=0; $i<@IMAGE_PLOT_TYPES; ++$i) {
    # Load the data that helps this class determine if a particular
    # image file, such as the daily image, is current or needs to be
    # created or recreated.  The data saved is the Unix epoch file
    # modification time.  If the file does not exist or the file
    # modification time is newer than the time of te last data point
    # entered, then save a file modification time of -1 which will
    # definitely cause the image to be recreated.
    my $plot_type = $IMAGE_PLOT_TYPES[$i];
    my @stat      = stat("$image_basename-$plot_type.$IMAGE_SUFFIX");
    if (@stat and $stat[9] <= $plot_end_time) {
      $self->[I_UPDATE_TIME_BASE+$i] = $stat[9];
    } else {
      $self->[I_UPDATE_TIME_BASE+$i] = -1;
    }

    # Calculate how old this plot must be before it is recreated.
    my $image_pdp_count = int($IMAGE_PDP_COUNTS[$i]*300.0/$interval + 0.5);
    $image_pdp_count    = 1 if $image_pdp_count < 1;
    $self->[I_PLOT_AGE_BASE+$i] = $image_pdp_count*$interval;

    # Generate the unique plot title cotaining the period title for this
    # plot.
    $self->[I_PLOT_LEGEND_BASE+$i] =
      &::capatialize($plot_type) .
      ' ' .
      ::replace_subgroup_name($plot_ref->{title}, $subgroup_name);
  }

  $self->_update_graph_options;
}

sub _update_graph_options {
  my $self = shift;

  my $plot_ref      = $self->[I_PLOT_REF];
  my $subgroup_name = $self->[I_SUBGROUP_NAME];

  # Create the options for RRDs::graph that do not change across any
  # invocations of RRDs::graph.
  my @options = (
    '-v', ::replace_subgroup_name($plot_ref->{y_legend}, $subgroup_name),
    '-b', $plot_ref->{base}
  );

  # Add the lower-limit and upper-limit flags if defined.
  if (defined $plot_ref->{plot_min}) {
    push(@options, '-l', $plot_ref->{plot_min});
  }
  if (defined $plot_ref->{plot_max}) {
    push(@options, '-u', $plot_ref->{plot_max});
  }
  if (defined $plot_ref->{rigid_min_max}) {
    push(@options, '-r');
  }
  if (defined $plot_ref->{logarithmic}) {
    push(@options, '-o');
  }

  # By default create PNG files.
  unless ($opt_generate_gifs) {
    push(@options, '-a', 'PNG');
  }

  my $data_sources = @{$self->[I_MY_RRD_LIST]};
  for (my $i=0; $i<$data_sources; ++$i) {
    my $rrd_key      = $self->[I_MY_RRD_LIST][$i];
    my $rrd          = $self->[I_ALL_RRD_REF]{$rrd_key};
    my $rrd_filename = $rrd->filename;
    my $rrd_version  = $rrd->version;
    push(@options, "DEF:average$i=$rrd_filename:Orca$rrd_version:AVERAGE");
  }
  my @legends;
  my $max_legend_length = 0;
  for (my $i=0; $i<$data_sources; ++$i) {
    my $legend         = ::replace_subgroup_name($plot_ref->{legend}[$i],
                                                 $subgroup_name);
    my $line_type      = $plot_ref->{line_type}[$i];
    my $color          = $plot_ref->{color}[$i];
    push(@options,       "$line_type:average$i#$color:$legend");
    $legend            =~ s:%:\200:g;
    $legend            =~ s:\200:%%:g;
    my $legend_length  = length($legend);
    $max_legend_length = $legend_length if $legend_length > $max_legend_length;
    push(@legends, $legend);
  }

  # Force a break between the plot legend and comments.
  push(@options, 'COMMENT:\s', 'COMMENT:\s', 'COMMENT:\s');

  # Generate the legends containing the current, average, minimum, and
  # maximum values on the plot.
  for (my $i=0; $i<$data_sources; ++$i) {
    my $legend          = $legends[$i];
    $legend            .= ' ' x ($max_legend_length - length($legend));
    my $summary_format  = $plot_ref->{summary_format}[$i];
    push(@options, "GPRINT:average$i:LAST:$legend  Current\\: $summary_format",
                   "GPRINT:average$i:AVERAGE:Average\\: $summary_format",
                   "GPRINT:average$i:MIN:Min\\: $summary_format",
                   "GPRINT:average$i:MAX:Max\\: $summary_format\\l"
        );
  }

  $self->[I_GRAPH_OPTIONS] = \@options;

  $self;
}

sub add_rrds {
  my $self = shift;

  $self->[I_MY_RRD_LIST] = [ &::unique(@{$self->[I_MY_RRD_LIST]}, @_) ];

  $self->_update_graph_options;
}

sub image_width {
  $_[0]->[I_IMAGE_WIDTH];
}

sub image_height {
  $_[0]->[I_IMAGE_HEIGHT];
}

# For this image, return a string that can be used to size the image
# properly in HTML.  The output from this subroutine is either an
# empty string or the size of the image.
sub image_src_size {
  if ($_[0]->[I_IMAGE_HEIGHT] and $_[0]->[I_IMAGE_WIDTH]) {
    return "width=$_[0]->[I_IMAGE_WIDTH] height=$_[0]->[I_IMAGE_HEIGHT]";
  } else {
    return '';
  }
}

sub name {
  $_[0]->[I_NAME];
}

sub group_index {
  $_[0]->[I_GROUP_INDEX];
}

sub subgroup_name {
  $_[0]->[I_SUBGROUP_NAME];
}

sub no_subgroup_name {
  $_[0]->[I_NO_SUBGROUP_NAME];
}

sub plot_ref {
  $_[0]->[I_PLOT_REF];
}

sub rrds {
  @{$_[0]->[I_MY_RRD_LIST]};
}

# Calculate the time of the last data point entered into the RRD that
# this image will use.
sub plot_end_time {
  my $self = shift;

  my $plot_end_time = -1;
  foreach my $rrd_key (@{$self->[I_MY_RRD_LIST]}) {
    my $update_time = $self->[I_ALL_RRD_REF]{$rrd_key}->rrd_update_time;
    $plot_end_time  = $update_time if $update_time > $plot_end_time;
  }

  $plot_end_time;
}

sub plot {
  my $self = shift;

  # Make the plots and specify how far back in time to plot.
  my $plot_made = 0;
  for (my $i=0; $i<@IMAGE_PLOT_TYPES; ++$i) {
    $plot_made = 1 if $self->_plot($i);
  }

  $plot_made;
}

sub _plot {
  my ($self, $i) = @_;

  my $plot_type       = $IMAGE_PLOT_TYPES[$i];
  my $image_time_span = $IMAGE_TIME_SPAN[$i];

  # Get the time stamp of the last data point entered into the RRDs
  # that are used to generate this image.
  my $plot_end_time = $self->plot_end_time;

  # Determine if the plot needs to be generated by taking into account
  # that a new plot does not need to be generated until a primary data
  # point has been added.  Primary data points are added after a data
  # point falls into a new bin, where the bin ends on multiples of the
  # sampling iterval.
  my $time_update_index = I_UPDATE_TIME_BASE + $i;
  my $plot_age          = $self->[I_PLOT_AGE_BASE+$i];
  if (int($self->[$time_update_index]/$plot_age) ==
      int($plot_end_time/$plot_age)) {
    return;
  }

  my $image_filename = "$self->[I_IMAGE_BASENAME]-$plot_type.$IMAGE_SUFFIX";
  print "  Creating '$image_filename'.\n" if $opt_verbose > 1;

  my $plot_ref = $self->[I_PLOT_REF];

  my ($graph_return, $image_width, $image_height) =
    RRDs::graph
      $image_filename,
      @{$self->[I_GRAPH_OPTIONS]},
      '-t', $self->[I_PLOT_LEGEND_BASE+$i],
      '-s', ($plot_end_time-$image_time_span),
      '-e', $plot_end_time,
      '-w', $plot_ref->{plot_width},
      '-h', $plot_ref->{plot_height},
      'COMMENT:\s',
      'COMMENT:Last data entered at ' . localtime($plot_end_time) . '.';
  if (my $error = RRDs::error) {
    warn "$0: warning: cannot create '$image_filename': $error\n";
    return;
  } else {
    $self->[$time_update_index] = $plot_end_time;
    $self->[I_IMAGE_HEIGHT]     = $image_height;
    $self->[I_IMAGE_WIDTH]      = $image_width;
    utime $plot_end_time, $plot_end_time, $image_filename or
      warn "$0: warning: cannot change mtime for '$image_filename': $!\n";

    # Expire the image at the correct time using a META file if
    # requested.
    if ($config_global{expire_images}) {
      if (open(META, "> $image_filename.meta")) {
        print META "Expires: ",
                   _expire_string($plot_end_time + $plot_age + 30),
                   "\n";
        close(META) or
          warn "$0: warning: cannot close '$image_filename.meta': $!\n";
      } else {
        warn "$0: warning: cannot open '$image_filename.meta' for writing: $!\n";
      }
    }
  }

  1;
}

sub _expire_string {
  my @gmtime  = gmtime($_[0]);
  my ($wday)  = ('Sun','Mon','Tue','Wed','Thu','Fri','Sat')[$gmtime[6]];
  my ($month) = ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep',
                 'Oct','Nov','Dec')[$gmtime[4]];
  my ($mday, $year, $hour, $min, $sec) = @gmtime[3,5,2,1,0];
  if ($mday<10) {$mday = "0$mday";}
  if ($hour<10) {$hour = "0$hour";}
  if ($min<10)  {$min  = "0$min";}
  if ($sec<10)  {$sec  = "0$sec";}
  return "$wday, $mday $month ".($year+1900)." $hour:$min:$sec GMT";
}

1;
