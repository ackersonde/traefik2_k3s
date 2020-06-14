#!/bin/bash
## thanks to https://gist.github.com/mahowi for the perfect Idea
## put it in /etc/letsencrypt/renewal-hooks/post so it gets run after every renewal.

# parameters
USERNAME=""
PASSWORD="{{ROUTER_PASSWD}}"
CERTPATH="./dump"
HOST=https://fritz.ackerson.de

# make and secure a temporary file
TMP="$(mktemp -t XXXXXX)"
chmod 600 $TMP

# parse out certificates from Traefik 2.2 acme.json file
./traefik-certs-dumper file --version v2

# login to the box and get a valid SID
CHALLENGE=`wget -q -O - $HOST/login_sid.lua | sed -e 's/^.*<Challenge>//' -e 's/<\/Challenge>.*$//'`
HASH="`echo -n $CHALLENGE-$PASSWORD | iconv -f ASCII -t UTF16LE |md5sum|awk '{print $1}'`"
SID=`wget -q -O - "$HOST/login_sid.lua?sid=0000000000000000&username=$USERNAME&response=$CHALLENGE-$HASH"| sed -e 's/^.*<SID>//' -e 's/<\/SID>.*$//'`

# generate our upload request
BOUNDARY="---------------------------"`date +%Y%m%d%H%M%S`
printf -- "--$BOUNDARY\r\n" >> $TMP
printf "Content-Disposition: form-data; name=\"sid\"\r\n\r\n$SID\r\n" >> $TMP
printf -- "--$BOUNDARY\r\n" >> $TMP
printf "Content-Disposition: form-data; name=\"BoxCertImportFile\"; filename=\"BoxCert.pem\"\r\n" >> $TMP
printf "Content-Type: application/octet-stream\r\n\r\n" >> $TMP
cat $CERTPATH/private/\*.ackerson.de.key >> $TMP
cat $CERTPATH/certs/\*.ackerson.de.crt >> $TMP
printf "\r\n" >> $TMP
printf -- "--$BOUNDARY--" >> $TMP

# upload the certificate to the box
wget -q -O - $HOST/cgi-bin/firmwarecfg --header="Content-type: multipart/form-data boundary=$BOUNDARY" --post-file $TMP | grep SSL

# clean up
rm -f $TMP
rm -Rf ./dump/
