# orcallator_column: display selected columns from orcallator output.
#
# Copyright (C) 1998-2001 Blair Zajac and Yahoo!/GeoCities, Inc.

use strict;

$| = 1;

# This is the list of regular expressions that match column names to
# plot.
my @column_regexs;

# Plot the maximum data.
my $display_max = 0;

# The default width of columns.
my $col_width             = 9;
my $string_format         = "%${col_width}s";
my $number_format         = "%${col_width}.2f";
my @default_column_regexs = qw(httpop/s http/p5s httpb/s NoCP);

while (@ARGV and $ARGV[0] =~ /^-\w/) {
  my $arg = shift;
  if ($arg eq '-c') {
    unless (@ARGV) {
      die "$0: no argument for -c.\n";
    }
    my $value = shift;
    unless (defined $value) {
      die "$0: undefined value passed to -c.\n";
    }
    push(@column_regexs, $value);
  }
  elsif ($arg eq '-m') {
    $display_max = 1;
  }
}

unless (@ARGV) {
  print STDERR <<"END";
usage: $0 [-c column_name] [-m] files ...
  -c add the name of a column to print out
  -m instead of printing all the data, show only the maximum value
If no -c options are given, then by default the following column titles
are used:
  @default_column_regexs
If you want to process standard input, then you must list - on the
command line.
END
  exit 1;
}

# If no column titles were set, then choose these.
@column_regexs = @default_column_regexs unless @column_regexs;

# Compile the regular expressions.
my @column_res = map { qr/$_/ } @column_regexs;

# Unless the maximum is choosen, add the date to the list of columns.
unshift(@column_regexs, 'locltime');

# Find the string length of the longest filename.
my $col1_length = 0;
foreach my $file (@ARGV) {
  my $len = length($file);
  $col1_length = $len if $len > $col1_length;
}
my $col1_format = "%${col1_length}s ";

for (my $a=0; $a<@ARGV; ++$a) {
  my $file = $ARGV[$a];
  open(FILE, $file) or
    die "$0: unable to open `$file' for reading: $!\n";

  # Read the file and on each line look for redefinitions of the
  # column names.
  my @column_titles;
  my @column_pos;
  my $column_pos_set;
  my %max_values;
  while (<FILE>) {
    my @line = split;

    # If the line has the string timestamp in it, then use it to find
    # the proper column number for the requested data.
    if (/timestamp/) {
      @column_titles = ();
      @column_pos    = ();
      foreach my $regex (@column_regexs) {
        my $re = qr/$regex/;
        for (my $j=0; $j<@line; ++$j) {
          my $column_title = $line[$j];
          if ($column_title =~ $re) {
            push(@column_pos,    $j);
            push(@column_titles, $column_title);
            unless (defined $max_values{$column_title}) {
              $max_values{$column_title} = -1e20;
            }
          }
        }
      }
      $column_pos_set = 1;
      next;
    }

    next unless $column_pos_set;

    my @d = @line[@column_pos];
    if ($display_max) {
      for (my $i=0; $i<@d; ++$i) {
        my $column_title = $column_titles[$i];
        if (is_numeric($d[$i])) {
          if ($d[$i] > $max_values{$column_title}) {
            $max_values{$column_title} = $d[$i];
          }
        } else {
          $max_values{$column_title} = $d[$i];
        }
      }
    } else {
      printf $col1_format, $file;
      foreach my $d (@d) {
        printf is_numeric($d) ? "$number_format " : "$string_format ", $d;
      }
      print "\n";
    }
  }

  printf $col1_format, "Machine";
  grep { printf "$string_format ", $_ } @column_titles;
  print "\n";

  close(FILE);

  if ($display_max) {
    printf $col1_format, $file;
    foreach my $title (@column_titles) {
      my $max = $max_values{$title};
      printf is_numeric($max) ? "$number_format " : "$string_format ", $max;
    }
    print "\n";
  }
  print "\n" if $a < @ARGV -1;
}

exit 0;

sub getnum {
  use POSIX qw(strtod);
  my $str = shift;
  $str =~ s/^\s+//;
  $str =~ s/\s+$//;
  $! = 0;
  my($num, $unparsed) = strtod($str);
  if (($str eq '') || ($unparsed != 0) || $!) {
    return;
  } else {
    return $num;
  }
}

sub is_numeric {
  defined getnum(shift);
}
