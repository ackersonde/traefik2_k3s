#!/bin/bash
WORKING_DIR=/home/ubuntu/my-ca
GITHUB_DEPLOY_KEY_FILE=~/.ssh/github_deploy_params
if [ -s "$GITHUB_DEPLOY_KEY_FILE" ]; then
    source $GITHUB_DEPLOY_KEY_FILE
else
    echo "$GITHUB_DEPLOY_KEY_FILE required. No params == no run."
    exit
fi

rm -f $WORKING_DIR/id_ed25519_github_deploy* $WORKING_DIR/ghActions.conf $WORKING_DIR/ghActions.pub

ssh-keygen -t ed25519 -a 100 -f $WORKING_DIR/id_ed25519_github_deploy -q -N ""
ssh-keygen -s $WORKING_DIR/ca_key -I github -n ubuntu,ackersond -P "$CACERT_KEY_PASS" -V +5w -z $(date +%s) $WORKING_DIR/id_ed25519_github_deploy
CERT_INFO=`ssh-keygen -L -f $WORKING_DIR/id_ed25519_github_deploy-cert.pub`

# rm wireguard peer & server configs
sudo kubectl exec -i $(sudo kubectl get po | grep wireguard | awk '{print $1; exit}' | tr -d \\n) -- rm -Rf /config/peer_githubActions /config/wg0.conf

# restart wireguard container to force regeneration
sudo kubectl scale deployment --replicas=0 wireguard && sleep 45
sudo kubectl scale deployment --replicas=1 wireguard && sleep 45

# capture new peer config in file
sudo kubectl exec -i $(sudo kubectl get po | grep wireguard | awk '{print $1; exit}' | tr -d \\n) -- cat /config/peer_githubActions/peer_githubActions.conf | tee $WORKING_DIR/ghActions.conf
retVal=$?

if [ $retVal -eq 0 ]; then
    sudo kubectl exec -i $(sudo kubectl get po | grep wireguard | awk '{print $1; exit}' | tr -d \\n) -- cat /config/peer_githubActions/publickey-peer_githubActions | tee $WORKING_DIR/ghActions.pub

    NEW_WG_PUBKEY=`cat $WORKING_DIR/ghActions.pub`

    # heavy lifting which updates github secrets via API
    if $WORKING_DIR/github_deploy_secrets.py ; then
        rm $WORKING_DIR/id_ed25519_github_deploy* $WORKING_DIR/ghActions.conf $WORKING_DIR/ghActions.pub

        SLACK_URL=https://slack.com/api/chat.postMessage
        curl -s -d token=$SLACK_API_TOKEN -d channel=C092UE0H4 \
            -d text="$HOSTNAME just updated the SSH deploy key & cert in Org Secrets:" $SLACK_URL
        curl -s -d token=$SLACK_API_TOKEN -d channel=C092UE0H4 -d text="$CERT_INFO" $SLACK_URL
        curl -s -d token=$SLACK_API_TOKEN -d channel=C092UE0H4 \
            --data-binary text="New wireguard client public key: $NEW_WG_PUBKEY" $SLACK_URL
    fi
fi
