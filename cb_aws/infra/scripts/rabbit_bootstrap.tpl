#!/bin/bash

exec 1> /var/log/provisioning.log 2>&1
set -x

#### Get environment and Route53 Hosted Zone ID 
ZONE_ID="${zone}"
ENV="${env}"


RABBIT_NAME=$${ENV}-rabbit
AWS_CLI=$(which aws)

if [ -z $AWS_CLI ];then
	apt-get update; apt install python-pip -y
	pip install awscli
fi

TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
LOCAL_IP=`curl -H "X-aws-ec2-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/local-ipv4`

INDEX=0
DNS_NAME="$${RABBIT_NAME}-$${INDEX}.aws.cobrowser.io"


cat > /tmp/rabbit-record-set.json << EOF
                {
                  "Comment": "RabbitMQ Node: $${INDEX}",
                  "Changes": [{
                        "Action": "CREATE",
                        "ResourceRecordSet": {
                            "Name": "$${DNS_NAME}",
                            "Type": "A",
			    "TTL": 60, 
			    "ResourceRecords": [{ "Value": "$${LOCAL_IP}"}]
                              }
                          }]
                }
EOF
aws route53 change-resource-record-sets --hosted-zone-id $${ZONE_ID} --change-batch file:///tmp/rabbit-record-set.json
result=$?

until [ $result -eq 0 ];do
        INDEX=$(($INDEX + 1))
        DNS_NAME="$${RABBIT_NAME}-$${INDEX}.aws.cobrowser.io"
cat > /tmp/rabbit-record-set.json << EOF
                {
                  "Comment": "RabbitMQ Node: $${INDEX}",
                  "Changes": [{
                        "Action": "CREATE",
                        "ResourceRecordSet": {
                            "Name": "$${DNS_NAME}",
                            "Type": "A",
                            "TTL": 60,
                            "ResourceRecords": [{ "Value": "$${LOCAL_IP}"}]
                              }
                          }]
                }
EOF
aws route53 change-resource-record-sets --hosted-zone-id $${ZONE_ID} --change-batch file:///tmp/rabbit-record-set.json 2>/dev/null 1>&2
result=$?
echo "DNS Record added with index: $${INDEX}"
done
hostnamectl set-hostname $${DNS_NAME}
cat > /etc/rabbitmq/rabbitmq-env.conf << EOF
RABBITMQ_NODENAME=rabbit@$${DNS_NAME}
RABBITMQ_USE_LONGNAME=true
EOF

cat > /etc/rabbitmq/rabbitmq.conf << EOF
log.default.level = warning
log.connection.level = warning
queue_master_locator=min-masters
management.load_definitions = /etc/rabbitmq/definitions.json
EOF

echo "[rabbitmq_management]." > /etc/rabbitmq/enabled_plugins

cat > /etc/rabbitmq/definitions.json << EOF
{
      "users": [
        {
          "name": "queue_user",
          "password": "${queue_user_password}",
          "tags": ""
        }
      ],
      "permissions": [
        {
          "user": "queue_user",
          "vhost": "/",
          "configure": ".*",
          "write": ".*",
          "read": ".*"
        }
      ],
      "vhosts": [{"name": "/"}],
      "policies":[
        {
          "vhost":"/",
          "name":"ha",
          "pattern":"",
          "priority": 0,
          "definition":{"ha-mode":"all","ha-sync-mode":"automatic"}}
      ]
}
EOF

sed -i 's/LimitNOFILE=32768/LimitNOFILE=64000/g' /etc/systemd/system/multi-user.target.wants/rabbitmq-server.service

systemctl daemon-reload
systemctl restart rabbitmq-server

sleep 20
if [ $${INDEX} -ne 0 ];then
    rabbitmqctl stop_app
    rabbitmqctl join_cluster rabbit@$${RABBIT_NAME}-0.aws.cobrowser.io
    rabbitmqctl start_app
fi




