#!/bin/bash
force=0
gotify_addr="https://gotify.example.com"
gotify_token="abcABC123"
domain="domain.com.au"

if [ ! -z $1 ];then 
	if [ $1 == "--force" ];then
		force=1
	fi
fi
notify () {
        curl -q -s -X POST "${gotify_addr}/message?token=${gotify_token}" -F "title=$1" -F "message=$2" -F "priority=$3"
        if [ $3 = "10" ];then
                exit 1
        fi
}

renew () {
	certbot certonly --force-renew --manual --preferred-challenges=dns --manual-auth-hook /usr/local/scripts/lets-encrypt/gcpDNSAdd.sh --manual-cleanup-hook /usr/local/scripts/lets-encrypt/gcpDNSDel.sh -d *.${domain} --manual-public-ip-logging-ok || LEerror=$(tail -n1 /var/log/letsencrypt/letsencrypt.log | awk -F':' '/ERROR:certbot._internal/ {print $6}')
	if [ ! -z $LEerror ]; then
		notify "SSL Renewal Error" "Error - $LEerror" "10"
	else
		notify "SSL Renewal Complete" "SSL Certificate successfully renewed" "5"
	fi
}

# Check to see if we need to renew
expDate=$(curl --insecure -v https://${domain} 2>&1 | awk 'BEGIN { cert=0 } /^\* Server certificate:/ { cert=1 } /^\*/ { if (cert) print }' | awk -F': ' '/expire date/ { print $2 }')
days=$(expr '(' $(date -d "$expDate" +%s) - $(date +%s) + 86399 ')' / 86400)
if [ $days -le "30" -o $force == "1" ];then
	renew
else
	echo "No need to renew, $days days remaining"
	exit 0
fi

# Restart Nginx proxy to get new certificate
docker restart nginx

# Confirm new SSL has been installed
sleep 5
expDate=$(curl --insecure -v https://${domain} 2>&1 | awk 'BEGIN { cert=0 } /^\* Server certificate:/ { cert=1 } /^\*/ { if (cert) print }' | awk -F': ' '/expire date/ { print $2 }')
days=$(expr '(' $(date -d "$expDate" +%s) - $(date +%s) + 86399 ')' / 86400)
notify "Nginx Proxy" "Successfully restarted - $days days remaining" "5"

# Install new SSL on EdgeRouter
cat /etc/letsencrypt/live/${domain}/privkey.pem /etc/letsencrypt/live/${domain}/fullchain.pem > /etc/letsencrypt/live/${domain}/server.pem
scp -P 22 -i router_ssh_key.txt /etc/letsencrypt/live/${domain}/server.pem admin@192.168.1.254:/config/auth/${domain}.certkey
scp -P 22 -i router_ssh_key.txt /etc/letsencrypt/live/${domain}/chain.pem admin@192.168.1.254:/config/auth/${domain}.ca
ssh -p 22 -i router_ssh_key.txt admin@192.168.1.254 "sudo kill \$(cat /var/run/lighttpd.pid) && sudo /usr/sbin/lighttpd -f /etc/lighttpd/lighttpd.conf"

sleep 5
expDate=$(curl --insecure -v https://gateway.${domain} 2>&1 | awk 'BEGIN { cert=0 } /^\* Server certificate:/ { cert=1 } /^\*/ { if (cert) print }' | awk -F': ' '/expire date/ { print $2 }')
days=$(expr '(' $(date -d "$expDate" +%s) - $(date +%s) + 86399 ')' / 86400)
if [ $days -le "60" ];then
	notify "Ubiquiti EdgeRouter" "Certificate error - $days days remaining" "10"
else
	notify "Ubiquiti EdgeRouter" "Successfully updated - $days days remaining" "5"
fi
