From: "Claus Norrbohm" <james@type-this.com>

RRD-Explorer (formally known as clickable rrd graphs) is a
general tool for exploring RRD-files. It eliminates the need
for creating individual RRDs cgi-scripts to show your RRD
graphs, just plug these 4 lines into your httpd.conf (thanks
to Alex van den Bogaerdt):

   # rrd files
   AddIcon /icons/rrd.png .rrd
   AddDescription "Round Robin Database" .rrd

   # rrdtool handler
   AddHandler rrd-handler rrd
   Action rrd-handler /cgi-bin/map.cgi

Last line must be modified to match your system...

If your placed map.cgi & png.cgi - change owner to reflect
your cgi-bin user and make the scripts executable ex.:

   chown root.root map.cgi png.cgi
   chmod a+rx map.cgi png.cgi

Now place your RRD-files in a directory below your "DocumentRoot"
where they can be seen, i.e. "Options Indexes" must be set for
the directory.

Enjoy, Claus
