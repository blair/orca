#
# Utils.pm : Orca_Services package for some usefull functions
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

package Orca_Services::Utils;

use strict;
use Carp;
use Exporter;
use IO::File;
use Sys::Syslog;
use Orca_Services::Vars;
use vars qw(@EXPORT @ISA $VERSION);

@EXPORT = qw(logit
				OpenFile
				CheckFileChange
				);
@ISA       = qw(Exporter);
$VERSION   = substr q$Revision: 0.01 $, 10;

#
# logit -- send MSG(s) to the syslog.
#
# usage: &logit($msg_to_log);
#

sub logit {
	my($Msg) = @_;

	&Sys::Syslog::openlog("$progname", 'cons,pid', "$log_facility");
	&Sys::Syslog::syslog("$log_priority", $Msg);
	&Sys::Syslog::closelog();
}

sub OpenFile {
	my ($filename, $ServName, $ref_ino, $ref_size) = @_;
	my ($retval, $seek_ok);

	$retval = 0;
	$Services{$ServName}{FileD} = new IO::File "$filename", "r";
	if (defined($Services{$ServName}{FileD})) {
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
		$atime,$mtime,$ctime,$blksize,$blocks) = stat($Services{$ServName}{FileD});
		if (!$dev) {
			&logit ("can't stat $filename");
			warn "$progname: can't stat $filename\n";
			$retval = 1;
		}
		$$ref_ino = $ino;
		$$ref_size = $size;
		$seek_ok = seek($Services{$ServName}{FileD}, 0, SEEK_END);
		if (!$seek_ok) {
			&logit ("can't seek into EOF on $filename");
			warn "$progname: can't seek into EOF on $filename\n";
			$retval = 2;
		}
	} else {
		&logit ("can't open $filename");
		warn "$progname: can't open $filename\n";
		$retval = 3;
	}

	return $retval;
}

sub CheckFileChange {
	my ($ServName, $ref_ino, $ref_size) = @_;
	my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev );
	my ($size, $atime, $mtime, $ctime, $blksize, $blocks);

	# test for file change via different inode or filesize decrease
	$dev = $ino = $mode = $nlink = $uid = $gid = $rdev = 
	$size = $atime = $mtime = $ctime = $blksize = $blocks = '';
	($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	$atime,$mtime,$ctime,$blksize,$blocks) = stat($Services{$ServName}{File});
	if (!$dev) {
		&logit ("can't stat $Services{$ServName}{File}");
		warn "$progname: can't stat $Services{$ServName}{File}\n";
		return 1;
	}
	printf "Filedesc %s  old_ino=%s vs. ino=%s\told_size=%s vs. size=%s\n", $ServName, $$ref_ino, $ino, $$ref_size, $size if $Options{debug};
	if (($$ref_ino != $ino) || ($$ref_size > $size)) {
		undef $Services{$ServName}{FileD};
		printf "Ffile change on $Services{$ServName}{File}\n" if $Options{debug};
		$Services{$ServName}{FileD} = new IO::File "$Services{$ServName}{File}", "r";
		if (!defined ($Services{$ServName}{FileD})) {
			&logit ("can't re-open $Services{$ServName}{File}");
			warn "$progname: can't re-open $Services{$ServName}{File}\n";
			$$ref_ino = $$ref_size = 0;
			return 2;
		}
		$$ref_ino = $ino;
		$$ref_size = $size;
	}
	return 0;
}

1;
