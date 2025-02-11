#!/bin/bash
service=$(cat /var/dashboard/services/fastsync | tr -d '\n')

if [[ $service == 'start' ]]; then
minername=$(docker ps -a|grep miner|awk -F" " '{print $NF}')
newheight=`curl --silent https://snapshots-wtf.sensecapmx.cloud/latest-snap.json|awk -F':' '{print $3}'| rev | cut -c2- | rev`
echo "Snapshot height is $newheight"; > /home/pi/hnt/miner/log/console.log

echo "Stopping the miner... " > /home/pi/hnt/miner/log/console.log
sudo docker stop $minername
echo "Clearing blockchain data... " > /home/pi/hnt/miner/log/console.log
sudo rm -rf /home/pi/hnt/miner/blockchain.db
sudo rm -rf /home/pi/hnt/miner/ledger.db
echo -n "Starting the miner... " > /home/pi/hnt/miner/log/console.log
sudo docker start $minername

filepath=/tmp/snap-$newheight;
if [ ! -f "$filepath" ]; then
  echo "Downloading latest snapshot" > /home/pi/hnt/miner/log/console.log
  wget -q --show-progress https://snapshots-wtf.sensecapmx.cloud/snap-$newheight -O /tmp/snap-$newheight
else
  modified=`stat -c %Y $filepath`
  now=`date +%s`
  longago=`expr $now - $modified`
  longagominutes=`expr $longago / 60`
  #NUM_SECS=`expr $HOW_LONG % 60`
  echo "Up-to-date snapshot already downloaded $longagominutes minutes ago" > /home/pi/hnt/miner/log/console.log
  sleep 5; # Wait until the miner is fully functional

fi



sudo docker exec $minername cp /opt/miner/bin/miner /opt/miner/bin/miner_load
sudo docker cp $minername:/opt/miner/bin/miner ~/miner_load
sudo sed -i 's/export RELX_RPC_TIMEOUT/RELX_RPC_TIMEOUT=3600\nexport RELX_RPC_TIMEOUT/g' ~/miner_load
sudo docker cp ~/miner_load $minername:/opt/miner/bin/miner_load

echo -n "Pausing sync... " > /home/pi/hnt/miner/log/console.log
sudo docker exec  $minername  miner repair sync_pause
echo -n "Cancelling pending sync... " > /home/pi/hnt/miner/log/console.log
sudo docker exec  $minername  miner repair sync_cancel

echo "Deleting stale snapshots" > /home/pi/hnt/miner/log/console.log
sudo rm -f /home/pi/hnt/miner/snap/*

echo "Loading snapshot. This can take up to 20 minutes" > /home/pi/hnt/miner/log/console.log
echo 'stopped' > /var/dashboard/services/fastsync
sudo cp /tmp/snap-$newheight /home/pi/hnt/miner/snap/snap-$newheight

> /tmp/load_result
now=`date +%s`
((docker exec  $minername  miner_load snapshot load /var/data/snap/snap-$newheight > /tmp/load_result) > /dev/null 2>&1 &)

#(((sleep 30 && echo "ok") > /tmp/load_result) > /dev/null 2>&1 &)


while :
do
    result=$(cat /tmp/load_result);
    if [ "$result" = "ok" ]; then
       modified=`stat -c %Y /tmp/load_result`
       longago=`expr $modified - $now`
       longagominutes=`expr $longago / 60`
       echo " " > /home/pi/hnt/miner/log/console.log
       echo "Snapshot loaded in $longagominutes minutes" > /home/pi/hnt/miner/log/console.log
       sudo rm -f /home/pi/hnt/miner/snap/snap-$newheight
       rm /tmp/load_result
       echo -n "Resuming sync... " > /home/pi/hnt/miner/log/console.log
       docker exec  $minername  miner repair sync_resume
       echo "Done!" > /home/pi/hnt/miner/log/console.log
       break;
    elif [ "$result" = "" ];then
       echo -n "."
    else
       echo "Error: Snapshot could not be loaded. Try again" > /home/pi/hnt/miner/log/console.log
       break;
    fi
    sleep 10
done
fi
