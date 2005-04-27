#! /usr/bin/perl

# batch.pl, simple program to help add datasources to an existing RRD
#   goes with add_ds.pl
#
#    Copyright (C) 2000 Selena M. Brewington
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
# 
# for use with add_ds.pl script to add datasources to an RRD
#
# usage: ls -1 | ./batch.pl [-o] <# ds to add>
#
# -o will let you overwrite your rrds.  i don't recommend using this 
# switch the first time you run this program.  If something
# gets messed up, the original xml files will be in the xml
# directory and you can run 'rrdtool restore' on all of them
# uncomment the commented out lines below to make this work.
#
# also, you can change the name of the directory the XML is
# getting dumped to, where your rrdtool binary is located, 
# and where add_ds.pl is located.  the variables are listed 
# below.
#
# This script could theoretically take fully-qualified pathnames
# as input from STDIN rather than the output from ls -1. 
#

use strict;

########### USER CONFIGURABLE SECTION #######################

my $newdir = "xml";
my $rrdtool = "/usr/local/rrdtool-1.0.50/bin/rrdtool";
my $add_ds = "./add_ds.pl";  # path to add_ds.pl script

########### END CONFIGURE SECTION ###########################


my $ds = shift || die 'need number of datasources to add';

my $overwrite = 0;

if ($ds eq '-o') {
  $overwrite = 1;
  $ds = shift || die 'need number of datasources to add';
} 

if (! (-x $newdir)) {
  `mkdir xml` || die "can't make directory xml";
}

while (<STDIN>) {

  next if (! /rrd/);
  chop;
  my $file = $_;

  $_ =~ s/rrd$/xml/;

  open(FILE, ">$newdir/$_");

  my @output = `$rrdtool dump $file`;
  print FILE @output;

  close(FILE);

  open (FILE, ">$newdir/$_.2");

  my @new = `cat $newdir/$_ | $add_ds $ds`; 

  print FILE @new;

  close (FILE);

  system("$rrdtool restore $newdir/$_.2 $newdir/$file") == 0 
    or die "rrdtool restore failed for $file";

  if ($overwrite == 1) {
    system("mv $newdir/$file $file") == 0
      or die "can't overwrite $file";
  }
}
