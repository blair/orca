#
# Radius.pm : Orca_Services package for monitoring Radius
# 
# Author: Sjaak Westdijk <westdijk@fastmail.fm>
#
# thanks to :
#     Carlos Canau <Carlos.Canau@KPNQwest.pt>
#     Jose Carlos Pereira <Jose.Pereira@KPNQwest.pt>
#
# Most code is adapted from Orca_servcies 1.X written by Carlos Canau
#
# Portions ported to perl from Orcallator.se written by Blair Zajac
# other portions adapted from several other open source scripts
#
#
# BUGS:
#
#
# TODO:
#
#
# LICENSE:
#         GPL.
#         (c) 2003      Sjaak Westdijk
#         (c) 2000-2002 Carlos Canau & Jose Carlos Pereira
#
#
# DISCLAIMER:
#            you use this program at your own and complete risk
#            if you don't agree with that then delete it
#
#

package Orca_Services::Radius;

BEGIN {
	use strict;
	use Carp;
	use Exporter;
	use IO::File;
	use Sys::Syslog;
	use Orca_Services::Vars;
	$Services{Radius}{File} = "/usr/local/lib/Orca_Services.DB.$nodename";
	$Services{Radius}{FileD} = "";
	$Services{Radius}{Ok} = -1;
	$Services{Radius}{External} = 1;
	$Services{Radius}{Init} = "init_radius";
	$Services{Radius}{Init_Vars} = "";
	$Services{Radius}{Measure} = "measure_radius";
	$Services{Radius}{Put} = "put_radius";

	$PrgOptions{"radius_db=s"} = \$Services{Radius}{File};

	$HelpText{$Services{Radius}{File}} = "--radius_db=FILE      file for user/passwd for DB access (default:";
}

#use DBI;
use Orca_Services::Utils;
use Orca_Services::Output;
use vars qw(@EXPORT @ISA $VERSION);

@EXPORT = qw(init_radius
		measure_radius
		put_radius
                );
@ISA       = qw(Exporter);
$VERSION   = substr q$Revision: 0.01 $, 10;

my ($radius_inc_time ,$radius_inc_sessions);
my ($radius_base_ts, $rad_sessions, $rad_time, $ACCUM_radius_DB);

sub init_radius {
	my ($filename) = @_;
	my ($radius_ok);

	#check if database user/passwd is given!
	if( ! -f $filename){
		print "Database init error: No such file: $filename\n";
		print "Not using Radius module\n";
		return -1;
	}

	my($proto,$drv,$database,$user,$pass)= split(/:/,`$CAT $filename`);

	if(!$proto || !$drv || !$database || !$user || !$pass){
		print "Database init error: unable to parse $filename\n";
		print "Syntax must be: protocol:driver:database:user:passwd ex: DBI:oracle:ORCA:user:pass\n";
		print "Not using Radius module\n";
		return -1;
	}
	chomp($pass);

	if ( ($radius_ok = &init_radius_vars("$proto:$drv:$database",$user,$pass)) ) {
		print "ERROR: Radius init failed! Aborting $radius_ok\n";
		return -1;
	}
}

#
# init_radius - set RADIATOR_RADIUS vars, connect to DB, calculate correct time stamp
#
# usage: &init_radius($db,$user,$pass);
#

sub init_radius_vars {
	my ($db,$user,$pass) = @_;
	my ($BASE_ACCUM_radius_DB);


	$Services{Radius}{FileD}   = DBI->connect($db,$user,$pass);
	if(!$Services{Radius}{FileD}) {
		print "Connect error $DBI::errstr\n";
		return 1;
	}

	#get the lower time limit that our queries will start from
	#get a "history" of 5minutes

	$radius_base_ts= time - 5*60;

	#get accumulated values for what we want to measure:

	#jcp correct this please!
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, undef) = localtime($radius_base_ts);
	$year += 1900;
	$mon++;


	$BASE_ACCUM_radius_DB="/var/orca/Orca_Services/$nodename";
	if ($mon<10) {
		$ACCUM_radius_DB= "$BASE_ACCUM_radius_DB/radiatorRadiusAccum.$year"."0"."$mon.txt";
	} else {
		$ACCUM_radius_DB= "$BASE_ACCUM_radius_DB/radiatorRadiusAccum.$year$mon.txt";
	}
	`$TOUCH $ACCUM_radius_DB`;

	($radius_inc_time,$radius_inc_sessions) = split(/:/,`$CAT $ACCUM_radius_DB`);
	chomp $radius_inc_sessions if $radius_inc_sessions;

	$radius_inc_time       ||= 0;
	$radius_inc_sessions   ||= 0;

	#END jcp correct this please!

	return 0;
}


#
# Get values for radiator radius columns
#
# usage: &measure_radius( );
#

sub measure_radius () {
	my ($query);

	my $upper_ts= time;

	#Begin GET  Accounting

	$query  = "SELECT ACCT_SESSION_TIME,ACCT_STATUS_TYPE FROM ACCOUNTING ";
	$query .= " WHERE ACCT_STATUS_TYPE = 'Stop'";
	$query .= " AND TIMESTAMP > $radius_base_ts";
	$query .= " AND TIMESTAMP < $upper_ts";

	($rad_time,$rad_sessions) = calculateRadVals($query);

	## incremental/accumulated values
	$radius_inc_time += $rad_time;
	$radius_inc_sessions += $rad_sessions;

	#END GET  Accounting

	`$ECHO "$radius_inc_time:$radius_inc_sessions" > $ACCUM_radius_DB`;
	$radius_base_ts += ($upper_ts - $radius_base_ts);
	return 0;
}

##
# IN:   query
# RET:  time, sessions
##
sub calculateRadVals{
	my $query = shift(@_);
	my ($sth, @row);

	#print "radius query: $query\n";

	my ($rad_t,$rad_s)= (0,0);
	$sth = $Services{Radius}{FileD}->prepare($query);
	$sth ->execute();

	$"=" \t ";
	while ( @row = $sth -> fetchrow_array()){
		#print "$row[0].$row[1]: $eca\n";
		$rad_t += $row[0];
		$rad_s++;
	}

	#print "Time: $rad_t seconds\t Sess: $rad_s sessions\n";
return ($rad_t,$rad_s);
}


#
# Put the radiator radius  values for output
#
# usage: &put_radius();
#

sub put_radius() {
	&put_output("rad_time",  sprintf("%8.2f", $rad_time));
	&put_output("rad_sessions",  sprintf("%8.2f", $rad_sessions));

	#incremental graph
	&put_output("radius_inc_time",  sprintf("%8.2f", $radius_inc_time));
	&put_output("radius_inc_sessions",  sprintf("%8.2f", $radius_inc_sessions));

	return 0;
}


1;
