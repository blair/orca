<?

 ## the following line is only needed if built as a self-contained
 ## extension.  If you build the rrdtool module as an embedded
 ## extension, the rrd_* functions will always be available, so you
 ## do not need the dl() call.
 dl("rrdtool.so");

 ##
 ## demonstration of the rrd_create() command
 ##

  $_opts = array( "--step", "300", "--start", 0,
                 "DS:input:COUNTER:900:0:U",
                 "DS:output:COUNTER:900:0:U",
                 "RRA:AVERAGE:0.5:1:1000",
                 "RRA:MIN:0.5:1:1000",
                 "RRA:MAX:0.5:1:1000"
               );

  $ret = rrd_create("/tmp/test.rrd", $_opts, count($_opts));

  if ( $ret == 0 )
  {
      $err = rrd_error();
      echo "Create error: $err\n";
  }
  /*  else rrd_create was successful  */


?>
