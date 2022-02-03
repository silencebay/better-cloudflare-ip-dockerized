#!/bin/sh

# remove first and last quote (")
CRON="${CRON%\"}"
CRON="${CRON#\"}"
[ -z "$CRON" ] && CRON="0 */6 * * *"

echo "${CRON} /usr/bin/flock -n /tmp/fcj.lockfile /usr/local/bin/test.sh > /proc/1/fd/1 2>/proc/1/fd/2" > /etc/crontabs/root;

/usr/bin/flock -n /tmp/fcj.lockfile /usr/local/bin/test.sh > /proc/1/fd/1 2>/proc/1/fd/2 &

exec "$@"
