#!/usr/bin/perl
# Create rrdtool graph ... 

use CGI::Carp;
use CGI;
use POSIX;
use lib qw( /usr/local/rrdtool/lib/perl );
use RRDs;

my $query = new CGI;

# Get params from URL
$rrd = $query->param("rrd"); # RRD absolute path
$start = $query->param("start"); # start time
$end = $query->param("end"); # end time
$hight = $query->param("hight"); # Image sizes
$width = $query->param("width");
$use = $query->param("use"); # which DS shal I print

# List of colors for graphs
@color = ("#FF0000","#00FF00","#FFFF00","#0000FF","#FF00FF","#00FFFF","#FFFFFF",
	  "#800000","#008000","#808000","#000080","#800080","#008080","#808080");

# title of graph with start / end time
$title = $rrd.": ".scalar(localtime($start))." / ".scalar(localtime($end));

# Formated date(now)
$expiredate = strftime "%a, %e %b %Y %H:%M:%S GMT", gmtime(time);

print "Content-type: image/png\n"; # Use html
print "Cache-Control: no-cache\n"; # Ensure no cashing of page
print "Expires: $expiredate\n\n"; # Expire now
$| = 1;

$root = $ENV{"DOCUMENT_ROOT"};
# see rrdfetchnames
($begin,$step,$names,$data) = RRDs::fetch "$root$rrd", "AVERAGE", "--start", "now","--end","start+1";
if ( my $ERR = RRDs::error) {
  die "ERROR while fetching data from $NAME $ERR\n";
}
@names = @$names; # list of def's "@$name"
$j = @names; # how many DS's

# Append DEF's see examples/shared-demp.pl
for ($i = 0; $i < $j; $i++) {
  $val = substr($use, $i, 1);
  if ( $val == "1" ) {
    @options = (@options, "DEF:l$i=$root$rrd:@names[$i]:AVERAGE","LINE2:l$i@color[$i]:@names[$i]");
  }
}

# Draw the graph to std.out ("-")
($avg,$xsize,$ysize) = RRDs::graph "-","--title", "$title","--height","$hight","--width",
  "$width","--start",$start,"--end",$end,"-a","PNG",@options;
if ($ERROR = RRDs::error) {
  print "ERROR: $ERROR\n";
}
