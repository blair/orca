cp procallator.pl /usr/local/bin
cp procallator /etc/rc.d/init.d
ln -s /etc/rc.d/init.d/procallator /etc/rc.d/rc3.d/S99procallator
/etc/rc.d/init.d/procallator start
echo "Dont forget to copy procallator.cfg to your orca server, and start a new instance of orca using this file as the config file"
echo "To copy the collected files I suggest the use of rsync"
echo "This software is in alpha stagge, use at you own risk"
echo "Copyright (C) 2001 Guilherme Carvalho Chehab.  All Rights Reserved" 
