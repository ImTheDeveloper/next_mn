# NEXT Masternode Install Script

## Install
```
wget -N https://raw.githubusercontent.com/ImTheDeveloper/next_mn/master/install.sh
bash install.sh
```
Follow the on-screen instructions.

## Post Install Usage

For security reasons **NEXT Masternode** is installed under a normal user (but you can choose root if you really want to!).

The default user is **NEXT**, hence you need to **su - NEXT** before being able to use the following commands:
```
NEXTCOINUSER=NEXT  #replace NEXT with the username  of the user running the node you want to check
su - $NEXTCOINUSER
cd ~/.next
./next-cli masternode status
./next-cli getinfo
```

Also, if you want to check/start/stop **NEXT** daemon for a particular reason e.g. re-install, run one of the following commands as **root**:
```
NEXTCOINUSER=NEXT  #replace NEXT with the username  of the user running the node you want to check
systemctl status $NEXTCOINUSER #To check the service is running
systemctl start $NEXTCOINUSER #To start masternode service
systemctl stop $NEXTCOINUSER #To stop masternode service
systemctl is-enabled $NEXTCOINUSER #To check masternode service is enabled on boot
```