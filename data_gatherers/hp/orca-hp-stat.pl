#!/usr/contrib/bin/perl
#
# Version 1.5

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
# 0 0 * * * /<PATH_TO_SCRIPT>/orca-hp-stat.pl
# 
# 2003-09-10 - RV - Modifies for HP ... Rajesh Verma(rajeshverma@aixdude.com)
# ver 1.0
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
#
#
# There are some script which are used for gettting data and there are 
# 
# phymem -- for getting physical memory
# Copy this script in the path /usr/local/bin
#
##################BEGIN OF FILE##################
#/* Programma to determine statistics about the physical and virtual
#  memory of a HP workstation, independant of HP-UX version.
#Shows some of the fields on std out.
#
#Program:     phymem
#Author:      Eef Hartman
#Version:     1.1
#Last change: 97/01/06
#Compiled:    97/10/17 09:17:31
#
#Based on code, posted in the HPadmin mailing list.
#
#To compile: cc -o phys_mem phys_mem.c
#
 #*/
#
#static char SCCSid[] = "@(#)phys_mem    1.1";
#
##include <sys/pstat.h>
#
#void main() {
#struct pst_static stat_buf;
#struct pst_dynamic dyn_buf;
#
#pstat(PSTAT_STATIC,&stat_buf,sizeof(stat_buf),0,0);
#pstat(PSTAT_DYNAMIC,&dyn_buf,sizeof(dyn_buf),0,0);
#
#printf("Physical %ld \n",(stat_buf.physical_memory/256)*1000);
#
#return; }
#
############END OF FILE#################
#Other script is to get the df output correctly.
#File Name : hpdf PATH: /usr/local/bin
#
###########SOF##############
#Thanks to Mark.Deiss@acs-gsg.com, bdf output on HP-UX may appear on 2 lines
#bdf -l | sed -e '/^[^   ][^     ]*$/{
#N
#s/[     ]*\n[   ]*/ /
#}'
#####################EOF#####################
#
#
#
# Explicitly set PATH to prevent odd problems if run manually.
$ENV{PATH} = '/usr/bin:/etc:/usr/sbin:/usr/ucb:/sbin';

$Usage_Message = '
Usage: orca-hp-stat.pl [-r out_root] [-i interval] [-d duration] [-h]

-r out_root set root output directory, default: /opt/log/performance
-i interval number of seconds between checks, default: 300
-d duration number of hours to run, default: 24
-h this message

';

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
open IN, "netstat -i|";
while (<IN>) {

    # if ( /^(\S+):/ ) {
    if (/^(\w+).*link/) {
        push @net_interfaces, $1;
    }
}
close IN;

# Grab some base system info prior to collecting stats.
open IN, "/usr/local/bin/phymem|";
while (<IN>) {
    if (/Physical (\d+) /) {
        $pagestotl =
          $1 * 1024 / 4096;    # Grab realmem in KB and convert to pages.

        ## this gets used down in the vmstat section
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
    open IN, "uptime |";
    while (<IN>) {
        if (/load average:\s+(\S+),\s+(\S+),\s+(\S+)/) {
            $load_info = join "\t", $1, $2, $3;
        }
    }
    close IN;
    $load_header = "1runq\t5runq\t15runq";

    if ( scalar( split ' ', $load_header ) != scalar( split ' ', $load_info ) )
    {
        $load_header = '';
        $load_info   = '';
        $need_header = 1;
        print STDERR "WARNING: load header does not match load info.\n";
    }

    ## Get number of system processes
    $num_proc = -1;    # Don't count the header.
    open IN, "ps -e |";
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

    ## Get vmstat data
    open IN, "vmstat 1 2|";
    while (<IN>) {
        chomp;
        if (/^[\s\d]+$/) {

            # overwrite first line on 2nd pass
            (
              $vmstat_r,   $vmstat_b,  $vmstat_wa,  $vmstat_avm, $vmstat_fre,
              $vmstat_re,  $vmstat_at, $vmstat_pi, $vmstat_po,  $vmstat_fr,
              $vmstat_cy,  $vmstat_sr, $vmstat_inf, $vmstat_syf,
              $vmstat_csf, $vmstat_us, $vmstat_sy,  $vmstat_id
               )
              = split;
            $vmstat_info = join "\t", $vmstat_avm, $vmstat_fre, $pagestotl,
              $vmstat_pi, $vmstat_po, $vmstat_fr, $vmstat_sr, $vmstat_us,
              $vmstat_sy, $vmstat_wa, $vmstat_id;
        }
    }
    close IN;
    $vmstat_header =
"pagesactive\tpagesfree\tpagestotl\tPagesI/s\tPagesO/s\tPagesF/s\tscanrate\tusr%\tsys%\twio%\tidle%";

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
    open IN, "/usr/local/bin/hpdf |";
    while (<IN>) {
        chomp;

        if (m%^/%) {
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
    open IN, "iostat 1 2|";

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
    $iostat_header = "disk_t/s\tdisk_rK/s\tdisk_wK/s\t";
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
"${interface}Ipkt/s\t${interface}IErr/s\t${interface}Opkt/s\t${interface}OErr/s\t${interface}Coll/s\t";
        open IN, "netstat -I $interface 1|";

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
    open IN, "netstat -a |";
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

    ## Join header and info then verify column counts.
    $out_header = join "\t", "timestamp", "locltime", $load_header,
      $proc_header, $vmstat_header, $fs_header, $iostat_header, $packet_header,
      $tcp_header;
    $out_header =~ tr/ \t/\t/s;    # translate whitespace to single tabs

    $out_info = join "\t", $timestamp, $locltime, $load_info, $proc_info,
      $vmstat_info, $fs_info, $iostat_info, $packet_info, $tcp_info;
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

@args = ( "gzip", "-f", "$stat_file" );
system(@args);

exit 0;

# This subroutine is called by the signal handler.
sub exit_nicely {
    close OUT;
    @args = ( "gzip", "-f", "$stat_file" );
    system(@args);
    exit 0;
}
