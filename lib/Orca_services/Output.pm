#
# Output.pm : Orca_Services package for output funcions
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

package Orca_Services::Output;

use strict;
use Carp;
use Exporter;
use POSIX;   
use IO::File;
use Sys::Syslog;
use Orca_Services::Utils;
use Orca_Services::Vars;

use vars qw(@EXPORT @ISA $VERSION);

@EXPORT = qw(put_output
		flush_output
		check_output
                );
@ISA       = qw(Exporter);
$VERSION   = substr q$Revision: 0.01 $, 10;

my (@col_data, @col_comment);

#
# check_output - set outputfile vars, open the outputfile.
#
# usage: &check_output($outputdir);
#

sub check_output {
	my ($outputdir) = @_;
	my ($sec1,$min1,$hour1,$mday1,$mon1,$year1,$wday1,$yday1,$isdst1);
	my ($now_string);

	$sec1=$min1=$hour1=$mday1=$mon1=$year1=$wday1=$yday1=$isdst1 = 0;

	($sec1,$min1,$hour1,$mday1,$mon1,$year1,$wday1,$yday1,$isdst1) = localtime();    

	if ($mday1 != $SaveDay) {
		# First time or day has changed, start new logfile.
		if (OUTFD->opened) {
			close(OUTFD);                            # ignore error
		}
		if (($Options{compress}) && ($SaveDay)) {             # just on day change
			if ($OutputFilename) {
				&logit ("compressing $OutputFilename");
				system ("$Options{compress} $OutputFilename");  # ignore error ??
			}
		}

		$now_string = strftime "%Y-%m-%d", localtime;

		my $subday = 0;
		my $tempfilename = "$outputdir/orca_services-" . $now_string . "-" . sprintf("%03d", $subday);
		while (-f $tempfilename) {
			$subday ++;
			$tempfilename = "$outputdir/orca_services-" . $now_string . "-" . sprintf("%03d", $subday);
		}		
		$OutputFilename = $tempfilename;

		if (!open (OUTFD, ">$OutputFilename")) {
			&logit ("can't open outputfile $OutputFilename");
			die "$progname: can't open outputfile $OutputFilename\n";
		}

		$SaveDay = $mday1;
		$print_header = 1;
	}

	return 0;
}


#
# flush_output - dumps line into outputfile
#
# usage: &flush_output();
#

sub flush_output() {
	if ($print_header) {
		&print_columns(\@col_comment);
		$print_header = 0;
	}
	&print_columns(\@col_data);
	$current_column = 0;
}

#
# Send the stored columns of information to the output.
#
# usage: &print_columns( \@array );
#

sub print_columns() {
	my ($ref) = @_;
	my ($i, @col);

	@col = @$ref;

	for ($i=0; $i < $current_column; $i++) {
		printf OUTFD "%s", $col[$i];
		if ($i != $current_column - 1) {
			printf OUTFD " ";
		}
	}
	printf OUTFD "\n";
	OUTFD->flush;
}

#
# Add one column of comments and data to the buffers.
#
# usage: &put_output( $comment, $data );
#

sub put_output() {
	my ($comment, $data) = @_;

	printf "OUT: --%s-- %s\n", $comment, $data if $Options{debug};
	$col_comment[$current_column] = $comment;
	$col_data[$current_column]    = $data;
	$current_column++;
}

1;
