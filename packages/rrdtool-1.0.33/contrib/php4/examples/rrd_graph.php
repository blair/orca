<?

 ## the following line is only needed if built as a self-contained
 ## extension.  If you build the rrdtool module as an embedded
 ## extension, the rrd_* functions will always be available, so you
 ## do not need the dl() call.
 dl("rrdtool.so");

 ##
 ## demonstration of the rrd_graph() command
 ##

   $opts = array( "--start", "-4d", 
                  "DEF:in=/dir/router-port2.rrd:input:AVERAGE",
                  "DEF:out=/dir/router-port2.rrd:output:AVERAGE",
                  "LINE2:in#0000ff:Incoming Traffic Avg.",
                  "PRINT:in:AVERAGE:incoming\: %1.2lf b/s",
                  "PRINT:in:AVERAGE:incoming2\: %1.2lf b/s"
                );


   $ret = rrd_graph("/some-dir/router-port2.gif", $opts, count($opts));

   ##
   ## if $ret is an array, then rrd_graph was successful
   ##
   if ( is_array($ret) )
   {
       echo "Image size:  $ret[xsize] x $ret[ysize]\n";
       

       ##
       ## all results from any PRINT commands will be
       ## in the array $ret[calcpr][..]
       ##
       echo "rrd_graph1 print results: \n";

       for ($i = 0; $i < count($ret[calcpr]); $i++)
           echo $ret[calcpr][$i] . "\n";
   }
   else
   {
       $err = rrd_error();
       echo "rrd_graph() ERROR: $err\n";
   }

?>
