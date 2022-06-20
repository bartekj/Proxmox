#!/usr/bin/env bash
YW=`echo "\033[33m"`
RD=`echo "\033[01;31m"`
BL=`echo "\033[36m"`
GN=`echo "\033[1;92m"`
CL=`echo "\033[m"`
RETRY_NUM=10
RETRY_EVERY=3
NUM=$RETRY_NUM
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
BFR="\\r\\033[K"
HOLD="-"
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR

function error_exit() {
  trap - ERR
  local reason="Unknown failure occured."
  local msg="${1:-$reason}"
  local flag="${RD}‼ ERROR ${CL}$EXIT@$LINE"
  echo -e "$flag $msg" 1>&2
  exit $EXIT
}

function msg_info() {
    local msg="$1"
    echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
    local msg="$1"
    echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

msg_info "Setting up Container OS "
sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
locale-gen >/dev/null
while [ "$(hostname -I)" = "" ]; do
  1>&2 echo -en "${CROSS}${RD}  No Network! "
  sleep $RETRY_EVERY
  ((NUM--))
  if [ $NUM -eq 0 ]
  then
    1>&2 echo -e "${CROSS}${RD}  No Network After $RETRY_NUM Tries${CL}"
    exit 1
  fi
done
msg_ok "Set up Container OS"
msg_ok "Network Connected: ${BL}$(hostname -I)"

msg_info "Updating Container OS"
apt update &>/dev/null
apt-get -qqy upgrade &>/dev/null
msg_ok "Updated Container OS"

msg_info "Installing Dependencies"
apt-get install -y curl &>/dev/null
apt-get install -y sudo &>/dev/null
apt-get install -y apt-transport-https &>/dev/null
msg_ok "Installed Dependencies"

msg_info "Installing OpenJDK 11"
apt install -y openjdk-11-jre-headless uuid-runtime pwgen dirmngr &>/dev/null
msg_ok "Installed OpenJDK 11"

msg_info "Installing ElasticSearch"
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/oss-7.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-7.x.list
apt-get update &>/dev/null
apt-get install -y elasticsearch-oss &>/dev/null

sudo systemctl daemon-reload &>/dev/null
sudo systemctl start elasticsearch &>/dev/null
sudo systemctl enable elasticsearch &>/dev/null

msg_ok "Installed ElasticSearch"

msg_ok "Installing Greylog server"
wget https://packages.graylog2.org/repo/packages/graylog-4.2-repository_latest.deb &>/dev/null
sudo dpkg -i graylog-4.2-repository_latest.deb &>/dev/null
apt-get update &>/dev/null
apt install -y graylog-server &>/dev/null
GREYLOG_PASS=$(pwgen -N 1 -s 96)
sed -i 's/password_secret = /password_secret =  ${GREYLOG_PASS}/g' /etc/graylog/server/server.conf &>/dev/null
echo "rest_listen_uri = http://127.0.0.1:9000/api/" >> /etc/graylog/server/server.conf &>/dev/null
echo "web_listen_uri = http://127.0.0.1:9000/" >> /etc/graylog/server/server.conf &>/dev/null
GREYLOG_ROOT_PASS=$(echo -n Str0ngPassw0rd | sha256sum)
sed -i 's/root_password_sha2 = /root_password_sha2 =  ${GREYLOG_ROOT_PASS}/g' /etc/graylog/server/server.conf &>/dev/null
sudo systemctl daemon-reload &>/dev/null
sudo systemctl restart graylog-server &>/dev/null
sudo systemctl enable graylog-server &>/dev/null
echo "http_bind_address = 0.0.0.0:9000" >> /etc/graylog/server/server.conf &>/dev/null
msg_ok "Installed Greylog server"

PASS=$(grep -w "root" /etc/shadow | cut -b6);
  if [[ $PASS != $ ]]; then
msg_info "Customizing Container"
rm /etc/motd
rm /etc/update-motd.d/10-uname
touch ~/.hushlogin
GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
mkdir -p $(dirname $GETTY_OVERRIDE)
cat << EOF > $GETTY_OVERRIDE
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
systemctl daemon-reload
systemctl restart $(basename $(dirname $GETTY_OVERRIDE) | sed 's/\.d//')
msg_ok "Customized Container"
  fi

msg_info "Cleaning up"
apt-get autoremove >/dev/null
apt-get autoclean >/dev/null
rm -rf /var/{cache,log}/* /var/lib/apt/lists/*
mkdir /var/log/apache2
chmod 750 /var/log/apache2
msg_ok "Cleaned"
