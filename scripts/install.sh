#!/bin/bash

CONSUL_VERSION="1.0.0"
CONSUL_ZIP="consul_$${CONSUL_VERSION}_linux_amd64.zip"

yum install -y curl unzip

curl -O "https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/$${CONSUL_ZIP}"
unzip "$${CONSUL_ZIP}"
rm -f "$${CONSUL_ZIP}"
mv consul /usr/local/bin

cat > /etc/systemd/system/consul.service <<EOF
[Unit]
Description=consul agent
Requires=network-online.target
After=network-online.target

[Service]
EnvironmentFile=-/etc/sysconfig/consul
Restart=on-failure
ExecStart=/usr/local/bin/consul agent \
    -server -ui \
    -data-dir=/var/lib/consul \
    -datacenter=${DATACENTER} \
    -retry-join "provider=aws tag_key=ConsulCluster tag_value=${CLUSTER_NAME}" \
    -bootstrap-expect=3
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable consul.service
systemctl start consul.service
