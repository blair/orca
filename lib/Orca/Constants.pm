# Orca::Constants.pm: Global constants for Orca.
#
# Copyright (C) 1998, 1999 Blair Zajac and Yahoo!, Inc.

package Orca::Constants;

use strict;
use Exporter;
use vars qw(@EXPORT_OK @ISA $VERSION $ORCA_VERSION $ORCA_RRD_VERSION);

@ISA     = qw(Exporter);
$VERSION = substr q$Revision: 0.01 $, 10;

# Define the constants.

# ORCA_VERSION		This version of Orca.
# ORCA_RRD_VERSION	This is the version number used in creating the DS
#			names in RRDs.  This should be updated any time a
#			new version of Orca needs some new content in its
#			RRD files.  The DS name is a concatentation of the
#			string Orca with this string of digits.
# DAY_SECONDS		The number of seconds in one day.
$ORCA_VERSION        =    '0.26beta1';
$ORCA_RRD_VERSION    =    19990222;
sub DAY_SECONDS      () { 24*60*60 };
push(@EXPORT_OK, qw($ORCA_VERSION $ORCA_RRD_VERSION DAY_SECONDS));

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
use vars         qw(@RRA_PLOT_TYPES @RRA_PDP_COUNTS @RRA_ROW_COUNTS);
push(@EXPORT_OK, qw(@RRA_PLOT_TYPES @RRA_PDP_COUNTS @RRA_ROW_COUNTS));
@RRA_PLOT_TYPES = qw(daily weekly monthly yearly);
@RRA_PDP_COUNTS =   (    1,     6,     24,   288);
@RRA_ROW_COUNTS =   ( 2400,  1488,   1200,  1098);

# Define the different plots to create.  These settings do not need to
# be exactly the same as the RRA definitions, but they can be.  Here
# create a quarterly plot (100 days) between the monthly and yearly
# plots.  The quarterly plot is updated daily.  The last array here
# holds the number of days back in time to place data in the plot.  Be
# careful to not increase this so much that the number of data points
# to plot are greater than the number of pixels available for the
# image, otherwise there will be a 30% slowdown due to a reduction
# calculation to resample the data to the lower resolution for the
# plot.  For example, with 40 days of 2 hour data, there are 480 data
# points.  For no slowdown to occur, the image should be at least 481
# pixels wide.
use vars         qw(@IMAGE_PLOT_TYPES @IMAGE_PDP_COUNTS @IMAGE_DAYS_BACK);
push(@EXPORT_OK, qw(@IMAGE_PLOT_TYPES @IMAGE_PDP_COUNTS @IMAGE_DAYS_BACK));
@IMAGE_PLOT_TYPES = (@RRA_PLOT_TYPES[0..2], 'quarterly', $RRA_PLOT_TYPES[3]);
@IMAGE_PDP_COUNTS = (@RRA_PDP_COUNTS[0..2], @RRA_PDP_COUNTS[3, 3]);
@IMAGE_DAYS_BACK  = (  1.5,  10,  40, 100, 428);
# Data points ->    (432  , 480, 480, 100, 428);

# This subroutine is compiled once to prevent compiling of the
# subroutine sub { die $_[0] } every time an eval block is entered.
sub die_when_called {
  die $_[0];
}
push(@EXPORT_OK, qw(die_when_called));

# These variables are set once at program start depending upon the
# command line arguments.
#
# $opt_generate_gifs		Generate GIFs instead of PNGs.
# $opt_once_only		Do only one pass through Orca.
# $opt_rrd_update_only		Do not generate any images.
# $opt_verbose			Be verbose about my running.
#
use vars         qw($opt_generate_gifs
                    $opt_once_only
                    $opt_rrd_update_only
                    $opt_verbose
                    $IMAGE_SUFFIX);
push(@EXPORT_OK, qw($opt_generate_gifs
                    $opt_once_only
                    $opt_rrd_update_only
                    $opt_verbose
                    $IMAGE_SUFFIX));
$opt_generate_gifs   = 0;
$opt_once_only       = 0;
$opt_rrd_update_only = 0;
$opt_verbose         = 0;
$IMAGE_SUFFIX        = 'png';

# This contains the regular expression string to check if a string
# contains the "sub {" and "}" portions or this should be added.
use vars         qw($is_sub_re);
push(@EXPORT_OK, qw($is_sub_re));
$is_sub_re = '^\s*sub\s*{.*}\s*$';

# This constant stores the commonly used string to indicate that a
# subroutine has been passed an incorrect number of arguments.
use vars qw($incorrect_number_of_args);
push(@EXPORT_OK, qw($incorrect_number_of_args));
$incorrect_number_of_args = "passed incorrect number of arguments.\n";

1;
