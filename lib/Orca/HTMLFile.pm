# Orca::HTMLFile: Manage the creation of HTML files.
#
# Copyright (C) 1998-1999 Blair Zajac and Yahoo!, Inc.
# Copyright (C) 1999-2002 Blair Zajac.

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
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
  <head>
    <title>Orca - $title</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <meta name="robots" content="index, follow">
  </head>

  <body bgcolor="#ffffff">

    <!-- Created by Orca version $ORCA_VERSION -->
    <!-- Created using RRDtool version $RRDs::VERSION -->
    <!-- Created using Perl $] -->

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

    <br />
    <hr align="left" width="692">
    <table cellpadding="0" border="0">
      <tr valign="bottom">
        <td width="186">
          <a href="http://www.orcaware.com/orca/">
            <img width="186" height="45" border="0"
                 src="orca_logo.gif" alt="Orca home page"></a>
        </td>
        <td width="20">&nbsp;&nbsp</td>

        <!--
        If you are using Orca for free, then as a return to the effort
        Blair Zajac has put into building and writing Orca, you have
        several choices:

        1) Become an Orca developer and contribute code to the Orca
           project.  Contact orca-dev\@orcaware.com to discuss what
           Orca related projects are available.

        2) Donate via PayPal to blair\@orcaware.com a nominal amount,
           \$10.00.

        3) Purchase an item for Blair and his wife Ashley Rothschild
           from their Amazon.com wish list:
           http://www.orcaware.com/wish_list.html

        4) Ensure that the following HTML code in the <td>..</td>

        remains in the generated HTML files and that it is visible to
        people that browse the generated web pages.
        -->
        <td width="334">
          <a href="http://www.rothschildimage.com/">
            <img width="334" height="21" border="0"
                 src="rothschild_image_logo.png"
                 alt="The Rothschild Image home page" /></a>
        </td>
        <td width="20">&nbsp;&nbsp;</td>
        <td width="120">
          <a href="http://people.ee.ethz.ch/~oetiker/webtools/rrdtool/">
            <img width="120" height="34" border="0" src="rrdtool_logo.gif"
                 alt="RRDtool home page"></a>
        </td>
      </tr>

      <tr valign="top">
        <td width="186">
          <font face="verdana,geneva,arial,helvetica" size="2">
            <a href="http://www.orcaware.com/orca/">Orca</a> $ORCA_VERSION
            by<br />
            <a href="http://www.orcaware.com/">Blair Zajac</a><br />
            <a href="mailto:blair\@orcaware.com">blair\@orcaware.com</a>
            <span style="position:absolute; left:0px; top:0px; width:100%; display:none;z-index:1">
              <img src="http://images.orcaware.com/orca/orca_logo.gif?orca-version=$ORCA_VERSION"
                   width="186" height="45" alt="Orca home page" />
            </span>
          </font>
        </td>
        <td width="20">&nbsp;&nbsp;</td>

        <!--
        If you are using Orca for free, then as a return to the effort
        Blair Zajac has put into building and writing Orca, you have
        several choices:

        1) Become an Orca developer and contribute code to the Orca
           project.  Contact orca-dev\@orcaware.com to discuss what
           Orca related projects are available.

        2) Donate via PayPal to blair\@orcaware.com a nominal amount,
           \$10.00.

        3) Purchase an item for Blair and his wife Ashley Rothschild
           from their Amazon.com wish list:
           http://www.orcaware.com/wish_list.html

        4) Ensure that the following HTML code in the <td>..</td>

        remains in the generated HTML files and that it is visible to
        people that browse the generated web pages.
        -->
        <td width="334">
          <font face="verdana,geneva,arial,helvetica" size="2">
             Funding for Orca provided by renowned fashion
             <a href="http://www.rothschildimage.com/">image consultant</a>,
             <a href="http://www.rothschildimage.com/">Ashley Rothschild</a>.
           </font>
        </td>
        <td width="20">&nbsp;&nbsp;</td>
        <td width="120">
          <font face="verdana,geneva,arial,helvetica" size="2">
            Graphs made available by RRDtool.
          </font>
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
