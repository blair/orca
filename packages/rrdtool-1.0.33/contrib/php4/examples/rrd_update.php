<?

 ## the following line is only needed if built as a self-contained
 ## extension.  If you build the rrdtool module as an embedded
 ## extension, the rrd_* functions will always be available, so you
 ## do not need the dl() call.
 dl("rrdtool.so");

 ##
 ## demonstration of the rrd_update() command
 ##

  $ret = rrd_update("/some/file.rrd", "N:1245:98344");

  if ( $ret == 0 )
  {
      $err = rrd_error();
      echo "ERROR occurred: $err\n";
  }
 /* else rrd_update() was successful */


?>
