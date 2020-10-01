#!/bin/bash
GITHUB_DEPLOY_KEY_FILE=~/.ssh/github_deploy_params
if [ -s "$GITHUB_DEPLOY_KEY_FILE" ]; then
    source $GITHUB_DEPLOY_KEY_FILE
else
    echo "$GITHUB_DEPLOY_KEY_FILE required. No params == no run."
    exit
fi

ssh-keygen -t ed25519 -a 100 -f id_ed25519_github_deploy -q -N "$DEPLOY_KEY_PASS"
ssh-keygen -s ca_key -I github -n ubuntu,ackersond -P "$CACERT_KEY_PASS" -V +4w -z $(date +%s) id_ed25519_github_deploy
CERT_INFO=`ssh-keygen -L -f id_ed25519_github_deploy-cert.pub`

# heavy lifting which updates github secrets via API
python3 github_deploy_secrets.py

rm id_ed25519_github_deploy*

curl -s -F token=$SLACK_API_TOKEN -F channel=C092UE0H4 -F text="New Github deploy key uploaded: $CERT_INFO" https://slack.com/api/chat.postMessage
