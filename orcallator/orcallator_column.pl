# orcallator_column: display selected columns from orcallator output.
#
# Copyright (C) 1998, 1999 Blair Zajac and GeoCities, Inc.

use strict;

$| = 1;

# This is the list of columns to plot.
my @column_titles;

# Plot the maximum data.
my $display_max = 0;

# The default width of columns.
my $col_width             = 9;
my $string_format         = "%${col_width}s";
my $number_format         = "%${col_width}.2f";
my @default_column_titles = qw(httpop/s http/p5s httpb/s NoCP);

while (@ARGV and $ARGV[0] =~ /^-\w/) {
  my $arg = shift;
  if ($arg eq '-c') {
    push(@column_titles, shift);
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
  @default_column_titles
END
  exit 1;
}

# If no column titles were set, then choose these.
@column_titles = @default_column_titles unless @column_titles;

# Unless the maximum is choosen, add the date to the list of columns.
unshift(@column_titles, 'locltime');

# Find the length of the longest file.
my $col1_length = 0;
foreach my $file (@ARGV) {
  my $len = length($file);
  $col1_length = $len if $len > $col1_length;
}
my $col1_format = "%${col1_length}s ";

for (my $a=0; $a<@ARGV; ++$a) {
  my $file = $ARGV[$a];
  open(FILE, $file) or die "$0: unable to open `$file' for reading: $!\n";

  my @line = split(' ', <FILE>);
  my @column_pos;
  my @data;

  # Find the columns that contain the names.
  my @col_titles = @column_titles;
  for (my $i=0; $i<@col_titles; ++$i) {
    my $name = $col_titles[$i];
    my $col = -1;
    for (my $j=0; $j<@line; ++$j) {
      if ($line[$j] =~ /$name/) {
        $col = $j;
        $col_titles[$i] = $line[$j];
        last;
      }
    }
    die "$0: cannot column matching `$name' in $file.\n" if $col == -1;
    push(@column_pos, $col);
    push(@data, -1e20);
  }

  printf $col1_format, "Machine";
  grep { printf "$string_format ", $_ } @col_titles;
  print "\n";

  while (<FILE>) {
    my @line = split;
    my @d = @line[@column_pos];
    if ($display_max) {
      for (my $i=0; $i<@data; ++$i) {
        if (is_numeric($d[$i])) {
          $data[$i] = $d[$i] if $d[$i] > $data[$i];
        }
        else {
          $data[$i] = $d[$i];
        }
      }
    }
    else {
      printf $col1_format, $file;
      foreach my $d (@d) {
        printf is_numeric($d) ? "$number_format " : "$string_format ", $d;
      }
      print "\n";
    }
  }

  close(FILE);

  if ($display_max) {
    printf $col1_format, $file;
    foreach my $d (@data) {
      printf is_numeric($d) ? "$number_format " : "$string_format ", $d;
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
    return undef;
  } else {
    return $num;
  }
}

sub is_numeric {
  my $a = shift;
  defined getnum($a);
}
