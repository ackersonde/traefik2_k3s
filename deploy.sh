#NOTE: docker + k3s == DEAD k3s -> https://github.com/rancher/k3s/issues/703
#TODO: run following cmds in case
# sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
# sudo reboot
#NOTE2: docker stop traefik !! otherwise, pain & confusion

export INTERNAL_HOST_IP=`hostname --ip-address` # for patching 02-svcs.yml -> externalIPs!
curl -sfL https://get.k3s.io | sh -s - server --no-deploy traefik --no-deploy servicelb
sudo kubectl apply -f 01-clusterrole-CRDs.yml
sudo kubectl apply -f 02-svcs-middleware-secrets.yml
sudo kubectl apply -f 03-deployments.yml
sudo kubectl apply -f 04-ingressroutes.yml

curl -I http://apigcp.ackerson.de/
curl -k https://apigcp.ackerson.de/dashboard#/http/routers

sudo kubectl apply -f whoami.yml
curl -I http://k3sgcp.ackerson.de/notls
curl -k https://k3sgcp.ackerson.de/tls

# for DEBUG:
# sudo kubectl port-forward --address 0.0.0.0 service/traefik-ingress-service-lb 80:80 443:443 8080:8080 -n default &
