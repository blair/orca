#!/usr/bin/perl
#
# Version 1.7

# Description:
# Collect general perfromance statistics formatted for
# interpretaion by Orca.

# Usage: 
# The following variables may be set:
# 
# OUT_ROOT root directory for datafiles (eg /opt/log/performance)
# INTERVAL the number of seconds between checks (eg 300 = 5 min)
# DURATION numer of hours to run (eg 1 = 1 hr)
# 
# This script runs various standard system utilities to collect
# system performance statistics and writes them out to datafile named
# HOSTNAME/stats.YYYY-MM-DD-HHmm under the OUT_ROOT directory.
# 
# It runs for the the numbers specified by DURATION collecting data
# every INTERVAL number of seconds. After DURATION, the script
# closes and compresses it's datafile via /usr/bin/compress and then
# exits. If DURATION=24 and INTERVAL=300 (recommended) then the
# following cron entry would collect continuos stats for a system:
# 
# 0 0 * * * /<PATH_TO_SCRIPT>/orca-aix-stat.pl
# 
# 2003-09-10 - RV - Modified for AIX 4.3/5.x.. by Rajesh Verma
#                       (rajeshverma@aixdude.com)
# v1.7       - RV - ignores /proc now
# 2001-04-16 - JDK - Genesis... by Jason D. Kelleher
# 2001-05-02 - JDK - Updates to make data aggregation easier.
# Added #open connections, pagestotl.
# 2001-07-06 - JDK - added command-line args & data checks
# 2001-07-09 - JDK - added signal handler, column checks, & umask
# 2001-07-10 - JDK - now autodetects interfaces via netstat -i
# v1.5
#
# $HeadURL$
# $LastChangedDate$
# $LastChangedBy$
# $LastChangedRevision$

# Note: Execution speed is more important than cleanliness here.

# Explicitly set PATH to prevent odd problems if run manually.
$ENV{PATH} = '/usr/bin:/etc:/usr/sbin:/usr/ucb:/sbin';

$Usage_Message = '
Usage: orca-aix-stat.pl [-r out_root] [-i interval] [-d duration] [-h]

-r out_root set root output directory, default: /opt/log/performance
-i interval number of seconds between checks, default: 300
-d duration number of hours to run, default: 24
-h this message

';
############################
# These are the packages you need to install
# 1. perl
# 2. openssh - if using ssh to the collector server
# 3. openssl
# 4. zlib
# 5. rsync - To copy file to the collector server
# 6. gzip - to zip the files
# 7. rpm.rte - to install rpm tools
#
# This the site you can file everything
# http://www-1.ibm.com/servers/aix/products/aixos/linux/download.html
# http://www.bullfreeware.com
#
#
#  Good Luck, Rajesh Verma (rajeshverma@yahoo.com)
##############################

# Parse the command line arguments
while ( $#ARGV >= 0 ) {

    if ( $ARGV[0] eq "-r" ) {
        shift @ARGV;
        $OUT_ROOT = shift @ARGV;
    }
    elsif ( $ARGV[0] eq "-i" ) {
        shift @ARGV;
        $INTERVAL = shift @ARGV;
    }
    elsif ( $ARGV[0] eq "-d" ) {
        shift @ARGV;
        $DURATION = shift @ARGV;
    }
    elsif ( $ARGV[0] eq "-h" ) {
        print $Usage_Message;
        exit 0;
    }
    elsif ( $ARGV[0] =~ /^-/ ) {
        die "Invalid flag: $ARGV[0]\n$Usage_Message";
    }
    else {
        die "Invalid argument: $ARGV[0]\n$Usage_Message";
    }
}

## BEGIN set defaults

$OUT_ROOT ||= '/home/orca/orcallator';    # root directory for datafiles
$INTERVAL ||= 300;                       # seconds between checks
$DURATION ||= 24;                        # number of hours to run

## END set defaults

## Derived variables.
$iterations = $DURATION * 60 * 60 / $INTERVAL;    # Number of checks.
chomp( $HOST = `uname -n` );
$out_dir = "${OUT_ROOT}/${HOST}";
( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
  localtime(time);
$stat_file =
  sprintf( "%s/percol-%.2d-%.2d-%.2d-%1d%.2d", $out_dir, $year + 1900, $mon + 1,
  $mday, $hour, $min );

# Base all timestamps on start time.
$start_time = time();
$timestamp  = 0;

## Autodetect network interfaces
#open IN, "ifconfig -a|";
open IN, "netstat -ni|";
while (<IN>) {

    # if ( /^(\S+):/ ) {
    if (/^(\w+).*link/) {
        push @net_interfaces, $1;
    }
}
close IN;

# Grab some base system info prior to collecting stats.
open IN, "lsattr -El sys0 -a realmem |";
while (<IN>) {
    if (/^realmem (\d+) /) {
        $pagestotl = $1 * 1024 / 4096;    # Grab realmem in KB and convert to pages.
        $mem_totl = $1 * 1024;    # Grab realmem in KB and convert to Bytes.

        # this gets used down in the vmstat section
    }
}
close IN;

## Make sure we can write output.
umask 0022;    # make sure the file can be harvested
unless ( -d $out_dir ) {
    system( "mkdir", "-p", "$out_dir" );
}
open OUT, ">$stat_file" or die "ERROR: Could not open $stat_file: $!";
my $oldfh = select OUT;
$| = 1;
select $oldfh;

# Set signal handlers to close and compress the output
# file just in case.
$SIG{HUP}  = \&exit_nicely;
$SIG{INT}  = \&exit_nicely;
$SIG{QUIT} = \&exit_nicely;
$SIG{TERM} = \&exit_nicely;

# Set gloabals used for printing (or not) headers.
$need_header     = 1;
$prev_header_cnt = 0;
$prev_info_cnt   = 0;

while ( $iterations-- > 0 ) {

    $timestamp = $timestamp ? time() : $start_time;
    ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime(time);
    $locltime = sprintf( "%.2d:%.2d:%.2d", $hour, $min, $sec );

    ## Get runq data
   ## Get runq data
    $uptime = 0;
    open IN, "uptime |";
    while (<IN>) {
        if (/load average:\s+(\S+),\s+(\S+),\s+(\S+)/) {
            $load_info = join "\t", $1, $2, $3;
        }
        @upt = split(/ +/,);
        $uptd = $upt[3];
        $nusr = $upt[6];
        $up_day = $uptd * 24 * 60 * 60;
       if (/days,\s+(\S+):(\S+), /) {
         $up_hrs = $1 * 60 * 60;
         $up_min = $2 * 60;
        }
        $uptime = $up_day + $up_hrs + $up_min;
    }
    close IN;
    $load_header = "1runq\t5runq\t15runq";
    $up_header = "uptime\tnusr";
    $up_info = "$uptime\t$nusr";

    if ( scalar( split ' ', $load_header ) != scalar( split ' ', $load_info ) )
    {
        $load_header = '';
        $load_info   = '';
        $need_header = 1;
        print STDERR "WARNING: load header does not match load info.\n";
    }
    if ( scalar( split ' ', $up_header ) != scalar( split ' ', $up_info ) )
    {
        $up_header = '';
        $up_info   = '';
        $need_header = 1;
        print STDERR "WARNING: UP header does not match load info.\n";
    }


    ## Get number of system processes
    $num_proc = -1;    # Don't count the header.
    open IN, "ps -ek |";
    while (<IN>) {
        $num_proc++;
    }
    close IN;
    $proc_info   = $num_proc;
    $proc_header = '#proc';

    if ( scalar( split ' ', $proc_header ) != scalar( split ' ', $proc_info ) )
    {
        $proc_header = '';
        $proc_info   = '';
        $need_header = 1;
        print STDERR "WARNING: #proc header does not match #proc info.\n";
    }

    ## Get pstat data for pages
       $sw_used = 0;
       $sw_free = 0;
	open IN, "pstat -s |tail -3 |";
	while (<IN>) {
   	 @swp = split(/ +/,);
   	 if (/\d/) {
    	 $sw_used = $swp[1];
    	 $sw_free = $swp[2];
         $swap_used = $sw_used * 4096;
         $swap_free = $sw_free * 4096;
   	 }
	}
	close IN;
	$swap_info = "$swap_used\t$swap_free";
	$swap_header = "\tswap_used\tswap_free";

    if ( scalar( split ' ', $swap_header ) !=
      scalar( split ' ', $swap_info ) )
    {
        print STDERR "WARNING: pstat header does not match pstat info.\n";
        $swap_header = '';
        $swap_info   = '';
        $need_header   = 1;
    }
	


    ## Get vmstat data
    open IN, "vmstat 1 2|";
    while (<IN>) {
        chomp;
        if (/^[\s\d]+$/) {

            # overwrite first line on 2nd pass
            (
              $vmstat_r,   $vmstat_b,  $vmstat_avm, $vmstat_fre,
              $vmstat_re,  $vmstat_pi, $vmstat_po,  $vmstat_fr,
              $vmstat_sr,  $vmstat_cy, $vmstat_inf, $vmstat_syf,
              $vmstat_csf, $vmstat_us, $vmstat_sy,  $vmstat_id,
              $vmstat_wa )
              = split;
            $vmstat_info = join "\t", $vmstat_r, $vmstat_b, $vmstat_avm, 
  	      $vmstat_fre, $pagestotl, $vmstat_pi, $vmstat_po, $vmstat_fr, 
              $vmstat_sr, $vmstat_us, $vmstat_sy, $vmstat_wa, $vmstat_id;
        }
    }
    close IN;
    $vmstat_header =
"runque\twaiting\tpagesactive\tpagesfree\tpagestotl\tPagesI/s\tPagesO/s\tPagesF/s\tscanrate\tusr%\tsys%\twio%\tidle%";

    if ( scalar( split ' ', $vmstat_header ) !=
      scalar( split ' ', $vmstat_info ) )
    {
        print STDERR "WARNING: vmstat header does not match vmstat info.\n";
        $vmstat_header = '';
        $vmstat_info   = '';
        $need_header   = 1;
    }

    ## Get filesystem data
    $fs_header = '';
    $fs_info   = '';
    open IN, "df -k -v |";
    while (<IN>) {
        chomp;

        if (m%^/dev%) {
            ( $mnt_dev, $blocks, $used, $free, $pct_used, $iused, $ifree,
              $ipct_used, $mnt ) = split;

            # Recalculate percents because df rounds.
            $fs_info .= "\t" 
		. sprintf( "%s\t%s\t%s\t%.5f\t%d\t%s\t%s\t%.5f", $blocks, $used,
              $free, ( $used / $blocks ) * 100, ( $iused + $ifree ), $iused,
              $ifree, ( $iused / ( $iused + $ifree ) ) * 100 );
            $fs_header .= "\t" . join "\t", "mntC_$mnt", "mntU_$mnt",
              "mntA_$mnt", "mntP_$mnt", "mntc_$mnt", "mntu_$mnt", "mnta_$mnt",
              "mntp_$mnt";
        }
    }
    close IN;

    if ( scalar( split ' ', $fs_header ) != scalar( split ' ', $fs_info ) ) {
        print STDERR
          "WARNING: filesystem header does not match filesystem info.\n";
        $fs_header   = '';
        $fs_info     = '';
        $need_header = 1;
    }

    ## Get iostat data
    $disk_t  = 0;
    $disk_rK = 0;
    $disk_wK = 0;
    undef %disks;
    open IN, "iostat -d 1 2|";

    while (<IN>) {
        if (/^(\S+)\s+\S+\s+\S+\s+(\S+)\s+(\d+)\s+(\d+)/) {
            my $disk = $1;
            my $tps  = $2;
            my $rK   = $3;
            my $wK   = $4;
            if ( not $disks{$disk} ) {
                $disks{$disk}++;    # Get rK & wK from first pass.
                $disk_rK += $rK;
                $disk_wK += $wK;
            }
            else {
                $disk_t += $tps;    # Get trans per sec from second pass.
            }
        }
    }
    close IN;
    $iostat_header = "disk_t/s\tdisk_rK/s\tdisk_wK/s";
    $iostat_info   = "${disk_t}\t${disk_rK}\t${disk_wK}";

    if ( scalar( split ' ', $iostat_header ) !=
      scalar( split ' ', $iostat_info ) )
    {
        print STDERR "WARNING: iostat header does not match iostat info.\n";
        $iostat_header = '';
        $iostat_info   = '';
        $need_header   = 1;
    }

    ## Get packet data
    $packet_header = '';
    $packet_info   = '';

    #foreach $interface ( split(/\s+/, $NET_INTERFACES) ) {
    foreach $interface (@net_interfaces) {
        $packet_header .=
"\t${interface}Ipkt/s\t${interface}IErr/s\t${interface}Opkt/s\t${interface}OErr/s\t${interface}Coll/s\t";
        open IN, "netstat -n -I $interface 1|";

        while (<IN>) {
            if (/^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+/) {
                $packet_info .= "\t" . join "\t", $1, $2, $3, $4, $5;
                last;
            }
        }
        close IN;
    }

    if ( scalar( split ' ', $packet_header ) !=
      scalar( split ' ', $packet_info ) )
    {
        print STDERR "WARNING: packet header does not match packet info.\n";
        $packet_header = '';
        $packet_info   = '';
        $need_header   = 1;
    }

    ## Get TCP Connection data
    $tcp_estb = 0;
    open IN, "netstat -an |";
    while (<IN>) {
        if (/^tcp.+ESTABLISHED$/) {
            $tcp_estb++;
        }
    }
    close IN;
    $tcp_info   = $tcp_estb;
    $tcp_header = 'tcp_estb';

    if ( scalar( split ' ', $tcp_estb_header ) !=
      scalar( split ' ', $tcp_estb_info ) )
    {
        print STDERR "WARNING: tcp_estb header does not match tcp_estb info.\n";
        $tcp_estb_header = '';
        $tcp_estb_info   = '';
        $need_header     = 1;
    }

    ## Get TSM Database space usage
    $tsmdb = 0;
    open IN, "dsmadmc -id=view -password=view 'query db' |tail -r -n 5 |";
    while (<IN>) {
      @fld = split(/ +/,);
      if (/\d/) {
        $tsmdb = $fld[8];
       }
    }
    close IN;
    $tsm_info = $tsmdb;
    $tsm_header = "tsmdb\t";

    if ( scalar( split ' ', $tsm_header ) !=
      scalar( split ' ', $tsm_info ) )
    {
        print STDERR "WARNING: tsmdb header does not match tsmdb info.\n";
        $tsm_header = '';
        $tsm_info   = '';
        $need_header     = 1;
    }

    ## Get Memory Usage breakup using SVMON
    $mem_work = 0;
    $mem_pres = 0;
    $mem_clnt = 0;
    open IN, "svmon -G |tail -2 |";
    while (<IN>) {
     @memp = split(/ +/,);
     if (/use\s+(\d+) /) {
      $m_work = $memp[2];
      $m_pres = $memp[3];
      $m_clnt = $memp[4];
      $mem_work = $m_work * 4096;
      $mem_pres = $m_pres * 4096;
      $mem_clnt = $m_clnt * 4096;
     }
    }
    close IN;
    $mem_info = "$mem_work\t$mem_pres\t$mem_clnt\t$mem_totl";
    $mem_header = "mem_work\tmem_pres\tmem_clnt\tmem_totl";

    if ( scalar( split ' ', $mem_header ) !=
      scalar( split ' ', $mem_info ) )
    {
        print STDERR "WARNING: memory header does not match memory info.\n";
        $mem_header = '';
        $mem_info   = '';
        $need_header     = 1;
    }

    ## Get TSM Tape Drive usage
    $rmt = 0;
    $rmt5 = 5;
    open IN, "dsmadmc -id=view -password=view 'query mount' |grep matches |";
    while (<IN>) {
    @fld = split(/ +/,);
    if (/\d/) {
      $rmt = $fld[1];
     }
    }
    close IN;
    $tsm_rmt_header = "rmt5\trmt\t";
    $tsm_rmt_info = "$rmt5\t$rmt";

    if ( scalar( split ' ', $tsm_rmt_header ) !=
      scalar( split ' ', $tsm_rmt_info ) )
    {
        print STDERR "WARNING: TSM RMT header does not match TSM RMT info.\n";
        $tsm_rmt_header = '';
        $tsm_rmt_info   = '';
        $need_header     = 1;
    }

    ## Get TSM Recovery Log space usage
    $tsmdb = 0;
    open IN, "dsmadmc -id=view -password=view 'query log' |tail -r -n 4 |";
    while (<IN>) {
    @fld = split(/ +/,);
    if (/\d/) {
      $tsmlog = $fld[8];
     }
    }
    close IN;
    $tsm_log_info = $tsmlog;
    $tsm_log_header = 'tsmlog';

    if ( scalar( split ' ', $tsm_log_header ) !=
      scalar( split ' ', $tsm_log_info ) )
    {
        print STDERR "WARNING: TSM Log header does not match TSM Log info.\n";
        $tsm_log_header = '';
        $tsm_log_info   = '';
        $need_header     = 1;
    }

    ## Join header and info then verify column counts.
    $out_header = join "\t", "timestamp", "locltime", $load_header, $up_header,
      $proc_header, $vmstat_header, $fs_header, $iostat_header, $packet_header,
      $tcp_header, $tsm_header, $swap_header, $mem_header, $tsm_rmt_header;
    $out_header =~ tr/ \t/\t/s;    # translate whitespace to single tabs

    $out_info = join "\t", $timestamp, $locltime, $load_info, $up_info, $proc_info,
      $vmstat_info, $fs_info, $iostat_info, $packet_info, $tcp_info, $tsm_info, 
	$swap_info, $mem_info, $tsm_rmt_info;
    $out_info =~ tr/ \t/\t/s;      # translate whitespace to single tabs

    $header_cnt = split ' ', $out_header;
    $info_cnt = split ' ', $out_info;
    if ( $header_cnt != $info_cnt ) {
        print STDERR
          "ERROR: header columns do not equal data columns. Exiting.\n";
        &exit_nicely;
    }
    elsif ( $header_cnt != $prev_header_cnt or $info_cnt != $prev_info_cnt ) {
        $need_header = 1;
    }
    $prev_header_cnt = $header_cnt;
    $prev_info_cnt   = $info_cnt;

    ## Write output
    if ($need_header) {
        print OUT $out_header, "\n";
        $need_header = 0;
    }
    print OUT $out_info, "\n";

    sleep $INTERVAL - ( time() - $timestamp );

}
close OUT;

@args = ( "/usr/bin/gzip", "-f", "$stat_file" );
system(@args);

exit 0;

# This subroutine is called by the signal handler.
sub exit_nicely {
    close OUT;
    @args = ( "/usr/bin/gzip", "-f", "$stat_file" );
    system(@args);
    exit 0;
}
