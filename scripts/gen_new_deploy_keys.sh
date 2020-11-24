#!/bin/bash
WORKING_DIR=/home/ubuntu/my-ca
GITHUB_DEPLOY_KEY_FILE=~/.ssh/github_deploy_params
if [ -s "$GITHUB_DEPLOY_KEY_FILE" ]; then
    source $GITHUB_DEPLOY_KEY_FILE
else
    echo "$GITHUB_DEPLOY_KEY_FILE required. No params == no run."
    exit
fi

rm -f $WORKING_DIR/id_ed25519_github_deploy* $WORKING_DIR/ghActions.conf

ssh-keygen -t ed25519 -a 100 -f $WORKING_DIR/id_ed25519_github_deploy -q -N ""
ssh-keygen -s $WORKING_DIR/ca_key -I github -n ubuntu,ackersond -P "$CACERT_KEY_PASS" -V +5w -z $(date +%s) $WORKING_DIR/id_ed25519_github_deploy
CERT_INFO=`ssh-keygen -L -f $WORKING_DIR/id_ed25519_github_deploy-cert.pub`

# rm wireguard peer & server configs
sudo kubectl exec -it $(sudo kubectl get po | grep wireguard | awk '{print $1; exit}' | tr -d \\n) -- rm -Rf /config/peer_githubActions /config/wg0.conf

# restart wireguard container to force regeneration
sudo kubectl scale deployment --replicas=0 wireguard && sudo kubectl scale deployment --replicas=1 wireguard && sleep 20

# capture new peer config in file
sudo kubectl exec -it $(sudo kubectl get po | grep wireguard | awk '{print $1; exit}' | tr -d \\n) -- cat /config/peer_githubActions/peer_githubActions.conf | tee $WORKING_DIR/ghActions.conf

NEW_WG_PUBKEY=`cat $WORKING_DIR/ghActions.conf | grep Public`

# heavy lifting which updates github secrets via API
if $WORKING_DIR/github_deploy_secrets.py ; then
    rm $WORKING_DIR/id_ed25519_github_deploy* $WORKING_DIR/ghActions.conf

    curl -s -F token=$SLACK_API_TOKEN -F channel=C092UE0H4 \
        -F text="$HOSTNAME just updated the SSH deploy key, cert & wireguard keys in Org Secrets\n: $CERT_INFO\nWireguard client $NEW_WG_PUBKEY" https://slack.com/api/chat.postMessage
fi
