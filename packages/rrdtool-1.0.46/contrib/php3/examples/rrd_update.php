<?

 dl("/tmp/php3_rrdtool.so");

 ##
 ## demonstration of the rrd_update() command
 ##

  $ret = rrd_update("/some/file.rrd", "N:1245:98344");

  if ( $ret == -1 )
  {
      $err = rrd_error();
      echo "ERROR occurred: $err\n";
  }
 /* else rrd_update() was successful */


?>
