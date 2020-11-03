#!/bin/bash
WORKING_DIR=/home/ubuntu/my-ca
GITHUB_DEPLOY_KEY_FILE=~/.ssh/github_deploy_params
if [ -s "$GITHUB_DEPLOY_KEY_FILE" ]; then
    source $GITHUB_DEPLOY_KEY_FILE
else
    echo "$GITHUB_DEPLOY_KEY_FILE required. No params == no run."
    exit
fi

rm $WORKING_DIR/id_ed25519_github_deploy*

ssh-keygen -t ed25519 -a 100 -f $WORKING_DIR/id_ed25519_github_deploy -q -N ""
ssh-keygen -s ca_key -I github -n ubuntu,ackersond -P "$CACERT_KEY_PASS" -V +4w -z $(date +%s) $WORKING_DIR/id_ed25519_github_deploy
CERT_INFO=`ssh-keygen -L -f $WORKING_DIR/id_ed25519_github_deploy-cert.pub`

# heavy lifting which updates github secrets via API
if $WORKING_DIR/github_deploy_secrets.py ; then
    rm $WORKING_DIR/id_ed25519_github_deploy*
    #TODO kick off deploy of bender-slackbot

    curl -s -F token=$SLACK_API_TOKEN -F channel=C092UE0H4 \
        -F text="$HOSTNAME just updated the SSH deploy key and cert in Org Secrets\n: $CERT_INFO" https://slack.com/api/chat.postMessage
fi
