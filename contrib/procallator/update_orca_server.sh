server=Orca_Server::package
host=`hostname` 
cd /usr/local/var/orca/$host
rsync --times --delete --recursive . $server/$host
cd /
