#!/bin/bash
echo "Validation: $CERTBOT_VALIDATION"
if [ -z $CERTBOT_VALIDATION ]; then
	echo "Validation empty, exiting"
	exit 1
fi

service_account_email=service-account-email-goes-here
project=project_name
domain=domain.com.au
zone=zone_name

# Create the GCP TXT record
gcloud beta dns --account=${service_account_email} --project=${project} record-sets transaction start --zone=${zone_name} &> /dev/null
gcloud beta dns --account=${service_account_email} --project=${project} record-sets transaction add $CERTBOT_VALIDATION --name=_acme-challenge.${domain}. --ttl=60 --type=TXT --zone=${zone_name} &> /dev/null
gcloud beta dns --account=${service_account_email} --project=${project} record-sets transaction execute --zone=${zone_name} &> /dev/null


sleep 120
rm -f transaction.yaml
