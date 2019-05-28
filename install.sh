#!/bin/bash

CONFIG_FILE='nextcoin.conf'
COIN_DAEMON='nextd'
COIN_CLI='next-cli'
COIN_REPO='https://github.com/ImTheDeveloper/next_mn/raw/master/next_linux_bin.zip'
COIN_NAME='NEXT'
COIN_PORT=7077
RPC_PORT=10001
SENTINEL_REPO='https://github.com/NextExchange/sentinel.git'

NODEIP=$(curl -s4 icanhazip.com)

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

progressfilt () {
  local flag=false c count cr=$'\r' nl=$'\n'
  while IFS='' read -d '' -rn 1 c
  do
    if $flag
    then
      printf '%c' "$c"
    else
      if [[ $c != $cr && $c != $nl ]]
      then
        count=0
      else
        ((count++))
        if ((count > 1))
        then
          flag=true
        fi
      fi
    fi
  done
}

function compile_node() {
  echo -e "Prepare to download $COIN_NAME"
  TMP_FOLDER=$(mktemp -d)
  cd $TMP_FOLDER
  wget --progress=bar:force $COIN_REPO 2>&1 | progressfilt
  compile_error
  COIN_ZIP=$(echo $COIN_REPO | awk -F'/' '{print $NF}')
  unzip $COIN_ZIP
  compile_error
  rm -f $COIN_ZIP
  chmod +x $COIN_DAEMON $COIN_CLI
  cp $COIN_DAEMON $COIN_CLI $NEXTCOINFOLDER
  cd -
  rm -rf $TMP_FOLDER
}

function configure_systemd() {
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target
[Service]
User=$NEXTCOINUSER
Group=$NEXTCOINUSER
Type=forking
#PIDFile=$NEXTCOINFOLDER/$COIN_NAME.pid
ExecStart=$NEXTCOINFOLDER/$COIN_DAEMON -daemon -conf=$NEXTCOINFOLDER/$CONFIG_FILE -datadir=$NEXTCOINFOLDER
ExecStop=$NEXTCOINFOLDER/$COIN_CLI -conf=$NEXTCOINFOLDER/$CONFIG_FILE -datadir=$NEXTCOINFOLDER stop
Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}

function configure_startup() {
  cat << EOF > /etc/init.d/$COIN_NAME
#! /bin/bash
### BEGIN INIT INFO
# Provides: $COIN_NAME
# Required-Start: $remote_fs $syslog
# Required-Stop: $remote_fs $syslog
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: $COIN_NAME
# Description: This file starts and stops $COIN_NAME MN server
#
### END INIT INFO
case "\$1" in
 start)
   $NEXTCOINFOLDER/$COIN_DAEMON -daemon
   sleep 5
   ;;
 stop)
   $NEXTCOINFOLDER/$COIN_CLI stop
   ;;
 restart)
   $NEXTCOINFOLDER/$COIN_CLI stop
   sleep 10
   $NEXTCOINFOLDER/$COIN_DAEMON -daemon
   ;;
 *)
   echo "Usage: $COIN_NAME {start|stop|restart}" >&2
   exit 3
   ;;
esac
EOF
chmod +x /etc/init.d/$COIN_NAME
update-rc.d $COIN_NAME defaults
/etc/init.d/$COIN_NAME start
if [ "$?" -gt "0" ]; then
 sleep 5
 /etc/init.d/$COIN_NAME start
fi
}


function create_config() {
  mkdir $NEXTCOINFOLDER
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > $NEXTCOINFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcport=$RPC_PORT
#rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
port=$COIN_PORT
EOF
}

function create_key() {
  echo -e "Enter your ${RED}$COIN_NAME Masternode Private Key${NC}.\nLeave it blank to generate a new ${RED}$COIN_NAME Masternode Private Key${NC} for you:"
  read -e COINKEY
  if [[ -z "$COINKEY" ]]; then
  $NEXTCOINFOLDER/$COIN_DAEMON -daemon
  sleep 30
  if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
   echo -e "${RED}$COIN_NAME server couldn not start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  COINKEY=$($NEXTCOINFOLDER/$COIN_CLI masternode genkey)
  if [ "$?" -gt "0" ];
    then
    echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the Private Key${NC}"
    sleep 30
    COINKEY=$($NEXTCOINFOLDER/$COIN_CLI masternode genkey)
  fi
  $NEXTCOINFOLDER/$COIN_CLI stop
fi

}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $NEXTCOINFOLDER/$CONFIG_FILE
  cat << EOF >> $NEXTCOINFOLDER/$CONFIG_FILE
logintimestamps=1
maxconnections=64
#bind=$NODEIP
testnet=0
debug=0
masternode=1
externalip=$NODEIP
port=$COIN_PORT
masternodeprivkey=$COINKEY
EOF
}

function enable_firewall() {
  echo -e "Installing and setting up firewall to allow ingress on port ${GREEN}$COIN_PORT${NC}"
  ufw allow ssh
  ufw allow $COIN_PORT
  ufw default allow outgoing
  echo "y" | ufw enable
}

function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}

function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $COIN_NAME. Please investigate.${NC}"
  exit 1
fi
}

function detect_ubuntu() {
 if [[ $(lsb_release -d) == *18.04* ]]; then
   UBUNTU_VERSION=18
 elif [[ $(lsb_release -d) == *16.04* ]]; then
   UBUNTU_VERSION=16
 elif [[ $(lsb_release -d) == *14.04* ]]; then
   UBUNTU_VERSION=14
else
   echo -e "${RED}You are not running Ubuntu 14.04, 16.04 or 18.04 Installation is cancelled.${NC}"
   exit 1
fi
}

function checks() {
 detect_ubuntu 
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof $COIN_DAEMON)" ] || [ -e "$COIN_DAEMOM" ] ; then
  echo -e "${RED}$COIN_NAME is already installed.${NC}"
  exit 1
fi
}

function prepare_system() {
echo -e "Prepare the system to install ${GREEN}$COIN_NAME${NC} master node."
apt-get update
apt-get install -y wget curl ufw binutils net-tools
clear
echo -e "Checking if swap space is needed."
PHYMEM=$(free -g|awk '/^Mem:/{print $2}')
SWAP=$(swapon -s)
if [[ "$PHYMEM" -lt "2" && -z "$SWAP" ]];
  then
    echo -e "${GREEN}Server is running with less than 2G of RAM, creating 2G swap file.${NC}"
    dd if=/dev/zero of=/swapfile bs=1024 count=2M
    chmod 600 /swapfile
    mkswap /swapfile
    swapon -a /swapfile
else
  echo -e "${GREEN}The server running with at least 2G of RAM, or SWAP exists.${NC}"
fi
clear
}

function important_information() {
 echo
 echo -e "================================================================================"
 echo -e "$COIN_NAME Masternode is up and running listening on port ${RED}$COIN_PORT${NC}."
 echo -e "Configuration file is: ${RED}$NEXTCOINFOLDER/$CONFIG_FILE${NC}"
 if (( $UBUNTU_VERSION == 16 || $UBUNTU_VERSION == 18 )); then
   echo -e "Start: ${RED}systemctl start $COIN_NAME.service${NC}"
   echo -e "Stop: ${RED}systemctl stop $COIN_NAME.service${NC}"
   echo -e "Status: ${RED}systemctl status $COIN_NAME.service${NC}"
 else
   echo -e "Start: ${RED}/etc/init.d/$COIN_NAME start${NC}"
   echo -e "Stop: ${RED}/etc/init.d/$COIN_NAME stop${NC}"
   echo -e "Status: ${RED}/etc/init.d/$COIN_NAME status${NC}"
 fi
 echo -e "VPS_IP:PORT ${RED}$NODEIP:$COIN_PORT${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}$COINKEY${NC}"
 if [[ -n $SENTINEL_REPO  ]]; then
  echo -e "${RED}Sentinel${NC} is installed in ${RED}$NEXTCOINFOLDER/sentinel${NC}"
  echo -e "Sentinel logs is: ${RED}$NEXTCOINFOLDER/sentinel.log${NC}"
 fi
 echo -e "Check if $COIN_NAME is running by using the following command:\n${RED}ps -ef | grep $COIN_DAEMON | grep -v grep${NC}"
 echo -e "================================================================================"
 echo -e "Useful commands for checking your node:${NC}"
 echo -e "Wallet status: $NEXTCOINFOLDER/$COIN_CLI getinfo${NC}"
 echo -e "Masternode status: $NEXTCOINFOLDER/$COIN_CLI masternode status${NC}"
 echo -e "Produced by @munkee - any questions catch me on telegram!${NC}"
}


function install_sentinel() {
   echo -e "${GREEN}Installing sentinel.${NC}"
   apt-get -y install python-virtualenv virtualenv >/dev/null 2>&1
   git clone $SENTINEL_REPO $NEXTCOINFOLDER/sentinel >/dev/null 2>&1
   cd $NEXTCOINFOLDER/sentinel
   virtualenv ./venv >/dev/null 2>&1
   ./venv/bin/pip install -r requirements.txt >/dev/null 2>&1
   echo  "*/2 * * * * cd $NEXTCOINFOLDER/sentinel && ./venv/bin/python bin/sentinel.py >> $NEXTCOINFOLDER/sentinel.log 2>&1" > $NEXTCOINFOLDER/$COIN_NAME.cron
   crontab $NEXTCOINFOLDER/$COIN_NAME.cron
   rm $NEXTCOINFOLDER/$COIN_NAME.cron >/dev/null 2>&1
}


function ask_user() {
  DEFAULTNEXTCOINUSER=$COIN_NAME
  read -p "Which user do you wish to use/create to run this masternode as?: " -i $DEFAULTNEXTCOINUSER -e NEXTCOINUSER
  : ${NEXTCOINUSER:=$DEFAULTNEXTCOINUSER}

  if [ -z "$(getent passwd $NEXTCOINUSER)" ]; then
    useradd -m $NEXTCOINUSER
    USERPASS=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w12 | head -n1)
    echo "$NEXTCOINUSER:$USERPASS" | chpasswd
  fi
    NEXTCOINHOME=$(sudo -H -u $NEXTCOINUSER bash -c 'echo $HOME')
    DEFAULTNEXTCOINFOLDER="$NEXTCOINHOME/.next"
    read -p "Configuration folder: " -i $DEFAULTNEXTCOINFOLDER -e NEXTCOINFOLDER
    : ${NEXTCOINFOLDER:=$DEFAULTNEXTCOINFOLDER}
    mkdir -p $NEXTCOINFOLDER
    chown -R $NEXTCOINUSER: $NEXTCOINFOLDER >/dev/null
}



function setup_node() {
  ask_user
  get_ip
  compile_node
  create_config
  create_key
  update_config
  enable_firewall
  install_sentinel
  important_information
  if (( $UBUNTU_VERSION == 16 || $UBUNTU_VERSION == 18 )); then
    configure_systemd
  else
    configure_startup
  fi
}


##### Main #####
checks
prepare_system
setup_node
