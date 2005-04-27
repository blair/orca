<?

 dl("/tmp/php3_rrdtool.so");

 ##
 ## demonstration of the rrd_last() command
 ##

 $ret = rrd_last("/some/path/some-router-fe2.rrd");

 if ( $ret != - 1 )
 {
     printf("Last update time:  %s\n", strftime("%m/%d/%Y %H:%M:%S");
 }
 else
 {
     $err_msg = rrd_error();
     echo "Error occurred:  $err_msg\n";
 }


?>
