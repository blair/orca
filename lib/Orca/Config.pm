# Orca::Config: Manage configuration options for Orca.
#
# Copyright (C) 1998, 1999 Blair Zajac and Yahoo!, Inc.

package Orca::Config;

use strict;
use Carp;
use Exporter;
use Orca::Constants     qw($opt_verbose
                           $is_sub_re
                           die_when_called);
use Orca::SourceFileIDs qw(@sfile_fids);
use vars qw(@EXPORT_OK @ISA $VERSION);

@ISA     = qw(Exporter);
$VERSION = substr q$Revision: 0.01 $, 10;

# Export the main subroutine to load configuration data and a subroutine
# to get a color indexed by an integer.
push(@EXPORT_OK, qw(load_config get_color));

# The following array and hashes hold the contents of the
# configuration file.
use vars         qw(%config_options %config_groups @config_plots);
push(@EXPORT_OK, qw(%config_options %config_groups @config_plots));

# These are state variables for reading the config file.  The
# $pcl_group_name variable holds the name of the group when a
# group is being defined.  If $pcl_group_name is '', then a group
# configuration is not being read.  $pcl_plot_index is a string that
# represents a number that is used as an index into @plots.  If the
# string is negative, including -0, then the plot configuration is not
# being defined, otherwise it holds the index into the @plots array
# the is being defined.
my $pcl_group_name  = '';
my $pcl_plot_index = '-0';

# The following options go into the options and files hashes.  If you
# add any elements to pcl_plot_append_elements, make sure to update
# Orca::SourceFile::add_plots.
my @pcl_option_elements        = qw(base_dir
                                    expire_images
                                    find_times
                                    html_dir
                                    html_page_footer
                                    html_page_header
                                    html_top_title
                                    late_interval
                                    rrd_dir
                                    state_file
                                    sub_dir
                                    warn_email);
my @pcl_group_elements         = qw(column_description
                                    date_format
                                    date_source
                                    filename_compare
                                    find_files
                                    interval
                                    reopen);
my @pcl_plot_elements          = qw(base
                                    color
                                    data
                                    data_min
                                    data_max
                                    data_type
                                    flush_regexps
                                    href
                                    legend
                                    line_type
                                    logarithmic
                                    plot_height
                                    plot_min
                                    plot_max
                                    plot_width
                                    required
                                    rigid_min_max
                                    source
                                    title
                                    y_legend);
my @pcl_plot_append_elements   = qw(color
                                    data
                                    legend
                                    line_type);
my @pcl_filepath_elements      = qw(find_files
                                    html_dir
                                    rrd_dir
                                    state_file);
my @pcl_no_arg_elements        = qw(flush_regexps
                                    logarithmic
                                    required
                                    rigid_min_max);
my %pcl_option_keep_as_array   =   ();
my %pcl_group_keep_as_array    =   (column_description => 1,
                                    date_source        => 1,
                                    find_files         => 1);
my %pcl_plot_keep_as_array     =   (data               => 1);

# The following variables are used to check that the configuration file
# contains the required options.  the @cc_required_* are the names of
# the options that must occur in a configuration file.  The @cc_optional_*
# options are options set to '' if they are not set in the configuration
# file.
my @cc_required_option         = qw(html_dir
                                    rrd_dir
                                    state_file);
my @cc_required_group          = qw(column_description
                                    date_source
                                    find_files
                                    interval);
my @cc_required_plot           = qw(data
                                    source);
my @cc_optional_option         = qw(expire_images
                                    html_page_footer
                                    html_page_header
                                    html_top_title
                                    late_interval
                                    sub_dir
                                    warn_email);
my @cc_optional_group          = qw(reopen);
my @cc_optional_plot           = qw(flush_regexps
                                    href
                                    plot_width
                                    plot_height);

# This is the default list of colors.
my @cc_default_colors          =   ('00ff00',	# Green
                                    '0000ff',	# Blue
                                    'ff0000',	# Red
                                    'a020f0',	# Magenta
                                    'ffa500',	# Orange
                                    'a52a2a',	# Brown
                                    '00ffff',	# Cyan
                                    '00aa00',	# Dark Green
                                    'eeee00',	# Yellow
                                    '5e5e5e',	# Dark Gray
                                    '0000aa');	# Dark Blue

sub get_color {
  $cc_default_colors[$_[0] % @cc_default_colors];
}

# This variable stores the anonymous subroutine that compares FIDs
# when a group in the configuration files does not contain a
# filename_compare parameter.
my $cmp_fids_sub;

sub check_config {
  my $config_filename = shift;

  # If rrd_dir is not set, then use base_dir.  Only die if both are
  # not set.
  unless (defined $config_options{rrd_dir}) {
    if (defined $config_options{base_dir}) {
      $config_options{rrd_dir} = $config_options{base_dir};
    } else {
      die "$0: error: must define `rrd_dir' in `$config_filename'.\n";
    }
  }

  # Check that we the required options are satisfied.
  foreach my $option (@cc_required_option) {
    unless (defined $config_options{$option}) {
      die "$0: error: must define `$option' in `$config_filename'.\n";
    }
  }

  # Check if the html_dir and rrd_dir directories exist.
  foreach my $dir_key ('html_dir', 'rrd_dir') {
    my $dir = $config_options{$dir_key};
    die "$0: error: please create $dir_key `$dir'.\n" unless -d $dir;
  }

  # Set any optional options to '' if it isn't defined.
  foreach my $option (@cc_optional_option) {
    $config_options{$option} = '' unless defined $config_options{$option};
  }

  # Late_interval is a valid mathematical expression. Replace the word
  # interval with $_[0].  Try the subroutine to make sure it works.
  unless ($config_options{late_interval}) {
    $config_options{late_interval} = 'interval';
  }
  my $expr = "sub { $config_options{late_interval}; }";
  $expr =~ s/interval/\$_[0]/g;
  my $sub;
  {
    local $SIG{__DIE__}  = 'DEFAULT';
    local $SIG{__WARN__} = \&die_when_called;
    $sub = eval $expr;
  }
  if ($@) {
    die "$0: cannot evaluate `late_interval' in `$config_filename':\n   ",
        "$expr\nOutput: $@\n";
  }
  {
    local $SIG{__DIE__}  = 'DEFAULT';
    local $SIG{__WARN__} = \&die_when_called;
    eval '&$sub(3.1415926) + 0;';
  }
  if ($@) {
    die "$0: cannot execute `late_interval' in `$config_filename':\n   ",
         "$expr\nOutput: $@\n";
  }
  $config_options{late_interval} = $sub;

  # Convert the list of find_times into an array of fractional hours.
  my @find_times;
  unless (defined $config_options{find_times}) {
    $config_options{find_times} = '';
  }
  foreach my $find_time (split(' ', $config_options{find_times})) {
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
    } else {
      warn "$0: warning: ignoring find_times `$find_time': illegal format.\n";
    }
  }
  $config_options{find_times} = [ sort { $a <=> $b } @find_times ];

  # There must be at least one group.
  unless (keys %config_groups) {
    die "$0: error: must define at least one `group' in `$config_filename'.\n";
  }

  # For each group parameter there are required options.
  foreach my $group_name (keys %config_groups) {
    my $group = $config_groups{$group_name};

    foreach my $option (@cc_required_group) {
      unless (defined $group->{$option}) {
        die "$0: error: must define `$option' for `group $group_name' ",
            "in `$config_filename'.\n";
      }
    }

    # Optional group options will be set to '' here if they haven't
    # been set by the user.
    foreach my $option (@cc_optional_group) {
      $group->{$option} = '' unless defined $group->{$option};
    }

    # Create the filename comparison function.  The function must be
    # handle input ala sort() via the package global $a and $b variables.
    if (defined $group->{filename_compare} or !$cmp_fids_sub) {
      my $expr = defined $group->{filename_compare} ?
                 $group->{filename_compare} :
                 'sub { $a cmp $b }';
      $expr = "sub { $expr }" if $expr !~ /$is_sub_re/o;
      my $sub;
      {
        local $SIG{__DIE__}  = 'DEFAULT';
        local $SIG{__WARN__} = \&die_when_called;
        $sub = eval $expr;
      }
      if ($@) {
        if ($group->{filename_compare}) {
          die "$0: cannot compile `filename_compare' for group `$group_name' ",
              "in `$config_filename':\n   $expr\nOutput: $@\n";
        } else {
          die "$0: internal error: cannot compile default ",
              "`filename_compare':\n   $expr\nOutput: $@\n";
        }
      }

      # This subroutine looks fine.  Now change all the variables to use
      # file IDs instead.
      $expr =~ s/\$a(\W)/\$sfile_fids[\$a]$1/g;
      $expr =~ s/\$b(\W)/\$sfile_fids[\$b]$1/g;
      {
        no strict;
        local $SIG{__DIE__}  = 'DEFAULT';
        local $SIG{__WARN__} = \&die_when_called;
        $sub = eval $expr;
      }
      if ($@) {
        if ($group->{filename_compare}) {
          die "$0: cannot compile `filename_compare' for group `$group_name' ",
              "in `$config_filename':\n   $expr\nOutput: $@\n";
        } else {
          die "$0: internal error: cannot compile default ",
              "`filename_compare':\n   $expr\nOutput: $@\n";
        }
      }
      $cmp_fids_sub = $sub if !$group->{filename_compare};
      $group->{filename_compare} = $sub;
    } else {
      $group->{filename_compare} = $cmp_fids_sub;
    }

    # Check that the date_source is either column_name followed by a
    # column name or file_mtime for the file modification time.  If a
    # column_name is used, then the date_format is required.
    my $date_source = $group->{date_source}[0];
    if ($date_source eq 'column_name') {
      unless (@{$group->{date_source}} == 2) {
        die "$0: error: incorrect number of arguments for `date_source' for ",
            "`group $group_name'.\n";
      }
      unless (defined $group->{date_format}) {
        die "$0: error: must define `date_format' with ",
            "`date_source columns ...' for `group $group_name'.\n";
      }
    } else {
      unless ($date_source eq 'file_mtime') {
        die "$0: error: illegal argument for `date_source' for ",
             "`group $group_name'.\n";
      }
    }
    $group->{date_source}[0] = $date_source;

    # Validate the regular expression for find_files and get a unique list
    # of them.  Check if the regular expressions contain any ()'s that will
    # place the found files into different groups.  If any ()'s are found,
    # then the output HTML and image tree will use subdirectories for each
    # group.
    #
    # In this comment, all path names are Perl escaped, so the directory
    # . would be written as \. instead.
    #
    # Since we do not want to search on the current directory, find any
    # text that begins a regular expression with a \./ and remove it.  Also
    # Remove any matches for /\./ in the path since they are unnecessary.
    # However, do not remove searches for /./, since this can match single
    # character files or directories.
    my $sub_dir = 0;
    my %find_files;
    my $number_finds = @{$group->{find_files}};
    for (my $i=0; $i<$number_finds; ++$i) {
      my $orig_find = $group->{find_files}[$i];
      my $find      = $orig_find;
      $find         =~ s:^\\\./+::;
      $find         =~ s:/+\\\./+:/:g;
      $find         = $orig_find unless $find;
      $group->{find_files}[$i] = $find;
      my $test_string          = 'abcdefg';
      local $SIG{__DIE__}      = 'DEFAULT';
      local $SIG{__WARN__}     = \&die_when_called;
      eval { $test_string =~ /$find/ };
      if ($@) {
        die "$0: error: illegal regular expression in `find_files $orig_find' ",
            "for `files $group_name' in `$config_filename':\n$@\n";
      }
      $find_files{$find} = 1;
      $sub_dir = 1 if $find =~ m:\(.+\):;
    }
    $group->{find_files} = [sort keys %find_files];
    $group->{sub_dir}    = $sub_dir || $config_options{sub_dir};
  }

  # There must be at least one plot.
  unless (@config_plots) {
    die "$0: error: must define at least one `plot' in `$config_filename'.\n";
  }

  # Foreach plot there are required options.  Create default options
  # if the user has not done so.
  for (my $i=0; $i<@config_plots; ++$i) {
    my $plot = $config_plots[$i];

    my $j = $i + 1;
    foreach my $option (@cc_required_plot) {
      unless (defined $plot->{$option}) {
        die "$0: error: must define `$option' for `plot' #$j in ",
            "`$config_filename'.\n";
      }
    }

    # Create an array for each plot that will have a list of images that
    # were generated from this plot.
    $plot->{creates} = [];

    # Optional options will be set to '' here if they haven't been set
    # by the user.
    foreach my $option (@cc_optional_plot) {
      $plot->{$option} = '' unless defined $plot->{$option};
    }

    # Set the default plot width and height.
    $plot->{plot_width}  =  500 unless $plot->{plot_width};
    $plot->{plot_height} =  125 unless $plot->{plot_height};

    # Make sure the base is either 1000 or 1024.
    if (defined $plot->{base} && length($plot->{base})) {
      if ($plot->{base} != 1000 and $plot->{base} != 1024) {
        die "$0: error: plot #$j must define base to be either 1000 or 1024.\n";
      }
    } else {
      $plot->{base} = 1000;
    }

    # Set the plot minimum and maximum values to U unless they are
    # set.
    $plot->{data_min} = 'U' unless defined $plot->{data_min};
    $plot->{data_max} = 'U' unless defined $plot->{data_max};

    # The data type must be either gauge, absolute, or counter.
    if (defined $plot->{data_type}) {
      my $type = substr($plot->{data_type}, 0, 1);
      if ($type eq 'g' or $type eq 'G') {
        $plot->{data_type} = 'GAUGE';
      } elsif ($type eq 'c' or $type eq 'C') {
        $plot->{data_type} = 'COUNTER';
      } elsif ($type eq 'a' or $type eq 'A') {
        $plot->{data_type} = 'ABSOLUTE';
      } elsif ($type eq 'd' or $type eq 'D') {
        $plot->{data_type} = 'DERIVE';
      } else {
        die "$0: error: `data_type $plot->{data_type}' for `plot' #$j in ",
            "`$config_filename' must be gauge, counter, derive, or absolute.\n";
      }
    } else {
      $plot->{data_type} = 'GAUGE';
    }

    # The data source needs to be a valid group name.
    my $source = $plot->{source};
    unless (defined $config_groups{$source}) {
      die "$0: error: plot #$j `source $source' references non-existant ",
          "`group' in `$config_filename'.\n";
    }
    unless ($plot->{source}) {
      die "$0: error: plot #$j `source $source' requires one group_name ",
          "argument in `$config_filename'.\n";
    }

    # Set the legends of any columns not defined.
    $plot->{legend} = [] unless defined $plot->{legend};
    my $number_datas = @{$plot->{data}};
    for (my $k=@{$plot->{legend}}; $k<$number_datas; ++$k) {
      $plot->{legend}[$k] = "@{$plot->{data}[$k]}";
    }

    # Set the colors of any data not defined.
    $plot->{color} = [] unless defined $plot->{color};
    for (my $k=@{$plot->{color}}; $k<$number_datas; ++$k) {
      $plot->{color}[$k] = get_color($k);
    }

    # Check each line type setting.
    for (my $k=0; $k<$number_datas; ++$k) {
      if (defined $plot->{line_type}[$k]) {
      my $line_type = $plot->{line_type}[$k];
        if ($line_type =~ /^line([123])$/i) {
          $line_type = "LINE$1";
        } elsif ($line_type =~ /^area$/i) {
          $line_type = 'AREA';
        } elsif ($line_type =~ /^stack$/i) {
          $line_type = 'STACK';
        } else {
          die "$0: error: plot #$j illegal `line_type' `$line_type'.\n";
        }
        $plot->{line_type}[$k] = $line_type;
      } else {
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

  1;
}

sub _trim_path {
  my $path = shift;

  # Replace any multiple /'s with a single /.
  $path =~ s:/{2,}:/:g;

  # Trim any trailing /.'s unless the path is only /., in which case
  # make it /.
  if ($path eq '/.') {
    $path = '/';
  } else {
    $path =~ s:/\.$::;
  }
  $path;
}

sub process_config_line {
  my ($config_filename, $line_number, $line) = @_;

  # Take the line and split it and make the first element lowercase.
  my @line = split(' ', $line);
  my $key  = lc(shift(@line));

  # Warn if there is no option and it requires an option.  Turn on
  # options that do not require an option argument and do not supply
  # one.
  if ($key ne '}') {
    if (grep {$key eq $_} @pcl_no_arg_elements) {
      push(@line, 1) unless @line;
    } else {
      unless (@line) {
        warn "$0: warning: option `$key' needs arguments in `$config_filename' line $line_number.\n";
        return;
      }
    }
  }

  # Clean up paths in the following order:
  # 1) Trim the path.
  # 2) Prepend the base_dir to paths that are not prepended by
  #    ^\\?\.{0,2}/, which matches /, ./, ../, and \./.
  # 3) Trim the resulting path.
  if (grep {$key eq $_} @pcl_filepath_elements) {
    my $base_dir = defined $config_options{base_dir}?
      _trim_path($config_options{base_dir}) : '';
    for (my $i=0; $i<@line; ++$i) {
      my $path = _trim_path($line[$i]);
      if ($base_dir) {
        $path = "$base_dir/$path" unless $path =~ m:^\\?\.{0,2}/:;
      }
      $line[$i] = _trim_path($path);
    }
  }

  my $value = "@line";

  # Process the line differently if we're reading for a particular
  # option.  This one is for groups.
  if ($pcl_group_name) {
    if ($key eq '}') {
      $pcl_group_name = '';
      return;
    }
    unless (grep {$key eq $_} @pcl_group_elements) {
      warn "$0: warning: directive `$key' unknown for group at line $line_number in `$config_filename'.\n";
      return;
    }

    if (defined $config_groups{$pcl_group_name}{$key}) {
      warn "$0: warning: `$key' for group already defined at line $line_number in `$config_filename'.\n";
    }
    if ($pcl_group_keep_as_array{$key}) {
      $config_groups{$pcl_group_name}{$key} = [ @line ];
    } else {
      $config_groups{$pcl_group_name}{$key} = $value;
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
      unless (defined $config_plots[$pcl_plot_index]{$key}) {
        $config_plots[$pcl_plot_index]{$key} = [];
      }
      if ($pcl_plot_keep_as_array{$key}) {
        push(@{$config_plots[$pcl_plot_index]{$key}}, [ @line ]);
      } else {
        push(@{$config_plots[$pcl_plot_index]{$key}}, $value);
      }
      return;
    }

    if (defined $config_plots[$pcl_plot_index]{$key}) {
      warn "$0: warning: `$key' for plot already defined at line $line_number in `$config_filename'.\n";
      return;
    }
    if ($pcl_plot_keep_as_array{$key}) {
      $config_plots[$pcl_plot_index]{$key} = [ @line ];
    } else {
      $config_plots[$pcl_plot_index]{$key} = $value;
    }
    return;
  }

  # Take care of generic options.
  if (grep {$key eq $_} @pcl_option_elements) {
    if ($pcl_option_keep_as_array{$key}) {
      $config_options{$key} = [ @line ];
    } else {
      $config_options{$key} = $value;
    }
    return;
  }

  # Take care of a group.
  if ($key eq 'group') {
    unless (@line) {
      die "$0: error: group needs a group name followed by { at ",
          "line $line_number in `$config_filename'.\n"
    }
    $pcl_group_name = shift(@line);
    unless (@line == 1 and $line[0] eq '{' ) {
      warn "$0: warning: '{' required after `group $pcl_group_name' at ",
           "line $line_number in `$config_filename'.\n";
    }
    if (defined $config_groups{$pcl_group_name}) {
      warn "$0: warning: `group $key' at line $line_number in ",
           "`$config_filename' previously defined.\n";
    }
    return;
  }

  # Take care of plots to make.  Include in each plot its index.
  if ($key eq 'plot') {
    $pcl_plot_index =~ s:^-::;
    $config_plots[$pcl_plot_index]{_index} = $pcl_plot_index;
    unless (@line == 1 and $line[0] eq '{') {
      warn "$0: warning: '{' required after `plot' at line $line_number in `$config_filename'.\n";
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
  my %groups;
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

    # Process the previously read complete line.
    if ($complete_line) {
      process_config_line($config_filename, $line_number, $complete_line);
    }

    # Now save this read line.
    $complete_line = $_;
    $line_number = $.;
  }

  # Process any remaining line.
  if ($complete_line) {
    process_config_line($config_filename, $line_number, $complete_line);
  }

  close(CONFIG) or
    warn "$0: error in closing `$config_filename': $!\n";

  check_config($config_filename);
}

1;
