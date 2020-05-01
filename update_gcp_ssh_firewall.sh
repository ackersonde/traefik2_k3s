#!/bin/bash
PROJECT_ID=serious-house-242812
FIREWALL_NAME=default-allow-ssh
/usr/bin/gcloud auth activate-service-account --key-file=~/.ssh/$PROJECT_ID-b2fcc2e0cff0-update-firewall.json
/usr/bin/gcloud --quiet config set project $PROJECT_ID

## This daily cronjob updates the Google SSH firewall rule to allow Home IP address(es)
# m h  dom mon dow   command
# 15 7 * * * /bin/bash /home/pi/update_gcp_ssh_firewall.sh >> /var/log/update_gcp_ssh_firewall.log 2>&1

ipv4_current=`curl --silent https://ipv4.icanhazip.com/ | xargs echo -n`

# https://cloud.google.com/sdk/gcloud/reference/compute/firewall-rules/update
gcloud compute firewall-rules update $FIREWALL_NAME --source-ranges=$ipv4_current
