# Orca::HTMLFile: Manage the creation of HTML files.
#
# Copyright (C) 1998, 1999 Blair Zajac and Yahoo!, Inc.

package Orca::HTMLFile;

use strict;
use Carp;
use Orca::Constants qw($ORCA_VERSION);
use vars            qw($VERSION);

$VERSION = substr q$Revision: 0.02 $, 10;

# Use a blessed reference to an array as the storage for this class.
# Define these constant subroutines as indexes into the array.  If
# the order of these indexes change, make sure to rearrange the
# constructor in new.
sub I_FILENAME () { 0 }
sub I_FD       () { 1 }
sub I_BOTTOM   () { 2 }

sub new {
  unless (@_ == 4 or @_ == 5) {
    confess "$0: Orca::HTMLFile::new passed wrong number of arguments.\n";
  }
  my ($class, $filename, $title, $top, $bottom) = @_;
  $bottom = '' unless defined $bottom;

  local *FD;
  unless (open(FD, "> $filename.htm")) {
    $@ = "cannot open `$filename.htm' for writing: $!";
    return;
  }

  print FD <<END;
<html>
<head>
<title>$title</title>
</head>
<body bgcolor="#ffffff">

$top
<h1>$title</h1>
END

  bless [$filename, *FD, $bottom], $class;
}

sub print {
  my $self = shift;
  print { $self->[I_FD] } "@_";
}

my $i_bottom = I_BOTTOM;

sub DESTROY {
  my $self = shift;

  print { $self->[I_FD] } <<END;
$self->[$i_bottom]
<p>
<hr align=left width=475>
<table cellpadding=0 border=0>
  <tr>
    <td width=350 valign=center>
      <a href="http://www.gps.caltech.edu/~blair/orca/">
        <img width=186 height=45 border=0 src="orca.gif" alt="Orca Home Page"></a>
      <br>
      <font FACE="Arial,Helvetica" size=2>
        Orca-$ORCA_VERSION by
        <a href="http://www.gps.caltech.edu/~blair/">Blair Zajac</a>
        <a href="mailto:blair\@akamai.com">blair\@akamai.com</a>.
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

  my $filename = $self->[I_FILENAME];
  close($self->[I_FD]) or
    warn "$0: warning: cannot close `$filename.htm': $!\n";
  rename("$filename.htm", $filename) or
    warn "$0: cannot rename `$filename.htm' to `$filename': $!\n";
}

1;
