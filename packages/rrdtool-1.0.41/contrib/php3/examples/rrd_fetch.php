<?

 dl("/tmp/php3_rrdtool.so");

 ##
 ## demonstration of the rrd_fetch() command
 ##



  $opts = array ( "AVERAGE", "--start", "-1h" );

  $ret = rrd_fetch("/dir/router-port2.rrd", $opts, count($opts));
 
  ##
  ## if $ret is an array, rrd_fetch() succeeded
  ## 
  if ( is_array($ret) )
  {
      echo "Start time    (epoch): $ret[start]\n";
      echo "End time      (epoch): $ret[end]\n";
      echo "Step interval (epoch): $ret[step]\n";

      ##
      ## names of the DS's (data sources) will be 
      ## contained in the array $ret[ds_namv][..]
      ##
      for($i = 0; $i < count($ret[ds_namv]); $i++)
      {
          $tmp = $ret[ds_namv][$i];
          echo "$tmp \n";
      }

      ##
      ## all data will be packed into the
      ## $ret[data][..]  array
      ##
      for($i = 0; $i < count($ret[data]); $i++)
      {
          $tmp = $ret[data][$i];
          echo "$hi\n";
      }
  }
  else
  {
      $err = rrd_error();
      echo "fetch() ERROR: $err\n";
  }


?>
