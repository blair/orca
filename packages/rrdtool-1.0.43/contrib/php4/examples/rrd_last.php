<?

 ## the following line is only needed if built as a self-contained
 ## extension.  If you build the rrdtool module as an embedded
 ## extension, the rrd_* functions will always be available, so you
 ## do not need the dl() call.
 dl("rrdtool.so");

 ##
 ## demonstration of the rrd_last() command
 ##

 $ret = rrd_last("/some/path/some-router-fe2.rrd");

 if ( $ret != - 1 )
 {
     printf("Last update time:  %s\n", strftime("%m/%d/%Y %H:%M:%S"), $ret);
 }
 else
 {
     $err_msg = rrd_error();
     echo "Error occurred:  $err_msg\n";
 }


?>
