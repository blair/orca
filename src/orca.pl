# Orca: display arbitrary data from files onto web pages using RRD.
#
# Copyright (C) 1998, 1999 Blair Zajac and GeoCities, Inc.

use strict;
require 5.005;

$| = 1;

use Carp;
use Digest::MD5 2.00 qw(md5);
use Math::IntervalSearch 1.00 qw(interval_search);
use Data::Dumper;
$Data::Dumper::Indent   = 1;
$Data::Dumper::Purity   = 1;
$Data::Dumper::Deepcopy = 1;

# This is the version of Orca.
use vars qw($VERSION);
$VERSION = '0.22';

# This is the version number used in creating the DS names in RRDs.
# This should be updated any time a new version of Orca needs some new
# content in its RRD files.  The DS name is a concatentation of the
# string Orca with this string of digits.
my $ORCA_RRD_VERSION = 19990222;

# The number of seconds in one day.
my $day_seconds = 24*60*60;

# These define the name of the different RRAs create in each RRD file,
# how many primary data points go into a consolidated data point, and
# how far back in time they go.
#
# The first RRA one is every 5 minutes for 200 hours, the second is
# every 30 minutes for 31 days, the third is every 2 hours for 100
# days, and the last is every day for 3 years.
#
# The first array holds the names of the different plot types to
# create.  The second array holds the number of 300 second intervals
# are used to create a consolidated data point.  The third array is
# the number of consolidated data points held in the RRA.
my @rra_plot_type = qw(daily weekly monthly yearly);
my @rra_pdp_count =   (    1,     6,     24,   288);
my @rra_row_count =   ( 2400,  1488,   1200,  1098);

# Define the different plots to create.  These settings do not need to
# be exactly the same as the RRA definitions, but they can be.  Here
# create a quarterly plot (100 days) between the monthly and yearly
# plots.  Only update the quarterly plot daily.  The last array here
# holds the number of days back in time to plot in the GIF.  Be
# careful to not increase this so much that the number of data points
# to plot are greater than the number of pixels available for the GIF,
# otherwise there will be a 30% slowdown due to a reduction
# calculation to resample the data to the lower resolution for the
# plot.  For example, with 40 days of 2 hour data, there are 480 data
# points.  For no slowdown to occur, the GIF should be atleast 481
# pixels wide.
my @gif_plot_type = (@rra_plot_type[0..2], 'quarterly', $rra_plot_type[3]);
my @gif_pdp_count = (@rra_pdp_count[0..2], @rra_pdp_count[3, 3]);
my @gif_days_back = (  1.5,  10,  40, 100, 428);
# Data points ->    (432  , 480, 480, 100, 428);

# These are command line options.
my $opt_verbose         = 0;
my $opt_once_only       = 0;
my $opt_rrd_update_only = 0;

# Set up a signal handler to force looking for new files.
my $force_find_files = 0;
sub handle_hup {
  $force_find_files = 1;
}
$SIG{HUP} = \&handle_hup;

package Orca::HTMLFile;

use Carp;

sub new {
  unless (@_ >= 4) {
    confess "$0: Orca::HTMLFile::new passed wrong number of arguments.\n";
  }
  my ($class, $filename, $title, $top, $bottom) = @_;
  $bottom = '' unless defined $bottom;

  local *FD;
  open(FD, "> $filename") or return;

  print FD <<END;
<html>
<head>
<title>$title</title>
</head>
<body bgcolor="#ffffff">

$top
<h1>$title</h1>
END

  bless {_filename => $filename,
         _handle   => *FD,
         _bottom   => $bottom,
  }, $class;
}

sub print {
  my $self = shift;
  print { $self->{_handle} } "@_";
}

sub DESTROY {
  my $self = shift;

  print { $self->{_handle} } <<END;
$self->{_bottom}
<p>
<hr align=left width=475>
<table cellpadding=0 border=0>
  <tr>
    <td width=350 valign=center>
      <a href="http://www.geocities.com/~bzking/">
        <img width=186 height=45 border=0 src="orca.gif" alt="Orca Home Page"></a>
      <br>
      <font FACE="Arial,Helvetica" size=2>
        Orca-$::VERSION by
        <a href="http://www.geocities.com/~bzking/">Blair Zajac</a>
        <a href="mailto:bzajac\@geostaff.com">bzajac\@geostaff.com</a>.
      </font>
    </td>
    <td width=120 valign=center>
      <a href="http://ee-staff.ethz.ch/~oetiker/webtools/rrdtool">
        <img width=120 height=34 border=0 src="rrdtool.gif" alt="RRDTool Home Page"></a>
    </td>
  </tr>
</table>
</body>
</html>
END

  close($self->{_handle}) or
    warn "$0: warning: cannot close `$self->{_filename}': $!\n";
}

package Orca::OpenFileHash;

use Carp;

sub new {
  unless (@_ == 2) {
    confess "$0: Orca::OpenFileHash::new passed wrong number of arguments.\n";
  }

  my ($class, $max_elements) = @_;

  bless {_max_elements => $max_elements,
         _hash         => {},
         _weights      => {},
         _filenos      => {},
         _buffer       => {},
         _vec          => ''
  }, $class;
}

sub open {
  unless (@_ == 3) {
    confess "$0: Orca::OpenFileHash::open passed wrong number of arguments.\n";
  }

  my ($self, $filename, $weight) = @_;

  local *FD;

  unless (open(FD, $filename)) {
    warn "$0: warning: cannot open `$filename' for reading: $!\n";
    return;
  }

  $self->add($filename, $weight, *FD);

  *FD;
}

sub add {
  my ($self, $filename, $weight, $fd) = @_;

  # If there is an open file descriptor for this filename, then force
  # it to close.  Then make space for the new file descriptor in the
  # cache.
  $self->close($filename);
  $self->_close_extra($self->{_max_elements} - 1);

  my $fileno = fileno($fd);

  $self->{_hash}{$filename}{weight} = $weight;
  $self->{_hash}{$filename}{fd}     = $fd;
  $self->{_filenos}{$filename}      = $fileno;
  $self->{_buffer}{$filename}       = '';
  vec($self->{_vec}, $fileno, 1)    = 1;

  unless (defined $self->{_weights}{$weight}) {
    $self->{_weights}{$weight} = [];
  }
  push(@{$self->{_weights}{$weight}}, $filename);

}

sub close {
  my ($self, $filename) = @_;

  return $self unless defined $self->{_hash}{$filename};

  my $close_value = close($self->{_hash}{$filename}{fd});
  $close_value or warn "$0: warning: cannot close `$filename': $!\n";

  my $weight = $self->{_hash}{$filename}{weight};
  delete $self->{_hash}{$filename};

  my $fileno = delete $self->{_filenos}{$filename};
  vec($self->{_vec}, $fileno, 1) = 0;

  my @filenames = @{$self->{_weights}{$weight}};
  @filenames = grep { $_ ne $filename } @filenames;
  if (@filenames) {
    $self->{_weights}{$weight} = \@filenames;
  }
  else {
    delete $self->{_weights}{$weight};
  }

  $close_value;
}

sub _close_extra {
  my ($self, $max_elements) = @_;

  # Remove this number of elements from the structure.
  my $close_number = (keys %{$self->{_hash}}) - $max_elements;

  return $self unless $close_number > 0;

  my @weights = sort { $a <=> $b } keys %{$self->{_weights}};

  while ($close_number > 0) {
    my $weight = shift(@weights);
    foreach my $filename (@{$self->{_weights}{$weight}}) {
      $self->close($filename);
      --$close_number;
    }
  }

  $self;
}

sub change_weight {
  my ($self, $filename, $new_weight) = @_;

  return unless defined $self->{_hash}{$filename};

  my $old_weight = $self->{_hash}{$filename}{weight};
  return if $old_weight == $new_weight;

  # Save the new weight.
  $self->{_hash}{$filename}{weight} = $new_weight;

  unless (defined $self->{_weights}{$new_weight}) {
    $self->{_weights}{$new_weight} = [];
  }
  push(@{$self->{_weights}{$new_weight}}, $filename);

  # Remove the old weight.
  my @filenames = @{$self->{_weights}{$old_weight}};
  @filenames = grep { $_ ne $filename } @filenames;
  if (@filenames) {
    $self->{_weights}{$old_weight} = \@filenames;
  }
  else {
    delete $self->{_weights}{$old_weight};
  }

  1;
}

sub get_fd {
  my ($self, $filename) = @_;

  if (defined $self->{_hash}{$filename}) {
    return $self->{_hash}{$filename}{fd};
  }
  else {
    return;
  }
}

sub is_open {
  defined $_[0]->{_hash}{$_[1]};
}

package main;

# Set up a cache of 150 open file descriptors.  This leaves 255-150-3
# = 102 file descriptors for other use in the program.
use vars qw($open_file_cache);
$open_file_cache = Orca::OpenFileHash->new(150) unless $open_file_cache;

package Orca::DataFile;

use Carp;

sub new {
  unless (@_ == 2) {
    confess "$0: Orca::DataFile::new passed wrong number of arguments.\n";
  }

  my ($class, $filename) = @_;

  confess "$0: filename not passed to $class.\n" unless $filename;
  my $self = bless {_filename       => $filename,
                    _last_stat_time => -1,
                    _file_dev       => -1,
                    _file_ino       => -1,
                    _file_mtime     => -1
             }, $class;
  $self->update_stat;
  $self;
}

sub filename {
  $_[0]->{_filename};
}

sub file_dev {
  $_[0]->{_file_dev};
}

sub file_ino {
  $_[0]->{_file_ino};
}

sub file_mtime {
  $_[0]->{_file_mtime};
}

sub last_stat_time {
  $_[0]->{_last_stat_time};
}

# Return 1 if the file exists, 0 otherwise.
sub update_stat {
  my $self = shift;

  # Only update the stat if the previous stat occured more than one
  # second ago.  This is used when this function is called immediately
  # after the object has been constructed and when we don't want to
  # call two stat's immediately.  The tradeoff is to call time()
  # instead.
  my $time = time;
  if ($time > $self->{_last_stat_time} + 1) {
    if (my @stat = stat($self->{_filename})) {
      $self->{_file_dev}   = $stat[0];
      $self->{_file_ino}   = $stat[1];
      $self->{_file_mtime} = $stat[9];
    }
    else {
      $self->{_file_dev}   = -1;
      $self->{_file_ino}   = -1;
      $self->{_file_mtime} = -1;
    }
    $self->{_last_stat_time} = $time;
  }

  $self->{_file_mtime} != -1;
}

# Return a status depending upon the file:
#   -1 if the file does not exist.
#    0 if the file has not been updated since the last status check.
#    1 if the file has been updated since the last status check.
#    2 if the file has a new device or inode since the last status check.
sub status {
  my $self = shift;

  my $filename   = $self->{_filename};
  my $file_dev   = $self->{_file_dev};
  my $file_ino   = $self->{_file_ino};
  my $file_mtime = $self->{_file_mtime};

  my $result = 0;
  if ($self->update_stat) {
    if ($self->{_file_dev} != $file_dev or $self->{_file_ino} != $file_ino) {
      $result = 2;
    }
    elsif ($self->{_file_mtime} != $file_mtime) {
      $result = 1;
    }
  }
  else {
    $result = -1;
  }

  $result;
}

package Orca::GIFFile;

use RRDs 0.99029;
use Carp;

sub new {
  unless (@_ == 11) {
    confess "$0: Orca::GIFFile::new passed incorrect number of arguments.\n";
  }

  my ($class,
      $config_options,
      $config_files,
      $config_plots,
      $files_key,
      $group,
      $name,
      $no_group_name,
      $plot_ref,
      $rrd_data_files_ref,
      $my_rrds_ref) = @_;

  unless (@$my_rrds_ref) {
    confess "$0: Orca::GIFFile::new passed empty \@rrds_ref reference.\n";
  }
  unless ($name) {
    confess "$0: Orca::GIFFile::new passed empty \$name.\n";
  }

  # Remove any special characters from the unique name and do some
  # replacements.
  $name = &::strip_key_name($name);

  # Create the paths to the html directory and subdirectories.
  my $html_dir     = $config_options->{html_dir};
  if ($config_files->{$files_key}{sub_dir}) {
    $html_dir .= "/$group";
    # Create the html_dir directories if necessary.
    unless (-d $html_dir) {
      warn "$0: making directory `$html_dir'.\n";
      ::recursive_mkdir($html_dir);
    }
  }
  my $gif_basename = "$html_dir/$name";

  # Create the new object.
  my $self = bless {
    _files_key		=> $files_key,
    _group		=> $group,
    _name		=> $name,
    _no_group_name	=> $no_group_name,
    _gif_basename	=> $gif_basename,
    _all_rrd_ref	=> $rrd_data_files_ref,
    _my_rrd_list	=> [ &::unique(@$my_rrds_ref) ],
    _plot_ref           => $plot_ref,
    _interval           => int($config_files->{$files_key}{interval}+0.5),
    _expire             => $config_options->{expire_gifs},
    _gif_height         => 0,
    _gif_width          => 0,
    _graph_options      => []
  }, $class;

  # If the GIF already exists, then use its last modification time to
  # calculate when it was last updated.  If the file modification time
  # is newer than the timestamp of the last data point entered, then
  # assume that the GIF needs to be recreated.  This data will cause
  # the GIF to be created if the GIF does not exist.
  my $plot_end_time = $self->plot_end_time;
  foreach my $plot_type (@gif_plot_type) {
    my @stat = stat("$gif_basename-$plot_type.gif");
    if (@stat and $stat[9] <= $plot_end_time) {
      $self->{"_${plot_type}_update_time"} = $stat[9];
    }
    else {
      $self->{"_${plot_type}_update_time"} = -1;
    }
  }

  $self->_update_graph_options;
}

sub _update_graph_options {
  my $self = shift;

  my $plot_ref = $self->{_plot_ref};
  my $group    = $self->{_group};

  # Create the options for RRDs::graph that do not change across any
  # invocations of RRDs::graph.
  my @options = (
    '-t', ::replace_group_name($plot_ref->{title}, $group),
    '-v', ::replace_group_name($plot_ref->{y_legend}, $group)
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
  my $data_sources = @{$self->{_my_rrd_list}};
  for (my $i=0; $i<$data_sources; ++$i) {
    my $rrd_key      = $self->{_my_rrd_list}[$i];
    my $rrd          = $self->{_all_rrd_ref}{$rrd_key};
    my $rrd_filename = $rrd->filename;
    my $rrd_version  = $rrd->version;
    push(@options, "DEF:average$i=$rrd_filename:Orca$rrd_version:AVERAGE");
  }
  my @legends;
  my $max_legend_length = 0;
  for (my $i=0; $i<$data_sources; ++$i) {
    my $legend         = ::replace_group_name($plot_ref->{legend}[$i], $group);
    my $line_type      = $plot_ref->{line_type}[$i];
    my $color          = $plot_ref->{color}[$i];
    push(@options, "$line_type:average$i#$color:$legend");
    $legend            =~ s:%:\200:g;
    $legend            =~ s:\200:%%:g;
    my $legend_length  = length($legend);
    $max_legend_length = $legend_length if $legend_length > $max_legend_length;
    push(@legends, $legend);
  }

  # Force a break between the plot legend and comments.
  push(@options, 'COMMENT:\s',);

  # Generate the legends containing the current, average, minimum, and
  # maximum values on the plot.
  for (my $i=0; $i<$data_sources; ++$i) {
    my $legend = $legends[$i];
    $legend   .= ' ' x ($max_legend_length - length($legend));
    push(@options, "GPRINT:average$i:LAST:$legend  Current\\: %f",
                   "GPRINT:average$i:AVERAGE:Average\\: %f",
                   "GPRINT:average$i:MIN:Min\\: %f",
                   "GPRINT:average$i:MAX:Max\\: %f\\l"
        );
  }

  $self->{_graph_options} = \@options;

  $self;
}

sub add_rrds {
  my $self = shift;

  $self->{_my_rrd_list} = [ &::unique(@{$self->{_my_rrd_list}}, @_) ];

  $self->_update_graph_options;
}

sub files_key {
  $_[0]->{_files_key};
}

sub gif_width {
  $_[0]->{_gif_width};
}

sub gif_height {
  $_[0]->{_gif_height};
}

# For this GIF return a string that can be used to size the image
# properly in HTML.  The output from this subroutine is either an
# empty string or the size of the image.
sub gif_img_src_size {
  if ($_[0]->{_gif_height} and $_[0]->{_gif_width}) {
    return "width=$_[0]->{_gif_width} height=$_[0]->{_gif_height}";
  }
  else {
    return '';
  }
}

sub group {
  $_[0]->{_group};
}

sub name {
  $_[0]->{_name};
}

sub no_group_name {
  $_[0]->{_no_group_name};
}

sub plot_ref {
  $_[0]->{_plot_ref};
}

sub rrds {
  @{$_[0]->{_my_rrd_list}};
}

# Calculate the time of the last data point entered into the RRD that
# this gif will use.
sub plot_end_time {
  my $self = shift;

  my $plot_end_time = -1;
  foreach my $rrd_key (@{$self->{_my_rrd_list}}) {
    my $update_time = $self->{_all_rrd_ref}{$rrd_key}->rrd_update_time;
    $plot_end_time  = $update_time if $update_time > $plot_end_time;
  }

  $plot_end_time;
}

sub plot {
  my $self = shift;

  # Make the plots and specify how far back in time to plot.
  my $plot_made = 0;
  for (my $i=0; $i<@gif_plot_type; ++$i) {
    if ($self->_plot($gif_plot_type[$i],
                     $gif_days_back[$i],
                     $gif_pdp_count[$i])) {
      $plot_made = 1;
    }
  }

  $plot_made;
}

sub _plot {
  my ($self, $plot_type, $gif_days_back, $gif_pdp_count) = @_;

  # Get the time stamp of the last data point entered into the RRDs
  # that are used to generate this GIF.
  my $plot_end_time = $self->plot_end_time;

  # Determine if the plot needs to be generated.  First see if there
  # has been data flushed to the RRD that needs to be plotted.
  # Otherwise, see if the does not file exists or if the time
  # corresponding to the last data point is newer than the GIF.  Take
  # into account that a new plot does not need to be generated until a
  # primary data point has been added.  Primary data points are added
  # after a data point falls into a new bin, where the bin ends on
  # multiples of the sampling iterval.
  my $interval        = $self->{_interval};
  $gif_pdp_count      = int($gif_pdp_count*300.0/$interval + 0.5);
  $gif_pdp_count      = 1 if $gif_pdp_count < 1;
  my $plot_age        = $gif_pdp_count*$interval;
  my $time_update_key = "_${plot_type}_update_time";
  if (int($self->{$time_update_key}/$plot_age) == int($plot_end_time/$plot_age)) {
    return;
  }

  my $gif_filename = "$self->{_gif_basename}-$plot_type.gif";
  print "  Creating `$gif_filename'.\n" if $opt_verbose > 1;

  my $plot_ref  = $self->{_plot_ref};

  my ($graph_return, $gif_width, $gif_height) =
    RRDs::graph
      $gif_filename,
      @{$self->{_graph_options}},
      '-s', ($plot_end_time-$gif_days_back*$day_seconds),
      '-e', $plot_end_time,
      '-w', $plot_ref->{plot_width},
      '-h', $plot_ref->{plot_height},
      'COMMENT:\s',
      'COMMENT:Last data entered at ' . localtime($plot_end_time) . '.';
  if (my $error = RRDs::error) {
    warn "$0: warning: cannot create `$gif_filename': $error\n";
  }
  else {
    $self->{$time_update_key} = $plot_end_time;
    $self->{_gif_height}      = $gif_height;
    $self->{_gif_width}       = $gif_width;
    utime $plot_end_time, $plot_end_time, $gif_filename or
      warn "$0: warning: cannot change mtime for `$gif_filename': $!\n";

    # Expire the GIF at the correct time using a META file if
    # requested.
    if ($self->{_expire}) {
      if (open(META, "> $gif_filename.meta")) {
        my $time = 
        print META "Expires: ",
                   _expire_string($plot_end_time + $plot_age + 30),
                   "\n";
        close(META) or
          warn "$0: warning: cannot close `$gif_filename.meta': $!\n";
      }
      else {
        warn "$0: warning: cannot open `$gif_filename.meta' for writing: $!\n";
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

package Orca::RRDFile;

use RRDs;
use Carp;
use vars qw(@ISA);

@ISA = qw(Orca::DataFile);

sub new {
  unless (@_ == 7) {
    confess "$0: Orca::RRDFile::new passed incorrect number of arguments.\n";
  }

  my ($class,
      $config_options,
      $config_files,
      $files_key,
      $group,
      $name,
      $plot_ref) = @_;

  # Remove any special characters from the unique name and do some
  # replacements.
  $name = &::strip_key_name($name);

  # Create the paths to the data directory.
  my $data_dir = $config_options->{data_dir};
  if ($config_files->{$files_key}{sub_dir}) {
    $data_dir .= "/$group";
    unless (-d $data_dir) {
      warn "$0: making directory `$data_dir'.\n";
      ::recursive_mkdir($data_dir);
    }
  }
  my $rrd_filename = "$data_dir/$name.rrd";

  # Create the new object.
  my $self = $class->SUPER::new($rrd_filename);
  return unless $self;
  $self->{_name}             = $name;
  $self->{_new_data}         = {};
  $self->{_created_gifs}     = {};
  $self->{_plot_ref}         = $plot_ref;
  $self->{_interval}         = int($config_files->{$files_key}{interval}+0.5);
  $self->{_rrd_version}      = $ORCA_RRD_VERSION;
  $self->{_choose_data_subs} = {};

  # See if the RRD file meets two requirements. The first is to see if
  # the last update time can be sucessfully read.  The second is to
  # see if the RRD has an DS named "Orca$ORCA_RRD_VERSION".  If
  # neither one of these is true, then create a brand new RRD is
  # created when data is first flushed to it.
  $self->{_rrd_update_time} = -2;
  if ($self->status >= 0) {
    my $update_time = RRDs::last $rrd_filename;
    if (my $error = RRDs::error) {
      warn "$0: RRDs::last error: `$rrd_filename' $error\n";
    }
    else {
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
            $self->{_rrd_update_time} = $update_time;
            $self->{_rrd_version}     = $version;
          }
          else {
            warn "$0: old version $version RRD `$rrd_filename' found: will create new version $ORCA_RRD_VERSION file.\n";
          }
        }
        else {
          warn "$0: unknown version RRD `$rrd_filename' found: will create new version $ORCA_RRD_VERSION file.\n";
        }
      }
    }
  }

  $self;
}

sub version {
  $_[0]->{_rrd_version};
}

sub name {
  $_[0]->{_name};
}

sub rrd_update_time {
  $_[0]->{_rrd_update_time};
}

sub add_gif {
  my ($self, $gif) = @_;
  $self->{_created_gifs}{$gif->name} = $gif;
  $self;
}

sub created_gifs {
  values %{$_[0]->{_created_gifs}};
}

# Queue a list of (time, value) data pairs.  Return the number of data
# pairs sucessfully queued.
# Call:   $self->(unix_epoch_time1, value1, unix_epoch_time2, value2, ...);
sub queue_data {
  my $self = shift;

  my $count = 0;
  my $rrd_update_time = $self->{_rrd_update_time};
  while (@_ > 1) {
    my ($time, $value) = splice(@_, 0, 2);
    next if $time <= $rrd_update_time;
    $self->{_new_data}{$time} = $value;
    ++$count;
  }

  $count;
}

sub flush_data {
  my $self = shift;

  # Get the times of the new data to put into the RRD file.
  my @times = sort { $a <=> $b } keys %{$self->{_new_data}};

  return unless @times;

  my $rrd_filename = $self->filename;

  # Create the Orca data file if it needs to be created.
  if ($self->{_rrd_update_time} == -2) {

    # Assume that a maximum of two time intervals are needed before a
    # data source value is set to unknown.
    my $interval = $self->{_interval};
   
    my $data_source = "DS:Orca$ORCA_RRD_VERSION:$self->{_plot_ref}{data_type}";
    $data_source   .= sprintf ":%d:", 2*$interval;
    $data_source   .= "$self->{_plot_ref}{data_min}:";
    $data_source   .= "$self->{_plot_ref}{data_max}";
    my @options = ($rrd_filename,
                   '-b', $times[0]-1,
                   '-s', $interval,
                   $data_source);

    # Create the round robin archives.  Take special care to not
    # create two RRA's with the same number of primary data points.
    # This can happen if the interval is equal to one of the
    # consoldated intervals.
    my $count = int($rra_row_count[0]*300.0/$interval + 0.5);
    my @one_pdp_option = ("RRA:AVERAGE:0.5:1:$count");

    for (my $i=1; $i<@rra_pdp_count; ++$i) {
      next if $interval > 300*$rra_pdp_count[$i];
      my $rra_pdp_count = int($rra_pdp_count[$i]*300.0/$interval + 0.5);
      if (@one_pdp_option and $rra_pdp_count != 1) {
        push(@options, @one_pdp_option);
      }
      @one_pdp_option = ();
      push(@options, "RRA:AVERAGE:0.5:$rra_pdp_count:$rra_row_count[$i]");
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
  my $old_rrd_update_time = $self->{_rrd_update_time};
  foreach my $time (@times) {
    push(@options, "$time:$self->{_new_data}{$time}");
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
  delete $self->{_new_data};
  $self->{_new_data} = {};

  $self->{_rrd_update_time} = $times[-1];

  return 1;
}

package Orca::Config::Plot;

use Carp;

sub new {
  unless (@_ == 2) {
    confess "$0: Orca::Config::Plot::new passed incorrect number of arguments.\n";
  }

  bless $_[1], $_[0];
}

package Orca::Config::FilesGroup;

use Carp;

sub new {
  unless (@_ == 2) {
    confess "$0: Orca::Config::FilesGroup::new passed incorrect number of arguments.\n";
  }

  bless $_[1], $_[0];
}

package Orca::SourceDataFile;

use Carp;
use Digest::MD5 qw(md5);
use Storable 0.603 qw(dclone);
use vars qw(@ISA);

@ISA = qw(Orca::DataFile);

# This is a static variable that lists all of the column names for a
# particular files key.
my %files_key_column_names;

# This caches the reference to the array holding the column
# descriptions for files that have their column descriptions in the
# first line of the file.
my %first_line_cache;

# These are caches for the different objects that are used to add a
# plot.
my %all_rrds_cache;
my %my_rrd_list_cache;
my %choose_data_sub_cache;

sub new {
  unless (@_ == 10) {
    confess "$0: Orca::SourceDataFile::new passed incorrect number of arguments.\n";
  }

  my ($class,
      $filename,
      $interval,
      $late_interval,
      $reopen,
      $column_description,
      $date_source,
      $date_format,
      $warn_email,
      $saved_source_file_state) = @_;

  my $self = $class->SUPER::new($filename);
  $self->{_interval}           = $interval;
  $self->{_late_interval}      = int(&$late_interval($interval) + 0.5);
  $self->{_reopen}             = $reopen;
  $self->{_date_source}        = $date_source;
  $self->{_date_format}        = $date_format;
  $self->{_warn_email}         = $warn_email;
  $self->{_my_rrd_list}        = [];
  $self->{_all_rrd_ref}        = undef;
  $self->{_files_keys}         = {};
  $self->{_choose_data_sub}    = undef;

  $self->{_column_description} = $column_description;
  $self->{_last_data_time}     = -1;
  $self->{_last_read_time}     = -1;
  $self->{_first_line}         =  0;
  $self->{_date_column_index}  = undef;

  # There are three intervals associated with each file.  The first is
  # the data update interval.  This is the same interval used to
  # generate the RRDs.  The second interval is the interval before the
  # file is considered late and is larger than the data update
  # interval.  This interval is calculated by using the mathematical
  # expression given in the `late_interval' configuration option.  If
  # `late_interval' is not defined, then it gets defaulted to the data
  # update interval.  The last interval is the interval to use to tell
  # the program when to attempt to read the file next.  Because it can
  # take some time for the source files to be updated, we don't want
  # to read the file immediately after the data update interval is
  # done.  For this reason, choose a read interval that is somewhere
  # in between the data source interval and the late interval.  Use
  # the multiplicative average of the data update interval and the
  # late interval since the resulting value is closer to the data
  # update interval.  Ie: (20 + 5)/2 = 12.5.  Sqrt(20*5) = 10.
  my $read_interval = sqrt($self->{_interval}*$self->{_late_interval});
  $self->{_read_interval} = int($read_interval + 0.5);

  # Load in any state information for this file.
  if (defined $saved_source_file_state->{$filename}) {
    while (my ($key, $value) = each %{$saved_source_file_state->{$filename}}) {
      $self->{$key} = $value;
    }
  }

  # Test if the file has been updated in the last _interval number of
  # seconds.  If so, then note it so we can see when the file is no
  # longer being updated.
  $self->{_is_current} = $self->is_current;

  return unless $self->get_column_names;
  return unless $self->get_date_column;

  $self;
}

# For each files key store make a note of the column description names
# that appear.
sub add_files_keys {
  my $self = shift;

  foreach my $files_key (@_) {
    $self->{_files_keys}{$files_key} = 1;
    foreach my $description (@{$self->{_column_description}}) {
      $files_key_column_names{$files_key}{$description} = 1;
    }
  }
}

# Return 1 if the source data file is current or 0 otherwise.  Also
# note the day that this test was performed.  This lets the code
# ignore files that are not current because a new file was generated
# for the next day.
sub is_current {
  my $self = shift;

  $self->{_is_current_day} = (localtime)[3];

  $self->last_stat_time <= $self->file_mtime + $self->{_late_interval};
}

# This returns the time when the file should be next read.  To
# calculate the next read time, take into the account the time that it
# takes for the file to be updated.  In some sense, this is measured
# by the late interval.  Because we won't want to use the complete
# late interval, take the multiplicative average instead of the
# summation average, since the multiplicative average will result in
# an average closer to the smaller of the two values.  If the source
# file is current, then just add the modified late interval to the
# last file modification time, otherwise add the late interval to the
# last file stat time.  Use the late interval to watch old files so we
# don't spend as much time on them.
sub next_load_time {
  my $self = shift;

  my $last_stat_time = $self->last_stat_time;
  my $file_mtime     = $self->file_mtime;

  if ($last_stat_time <= $file_mtime + $self->{_late_interval}) {
    return $file_mtime + $self->{_read_interval};
  }
  else {
    return $last_stat_time + $self->{_late_interval};
  }
}

sub get_column_names {
  my $self = shift;

  return $self unless $self->{_column_description}[0] eq 'first_line';

  my $filename = $self->filename;
  $self->update_stat;
  my $fd = $::open_file_cache->open($filename, $self->file_mtime);
  return unless $fd;

  my $line = <$fd>;

  chomp($line);
  if ($line) {
    $self->{_first_line} = 1;
    my @line = split(' ', $line);
    my $cache_key = md5(join("\200", @line));
    unless (defined $first_line_cache{$cache_key}) {
      $first_line_cache{$cache_key} = \@line;
    }
    $self->{_column_description} = $first_line_cache{$cache_key};
  }
  else {
    warn "$0: warning: no first_line for `$filename' yet.\n";
    $::open_file_cache->close($filename) or
      warn "$0: warning: cannot close `$filename' for reading: $!\n";
    return;
  }

  $self;
}

sub get_date_column {
  my $self = shift;

  return $self if $self->{_date_source}[0] eq 'file_mtime';

  my $filename         = $self->filename;
  my $date_column_name = $self->{_date_source}[1];

  my $found = -1;
  for (my $i=0; $i<@{$self->{_column_description}}; ++$i) {
    if ($self->{_column_description}[$i] eq $date_column_name) {
      $found = $i;
      last;
    }
  }

  unless ($found > -1) {
    warn "$0: warning: cannot find date `$date_column_name' in `$filename'.\n";
    return;
  }
  $self->{_date_column_index} = $found;

  $self;
}

sub add_plots {
  # Make sure that the user has called the add_files_keys method and
  # inserted at least one key.
  unless (keys %files_key_column_names) {
    confess "$0: Orca::SourceDataFile::add_files_keys must be called before add_plots.\n";
  }

  unless (@_ == 8) {
    confess "$0: Orca::SourceDataFile::add_plots passed wrong number of arguments.\n";
  }

  my ($self,
      $config_options,
      $config_files,
      $config_plots,
      $files_key,
      $group,
      $rrd_data_files_ref,
      $gif_files_ref) = @_;

  # See if we have already done all the work for a plot with this
  # files_key, group, and column description.  Use an MD5 hash instead
  # of a very long key.  Store into a hash the column names found in
  # this file for this files key.  Finally, create a hash keyed by
  # column name with a value of the index into the column description
  # array.  for this files key.
  my @column_description = @{$self->{_column_description}};
  my %column_description;
  for (my $i=0; $i<@column_description; ++$i) {
    $column_description{$column_description[$i]} = $i;
  }
  my $plot_key  = join("\200", $files_key, $group, @column_description);
  my $cache_key = md5($plot_key);
  if (defined $all_rrds_cache{$cache_key}) {
    $self->{_all_rrd_ref}     = $all_rrds_cache{$cache_key};
    $self->{_my_rrd_list}     = $my_rrd_list_cache{$cache_key};
    $self->{_choose_data_sub} = $choose_data_sub_cache{$cache_key};
    return 1;
  }

  # Use this hash to keep a list of RRDs that this file uses.
  my %my_rrd_list;

  # This is the source for an anonymous subroutine that given a row
  # from a source data file returns a hash keyed by RRD name with the
  # values calculated from the row.
  my $choose_data_expr = "sub {\n  return (\n";

  # Go through each plot to create and process it for this file.
  my @regexp_pos          = map { 0 } (1..@$config_plots);
  my $oldest_regexp_index = 0;
  my $handle_regexps      = 0;
  my $i                   = 0;
  my $old_i               = 0;

  # This is the main loop where we keep looking for plots to create
  # until all of the column descriptions have been compared against.
  while ($handle_regexps or $i < @$config_plots) {
    # If we've reached an index value greater than the largest index
    # in the plots, then reset the index to the oldest regexp that
    # still needs to be completed.
    if ($handle_regexps and $i >= @$config_plots) {
      $i = $oldest_regexp_index;
    }

    my $plot = $config_plots->[$i];

    # Skip this plot if the files_key do not match.  Increment the
    # index of the next plot to handle.
    if ($plot->{source} ne $files_key) {
      if ($oldest_regexp_index == $i) {
        $handle_regexps = 0;
        ++$oldest_regexp_index;
      }
      ++$i;
      next;
    }

    # There are three cases to handle.  The first is a single data
    # source with a single element that has a regular expression.  In
    # this case, all of the columns are searched to match the regular
    # expression.  The second case is two or more data sources and
    # with one element in the first data source that has a regular
    # expression match.  This may generate more than one plot, while
    # the first one will only generate one plot.  The final case to
    # handle is when the previous two cases are not true.  The last
    # column matched on is stored in @regexp_pos.
    my $number_datas    = @{$plot->{data}};
    my $number_elements = @{$plot->{data}[0]};
    my $has_regexp      = $plot->{data}[0][0] =~ m:\(.+\):;
    if ($number_datas == 1 and $number_elements == 1 and $has_regexp) {

      # If we've gone up to the last column to match, then go on.
      if ($regexp_pos[$i] >= @column_description) {
        if ($oldest_regexp_index == $i) {
          $handle_regexps = 0;
          ++$oldest_regexp_index;
        }
        $i = $plot->{flush_regexps} ? $oldest_regexp_index : $i + 1;
        next;
      }
      $regexp_pos[$i] = @column_description;

      # In this case we're creating a whole new plot that will have as
      # many data sources as their are columns that match the regular
      # expression.  Start by making a deep copy of the plot.  Be
      # careful not to make a deep copy of the creates reference,
      # since it can cause recursion.
      my $creates = delete $plot->{creates};
      {
        my $new_plot = dclone($plot);
        $plot->{creates} = $creates;
        $new_plot->{creates} = $creates;
        $plot = $new_plot;
      }

      # At this point we have a copy of plot.  Now go through looking
      # for all the columns that match and create an additional data
      # source for each match.
      my $regexp = $plot->{data}[0][0];
      my $new_data_index = 0;
      my $original_legend = $plot->{legend}[0];
      foreach my $column_name (@column_description) {
        my @matches = $column_name =~ /$regexp/;
        next unless @matches;

        $plot->{data}[$new_data_index] = [ $column_name ];

        # Copy any items over that haven't been created for this new
        # data source.  Make sure that any new elements added to
        # pcl_plot_append_elements show up here.
        unless (defined $plot->{color}[$new_data_index]) {
          $plot->{color}[$new_data_index] = $::cc_default_colors[$new_data_index];
        }
        unless (defined $plot->{legend}[$new_data_index]) {
          $plot->{legend}[$new_data_index] = $original_legend;
        }
        unless (defined $plot->{line_type}[$new_data_index]) {
          $plot->{line_type}[$new_data_index] = $plot->{line_type}[0];
        }

        # Replace the regular expression in any legend elements.
        my $legend = $plot->{legend}[$new_data_index];
        my $count = 1;
        foreach my $match (@matches) {
          $legend =~ s/\$$count/$match/ge;
          $legend =~ s/\(.+\)/$match/ge;
          ++$count;
        }
        $plot->{legend}[$new_data_index] = $legend;

        ++$new_data_index;
      }

      if ($oldest_regexp_index == $i) {
        $handle_regexps = 0;
        ++$oldest_regexp_index;
      }
      $old_i = $i;
      $i = $plot->{flush_regexps} ? $oldest_regexp_index : $i + 1;
      next unless $new_data_index;
    }
    elsif ($number_datas > 1 and $number_elements == 1 and $has_regexp) {
      $handle_regexps = 1;

      # If we've gone up to the last column to match, then go on.  If
      # this is the oldest regexp, then increment oldest_regexp_index.
      if ($regexp_pos[$i] >= @column_description) {
        if ($oldest_regexp_index == $i) {
          $handle_regexps = 0;
          ++$oldest_regexp_index;
        }
        $i = $plot->{flush_regexps} ? $oldest_regexp_index : $i + 1;
        next;
      }

      # Go through all of the columns and stop at the first match.
      my $regexp = $plot->{data}[0][0];
      my @matches;
      for (;$regexp_pos[$i]<@column_description; ++$regexp_pos[$i]) {
        @matches = $column_description[$regexp_pos[$i]] =~ /$regexp/;
        last if @matches;
      }
      unless (@matches) {
        if ($oldest_regexp_index == $i) {
          ++$oldest_regexp_index;
          $handle_regexps = 0;
        }
        ++$i;
        next;
      }
      ++$regexp_pos[$i];

      # Make a deep copy of the plot.  In the string form of the plot
      # replace all of the $1, $2, ... with what was matched in the
      # first data source.  The tricky one is to replace the regular
      # expression that did the match in the first place.  Also, save
      # a copy of the creates array for this plot so it doesn't also
      # get dumped.
      my $creates      =  delete $plot->{creates};
      my $d            =  Data::Dumper->Dump([$plot], [qw(plot)]);
      $plot->{creates} =  $creates;
      $d               =~ s/$regexp/$matches[0]/mge;
      my $count = 1;
      foreach my $match (@matches) {
        $d =~ s/\$$count/$match/mge;
        $d =~ s/\(.+\)/$match/mge;
        ++$count;
      }
      {
        local $SIG{__WARN__} = sub { die $_[0] };
        eval $d;
      }
      die "$0: internal error: eval on\n   $d\nOutput: $@\n" if $@;

      # Either increment the index or reset it to the oldest regexp
      # index.
      $old_i = $i;
      $i = $plot->{flush_regexps} ? $oldest_regexp_index : $i + 1;
    }
    else {
      $old_i = $i++;
      ++$oldest_regexp_index unless $handle_regexps;
    }

    # Make a copy of the data's so that if we change anything, we're
    # not changing the original plot structure.  Look through each
    # element of each data and look for names appearing in the column
    # description array.  If there is a match for this file, then
    # convert the element to an index the @_ array where the data will
    # be pulled from.  If there is not a match, then see if the
    # element matches a name from one of the other column names from
    # the same files key.  In this case the data argument for this
    # file will not be used.
    my @datas;
    foreach my $one_data (@{$plot->{data}}) {
      push(@datas, [@$one_data]);
    }
    my $optional  = $plot->{optional};
    my $match_any = 0;
    for (my $j=0; $j<@datas; ++$j) {
      my $match_one_data = 0;
      for (my $k=0; $k<@{$datas[$j]}; ++$k) {
        my $element = $datas[$j][$k];
        my $pos;
        if (defined ($pos = $column_description{$element})) {
          $datas[$j][$k] = "\$_[$pos]";
          $match_one_data = 1;
        }
        elsif (defined $files_key_column_names{$files_key}{$element}) {
          my $m = $old_i + 1;
          warn "$0: $element in `data @{$plot->{data}[$j]}' in plot #$m not replaced since it is not in file `" . $self->filename . "'.\n" unless $optional;
          $datas[$j] = undef;
          last;
        }
      }
      # If there were no substitutions, then warn about it.
      if (!$match_one_data and !$optional) {
        my $m = $old_i + 1;
        warn "$0: warning: no substitutions performed for `data @{$plot->{data}[$j]}' in plot #$m in `" . $self->filename . "'.\n";
      }
      $match_any = $match_any || $match_one_data;
    }

    # Skip this plot if no matches were found and the plot is
    # optional.
    next if (!$match_any and $optional);

    # At this point we have a plot to create.

    # For each data source in this plot, try to create an anonymous
    # subroutine to see if the eval succeeds.  Place each data source
    # into a large anonymous subroutine that takes a single row of data
    # from an input source file and returns a hash keyed by the named
    # used for a RRD and the value calculated using the input row of
    # data.  Also create an unique Orca data file name for this plot
    # and a name for this plot that does not include the group.
    my @my_rrds;
    my @no_group_name;
    my @group_name;
    for (my $j=0; $j<@datas; ++$j) {

      my $expr         = "@{$datas[$j]}";
      my $sub_expr_sub = undef;
      my $data_name    = join('_', @{$plot->{data}[$j]});

      if (defined $datas[$j]) {
        my $sub_expr     = "sub {\n  return $expr;\n}\n";
        my $sub_expr_md5 = md5($sub_expr);

        unless (defined ($sub_expr_sub = $choose_data_sub_cache{$sub_expr_md5})) {
          {
            local $SIG{__WARN__} = sub { die $_[0] };
            $sub_expr_sub        = eval $sub_expr;
          }
          if ($@) {
            $sub_expr_sub = undef;
            unless ($optional) {
              my $m = $old_i + 1;
              warn "$0: warning: bad evaluation of commands for plot #$m `data @{$plot->{data}[$j]}':\n$sub_expr\nOutput: $@\n";
            }
          }
          $choose_data_sub_cache{$sub_expr_md5} = $sub_expr_sub;
        }
      }

      my $name = "${files_key}_${group}_${data_name}";
      push(@no_group_name, "${files_key}_${data_name}");
      push(@group_name, $name);

      # Create a new RRD only if it doesn't already exist and if a
      # valid get data subroutine is created.  Keep the
      # choose_data_sub for this file.
      if (defined $sub_expr_sub) {
        $choose_data_expr .= "    '$name', $expr,\n";
        unless (defined $rrd_data_files_ref->{$name}) {
          my $rrd_file = Orca::RRDFile->new($config_options,
                                            $config_files,
                                            $files_key,
                                            $group,
                                            $name,
                                            $plot);
          $rrd_data_files_ref->{$name} = $rrd_file;
        }
        $self->{_all_rrd_ref}             = $rrd_data_files_ref;
        $my_rrd_list{$name}               = 1;
        push(@my_rrds, $name);
      }
    }

    # Generate a new plot for these data.
    my $gif;
    my $group_name = join(',', @group_name);
    if (defined ($gif = $gif_files_ref->{hash}{$group_name})) {
      $gif->add_rrds(@my_rrds);
    }
    else {
      $gif = Orca::GIFFile->new($config_options,
                                $config_files,
                                $config_plots,
                                $files_key,
                                $group,
                                join(',', @my_rrds),
                                join(',', @no_group_name),
                                $plot,
                                $rrd_data_files_ref,
                                \@my_rrds);
      $gif_files_ref->{hash}{$group_name} = $gif;
      push(@{$gif_files_ref->{list}}, $gif);
      push(@{$config_plots->[$old_i]{creates}}, $gif);
    }

    # Put into each RRD the GIFs that are generated from it.
    foreach my $rrd_key (@my_rrds) {
      $rrd_data_files_ref->{$rrd_key}->add_gif($gif);
    }
  }

  $choose_data_expr .= "  );\n}\n";
  {
    local $SIG{__WARN__} = sub { die $_[0] };
    $self->{_choose_data_sub} = eval $choose_data_expr;
  }
  if ($@) {
    my $m = $old_i + 1;
    die "$0: warning: bad evaluation of command for plot #$m:\n$choose_data_expr\nOutput: $@\n";
  }

  $all_rrds_cache{$cache_key}        = $self->{_all_rrd_ref};
  $choose_data_sub_cache{$cache_key} = $self->{_choose_data_sub};
  my $tmp                            = [sort keys %my_rrd_list];
  $my_rrd_list_cache{$cache_key}     = $tmp;
  $self->{_my_rrd_list}              = $tmp;

  1;
}

sub load_new_data {
  my $self = shift;

  my $filename = $self->filename;

  # Test to see if we should read the file.  If the file has changed
  # in any way, then read it.  If the file is now gone and we have an
  # open file descriptor for it, then read to the end of it and then
  # close it.
  my $file_status = $self->status;
  my $fd          = $::open_file_cache->get_fd($filename);
  my $load_data   = $file_status != 0;
  if ($file_status == -1) {
    my $message = "file `$filename' did exist and is now gone.";
    ::email_message($self->{_warn_email}, $message);
    warn "$0: warning: $message\n";
    unless ($fd) {
      $self->{_last_read_time} = -1;
      return 0;
    }
  }

  # Test if the file was up to date and now is not.  If so, then send
  # a message.  Do not send a message if the file was current in the
  # previous day is now is not current today.
  my $old_is_current     = $self->{_is_current};
  my $old_is_current_day = $self->{_is_current_day};
  my $current_day        = (localtime($self->last_stat_time))[3];
  $self->{_is_current} = $self->is_current;
  if ($old_is_current and
      !$self->{_is_current} and
      ($old_is_current_day == $current_day)) {
    my $message = "file `$filename' was current and now is not.";
    warn "$0: warning: $message\n";
    ::email_message($self->{_warn_email}, $message);
  }

  # If we don't have to load the data from this file yet, then test to
  # see if the data needs to be loaded if the file modification time
  # is greater than the time at which it was last read.
  my $file_mtime = $self->file_mtime;
  unless ($load_data) {
    $load_data = $file_mtime > $self->{_last_read_time};
  }

  # If the file still does not have to be loaded, now test to see if
  # the timestamp of the last data point is larger than the last time
  # of any RRD files that depend on this source file.
  my $last_data_time = $self->{_last_data_time};
  unless ($load_data) {
    foreach my $rrd_key (@{$self->{_my_rrd_list}}) {
      if ($self->{_all_rrd_ref}{$rrd_key}->rrd_update_time < $last_data_time) {
        $load_data = 1;
        last;
      }
    }
  }

  return 0 unless $load_data;

  # Try to get a file descriptor to open the file.  Skip the first
  # line if the first line is used for column descriptions.

  my $opened_new_fd = !$fd;
  unless ($fd) {
    unless ($fd = $::open_file_cache->open($filename, $file_mtime)) {
      warn "$0: warning: cannot open `$filename' for reading: $!\n";
      return 0;
    }
    <$fd> if $self->{_first_line};
  }

  # Load in all of the data possible and send it to each plot.
  my $date_column_index = $self->{_date_column_index};
  my $use_file_mtime    = $self->{_date_source}[0] eq 'file_mtime';
  my $number_added      = 0;
  my $close_once_done   = 0;
  my $number_columns    = @{$self->{_column_description}};
  while (my $line = <$fd>) {
    # Skip the line if the word timestamp appears in it.  This is a
    # temporary fix for orcallator.se to place a new information line
    # in the output file when it starts up.
    next if $line =~ /timestamp/;

    my @line = split(' ', $line);

    # Skip this input line if 1) the file uses the first line to
    # define the column names, 2) the number of columns loaded is not
    # equal to the number of columns in the column description.
    if ($self->{_first_line} and @line != $number_columns) {
      warn "$0: number of columns in line $. of `$filename' does not match column description.\n";
      next;
    }

    my $time = $use_file_mtime ? $self->file_mtime : $line[$date_column_index];
    $last_data_time = $time if $time > $last_data_time;

    # If the file status from the source data file is greater than
    # zero, then it means the file has changed in some way, so we need
    # to do updates for all plots.  Load the available data, calculate
    # the value that needs to go to each RRD and push the value to the
    # RRD.
    my $add = 0;
    my %values = &{$self->{_choose_data_sub}}(@line);
    foreach my $rrd_key (@{$self->{_my_rrd_list}}) {
      my $value = $values{$rrd_key};
      if (defined $value) {
        if ($self->{_all_rrd_ref}{$rrd_key}->queue_data($time, $value)) {
          if ($opt_verbose > 2 and !$add) {
            print "  Loaded `@line' at ", scalar localtime($time), " ($time).\n";
          }
          $add = 1;
        }
      }
      else {
        $close_once_done = 1;
        warn "$0: internal error: expecting RRD name `$rrd_key' but no data loaded from `" . $self->filename . "' at time ", scalar localtime($time), " ($time).\n";
      }
    }
    ++$number_added if $add;
  }

  # Update the time when the file was last read.
  $self->{_last_data_time} = $last_data_time;
  $self->{_last_read_time} = time;

  $::open_file_cache->change_weight($filename, $file_mtime);

  # Now two special cases to handle.  First, if the file was removed
  # and we had an open file descriptor to it, then close the file
  # descriptor.  Second, if the file has a new device number or inode
  # and we had a already opened file descriptor to the file, then
  # close the descriptor, reopen it and read all the rest of the data.
  # If neither of these cases is true, then close the file if the file
  # should be reopened next time.
  if ($file_status == -1 or ($file_status == 2 and !$opened_new_fd)) {
    $::open_file_cache->close($filename) or
      warn "$0: warning: cannot close `$filename' for reading: $!\n";
    if ($file_status != -1) {
      # Setting the last_read_time to -1 will force load_new_data to
      # read it.
      $self->{_last_read_time} = -1;
      $number_added += $self->load_new_data;
    }
  }
  elsif ($close_once_done or $self->{_reopen}) {
    $::open_file_cache->close($filename) or
      warn "$0: warning: cannot close `$filename' for reading: $!\n";
  }

  $number_added;
}

sub rrds {
  @{$_[0]->{_my_rrd_list}};
}

package main;

sub Usage {
  die "usage: $0 [-o] [-r] [-v] config_file\n";
}

while (@ARGV and $ARGV[0] =~ /^-\w/) {
  my $arg = shift;
  if ($arg eq '-o') {
    ++$opt_once_only;
  }
  elsif ($arg eq '-v') {
    ++$opt_verbose;
  }
  elsif ($arg eq '-r') {
    ++$opt_rrd_update_only;
  }
  else {
    Usage;
  }
}

Usage unless @ARGV;

if ($opt_verbose) {
  print "Orca version $VERSION using RRDs version $RRDs::VERSION.\n";
}

&main(@ARGV);

exit 0;

sub main {
  my $config_filename = shift;

  my $start_time = time;

  # Load the configuration file.
  my ($config_options,
      $config_files,
      $config_plots) = &load_config($config_filename);

  # Check and do any work on the configuration information.
  &check_config($config_filename,
                $config_options,
                $config_files,
                $config_plots);

  # Load in any new data and update necessary plots.
  &watch_data_sources($config_filename,
                      $config_options,
                      $config_files,
                      $config_plots);

  my $time_span = time - $start_time;
  my $minutes   = int($time_span/60);
  my $seconds   = $time_span - 60*$minutes;

  if ($opt_verbose) {
    printf "Running time is %d:%02d minutes.\n", $minutes, $seconds;
  }
}

# Given a directory name, attempt to make all necessary directories.
sub recursive_mkdir {
  my $dir = shift;

  # Remove extra /'s.
  $dir =~ s:/{2,}:/:g;

  my $path;
  if ($dir =~ m:^/:) {
    $path = '/';
  }
  else {
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

sub get_time_interval {
  my $find_times_ref = shift;

  my @time = localtime;

  interval_search($time[2] + $time[1]/60.0, $find_times_ref);
}

sub watch_data_sources {
  unless (@_ == 4) {
    confess "$0: watch_data_sources: passed wrong number of arguments.\n";
  }

  my ($config_filename,
      $config_options,
      $config_files,
      $config_plots) = @_;

  my $rrd_data_files_ref  = {};
  my $old_found_files_ref = {};
  my $new_found_files_ref;
  my $group_files_ref;
  my $gif_files_ref = {list => [], hash => {}};

  # Load the current state of the source data files.
  my $saved_source_file_state = &load_state($config_options->{state_file});

  # The first time through we always find new files.  Determine the
  # time interval that the current time is in, where the intervals are
  # defined as the times to have Orca find new source data files.
  my $find_new_files = 1;
  my $time_interval  = get_time_interval($config_options->{find_times});

  # This hash holds the next time to load the data from all the files
  # in a particular group.
  my %group_load_time;

  for (;;) {
    # If Orca is being forced to find new files, then set up the
    # variables here.  Determine the current time interval we're in.
    if ($force_find_files) {
      $force_find_files = 0;
      $find_new_files   = 1;
      $time_interval    = get_time_interval($config_options->{find_times});
    }

    my $found_new_files = 0;
    if ($find_new_files) {
      $find_new_files = 0;
      if ($opt_verbose) {
        print "Finding files and setting up data structures at ",
              scalar localtime, ".\n";
      }

      # Get the list of files to watch and the plots that will be
      # created.  If files have been previously found, then use those
      # files in the search for new ones.
      $old_found_files_ref = $new_found_files_ref if $new_found_files_ref;
      ($found_new_files, $new_found_files_ref, $group_files_ref) =
         &find_files($config_filename,
                     $config_options,
                     $config_files,
                     $config_plots,
                     $saved_source_file_state,
                     $old_found_files_ref,
                     $rrd_data_files_ref,
                     $gif_files_ref);

      # Go through all of the groups and for each group and all of the
      # files in the group find the next load time in the future.
      undef %group_load_time;
      foreach my $group (keys %$group_files_ref) {
        my $group_load_time = 1e20;
        foreach my $filename (@{$group_files_ref->{$group}}) {
          my $load_time    = $new_found_files_ref->{$filename}->next_load_time;
          $group_load_time = $load_time if $load_time < $group_load_time;
        }
        $group_load_time{$group} = $group_load_time;
      }
    }

#    system("/bin/ps -p $$ -o\"rss vsz pmem time user pid comm\"");

    # Because the amount of data loaded from the source data files can
    # be large, go through each group of source files, load all of the
    # data for that group, flush the data, and then go on to the next
    # group.  For each source file that had new data, note the RRDs
    # that get updated from that source file.  When going through each
    # group note the time when the group should be next examined for
    # updates.  Only note the time to sleep to if it is in the future.
    my $updated_source_files = 0;
    my $sleep_till_time;
    foreach my $group (sort keys %group_load_time) {

      # Skip this group if the load time has not been reached and if
      # no new files were found.
      my $group_load_time = $group_load_time{$group};
      if ($group_load_time > time) {
        $sleep_till_time = $group_load_time unless $sleep_till_time;
        $sleep_till_time = $group_load_time if $group_load_time < $sleep_till_time;
        next unless $found_new_files;
      }

      if ($opt_verbose) {
        print "Loading new data", $group ? " from $group" : "", ".\n";
      }

      my %this_group_rrds;
      my $number_new_data_points = 0;
      $group_load_time = 1e20;
      foreach my $filename (@{$group_files_ref->{$group}}) {
        my $source_file = $new_found_files_ref->{$filename};
        my $number      = $source_file->load_new_data;
        $number_new_data_points += $number;
        if ($number) {
          foreach my $rrd ($source_file->rrds) {
            $this_group_rrds{$rrd} = $rrd_data_files_ref->{$rrd};
          }
          if ($opt_verbose) {
            printf "  Read %5d data point%s from `$filename'.\n",
              $number, $number > 1 ? 's' : '';
          }
        }
        my $load_time    = $source_file->next_load_time;
        $group_load_time = $load_time if $load_time < $group_load_time;
      }

      # Update the load time for this group.
      $group_load_time{$group} = $group_load_time;

      # Now that the source data files have been read, recalculate the
      # time to sleep to if the load time for this group is in the
      # future.
      if (time < $group_load_time) {
        $sleep_till_time = $group_load_time unless $sleep_till_time;
        $sleep_till_time = $group_load_time if $group_load_time < $sleep_till_time;
      }

      next unless $number_new_data_points;
      $updated_source_files = 1;

      # Flush the data that has been loaded for each plot.  To keep
      # the RRD that was just created in the system's cache, plot GIFs
      # that only depend on this RRD, since GIFs that depend upon two
      # or more RRDs will most likely be generated more than once and
      # the other required RRDs may not exist yet.
      if ($opt_verbose) {
        print "Flushing new data", $group ? " from $group" : "", ".\n";
      }
      foreach my $rrd (sort {$a->name cmp $b->name} values %this_group_rrds) {
        $rrd->flush_data;
        next if $opt_rrd_update_only;
        foreach my $gif ($rrd->created_gifs) {
          next if $gif->rrds > 1;
          $gif->plot;
        }
      }
    }

    # Save the current state of the source data files.
    if ($found_new_files or $updated_source_files) {
      &save_state($config_options->{state_file}, $new_found_files_ref);
    }

    # Create the HTML and GIF files now.
    unless ($opt_rrd_update_only) {
      # Plot the data in each gif.
      print "Updating GIFs.\n" if $opt_verbose;;
      foreach my $gif (@{$gif_files_ref->{list}}) {
        $gif->plot;
      }

      # Make the HTML files.
      if ($found_new_files) {
        &create_html_files($config_options,
                           $config_files,
                           $config_plots,
                           $new_found_files_ref,
                           $group_files_ref,
                           $gif_files_ref);
        $found_new_files = 0;
      }
    }

    # Return now if this loop is being run only once.
    last if $opt_once_only;

    # Now decide if we need to find new files.  If the time interval
    # does change, then find new files only if the new time interval
    # is not -1, which signifies that the time is before the first
    # find_times.
    my $new_time_interval = get_time_interval($config_options->{find_times});
    if ($time_interval != $new_time_interval) {
      $find_new_files = 1 if $new_time_interval != -1;
      $time_interval  = $new_time_interval;
    }

    # Sleep if the sleep_till_time has not passed.  If sleep_till_time
    # is now defined, then loop immediately.  Sleep at least one
    # second if we need to sleep at all.
    if ($sleep_till_time) {
      my $now = time;
      if ($sleep_till_time > $now) {
        if ($opt_verbose) {
          print "Sleeping at ",
                scalar localtime($now),
                " until ",
                scalar localtime($sleep_till_time),
                ".\n";
        }
        sleep($sleep_till_time - $now + 1);
      }
    }
  }
}

# Take a string and capatialize only the first character of the
# string.
sub Capatialize {
  my $string = shift;
  substr($string, 0, 1) = uc(substr($string, 0, 1));
  $string;
}

# Sort group names depending upon the type of characters in the
# group's name.
sub sort_group_names {
  my $a_name = ref($a) ? $a->group : $a;
  my $b_name = ref($b) ? $b->group : $b;

  # If both names are purely digits, then do a numeric comparison.
  if ($a_name =~ /^[-]?\d+$/ and $b_name =~ /[-]?\d+$/) {
    return $a_name <=> $b_name;
  }

  # If the names are characters followed by digits, then compare the
  # characters, and if they match, compare the digits.
  my ($a_head, $a_digits, $b_head, $b_digits);
  if (($a_head, $a_digits) = $a_name =~ /^([-a-zA-Z]+)(\d+)$/ and
      ($b_head, $b_digits) = $b_name =~ /^([-a-zA-Z]+)(\d+)$/) {
    my $return = $a_head cmp $b_head;
    if ($return) {
      return $return;
    }
    else {
      return $a_digits <=> $b_digits;
    }
  }

  $a_name cmp $b_name;
}

# Create all of the different HMTL files with all of the proper HREFs
# to the GIFs.
sub create_html_files {
  my ($config_options,
      $config_files,
      $config_plots,
      $found_files_ref,
      $group_files_ref,
      $gif_files_ref) = @_;

  my $html_dir         = $config_options->{html_dir};
  my $index_filename   = "$html_dir/index.html";

  print "Creating HTML files in `$html_dir/'.\n" if $opt_verbose;

  # Create the main HTML index.html file.
  my $index_html = Orca::HTMLFile->new($index_filename,
                                       $config_options->{html_top_title},
                                       $config_options->{html_page_header},
                                       $config_options->{html_page_footer});
  unless ($index_html) {
    warn "$0: warning: cannot open `$index_filename' for writing: $!\n";
    return;
  }
  $index_html->print("<hr>\n<font size=\"-2\">");

  # The first step is to create the HTML files for each different
  # group.  This is only done if there is more than one group gathered
  # from the configuration and input data files.  If there is more
  # than one group first list the different available groups and
  # create for each group an HTML file that contains HREFs to the GIFs
  # for that group.  Also create an HTML file for the daily, weekly,
  # monthly, and yearly GIFs.

  # This variable sets the number of groups to place into a single
  # row.
  my $table_number_columns = 9;
  my @table_columns;

  # Go through each group.  If there is only one group and that group
  # does not have a name, then give the group the name Everything.
  # However, only refer to the name Everything in naming HTML files
  # and in HTML content.  Use the original group name as a hash key.
  my $number_groups = keys %$group_files_ref;
  $index_html->print("<h2>Available Targets</h2>\n\n<table>\n");
  foreach my $group (sort sort_group_names keys %$group_files_ref) {
    my $html_group = ($number_groups == 1 and !$group) ? 'Everything' : $group;

    # Create the HTML code for the main index.html file.
    my $group_basename = strip_key_name($html_group);
    my $element = "<table border=2><tr><td><b>$html_group</b></td></tr>\n<tr><td>\n";
    foreach my $plot_type (@gif_plot_type) {
      $element      .= "<a href=\"$group_basename-$plot_type.html\">";
      my $Plot_Type  = Capatialize($plot_type);
      $element      .= "$Plot_Type</a><br>\n";
    }
    $element .= "<a href=\"$group_basename-all.html\">All</a></td></tr>\n";
    $element .= "</table>\n\n";

    push(@table_columns, "<td>$element</td>");
    if (@table_columns == $table_number_columns) {
      $index_html->print("<tr valign=top>" . join('', @table_columns) . "</tr>\n");
      @table_columns = ();
    }

    # Create the daily, weekly, monthly, yearly, and all HTML files
    # for this group.
    my @html_files;
    foreach my $plot_type (@gif_plot_type, 'all') {
      my $href      = "$group_basename-$plot_type.html";
      my $filename  = "$html_dir/$href";
      my $Plot_Type = Capatialize($plot_type);
      my $fd = Orca::HTMLFile->new($filename,
                                   "$Plot_Type $html_group",
                                   $config_options->{html_page_header},
                                   $config_options->{html_page_footer});
      unless ($fd) {
        warn "$0: warning: cannot open `$filename' for writing: $!\n";
        next;
      }
      push (@html_files, {fd        => $fd,
                          href      => $href,
                          plot_type => $plot_type,
                          Plot_Type => $Plot_Type});
    }

    # At the top of the daily, weekly, monthly, yearly, and all HTML
    # files add HREFs to the other date span HTML files in the same
    # group.
    my $href_html;
    foreach my $plot_type (@html_files) {
      $href_html .= "<a href=\"$plot_type->{href}\">" .
                    "$plot_type->{Plot_Type} $group</a><br>\n";
    }
    foreach my $html_file (@html_files) {
      $html_file->{fd}->print($href_html);
    }

    # Use only those GIFs now that have the same group name as the
    # HTML files that are being created.
    my @gifs = grep {$group eq $_->group} @{$gif_files_ref->{list}};
    if (@gifs > 1) {
      my $href_html = "<hr>";
      for (my $i=0; $i<@gifs; ++$i) {
        $href_html .= "<a href=\"#$i\">[" .
                      replace_group_name($gifs[$i]->plot_ref->{title}, '') .
                      "]</a><spacer size=10>\n";
      }
      foreach my $html_file (@html_files) {
        $html_file->{fd}->print($href_html);
      }
    }

    # Add the images to the HTML files.
    for (my $i=0; $i<@gifs; ++$i) {
      my $gif      = $gifs[$i];
      my $name     = $gif->name;
      my $title    = replace_group_name($gif->plot_ref->{title}, $gif->group);
      my $href     = "href=\"" . strip_key_name($name) . ".html\"";
      my $sub_dir  = $config_files->{$gif->files_key}{sub_dir};
      my $gif_size = $gif->gif_img_src_size;

      foreach my $html_file (@html_files) {
        $html_file->{fd}->print("<hr>\n<h2><a ${href} name=\"$i\">$html_file->{Plot_Type} " .
                                "$title</a></h2>\n");
      }

      # Put the proper GIFs into each HTML file.  The all HTML file is
      # listed last and requires special handling.
      for (my $j=0; $j<@html_files-1; ++$j) {
        my $gif_filename = "$name-$html_files[$j]{plot_type}.gif";
        $gif_filename = "$group/$gif_filename" if $sub_dir;
        my $html = "<a $href><img src=\"$gif_filename\" $gif_size " .
                   "alt=\"$html_files[$j]{Plot_Type} $title\"></a>\n";
        $html_files[$j]{fd}->print($html);
        $html_files[-1]{fd}->print($html);
      }
    }

    foreach my $html_file (@html_files) {
      $html_file->{fd}->print("<hr>\n");
    }
  }

  # If there are any remaining groups to display, do it now.
  if (@table_columns) {
    $index_html->print("<tr valign=top>" .
                       join('', @table_columns) .
                       "</tr>\n");
  }
  $index_html->print("</table>\n\n\n<br>\n<hr>\n" .
                     "<h2>Available Data Sets</h2>\n\n");

  # Here the different available plots are listed and the HTML files
  # created that contain the HREFs to the proper GIFs.  The HTML files
  # created here HREF to the GIFs that are created for a single plot.
  # There are several steps to do here.  First, get a list of the
  # different plots.  For each different type of plot, create a list
  # GIFs that show that plot.  Use the @gifs_by_type array to keep the
  # ordering in the type of GIFs and the %gifs_by_type to hold
  # references to an array for each type of GIF.
  $index_html->print("<table>\n");

  # This sets the number of plot types to place into a single row in
  # the main index.html.
  $table_number_columns = 1;
  @table_columns = ();

  # Go through all of the configured plots.
  for (my $i=0; $i<@$config_plots; ++$i) {

    next unless @{$config_plots->[$i]{creates}};

    # Create an ordered list of GIFs sorted on the legend name for
    # each GIF.  Remember, each GIF represented here actually
    # represents the set of daily, weekly, monthly, and yearly GIF
    # files.  %gif_legend_no_group is a hash keyed by the GIF that
    # contains the legend with no group substitution for the GIF.  The
    # %legends hash is keyed by the legend name with no group
    # substitution and contains a reference to an array of GIFs that
    # have the same legend name.
    my %gif_legend_no_group;
    my %same_legends_gif_list;
    foreach my $gif (@{$config_plots->[$i]{creates}}) {
      my $legend_no_group = replace_group_name($gif->plot_ref->{title}, '');
      $gif_legend_no_group{$gif} = $legend_no_group; 
      
      unless (defined $same_legends_gif_list{$legend_no_group}) {
        $same_legends_gif_list{$legend_no_group} = [];
      }
      push(@{$same_legends_gif_list{$legend_no_group}}, $gif);
    }

    # Put together the correctly ordered list of GIFs using the array
    # references in the legends hash.  Sort the GIFs using the special
    # sorting routine for group names.
    my @gifs;
    foreach my $legend_no_group (sort keys %same_legends_gif_list) {
      @{$same_legends_gif_list{$legend_no_group}} =
        sort sort_group_names @{$same_legends_gif_list{$legend_no_group}};
      push(@gifs, @{$same_legends_gif_list{$legend_no_group}});
    }

    # This hash keyed by legend name holds an array of references to a
    # hash of file descriptor, HREF and plot type.
    my %legend_html_files;

    # Now for each set of daily, weekly, monthly and yearly GIFs, go
    # through and create the correct HTML files.
    foreach my $gif (@gifs) {

      my $no_group_name   = strip_key_name($gif->no_group_name);
      my $legend_no_group = $gif_legend_no_group{$gif};

      # If this is the first time that this legend has been seen in
      # for creating the proper HTML files, then create the new HTML
      # files and set up the top of them properly and place into the
      # main index.html the proper HREFs to these files.
      unless (defined $legend_html_files{$legend_no_group}) {

        # Now create the HTML files for the daily, weekly, monthly,
        # yearly, and all plots.  Use the legend name to create this
        # list.
        $legend_html_files{$legend_no_group} = [];
        foreach my $plot_type (@gif_plot_type, 'all') {
          my $href      = "$no_group_name-$plot_type.html";
          my $filename  = "$html_dir/$href";
          my $Plot_Type = Capatialize($plot_type);
          my $fd = Orca::HTMLFile->new($filename,
                                       "$Plot_Type $legend_no_group",
                                       $config_options->{html_page_header},
                                       "<hr>\n$config_options->{html_page_footer}");
          unless ($fd) {
            warn "$0: warning: cannot open `$filename' for writing: $!\n";
            next;
          }
          push(@{$legend_html_files{$legend_no_group}},
               {fd        => $fd,
                href      => $href,
                plot_type => $plot_type,
                Plot_Type => $Plot_Type});
        }

        # For each of the daily, weekly, monthy, yearly and all HTML
        # files add at the top of the file HREFs to all of the daily,
        # weekly, monthly, yearly and all HTML files.  Also add HREFs
        # to the different groups later on in the same HTML file.
        my @legend_html_files = @{$legend_html_files{$legend_no_group}};
        my $href_html;
        foreach my $plot_type (@legend_html_files) {
          $href_html .= "<a href=\"$plot_type->{href}\">" .
                        "$plot_type->{Plot_Type} $legend_no_group</a><br>\n";
        }

        # Add to the top of the file HREFs to all of the different
        # groups in the HTML file.  This makes traversing the HTML
        # page easier.  Do this if there are two or more groups in
        # this HTML page.
        if (@{$same_legends_gif_list{$legend_no_group}} > 1) {
          $href_html .= "<hr>\n";
          foreach my $legend_gif (@{$same_legends_gif_list{$legend_no_group}}) {
            my $group = $legend_gif->group;
            $href_html .= "<a href=\"#$group\">[$group]</a><spacer size=10>\n";
          }
        }
        foreach my $html_file (@legend_html_files) {
          $html_file->{fd}->print($href_html);
        }

        # Create the HTML code that goes into the main index.html that
        # links to these other HTML files.
        my $element = "<td><b>$legend_no_group</b></td>\n";
        foreach my $plot_type (@gif_plot_type, 'all') {
          $element .= "<td><a href=\"$no_group_name-$plot_type.html\">";
          $element .= Capatialize($plot_type) . "</a></td>\n";
        }
        push(@table_columns, $element);
        if (@table_columns == $table_number_columns) {
          $index_html->print("<tr>" . join('', @table_columns) . "</tr>\n");
          @table_columns = ();
        }
      }

      # At this point the HTML files for this set of daily, weekly,
      # monthly, and yearly GIFs have been opened.  Now create the
      # summary HTML file that contains only four GIF images, the
      # daily, weekly, monthly, and yearly GIFs for a particular plot
      # for a particular group.
      my $with_group_name   = strip_key_name($gif->name);
      my $legend_with_group = replace_group_name($gif->plot_ref->{title},
                                                 $gif->group);
      my $summarize_name = "$html_dir/$with_group_name.html";
      my $summarize_html = Orca::HTMLFile->new($summarize_name,
                                               $legend_with_group,
                                               $config_options->{html_page_header},
                                               $config_options->{html_page_footer});
      unless ($summarize_html) {
        warn "$0: warning: cannot open `$summarize_name' for writing: $!\n";
        next;
      }
      my $sub_dir      = $config_files->{$gif->files_key}{sub_dir};
      my $gif_filename = $with_group_name;
      $gif_filename    = $gif->group . "/$gif_filename" if $sub_dir;
      my $gif_size     = $gif->gif_img_src_size;
      foreach my $plot_type (@gif_plot_type) {
        my $Plot_Type = Capatialize($plot_type);
        $summarize_html->print("<hr>\n<h2>$Plot_Type $legend_with_group</h2>\n",
                               "<img src=\"$gif_filename-$plot_type.gif\"",
                               $gif_size,
                               "alt=\"$Plot_Type $legend_with_group\">\n");
      }

      # Now add the images into each HTML file.
      my $name  = $gif->name;
      my $group = $gif->group;

      my $href = "href=\"$with_group_name.html\"";

      my @legend_html_files = @{$legend_html_files{$legend_no_group}};
      $legend_html_files[-1]{fd}->print("<hr>\n<h2><a ${href} name=\"$group\">$group $legend_no_group</a></h2>\n");
      for (my $i=0; $i<@legend_html_files-1; ++$i) {
        my $Plot_Type    = $legend_html_files[$i]{Plot_Type};
        my $gif_filename = "$name-$legend_html_files[$i]{plot_type}.gif";
        $gif_filename    = "$group/$gif_filename" if $sub_dir;
        my $html = "<a $href><img src=\"$gif_filename\" $gif_size " .
                   "alt=\"$Plot_Type $group $legend_no_group\"></a>\n";
        $legend_html_files[$i]{fd}->print("<hr>\n<h2><a ${href} name=\"$group\">$Plot_Type $group $legend_no_group</a></h2>\n");
        $legend_html_files[$i]{fd}->print($html);
        $legend_html_files[-1]{fd}->print($html);
      }
    }
  }

  if (@table_columns) {
    $index_html->print("<tr>" . join('', @table_columns) . "</tr>\n");
  }
  $index_html->print("\n</table>\n\n</font>\n<hr>\n");
}

sub perl_glob {
  my $regexp = shift;

  # The current directory tells where to open the directory for
  # matching.
  my $current_dir = @_ ? shift : '.';

  # Remove all multiple /'s, since they will confuse perl_glob.
  $regexp =~ s:/{2,}:/:g;

  # If the regular expression begins with a /, then remove it from the
  # regular expression and set the current directory to /.
  $current_dir = '/' if $regexp =~ s:^/::;

  # Get the first file path element from the regular expression to
  # match.
  my @regexp_elements = split(m:/:, $regexp);
  my $first_regexp = shift(@regexp_elements);

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
    return grep { -f } map { "$current_dir/$_" } @matches;
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

  return @results;
}

# Email the list of people a message.
sub email_message {
  my ($people, $subject) = @_;

  return unless $people;

  if (open(SENDMAIL, "|/usr/lib/sendmail -oi -t")) {
    print SENDMAIL <<"EOF";
To: $people
Subject: Orca: $subject
 
Orca: $subject
EOF
    close(SENDMAIL) or
      warn "$0: warning: sendmail did not close: $!\n";
  }
  else {
    warn "$0: warning: cannot fork for sendmail: $!\n";
  }
}

# Replace any %g with the group and any %G's with a capitalized
# version of the group in the title string with the group name.
sub replace_group_name {
  my ($title, $group) = @_;

  my $Group = $group;
  substr($Group, 0, 1) = uc(substr($Group, 0, 1));

  $title =~ s/%g/$group/ge;
  $title =~ s/%G/$Group/ge;
  $title =~ s/^\s+//;
  $title =~ s/\s+$//;
  $title;
}

# Strip special characters from key names.
sub strip_key_name {
  my $name = shift;
  $name =~ s/:/_/g;
  $name =~ s:/:_per_:g;
  $name =~ s:\s+:_:g;
  $name =~ s:%:_percent_:g;
  $name =~ s:#:_number_:g;
  $name =~ s:_{2,}:_:g;

  # Remove trailing _'s.
  $name =~ s:_+$::;
  $name =~ s:_+,:,:g;
  $name;
}

# Return an list of the unique elements of a list.
sub unique {
  my %a;
  my @unique;
  foreach my $element (@_) {
    unless (defined $a{$element}) {
      push(@unique, $element);
      $a{$element} = 1;
    }
  }
  @unique;
}

sub find_files {
  unless (@_ == 8) {
    confess "$0: find_files passed wrong number of arguments.\n";
  }

  my ($config_filename,
      $config_options,
      $config_files,
      $config_plots,
      $saved_source_file_state,
      $old_found_files_ref,
      $rrd_data_files_ref,
      $gif_files_ref) = @_;

  my $new_found_files_ref = {};
  my $group_files         = {};
  my $found_new_files     = 0;

  foreach my $files_key (sort keys %$config_files) {
    # Find all the files matching the regular expression.
    my @filenames;
    foreach my $regexp (@{$config_files->{$files_key}{find_files}}) {
      push(@filenames, grep {-r $_} perl_glob($regexp));
    }
    unless (@filenames) {
      warn "$0: warning: no files found for `find_files' for `files $files_key' in `$config_filename'.\n";
      next;
    }

    # Calculate which group the file belongs in and create a hash
    # listing the filenames for each group.
    my %tmp_files_by_group;
    my %tmp_group_by_file;
    foreach my $filename (unique(@filenames)) {
      # Find the group that the files belong in.
      my $group = undef;
      foreach my $regexp (@{$config_files->{$files_key}{find_files}}) {
        my @result = ($filename =~ $regexp);
        if (@result) {
          # There there are no ()'s in the regexp, then change (1) to
          # ().
          @result = () if (@result == 1 and $result[0] eq '1');
          # Remove any empty matches from @result.
          $group = join('_', grep {length($_)} @result);
          last;
        }
      }
      unless (defined $group) {
        warn "$0: warning: internal error: found `$filename' but no regexp match for it.\n";
        next;
      }
      unless (defined $tmp_files_by_group{$group}) {
        $tmp_files_by_group{$group} = [];
      }
      push(@{$tmp_files_by_group{$group}}, $filename);
      $tmp_group_by_file{$filename} = $group;
    }

    # Create a new list of filenames sorted by group name and inside
    # each group sorted by filename.  This will cause the created
    # plots to appear in group order.
    @filenames = ();
    foreach my $key (sort keys %tmp_files_by_group) {
      push(@filenames, sort @{$tmp_files_by_group{$key}});
    }

    # Now for each file, create the Orca::SourceDataFile object that
    # manages that file and the GIFs that get generated from the file.
    # Delete from the list of filenames those files that have not
    # successfully created Orca::SourceDataFile objects.
    for (my $i=0; $i<@filenames;) {
      my $filename = $filenames[$i];
      # Create the object that contains this file.  Take care if the
      # same file is being used in another files group.
      unless (defined $new_found_files_ref->{$filename}) {
        if (defined $old_found_files_ref->{$filename}) {
          $new_found_files_ref->{$filename} = $old_found_files_ref->{$filename};
        }
        else {
          print "  $filename\n" if $opt_verbose;
          my $data_file =
            Orca::SourceDataFile->new($filename,
                                      $config_files->{$files_key}{interval},
                                      $config_options->{late_interval},
                                      $config_files->{$files_key}{reopen},
                                      $config_files->{$files_key}{column_description},
                                      $config_files->{$files_key}{date_source},
                                      $config_files->{$files_key}{date_format},
                                      $config_options->{warn_email},
                                      $saved_source_file_state);
          unless ($data_file) {
            warn "$0: warning: cannot process `$filename'.\n";
            splice(@filenames, $i, 1);
            next;
          }
          $new_found_files_ref->{$filename} = $data_file;
          $found_new_files = 1;
        }
      }
      ++$i;
    }

    # Register with each source data file the files keys that use it.
    foreach my $filename (@filenames) {
      $new_found_files_ref->{$filename}->add_files_keys($files_key);
    }

    # Go through each source data file and register the new plots to
    # create.
    foreach my $filename (@filenames) {
      my $group = $tmp_group_by_file{$filename};
      $new_found_files_ref->{$filename}->add_plots($config_options,
                                                   $config_files,
                                                   $config_plots,
                                                   $files_key,
                                                   $group,
                                                   $rrd_data_files_ref,
                                                   $gif_files_ref);
      unless (defined $group_files->{$group}) {
        $group_files->{$group} = [];
      }
      push(@{$group_files->{$group}}, $filename);
    }
  }
  my @found_files = keys %$new_found_files_ref;

  die "$0: no data source files found.\n" unless @found_files;

  return ($found_new_files,
          $new_found_files_ref,
          $group_files);
}

# This loads the old source file state information.
my @save_state_keys;
sub load_state {
  my $state_file = shift;

  my %state;

  unless (@save_state_keys) {
    @save_state_keys = qw(_filename _last_data_time _last_read_time);
  }

  unless (open(STATE, $state_file)) {
    warn "$0: warning: cannot open state file `$state_file' for reading: $!\n";
    return \%state;
  }

  print "Loading state from `$state_file'.\n" if $opt_verbose;

  # Get the first line which contains the hash key name.  Check that
  # the first field is _filename.
  my $line = <STATE>;
  defined($line) or return \%state;
  chomp($line);
  my @keys = split(' ', $line);
  unless ($keys[0] eq '_filename') {
    warn "$0: warning: ignoring state file `$state_file': incorrect first field.\n";
    return \%state;
  }

  while (<STATE>) {
    my @line = split;
    if (@line != @keys) {
      warn "$0: inconsistent number of elements on line $. of `$state_file'.\n";
      next;
    }

    my $filename = $line[0];
    for (my $i=1; $i<@keys; ++$i) {
      $state{$filename}{$keys[$i]} = $line[$i];
    }
  }

  close(STATE) or
    warn "$0: warning: cannot close `$state_file' for reading: $!\n";

  \%state;
}

# Write the state information for the source data files.
sub save_state {
  my ($state_file, $state_ref) = @_;

  print "Saving state into `$state_file'.\n" if $opt_verbose;

  if (open(STATE, "> $state_file.tmp")) {

    print STATE "@save_state_keys\n";

    foreach my $filename (sort keys %$state_ref) {
      foreach my $key (@save_state_keys) {
        print STATE $state_ref->{$filename}{$key}, ' ';
      }
      print STATE "\n";
    }

    close(STATE) or
      warn "$0: warning: cannot close `$state_file' for writing: $!\n";

    rename("$state_file.tmp", $state_file) or
      warn "$0: warning: cannot rename `$state_file.tmp' to `$state_file': $!\n";
  }
  else {
    warn "$0: warning: cannot open state file `$state_file.tmp' for writing: $!\n";
  }
}

my @cc_required_options;
my @cc_required_files;
my @cc_required_plots;
my @cc_optional_options;
my @cc_optional_files;
my @cc_optional_plots;

sub check_config {
  my ($config_filename, $config_options, $config_files, $config_plots) = @_;

  unless (@cc_required_options) {
    @cc_required_options   = qw(state_file
                                data_dir
                                html_dir);
    @cc_required_files     = qw(column_description
                                date_source
                                find_files
                                interval);
    @cc_required_plots     = qw(data
                                source);
    @cc_optional_options   = qw(expire_gifs
                                html_page_footer
                                html_page_header
                                html_top_title
                                late_interval
                                sub_dir
                                warn_email);
    @cc_optional_files     = qw(date_format
                                reopen);
    @cc_optional_plots     = qw(flush_regexps
                                plot_width
                                plot_height
                                rigid_min_max);
    # This is a special variable that gets used in add_plots.
    @::cc_default_colors   =   ('00ff00',	# Green
                                '0000ff',	# Blue
                                'ff0000',	# Red
                                'a020f0',	# Magenta
                                'ffa500',	# Orange
                                'a52a2a',	# Brown
                                '00ffff');	# Cyan
  }

  # If data_dir is not set, then use base_dir.  Only die if both are
  # not set.
  unless (defined $config_options->{data_dir}) {
    if (defined $config_options->{base_dir}) {
      $config_options->{data_dir} = $config_options->{base_dir};
    }
    else {
      die "$0: error: must define `data_dir' in `$config_filename'.\n";
    }
  }

  # Check that we the required options are satisfied.
  foreach my $option (@cc_required_options) {
    unless (defined $config_options->{$option}) {
      die "$0: error: must define `$option' in `$config_filename'.\n";
    }
  }

  # Check if the data_dir and html_dir directories exist.
  foreach my $dir_key ('html_dir', 'data_dir') {
    my $dir = $config_options->{$dir_key};
    die "$0: error: please create $dir_key `$dir'.\n" unless -d $dir;
  }

  # Set any optional options to '' if it isn't defined.
  foreach my $option (@cc_optional_options) {
    unless (defined $config_options->{$option}) {
      $config_options->{$option} = '';
    }
  }

  # Late_interval is a valid mathematical expression. Replace the word
  # interval with $_[0].  Try the subroutine to make sure it works.
  unless ($config_options->{late_interval}) {
    $config_options->{late_interval} = 'interval';
  }
  my $expr = "sub { $config_options->{late_interval}; }";
  $expr =~ s/interval/\$_[0]/g;
  my $sub;
  {
    local $SIG{__WARN__} = sub { die $_[0] };
    $sub = eval $expr;
  }
  die "$0: cannot evaluate command for `late_interval' on\n   $expr\nOutput: $@\n" if $@;
  {
    local $SIG{__WARN__} = sub { die $_[0] };
    eval '&$sub(3.1415926) + 0;';
  }
  die "$0: cannot execute command for `late_interval' on\n$expr\nOutput: $@\n" if $@;
  $config_options->{late_interval} = $sub;

  # Convert the list of find_times into an array of fractional hours.
  my @find_times;
  unless (defined $config_options->{find_times}) {
    $config_options->{find_times} = '';
  }
  foreach my $find_time (split(' ', $config_options->{find_times})) {
    if (my ($hours, $minutes) = $find_time =~ /^(\d{1,2}):(\d{2})/) {
      # Because of the regular expression match we're doing, the hours
      # and minutes will only be positive, so check for hours > 23 and
      # minutes > 59.
      unless ($hours < 24) {
        warn "$0: warning: ignoring find_times `$find_time': hours must be less than 24.\n";
        next;
      }
      unless ($minutes < 60) {
        warn "$0: warning: ignoring find_times `$find_time': minutes must be less than 60.\n";
        next;
      }
      push(@find_times, $hours + $minutes/60.0);
    }
    else {
      warn "$0: warning: ignoring find_times `$find_time': illegal format.\n";
    }
  }
  $config_options->{find_times} = [ sort { $a <=> $b } @find_times ];

  # There must be at least one list of files.
  unless (keys %$config_files) {
    die "$0: error: must define at least one `files' in `$config_filename'.\n";
  }

  # For each files parameter there are required options.  Convert the
  # unblessed reference to a hash to a Orca::Config::FilesGroup
  # object.
  foreach my $files_key (keys %$config_files) {
    my $files_group = Orca::Config::FilesGroup->new($config_files->{$files_key});
    $config_files->{$files_key} = $files_group;

    foreach my $option (@cc_required_files) {
      unless (defined $files_group->{$option}) {
        die "$0: error: must define `$option' for `files $files_key' in `$config_filename'.\n";
      }
    }

    # Optional files options will be set to '' here if they haven't
    # been set by the user.
    foreach my $option (@cc_optional_files) {
      unless (defined $files_group->{$option}) {
        $files_group->{$option} = '';
      }
    }

    # Check that the date_source is either column_name followed by a
    # column name or file_mtime for the file modification time.  If a
    # column_name is used, then the date_format is required.
    my $date_source = $files_group->{date_source}[0];
    if ($date_source eq 'column_name') {
      unless (@{$files_group->{date_source}} == 2) {
        die "$0: error: incorrect number of arguments for `date_source' for `files $files_key'.\n";
      }
      unless (defined $files_group->{date_format}) {
        die "$0: error: must define `date_format' with `date_source columns ...' for `files $files_key'.\n";
      }
    }
    else {
      unless ($date_source eq 'file_mtime') {
        die "$0: error: illegal argument for `date_source' for `files $files_key'.\n";
      }
    }
    $files_group->{date_source}[0] = $date_source;

    # Check that we have a valid regular expression for find_files and
    # get a unique list of them.  Also to see if the find_files match
    # contains any ()'s that will split the files into groups.  If so,
    # then we will use subdirectories to create our structure.  If a
    # find begins with \./, then remove it from the path.  Be careful
    # of a search on only \./.  Also remove any /\./'s in the path.
    # Searches on both of these are unnecessary, since they involve
    # searching on a current directory.  However, do not remove /./'s
    # since this will match single character files and directories.
    my $sub_dir = 0;
    my %find_files;
    my $number_finds = @{$files_group->{find_files}};
    for (my $i=0; $i<$number_finds; ++$i) {
      my $orig_find = $files_group->{find_files}[$i];
      my $find = $orig_find;
      $find =~ s:^\\./::;
      $find =~ s:/\\./:/:g;
      $find = $orig_find unless $find;
      $files_group->{find_files}[$i] = $find;
      my $test_string = 'abcdefg';
      local $SIG{__WARN__} = sub { die $_[0] };
      eval { $test_string =~ /$find/ };
      die "$0: error: illegal regular expression in `find_files $orig_find' for `files $files_key' in `$config_filename':\n$@\n" if $@;
      $find_files{$find} = 1;
      $sub_dir = 1 if $find =~ m:\(.+\):;
    }
    $files_group->{find_files} = [sort keys %find_files];
    $files_group->{sub_dir}    = $sub_dir || $config_options->{sub_dir};
  }

  # There must be at least one plot.
  unless (@$config_plots) {
    die "$0: error: must define at least one `plot' in `$config_filename'.\n";
  }

  # Foreach plot there are required options.  Create default options
  # if the user has not done so.
  for (my $i=0; $i<@$config_plots; ++$i) {
    my $plot = Orca::Config::Plot->new($config_plots->[$i]);
    $config_plots->[$i] = $plot;

    my $j = $i + 1;
    foreach my $option (@cc_required_plots) {
      unless (defined $plot->{$option}) {
        die "$0: error: must define `$option' for `plot' #$j in `$config_filename'.\n";
      }
    }

    # Create an array for each plot that will have a list of GIFs that
    # were generated from this plot.
    $plot->{creates} = [];

    # Optional options will be set to '' here if they haven't been set
    # by the user.
    foreach my $option (@cc_optional_plots) {
      unless (defined $plot->{$option}) {
        $plot->{$option} = '';
      }
    }

    # Set the default plot width and height.
    $plot->{plot_width}  = 500 unless $plot->{plot_width};
    $plot->{plot_height} = 125 unless $plot->{plot_height};

    # Set the plot minimum and maximum values to U unless they are
    # set.
    unless (defined $plot->{data_min}) {
      $plot->{data_min} = 'U';
    }
    unless (defined $plot->{data_max}) {
      $plot->{data_max} = 'U';
    }

    # The data type must be either gauge, absolute, or counter.
    if (defined $plot->{data_type}) {
      my $type = substr($plot->{data_type}, 0, 1);
      if ($type eq 'g' or $type eq 'G') {
        $plot->{data_type} = 'GAUGE';
      }
      elsif ($type eq 'c' or $type eq 'C') {
        $plot->{data_type} = 'COUNTER';
      }
      elsif ($type eq 'a' or $type eq 'A') {
        $plot->{data_type} = 'ABSOLUTE';
      }
      elsif ($type eq 'd' or $type eq 'D') {
        $plot->{data_type} = 'DERIVE';
      }
      else {
        die "$0: error: `data_type $plot->{data_type}' for `plot' #$j in `$config_filename' must be gauge, counter, derive, or absolute.\n";
      }
    }
    else {
      $plot->{data_type} = 'GAUGE';
    }

    # The data source needs to be a valid files key.
    my $source = $plot->{source};
    unless (defined $config_files->{$source}) {
      die "$0: error: plot #$j `source $source' references non-existant `files' in `$config_filename'.\n";
    }
    unless ($plot->{source}) {
      die "$0: error: plot #$j `source $source' requires one files_key argument in `$config_filename'.\n";
    }

    # Set the legends of any columns not defined.
    unless (defined $plot->{legend}) {
      $plot->{legend} = [];
    }
    my $number_datas = @{$plot->{data}};
    for (my $k=@{$plot->{legend}}; $k<$number_datas; ++$k) {
      $plot->{legend}[$k] = "@{$plot->{data}[$k]}";
    }

    # Set the colors of any data not defined.
    unless (defined $plot->{color}) {
      $plot->{color} = [];
    }
    for (my $k=@{$plot->{color}}; $k<$number_datas; ++$k) {
      $plot->{color}[$k] = $::cc_default_colors[$k];
    }

    # Check each line type setting.
    for (my $k=0; $k<$number_datas; ++$k) {
      if (defined $plot->{line_type}[$k]) {
      my $line_type = $plot->{line_type}[$k];
        if ($line_type =~ /^line([123])$/i) {
          $line_type = "LINE$1";
        }
        elsif ($line_type =~ /^area$/i) {
          $line_type = 'AREA';
        }
        elsif ($line_type =~ /^stack$/i) {
          $line_type = 'STACK';
        }
        else {
          die "$0: error: plot #$j illegal `line_type' `$line_type'.\n";
        }
        $plot->{line_type}[$k] = $line_type;
      }
      else {
        $plot->{line_type}[$k] = 'LINE1';
      }
    }

    # If the generic y_legend is not set, then set it equal to the
    # first legend.
    unless (defined $plot->{y_legend}) {
      $plot->{y_legend} = $plot->{legend}[0];
    }

    # If the title is not set, then set it equal to all of the legends
    # with the group name prepended.
    unless (defined $plot->{title}) {
      my $title = '%G ';
      for (my $k=0; $k<$number_datas; ++$k) {
        $title .= $plot->{legend}[$k];
        $title .= " & " if $k < $number_datas-1;
      }
      $plot->{title} = $title;
    }
  }

  # Create the necessary GIF files in the HTML directory unless only
  # RRD files should be updated.  This should include orga.gif and
  # rrdtool.gif.  Convert the hexadecimal forms stored in the DATA
  # section to the raw GIF form on disk.
  return if $opt_rrd_update_only;
  my $gif_filename = '';
  while (<main::DATA>) {
    chomp;
    if ($gif_filename) {
      if (/CLOSE/) {
        close(ORCA_WRITE) or
          warn "$0: error in closing `$gif_filename' for writing: $!\n";
        $gif_filename = '';
      }
      else {
        chomp;
        print ORCA_WRITE pack('h*', $_);
      }
    }
    elsif (/OPEN (.*)/) {
      $gif_filename = "$config_options->{html_dir}/$1";
      print "Creating $1.\n" if $opt_verbose;
      unless (open(ORCA_WRITE, ">$gif_filename")) {
        warn "$0: cannot open `$gif_filename' for writing: $!\n";
        $gif_filename = '';
      }
    }
  }
  if ($gif_filename) {
    close(ORCA_WRITE) or
      warn "$0: error in closing `$gif_filename' for writing: $!\n";
    $gif_filename = '';
  }
}

# These are state variables for reading the config file.  The
# $files_key variable holds the name of the file parameter when a file
# configuration is being defined.  If $files_key is '', then the a
# file configuration is not being read.  $plot_index is a string that
# represents a number that is used as an index into @plots.  If the
# string is negative, including -0, then the plot configuration is not
# being defined, otherwise it holds the index into the @plots array
# the is being defined.
my $pcl_files_key;
my $pcl_plot_index;

# The following options go into the options and files hashes.  If you
# add any elements to pcl_plot_append_elements, make sure up update
# Orca::SourceDataFile::add_plots.
my @pcl_option_elements;
my @pcl_file_elements;
my @pcl_plot_elements;
my @pcl_plot_append_elements;
my @pcl_filepath_elements;
my @pcl_no_arg_elements;
my @pcl_keep_as_array_options;
my @pcl_keep_as_array_files;
my @pcl_keep_as_array_plots;

sub process_config_line {
  my ($config_filename, $line_number, $line,
      $config_options, $config_files, $config_plots) = @_;

  unless (@pcl_option_elements) {
    $pcl_files_key              = '';
    $pcl_plot_index             = '-0';
    @pcl_option_elements        = qw(base_dir
                                     data_dir
                                     expire_gifs
                                     find_times
                                     html_dir
                                     html_page_footer
                                     html_page_header
                                     html_top_title
                                     late_interval
                                     state_file
                                     sub_dir
                                     warn_email);
    @pcl_file_elements          = qw(column_description
                                     date_format
                                     date_source
                                     find_files
                                     interval
                                     reopen);
    @pcl_plot_elements          = qw(color
                                     data
                                     data_min
                                     data_max
                                     data_type
                                     flush_regexps
                                     legend
                                     line_type
                                     optional
                                     plot_height
                                     plot_min
                                     plot_max
                                     plot_width
                                     rigid_min_max
                                     source
                                     title
                                     y_legend);
    @pcl_plot_append_elements   = qw(color
                                     data
                                     legend
                                     line_type);
    @pcl_filepath_elements      = qw(data_dir
                                     find_files
                                     html_dir
                                     state_file);
    @pcl_no_arg_elements        = qw(flush_regexps
                                     optional
                                     rigid_min_max);
   @pcl_keep_as_array_options   = qw();
   @pcl_keep_as_array_files     = qw(column_description
                                     date_source
                                     find_files);
   @pcl_keep_as_array_plots     = qw(data);
  }

  # Take the line and split it and make the first element lowercase.
  my @line  = split(' ', $line);
  my $key   = lc(shift(@line));

  # Warn if there is no option and it requires an option.  Turn on
  # options that do not require an option argument and do not supply
  # one.
  if ($key ne '}') {
    if (grep { $key eq $_} @pcl_no_arg_elements) {
      push(@line, 1) unless @line;
    }
    else {
      unless (@line) {
        warn "$0: warning: option `$key' needs arguments in `$config_filename' line $line_number.\n";
        return;
      }
    }
  }

  # Clean up paths.  Prepend the base_dir to paths that are not
  # prepended by ^\\?\.{0,2}/, which matches /, ./, ../, and \./.
  # Then, remove any //'s.
  my $base_dir = defined $config_options->{base_dir} ?
    $config_options->{base_dir} : '';
  if (grep {$key eq $_} @pcl_filepath_elements) {
    foreach my $path (@line) {
      if ($base_dir) {
        $path = "$base_dir/$path" unless $path =~ m:^\\?\.{0,2}/:;
      }
      $path =~ s:/{2,}:/:g;
    }
  }

  my $value = "@line";

  # Process the line differently if we're reading for a particular
  # option.  This one is for files.
  if ($pcl_files_key) {
    if ($key eq '}') {
      $pcl_files_key = '';
      return;
    }
    unless (grep {$key eq $_} @pcl_file_elements) {
      warn "$0: warning: directive `$key' unknown for files at line $line_number in `$config_filename'.\n";
      return;
    }

    if (defined $config_files->{$pcl_files_key}{$key}) {
      warn "$0: warning: `$key' for files already defined at line $line_number in `$config_filename'.\n";
    }
    if (grep {$key eq $_} @pcl_keep_as_array_files) {
      $config_files->{$pcl_files_key}{$key} = [ @line ];
    }
    else {
      $config_files->{$pcl_files_key}{$key} = $value;
    }
    return;
  }

  # Handle options for plot.
  if ($pcl_plot_index !~ /^-/) {
    if ($key eq '}') {
      ++$pcl_plot_index;
      $pcl_plot_index = "-$pcl_plot_index";
      return;
    }
    unless (grep {$key eq $_} @pcl_plot_elements) {
      warn "$0: warning: directive `$key' unknown for plot at line $line_number in `$config_filename'.\n";
      return;
    }

    # Handle those elements that can just append.
    if (grep { $key eq $_ } @pcl_plot_append_elements) {
      unless (defined $config_plots->[$pcl_plot_index]{$key}) {
        $config_plots->[$pcl_plot_index]{$key} = [];
      }
      if (grep {$key eq $_} @pcl_keep_as_array_plots) {
        push(@{$config_plots->[$pcl_plot_index]{$key}}, [ @line ]);
      }
      else {
        push(@{$config_plots->[$pcl_plot_index]{$key}}, $value);
      }
      return;
    }

    if (defined $config_plots->[$pcl_plot_index]{$key}) {
      warn "$0: warning: `$key' for plot already defined at line $line_number in `$config_filename'.\n";
      return;
    }
    if (grep {$key eq $_} @pcl_keep_as_array_plots) {
      $config_plots->[$pcl_plot_index]{$key} = [ @line ];
    }
    else {
      $config_plots->[$pcl_plot_index]{$key} = $value;
    }
    return;
  }

  # Take care of generic options.
  if (grep {$key eq $_} @pcl_option_elements) {
    if (grep {$key eq $_} @pcl_keep_as_array_options) {
      $config_options->{$key} = [ @line ];
    }
    else {
      $config_options->{$key} = $value;
    }
    return;
  }

  # Take care of files to watch.
  if ($key eq 'files') {
    unless (@line) {
      die "$0: error: files needs a files name followed by { at line $line_number in `$config_filename'.\n"
    }
    $pcl_files_key = shift(@line);
    unless (@line == 1 and $line[0] eq '{' ) {
      warn "$0: warning: '{' required after 'files $pcl_files_key' at line $line_number in `$config_filename'.\n";
    }
    if (defined $config_files->{$pcl_files_key}) {
      warn "$0: warning: files `$key' at line $line_number in `$config_filename' previously defined.\n";
    }
    return;
  }

  # Take care of plots to make.
  if ($key eq 'plot') {
    $pcl_plot_index =~ s:^-::;
    unless (@line == 1 and $line[0] eq '{') {
      warn "$0: warning: '{' required after 'plot' at line $line_number in `$config_filename'.\n";
    }
    return;
  }

  warn "$0: warning: unknown directive `$key' at line $line_number in `$config_filename'.\n";
}

sub load_config {
  my $config_filename = shift;

  open(CONFIG, $config_filename) or
    die "$0: error: cannot open `$config_filename' for reading: $!\n";

  # These values hold the information from the config file.
  my %options;
  my %files;
  my @plots;

  # Load in all lines in the file and then process them.  If a line
  # begins with whitespace, then append it to the previously read line
  # and do not process it.
  my $complete_line = '';
  my $line_number = 1;
  while (<CONFIG>) {
    chomp;
    # Skip lines that begin with #.
    next if /^#/;

    # If the line begins with whitespace, then append it to the
    # previous line.
    if (/^\s+/) {
      $complete_line .= " $_";
      next;
    }

    # Process the previously read line.
    if ($complete_line) {
      process_config_line($config_filename, $line_number, $complete_line,
                          \%options, \%files, \@plots);
    }

    # Now save this read line.
    $complete_line = $_;
    $line_number = $.;
  }
  process_config_line($config_filename, $line_number, $complete_line,
                      \%options, \%files, \@plots) if $complete_line;

  close(CONFIG) or
    warn "$0: error in closing `$config_filename': $!\n";

  (\%options, \%files, \@plots);
}

__END__

=pod

=head1 NAME

orca - Make HTML & GIF plots of daily, weekly, monthly & yearly data

=head1 SYNOPSIS

  orca [-o] [-r] [-v [-v [-v]]] configuration_file

=head1 DESCRIPTION

Orca is a tool useful for plotting arbitrary data from text files onto
a directory on Web server.  It has the following features:

  * Configuration file based.
  * Reads white space separated data files.
  * Watches data files for updates and sleeps between reads.
  * Finds new files at specified times.
  * Remembers the last modification times for files so they do not have to
    be reread continuously.
  * Can plot the same type of data from different files into different
    or the same GIFs.
  * Different plots can be created based on the filename.
  * Parses the date from the text files.
  * Create arbitrary plots of data from different columns.
  * Ignore columns or use the same column in many plots.
  * Add or remove columns from plots without having to deleting RRDs.
  * Plot the results of arbitrary Perl expressions, including mathematical
    ones, using one or more columns.
  * Group multiple columns into a single plot using regular expressions on
    the column titles.
  * Creates an HTML tree of HTML files and GIF plots.
  * Creates an index of URL links listing all available targets.
  * Creates an index of URL links listing all different plot types.
  * No separate CGI set up required.
  * Can be run under cron or it can sleep itself waiting for file updates
    based on when the file was last updated.

Orca is based the RRD tool by Tobias Oetiker.  While it is similar to the
other tools based on RRD, such as Cricket and MRTG, it is significantly
different.  To see these other tools, examine

  http://ee-staff.ethz.ch/~oetiker/webtools/mrtg/mrtg.html

and

  http://www.munitions.com/~jra/cricket/

=head1 EXAMPLES

A small static example of Orca is at

  http://www.geocities.com/~bzking/orca-example/

Please inform me of any other sites using Orca and I will include them
here.

=head1 COMMAND LINE OPTIONS

Orca has only three command line options.  They are:

B<-o>: Once.  This tells Orca to go through the steps of finding files,
updating the RRDs, updating the GIFs, and creating the HTML files once.
Normally, Orca loops continuously looking for new and updated files.

B<-r>: RRD only.  Have Orca only update its RRD files.  Do not generate
any HTML or GIF files.  This is useful if you are loading in a large
amount of data in several invocations of Orca and do not want to create
the HTML and GIF files in each run since it is time consuming.

B<-v>: Verbose.  Have Orca spit out more verbose messages.  As you add
more B<-v>'s to the command line, more messages are sent out.  Any more
than three B<-v>'s are not used by Orca.

After the command line options are listed, Orca takes one more argument
which is the name of the configuration file to use.  Sample configuration
files can be found in the sample_configs directory with the distribution
of this tool.

=head1 ARCHITECTURE ISSUES

Because Orca is extremely IO intensive, I recommend that the host that
locally mounts the web server content be the same machine that runs Orca.
In addition, the RRD data files that Orca uses also require a good amount
of IO.  The machine running Orca should always have the B<data_dir>
directory locally mounted.  It is more important this B<data_dir>
be locally stored than B<html_dir> for performance concerns.  The two
options B<data_dir> and B<html_dir> are described in more detail below.

=head1 INSTALLATION AND CONFIGURATION

The first step in using Orca is to set up a configuration file that
instructs Orca on what to do.  The configuration file is based on a
key/value pair structure.  The key name must start at the beginning of
a line.  Lines that begin with whitespace are concatenated onto the last
key's value.  This is the same format as used by MRTG and Cricket.

There are three main groups of options in a Orca confg: general options,
file specific options, and plot specific options.  General options may
be used by the file and plot specific options.  If an option is required,
then it is only placed one time into the configuration file.

General options break down into two main groups, required and options.
These are the required options:

=head2 Required General Options

=item B<state_file> I<filename>

For Orca to work efficiently, it saves the last modification time of
all input data files and the Unix epoch time when they were last read
by Orca into a state file.  The value for B<state_file> must be a
valid, writable filename.  If I<filename> does not begin with a / and
the B<base_dir> option was set, then the B<base_dir> directory will be
prepended to the I<filename>.

Each entry for a data input file is roughly 100 bytes, so for small sites,
this file will not be large.

=item B<html_dir> I<directory>

B<html_dir> specifies the root directory for the main index.html and
all underlying HTML and GIF files that Orca generates.  This should
not be a directory that normal users will edit.  Ideally this directory
should be on a disk locally attached to the host running Orca, but is
not necessary.

If I<directory> does not begin with a / and the B<base_dir> option was
set, then the B<base_dir> directory will be prepended to I<directory>.

=item B<data_dir> I<directory>

B<data_dir> specifies the root directory for the location of the RRD data
files that Orca generates.  For best performance, this directory should
be on a disk locally attached to the host running Orca.  Otherwise,
the many IO operations that Orca performs will be greatly slowed down.
It is more important this B<data_dir> be locally stored than B<html_dir>
for performance concerns.

If I<directory> does not begin with a / and the B<base_dir> option was
set, then the B<base_dir> directory will be prepended to I<directory>.

If B<data_dir> is not defined, then B<base_dir> will be used as B<data_dir>.
Orca will quit with an error if both B<data_dir> and B<base_dir> are
not set.

=item B<base_dir> I<directory>

If B<base_dir> is set, then it is used to prepend to any file or directory
based names that do not begin with /.  These are currently B<state_file>,
B<html_dir>, B<data_dir>, and the B<find_files> option in the B<files>
options.

=head2 Optional General Options

=item B<late_interval> I<Perl expression>

B<late_interval> is used to calculate the time interval between a
files last modification time and the time when that file is considered
to be late for an update.  In this case, an email message may be sent
out using the B<warn_email> addresses.  Because different input files
may be updated at different rates, B<late_interval> takes an arbitrary
Perl expression, including mathematical expressions, as its argument.
If the word I<interval> occurs in the mathematical expression it is
replaced with the sampling interval of the input data file in question.

This is useful for allowing the data files to update somewhat later
than they would in an ideal world.  For example, to add a 10% overhead
to the sampling_interval before an input file is considered late, this
would be used

  late_interval 1.1 * interval

By default, the input file's sampling interval is used as the
late_interval.

=item B<warn_email> I<email_address> [I<email_address> ...]

B<warn_email> takes a list of email addresses of people to email
when something goes wrong with either Orca or the input data files.
Currently email messages are sent out the following circumstances:

  1) When a file did exist and now is gone.
  2) When a file was being updated regularly and then no longer is updated.

By default, nobody is emailed.

=item B<expire_gifs> 1

If B<expire_gifs> is set then .meta files will be created for all
generated GIF files.  If the Apache web server 1.3.2 or greater is being
used, then the following modifications must added to srm.conf or
httpd.conf.

  < 
  < #MetaDir .web
  ---
  >
  > MetaFiles on
  > MetaDir .

  < #MetaSuffix .meta
  ---
  > MetaSuffix .meta

By default, expiring the GIF files is not enabled.

=item B<find_times> I<hours:minutes> [I<hours:minutes> ...]

The B<find_times> option is used to tell Orca when to go and find new
files.  This particularly useful when new input data files are created
at midnight.  In this case, something like

  find_times 0:10

would work.

By default, files are only searched for when Orca starts up.

=item B<html_top_title> I<text> ...

The I<text> is placed at the top of the main index.html that Orca
creates.  By default, no addition text is placed at the top of the
main index.html.

=item B<html_page_header> I<text> ...

The I<text> is placed at the top of each HTML file that Orca creates.
By default, no additional text is placed at the top of each HTML file.

=item B<html_page_footer> I<text> ...

The I<text> is placed at the bottom of each HTML file that Orca creates.
By default, no additional text is placed at the bottom of each HTML file.

=item B<sub_dir> I<directory>

In certain cases Orca will not create sub directories for the different
groups of files that it processes.  If you wish to force Orca to create
sub directories, then do this

  sub_dir 1

=head2 Files Options

The next step in configuring Orca is telling where to find the files to
use as input, a description of the columns of data comprising the file,
the interval at which the file is updated, and where the measurement
time is stored in the file.  This is stored into a files set.

A generic example of the files set and its options are:

  files FILES_KEY1 {
  find_files		filename1 filename2 ...
  column_description	column1_name column2_name ...
  date_source		file_mtime
  interval		300
  .
  .
  .
  }

  files FILES_KEY2 {
  .
  .
  }

The key for a files set, in this example FILES_KEY1 and FILE_KEY2, is a
descriptive name that is unique for all files and is used later when the
plots to create are defined.  Files that share the same general format
of column data may be grouped under the same files key.  The options
for a particular files set must be enclosed in the curly brackets {}'s.
An unlimited number of file sets may be listed.

=head2 Required Files Options

=item B<find_files> I<path|regexp> [I<path|regexp> ...]

The B<find_files> option tells Orca what data files to use as
its input.  The arguments to B<find_files> may be a simple filename,
a complete path to a filename, or a regular expression to find files.
The regular expression match is not the normal shell globbing that the
Bourne shell, C shell or other shells use.  Rather, Orca uses the Perl
regular expressions to find files.  For example:

  find_files /data/source1 /data/source2

will have Orca use /data/source1 and /data/source2 as the inputs
to Orca.  This could have also been written as

  find_files /data/source\d

and both data files will be used.

In the two above examples, Orca will assume that both data files
represent data from the same source.  If this is not the case, such as
source1 is data from one place and source2 is data from another place,
then Orca needs to be told to treat the data from each file as distinct
data sources.  This be accomplished in two ways.  The first is by creating
another files { ... } option set.  However, this requires copying all
of the text and makes maintenance of the configuration file complex.
The second and recommend approach is to place ()'s around parts of the
regular expression to tell Orca how to distinguish the two data files:

  find_files /data/(source\d)

This creates two "groups", one named source1 and the other named source2
which will be plotted separately.  One more example:

  find_files /data/solaris.*/(.*)/percol-\d{4}-\d{2}-\d{2}

will use files of the form

  /data/solaris-2.6/olympia/percol-1998-12-01
  /data/solaris-2.6/olympia/percol-1998-12-02
  /data/solaris-2.5.1/sunridge/percol-1998-12-01
  /data/solaris-2.5.1/sunridge/percol-1998-12-02

and treat the files in the olympia and sunridge directories as distinct,
but the files within each directory as from the same data source.

If any of the paths or regular expressions given to B<find_Files> do not
begin with a / and the B<base_dir> option was set, then the B<base_dir>
directory will be prepended to the path or regular expression.

=item B<interval> I<seconds>

The B<interval> options takes the number of seconds between updates for
the input data files listed in this files set.

=item B<column_description> I<column_name> [I<column_name> ...]

=item B<column_description> first_line

For Orca to plot the data, it needs to be told what each column of
data holds.  This is accomplished by creating a text description for
each column.  There are two ways this may be loaded into Orca.  If the
input data files for a files set do not change, then the column names
can be listed after B<column_description>:

  column_description date in_packets/s out_packets/s

Files that have a column description as the first line of the file may
use the argument "first_line" to B<column_description>:

  column_description first_line

This informs Orca that it should read the first line of all the input
data files for the column description.  Orca can handle different files
in the same files set that have different number of columns and column
descriptions.  The only limitation here is that column descriptions
are white space separated and therefore, no spaces are allowed in the
column descriptions.

=item B<date_source> column_name I<column_name>

=item B<date_source> file_mtime

The B<date_source> option tells Orca where time and date of the
measurement is located.  The first form of the B<date_source> options
lists the column name as given to B<column_description> that contains
the Unix epoch time.  The second form with the file_mtime argument tells
Orca that the date and time for any new data in the file is the last
modification time of the file.

=item B<date_format> I<string>

The B<date_format> option is only required if the column_name argument
to B<date_source> is used.  Current, this argument is not used by Orca.

=head2 Optional Files Options

=item B<reopen> 1

Using the B<reopen> option for a files set instructs Orca to close
and reopen any input data files when there is new data to be read.
This is of most use when an input data file is erased and rewritten by
some other process.

=head2 Plot Options

The final step is to tell Orca what plots to create and how to create
them.  The general format for creating a plot is:

  plot {
  title		Plot title
  source	FILES_KEY1
  data		column_name1
  data		1024 * column_name2 + column_name3
  legend	First column
  legend	Some math
  y_legend	Counts/sec
  data_min	0
  data_max	100
  .
  .
  }

Unlike the files set, there is no key for generating a plot.  An unlimited
number of plots can be created.

Some of the plot options if they have the two characters %g or %G
will perform a substitution of this substring with the group name from
the find_files ()'s matching.  %g gets replaced with the exact match
from () and %G gets replaced with the first character capitalized.
For example, if

  find_files /(olympia)/data

was used to locate a file, then %g will be replaced with olympia and %G
replaced with Olympia.  This substitution is performed on the B<title>
and B<legend> plot options.

=head2 Required Plot Options

=item B<source> I<files_key>

The B<source> argument should be a single key name for a files set from
which data will be plotted.  Currently, only data from a single files
set may be put into a single plot.

=item B<data> I<Perl expression>

=item B<data> I<regular expression>

The B<data> plot option tells Orca the data sources to use to place
in a single GIF plot.  At least one B<data> option is required for a
particular plot and as many as needed may be placed into a single plot.

Two forms of arguments to B<data> are allowed.    The first form
allows arbitrary Perl expressions, including mathematical expressions,
that result in a number as a data source to plot.  The expression may
contain the names of the columns as found in the files set given to the
B<source> option.  The column names must be separated with white space
from any other characters in the expression.  For example, if you have
number of bytes per second input and output and you want to plot the
total number of bits per second, you could do this:

  plot {
  source	bytes_per_second
  data		8 * ( in_bytes_per_second + out_bytes_per_second )
  }

The second form allows for matching column names that match a regular
expression and plotting all of those columns that match the regular
expression in a single plot.  To tell Orca that a regular expression
is being used, then only a single non whitespace separated argument to
B<data> is allowed.  In addition, the argument must contain at least one
set of parentheses ()'s.  When a regular expression matches a column name,
the portion of the match in the ()'s is placed into the normal Perl $1,
$2, etc variables.  Take the following configuration for example:

  files throughput {
  find_files /data/solaris.*/(.*)/percol-\d{4}-\d{2}-\d{2}
  column_description hme0Ipkt/s hme0Opkt/s
                     hme1Ipkt/s hme1Opkt/s
                     hme0InKB/s hme0OuKB/s
                     hme1InKB/s hme1OuKB/s
                     hme0IErr/s hme0OErr/s
                     hme1IErr/s hme1OErr/s
  .
  .  
  }

  plot {
  source	throughput
  data		(.*\d)Ipkt/s
  data		$1Opkt/s
  .
  .
  }

  plot {
  source	throughput
  data		(.*\d)InKB/s
  data		$1OuKB/s
  .
  .
  }

  plot {
  source	throughput
  data		(.*\d)IErr/s
  data		$1OErr/s
  .
  .
  }

If the following data files are found by Orca

  /data/solaris-2.6/olympia/percol-1998-12-01
  /data/solaris-2.6/olympia/percol-1998-12-02
  /data/solaris-2.5.1/sunridge/percol-1998-12-01
  /data/solaris-2.5.1/sunridge/percol-1998-12-02

then separate plots will be created for olympia and sunridge, with each
plot containing the input and output number of packets per second.

By default, when Orca finds a plot set with a regular expression
match, it will only find one match, and then go on to the next plot set.
After it reaches the last plot set, it will go back to the first plot set
with a regular expression match and look for the next data that matches
the regular expression.  The net result of this is that the generated
HTML files using the above configuration will have links in this order:

  hme0 Input & Output Packets per Second
  hme0 Input & Output Kilobytes per Second
  hme0 Input & Output Errors per Second
  hme1 Input & Output Packets per Second
  hme1 Input & Output Kilobytes per Second
  hme1 Input & Output Errors per Second

If you wanted to have the links listed in order of hme0 and hme1,
then you would add the B<flush_regexps> option to tell Orca to find
all regular expression matches for a particular plot set and all plot
sets before the plot set containing B<flush_regexps> before continuing
on to the next plot set.  For example, if

  flush_regexps 1

were added to the plot set for InKB/s and OuKB/s, then the order would be

  hme0 Input & Output Packets per Second
  hme0 Input & Output Kilobytes per Second
  hme1 Input & Output Packets per Second
  hme1 Input & Output Kilobytes per Second
  hme0 Input & Output Errors per Second
  hme1 Input & Output Errors per Second

If you wanted to have all of the plots be listed in order of the type
of data being plotted, then you would add "flush_regexps 1" to all the
plot sets and the order would be

  hme0 Input & Output Packets per Second
  hme1 Input & Output Packets per Second
  hme0 Input & Output Kilobytes per Second
  hme1 Input & Output Kilobytes per Second
  hme0 Input & Output Errors per Second
  hme1 Input & Output Errors per Second

=head2 Data Source Optional Plot Options

The following options are plot optional.  Like the B<data> option,
multiple copies of these may be specified.  The first option of a
particular type sets the option for the first B<data> option, the second
option refers to the second B<data> option, etc.

=item B<data_type> I<type>

When defining data types, Orca uses the same data types as provided
by RRD.  These are (a direct quote from the RRDcreate manual page):

I<type> can be one of the following: B<GAUGE> this is for things like
temperatures or number of people in a room. B<COUNTER> is for continuous
incrementing counters like the InOctets counter in a router. The
B<COUNTER> data source assumes that the counter never decreases, except
when a counter overflows.  The update function takes the overflow into
account.  B<DERIVE> will store the derivative of the line going from
the last to the current value of the data source. This can be useful for
counters which do raise and fall, for example, to measure the rate of
people entering or leaving a room.  B<DERIVE> does not test for overflow.
B<ABSOLUTE> is for counters which get reset upon reading.

If the B<data_type> is not specified for a B<data> option, it defaults
to GAUGE.

=item B<data_min> I<number>

=item B<data_max> I<number>

B<data_min> and B<data_max> are optional entries defining the expected
range of the supplied data.  If B<data_min> and/or B<data_max> are
defined, any value outside the defined range will be regarded as
I<*UNKNOWN*>.

If you want to specify the second data sources minimum and maximum but do
not want to limit the first data source, then set the I<number>'s to U.
For example:

  plot {
  data		column1
  data		column2
  data_min	U
  data_max	U
  data_min	0
  data_max	100
  }

=item B<color> I<rrggbb>

The optional B<color> option specifies the color to use for a particular
plot.  The color should be of the form I<rrggbb> in hexadecimal.

=item B<flush_regexps> 1

Using the B<flush_regexps> option tells Orca to make sure that the plot
set including this option and all previous plot sets have matched all of
the columns with their regular expressions.  See the above description
of using regular expressions in the B<data> option for an example.

=item B<optional> 1

Because some of the input data files may not contain the column names
that are listed in a particular plot, Orca provides two ways to handle
missing data.  By default, Orca will generate a plot with I<*UNKNOWN*>
data if the data is mission.  If you want Orca to not generate a plot
if the data does not exist, then place

  optional 1

in the options for a particular plot.

=head2 GIF Plot Plotting Options

=item B<plot_width> I<number>

Using the B<plot_width> option specifies how many pixels wide the drawing
area inside the GIF is.

=item B<plot_height> I<number>

Using the B<plot_height> option specifies how many pixels high the
drawing area inside the GIF is.

=item B<plot_min> I<number>

By setting the B<plot_min> option, the minimum value to be graphed is set.
By default this will be auto-configured from the data you select with
the graphing functions.

=item B<plot_max> I<number>

By setting the B<plot_max> option, the minimum value to be graphed is set.
By default this will be auto-configured from the data you select with
the graphing functions.

=item B<rigid_min_max> 1

Normally Orca will automatically expand the lower and upper limit if
the graph contains a value outside the valid range.  By setting the
B<rigid_min_max> option, this is disabled.

=item B<title> <text>

Setting the B<title> option sets the title of the plot.  If you place
%g or %G in the title, it is replaced with the text matched by any
()'s in the files set B<find_files> option.  %g gets replaced with the
exact text matched by the ()'s and %G is replaced with the same text,
except the first character is capitalized.

=item B<y_legend> <text>

Setting B<y_legend> sets the text to be displayed along the Y axis of
the GIF plot.

=head2 Multiple GIF Plot Ploting Options

The following options should be specified multiple times for each data
source in the plot.

=item B<line_type> I<type>

The B<line_type> option specifies the type of line to plot a particular
data set with.  The available options are: LINE1, LINE2, and LINE3 which
generate increasingly wide lines, AREA, which does the same as LINE? but
fills the area between 0 and the graph with the specified color, and
STACK, which does the same as LINE?, but the graph gets stacked on top
of the previous LINE?, AREA, or STACK graph.  Depending on the type of
previous graph, the STACK will either be a LINE? or an AREA.

=item B<legend> I<text>

The B<legend> option specifies for a single data source the comment that
is placed below the GIF plot.

=head1 MAILING LISTS

Discussions regarding Orca take place on the mrtg-developers mailing
list located at mrtg-developers@list.ee.ethz.ch.  To place yourself
on the mailing list, send a message with the word subscribe to it
to mrtg-developers-request@list.ee.ethz.ch.

=head1 IMPLEMENTATION NOTES

Orca makes very heavy use of references to hashes and arrays to store
all of the different data it uses.

The I<Digest::MD5> module is used to cache the result of some
expensive calculations that commonly could be performed more than once.
In particular, this arrises when the same code is used to pull data from
many different input data files into the same type of data structures.
In this case, the code to be evaluated is run through MD5, where the
resulting binary code is used as a key in a hash with the value being the
anonymous subroutine array.  This saves in memory and in processing time.

=head1 AUTHOR, COMMENTS, AND BUGS

I welcome all comments and bug reports.  Please email them to Blair
Zajac <blair@geostaff.com>.

=cut

These are hexadecimal forms of GIFs used by Orca.

OPEN orca.gif
749464839316ab00d2007fff00ffffff1f0f8f2e1e2f4d1dbe5c2c4e7b3bed8a4a7da9
490dc858ace7774c0776db16856b35940b44a39a63a22a72b1c991c059000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000129f401000000000c200000000ab00d2000480ff001080c1
840b02081080610387001a1e3060a0e0c003841b2a5cb88133a642830e042060d0a124
0700152e6c3982352542022b5abc6882304846051952d469f2376a45001e1808b88337
ab4493081a3800a2506007024b1e184a10a1edc6a3439208300121014b900282558065
1003080406023d9af51668d39c31100010c03de8c39804a6759b063c23df9209ba75aa
65bee281860ceefd6ab6f26186856906d57020972ed6c71500ad4b941b2dc28e71f248
60849260040c4b7a18b81060f161a9431c7e281081a28d883bcea61a38736a64c53718
3c20a1b3bc5b8204273c60708fe9c00ea9575410802e6280d50d7f1d4cc3377969bacd
0e0809cbd221ff81b018105fa95efee0fa8d11c340507e53e08dea31828f60dd317d57
949daa28bcf5145c0d44b55a77bdb465135402160020698d94208763b1a44e5381e525
361562c16618140e6100bf958ecd38515c6e1200c3d664f155e3964339a7c1625c3d96
30d68106c412530609f6226d742e04c3d575151601cf4bf9c5f1264300e5bcd850a1a7
d32282051017d209f5a4b4ea7b11f4f0c2835a76d49b5112e50952610010866c7f3ea9
c6a2586210756b927e6430097e292776e10a04c5fe5c9b2918066e4e0820608a9a2517
93db986610808d9d7ec9b8984e7a55545c8a4235d5a8708a69a42874326444ed891110
c0d30df955e86b40cda56b139921e475adff8e02a407140f927403a8a7219aba6a436e
75942a4a95ea3bafaa65d8b9a5a4bec530d29156553761431dfa96d66b15884ce58a2d
1b77d3bd258557d788397b2254b409d93b99827d3068a145166b322684612b4e27b929
282016b7024b27e89f96d5a3a85e9d4ad7916ea625b460c507db975a457d3040d89c0f
c9f07c9581bb0043727dda6054831725585e64f2cb935bbed97a2ad3442b49a2910e5e
04f22645b1001a6a53120570be61250b32febd29c4f5530c1bcc93b64b45652d634c33
64efe14e995b615dc1fa5445e766277bb23fb356c5f002075f54600f9353b71256a505
5c16d859ea8dc2e7d405109a635d531c609caad698608f6d2d2d8151ff0a7bc5c04fa6
0d1d05fa557d66177357a2b7b7ac5e042047b4bc08655723069f5e8976e90020c93a93
7a0090ca824d3e19fa5ff130c7398ccddd301cd225aec952bf5d2ac973aee534a0c2ea
b96cc23c6608d90bb5574b8422ff85961b6116532dbc1bf7c5994666b6416bea61de71
dfa54da84587855ba2b8a5e8deadd36f54299eec151d7155a7dba419a0a42afc5e6c4c
01fd2ebf8725cc8e17a2f9c6d16bd65900aa14f964c535cb5856deb5a29169146630f3
b79e60558792d1c64678c3abcb7a9770c8f5201967e27e99bec5e913f954e54d0c689a
4c7328baf5feee55420215095727a5a025c83961116ddc06af32acb6a7620cb6140e92
0088acb0ff7c7d6ac25b8e849691a5544f5d3cd80358a3a24da1a42c5f5a12adf6e471
3c9c444a64590ed04ed552c5b46887893c39c85655c4c23ea9e13849a5595ad763bc80
81b98a1913a103c894913d042d8edb53d850a662a3d4903d3711e325f252cda8222035
218446951758b626acdc602743139764162a1c16f173258994a22538729c21fc812e1c
f15da067c41da8ab2d2242a8c0b0f8a2112e97e39e0cfe53489758925e38072a442848
42d52a31a06ca22ff9c06d2532c49351d21205041dc19a79022d5a1d8127a25e9d0fb8
48cbdd75625da2536af6047346859ae3530064dde81019b980c2349c8928437428000b
e804217241b1ea3be848c07a133f249a3c688306109c159cd3332eb9721805a299b482
6ea437d9e72550a9433f66144000e3d49703004e9ea9bd2a6215284008b4f2b3ad2041
542d29294f168414220b466c6392e449c339482de3543a1b7004e0161c405a33912d00
6ed89cb844b61a2f0941c906257ec46086c5346a34b974ab43269001bd0a010cc31f42
e4a56e419430cc78311cdffad9c5c6a4c499697b06e4ecbaf1449010a15e004ba1d29a
ad4f721a0e9965d8404000b3
CLOSE

OPEN rrdtool.gif
749464837316870022003f0000000066003399046699e375c864284bf7f73b9a9a9a08
99ccfbccccffffccffffff7f7f7f7e7e7e000000000000000000c20000000087002200
0040ef099c94badb83be9b63fbd57c882e866790ac4abe93e292c5032016fd87eafe97
d44d04b5050342a1f88c4627020663f9fc184b92daa5fa2d0c0201010081cb0b87c4e2
39d7fb4bad8f302b78965e1fb6eabdbd7cd11b7b777e3ed61727d738a44763909806c3
905040b077c360984990b390b7738928399043d78784694090e458445a947840c0e890
70c30b4a5370b9a78386a3d84050e6969a7460e73963b274e430c060d53060304ad505
a58c250090c5c564ba8920214080e8cafdb8b9d21e2460c080f360cadaa330691421db
20909e2cdd80f62fd469fc8fe9922109e05579f4dd0c841a10669dc0a1c46bd1851f3e
5df084504ed20a53a0705436efb2a04d24304645d86491b71ac4080a917bd30c2e93bb
74a69923203023a0c007f40618c883d351892694854c544ae0c4cd761de55ca844642e
a7989491aac424af940225071839254ac49e4229cc041410913082362c3506a3e265b9
130e93d4a06200cc65d6444ddad93dfbb9a06e8d4e4f6a35041f4885528c02e139878a
c49db86c376872906379900e98a65079bc899ee3e004aa4d15d403bbd1045f4de119c8
85d5f5d5cf23d426ea4320020a16ade13106efa08617df61b9ad56b525d5b47f5c00e5
cb2a3b0086ea542ea8d780ee1540c43a6a035cd8c35956d48ef2a23bcdeed4afe0c1da
afb7d5ed7395f40ad243ec6f0db69b6b9de6647ee547ef7408250b00160ca350af5cac
b6c0ca617cc09fcf4c51c1401e140895d6895de8319f8114a973f89c534d6181600ec4
333c907409102c533875519e4b830c71425f0088f00acb17a4121a0212914184c43465
f73585157d07b5c616c17195c610d55143a919b40248cd0b36e154c597cc09f854154e
79946d594e513d80900453206f884801a6a6964cf827488d5e5134631b4a5145819b42
6355861b7639650d8200c240e25a45d314028a412080c1a04e0acbc10f3d1a831c9dc8
4af356aa9ef454271fdc20a0083c42999dc441ae10c7af9db832e8c8a36200b19e3408
20a04b27008a4b22a3b6234be2a4b6da15820e80dab04108001b32e137c6dab0ef4b4f
be2b37561be0dace4fa3a2636c2302c2a54b220c4271a0c584b227242a9c443aba920b
a545a0c2009811a04d07ca09de670d54005c6ab8ae618be108cc667048b1081bef68a7
66dae763b00820a4e0cdde7ba61300ba079d0da371635c6f22c6d5e50a9440ab40f11e
e20bb958bec2231038a448a529e73ef631504bb1ee41b99a3c505a6c27150c2007514a
0c29327b810c253ba17f508aed2719fecad1f89e1b0002babf6e8cd259c8696b8c4cca
27dc22dca8aad95fec546523958843ca7bb584c30cfceec99b99a523363c6320b08bdb
5cdaa2700b07e460c6c85cc8f943a204fae1acc5f400f3b6bf3395a5f2ea696caee07a
6d8ce56f9600aaeff0763ab51cb1fb034b1e30fc584be6de2f25f2aa88f334d699faa7
53080e7ceab4485ce402e4a18a49d2b83d660e0faf57dc1437c67a1b004cc80c99a4e6
4fab0c3d1e5d83aadb70c70c373dd0eeea4c8fe660a6d7e4f3d40e32efa411bb926b71
bf3b7a5b27fc5b4ab0ceb96f8ceeb71f6b1b71e10947531e6ab2e2da5348d4787baea9
55ea6d63235a14d6d65004e93d0652e36452342547bd8d1101750af9de6ad5c4a59538
cf5da823db0cf6e4b189dfea6562bd1d0406b2b2e58d4d230a91c4f6436d3051e5ad7b
c01810acc53005ac73485b6ba71dca46303cd5ac4108c9c24b26051933260d097df1d9
5b4266713cf1a52062c1bf1aa688ec1078ef9ecb54035d9bb8760b2d286b88416a911f
ce57c934553e0d60632dd9fae5c03f0e05ca55d183629a96b502ed3c2b0622cc54eca8
ab1acd780651aa1a13ac160a2a8dbb657e7ab79915b0d8a1054e0f523bdd59c000ca05
00e56650aa86d614b81331a12e0457d83259d6f13b24b539e76b3bb81710007c2cd18b
0d27c28ecdc466f6bdb40c8b794af910e029a418adeb8398bba248b6e8e7af025ce173
4140c234768bcb65f9eb12c891c99a197baa1e29a298d222e0ea163ac94e2ce7288baf
06c2a516c7c1c229807bbe139e76a41f5671ce80791097d0b1a8337a19aa16fbf902cc
840bcf990c8b0bca71a3926641c756cc016e72685b32c50d1d61adc92d9aeaeb5da8d2
38bf593440a4b252d71e751f2859956c584c67dbda94524a7cfae5416a18d241c1adae
0af94946aba5dc02753aa17e2ba3002547e91f709d022543890cd3200472f4145f0d66
e53ce81a0b4ff6b58a3191bf49d83090ee944aac903aad185d8a6434e05d11b1896cad
d38a6917f96c13befd66aa6df35b5fe466d992b5ba190c6e9d5fea87dcbae57fac7deb
af5ffa08d0c200220000b3
CLOSE
