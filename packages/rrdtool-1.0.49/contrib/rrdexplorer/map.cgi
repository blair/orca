#!/usr/bin/perl
# Explore rrd via clickable graphs by. james@type-this.com (Claus Norrbohm)

# Basic idea: click high -> zoom out, click low -> zoom in,
# click left -> back history, click right -> forward history

use CGI::Carp;
use CGI;
use POSIX;
use lib qw( /usr/local/rrdtool/lib/perl );
use RRDs;

my $query = new CGI;

# modify as needed
$hight = 300; # Image size
$width = 600;
$refresh = 3600;
$expiredate = strftime "%a, %e %b %Y %H:%M:%S GMT", gmtime(time); # Format date(now)
$root = $ENV{"DOCUMENT_ROOT"}; # Location of rrd

print "Content-type: text/html\n"; # Use html
print "Cache-Control: no-cache\n"; # Ensure no cashing of page
print "Expires: $expiredate\n"; # Expire now
print "Refresh: $refresh\n\n";

print $query->start_html("Clickable rrd-graph"); # Title of html page

if ($query->param()) { # the form has already been filled out

  $rrd = $query->param("rrd"); # which rrd file are we tracking
  $start = $query->param("start"); # Start time
  $end = $query->param("end"); # End time
  $x = $query->param("img.x"); # x/y cordinates of click
  $y = $query->param("img.y");

  # see contrib/rrdfetchnames
  my ($begin,$step,$name,$data) = RRDs::fetch "$root$rrd","AVERAGE","--start","now","--end","start+1";
  if ( my $ERR = RRDs::error) {
    die "ERROR while fetching data from $NAME $ERR\n";
  }
  @names = @$name; # list of DS's "@$name"
  $j = @names;
  $esu = "";

  for ($i = 0; $i < $j; $i++) { # here we find which DS we are curently tracking
    if ($query->param("@names[$i]") == "1") {
      @use[$i] = 1;
      $esu .= "1"; # DS included
    } else {
      @use[$i] = 0;
      $esu .= "0"; # DS not included
    }
  }

  $intv = $end - $start; # Last used interval
  $zoom = ($hight + 100 - $y) / $hight; # Find zoom factor + 100 because hight is not exact
  $center = $start + $intv * $x / $width;  # Find time corresponding to click

  $start = int($center - $intv * $zoom); # Calc new start
  $end = int($center + $intv * $zoom); # Calc new end

} else { # first time through, so present clean form

  $rrd = $ENV{"REQUEST_URI"}; # Location of rrd

  $end = time(); # use now for end
  $start = $end - 86400; # and go back 24 hours

  # see rrdfetchnames
  my ($begin,$step,$name,$data) = RRDs::fetch "$root$rrd","AVERAGE","--start","now","--end","start+1";
  if ( my $ERR = RRDs::error) {
    die "ERROR while fetching data from $NAME $ERR\n";
  }
  @names = @$name; # list of DS's "@$name"
  $j = @names;
  $esu = "";

  for ($i = 0; $i < $j; $i++) { # All DS is included first time
    @use[$i] = 1;
    $esu .= "1";
  }

}

# Create a form with clickable image see page xxx in: Wallace, Shawn P.
# Programming Web Graphics with Perl
# and GNU Software
# O'Reilly UK,1999, UK, Paperback

print "<FORM ACTION=\"$rrd\">\n";

print "<TABLE border=\"0\">\n";
print "<TR><TD colspan=\"3\" align=\"center\">Click on top to zoom out</TD></TR>\n";
print "<TR><TD align=\"right\">Click<BR>left<BR>to<BR>go<BR>back<BR>in<BR>time</TD>";
print "<TD>\n";
# png.cgi prints the rrd graph, by printing to std.out (browser)
print "<INPUT TYPE=\"image\" NAME=\"img\" SRC=\"/cgi-bin/png.cgi?rrd=$rrd&start=$start&end=$end&hight=$hight&width=$width&use=$esu\">\n";
print "<INPUT TYPE=\"hidden\" NAME=\"start\" VALUE=\"$start\">\n";
print "<INPUT TYPE=\"hidden\" NAME=\"end\" VALUE=\"$end\">\n";
print "<INPUT TYPE=\"hidden\" NAME=\"rrd\" VALUE=\"$rrd\">\n";
print "</TD>";
print "<TD align=\"left\">Click<BR>right<BR>to<BR>go<BR>forward<BR>in<BR>time</TD></TR>\n";
print "<TR><TD colspan=\"3\" align=\"center\">Click on bottom to zoom in</TD></TR>\n";
print "</TABLE>\n";

print "<BR><HR><BR><TABLE border=\"0\"></TD><TD>Select / Deselect DS: </TD>\n";
for ($i = 0; $i < $j; $i++) { # present user with list of DS to select / deselect
  if (@use[$i] == 0) {
    print "<TD><INPUT TYPE=\"checkbox\" NAME=\"@names[$i]\" VALUE=1>@names[$i] </TD>\n";
  } else {
    print "<TD><INPUT TYPE=\"checkbox\" NAME=\"@names[$i]\" VALUE=1 CHECKED>@names[$i] </TD>\n";
  }
}
print "</TR></TABLE>\n";

print "</FORM>\n";

print "<P ALIGN=\"RIGHT\">Created by - Claus Norrbohm - <A HREF=\"mailto:james\@type-this.com\">james\@type-this.com</A></P>";

print $query->end_html(); # lmth ....
