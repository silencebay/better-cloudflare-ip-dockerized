#!/bin/sh

work_dir=/usr/local/bin/CloudflareSpeedTest
cd $work_dir
./CloudflareST $ARGS -o /tmp/result.csv
best_ip=$(cat /tmp/result.csv | grep -v "IP" | head -n 10 | awk -F, '{print $1}')
echo "${best_ip}" > /data/ip.txt
env | grep GIST_ &>1 && gist.sh /data/ip.txt