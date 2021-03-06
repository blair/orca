#! /usr/bin/perl

# add_ds.pl, program to add datasources to an existing RRD 
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

use strict;

my $ds = shift || die "need number of additional datasources desired";
if ($ds eq '-h') {
  &Usage;
  exit 0;
}

my $default_val = shift || 'NaN';
my $type = shift || 'COUNTER';
my $heartbeat = shift || '1800';
my $rrdmin = shift || 'NaN';
my $rrdmax = shift || 'NaN';

my $cdp_prep_end = '</cdp_prep>';

my $row_end = '</row>';
my $name = '<name>';
my $name_end = '</name>';

my $field = '<v> ' . $default_val . ' </v>';

my $found_ds = 0;
my $num_sources = 0;
my $last;
my $fields = " ";
my $datasource;
my $x;

while (<STDIN>) {

  if (($_ =~ s/$row_end$/$fields$row_end/) && $found_ds) {
    # need to hit <ds> types first, if we don't, we're screwed
    print $_; 

  } elsif (/$cdp_prep_end/) {
    print "\t\t\t<ds><value> NaN </value>  <unknown_datapoints> 0 </unknown_datapoints></ds>\n" x $ds;
    print $_;

  } elsif (/$name_end$/) {
    ($datasource) = /$name (\w+)/;
    $found_ds++;
    print $_;

  } elsif (/Round Robin Archives/) {
    # print out additional datasource definitions

    ($num_sources) = ($datasource =~ /(\d+)/);
    
    for ($x = $num_sources+1; $x < $num_sources+$ds+1; $x++) {

      $fields .= $field;
      
      print "\n\t<ds>\n";
      print "\t\t<name> ds$x <\/name>\n";
      print "\t\t<type> $type <\/type>\n";
      print "\t\t<minimal_heartbeat> $heartbeat <\/minimal_heartbeat>\n";
      print "\t\t<min> $rrdmin <\/min>\n";
      print "\t\t<max> $rrdmax <\/max>\n\n";
      print "\t\t<!-- PDP Status-->\n";
      print "\t\t<last_ds> NaN <\/last_ds>\n";
      print "\t\t<value> NaN <\/value>\n";
      print "\t\t<unknown_sec> NaN <\/unknown_sec>\n"; 
      print "\t<\/ds>\n\n";

    }

    print $_;
  } else {
    print $_;
  }

  $last = $_;
}




sub Usage {

  print "add-ds.pl <add'l ds> [default_val] [type] [heartbeat] [rrdmin] [rrdmax] < file.xml\n";
  print "\t<add'l ds>\tnumber of additional datasources\n";
  print "\t[default_val]\tdefault value to be entered in add'l fields\n";
  print "\t[type]\ttype of datasource (i.e. COUNTER, GAUGE...)\n";
  print "\t[heatbeat]\tlength of time in seconds before RRD thinks your DS is dead\n";
  print "\t[rrdmin]\tminimum value allowed for each datasource\n";
  print "\t[rrdmax]\tmax value allowed for each datasource\n\n";
  print "\tOptions are read in order, so if you want to change the\n";
  print "\tdefault heartbeat, you need to specify the default_val and\n";
  print "\ttype as well, etc.\n";
  print "\n\tOutput goes to STDOUT.\n";
}

