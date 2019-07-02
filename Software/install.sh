[ -z $BASH ] && { exec bash "$0" "$@" || exit; }
#!/bin/bash
# file: installWittyPi.sh
#
# This script will install required software for Witty Pi.
# It is recommended to run it in your home directory.
#

# check if sudo is used
if [ "$(id -u)" != 0 ]; then
  echo 'Sorry, you need to run this script with sudo'
  exit 1
fi

# target directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/wittypi"

# error counter
ERR=0

echo '================================================================================'
echo '|                                                                              |'
echo '|                   Witty Pi Software Installation Script                      |'
echo '|                                                                              |'
echo '================================================================================'

# enable I2C on Raspberry Pi
echo '>>> Enable I2C'
if grep -q 'i2c-bcm2708' /etc/modules; then
  echo 'Seems i2c-bcm2708 module already exists, skip this step.'
else
  echo 'i2c-bcm2708' >> /etc/modules
fi
if grep -q 'i2c-dev' /etc/modules; then
  echo 'Seems i2c-dev module already exists, skip this step.'
else
  echo 'i2c-dev' >> /etc/modules
fi
if grep -q 'dtparam=i2c1=on' /boot/config.txt; then
  echo 'Seems i2c1 parameter already set, skip this step.'
else
  echo 'dtparam=i2c1=on' >> /boot/config.txt
fi
if grep -q 'dtparam=i2c_arm=on' /boot/config.txt; then
  echo 'Seems i2c_arm parameter already set, skip this step.'
else
  echo 'dtparam=i2c_arm=on' >> /boot/config.txt
fi
if grep -q 'dtoverlay=pi3-miniuart-bt' /boot/config.txt; then
  echo 'Seems setting Pi3/4 Bluetooth to use mini-UART is done already, skip this step.'
else
  echo 'dtoverlay=pi3-miniuart-bt' >> /boot/config.txt
fi
if grep -q 'core_freq=250' /boot/config.txt; then
  echo 'Seems the frequency of GPU processor core is set to 250MHz already, skip this step.'
else
  echo 'core_freq=250' >> /boot/config.txt
fi
if [ -f /etc/modprobe.d/raspi-blacklist.conf ]; then
  sed -i 's/^blacklist spi-bcm2708/#blacklist spi-bcm2708/' /etc/modprobe.d/raspi-blacklist.conf
  sed -i 's/^blacklist i2c-bcm2708/#blacklist i2c-bcm2708/' /etc/modprobe.d/raspi-blacklist.conf
else
  echo 'File raspi-blacklist.conf does not exist, skip this step.'
fi

# install i2c-tools
echo '>>> Install i2c-tools'
if hash i2cget 2>/dev/null; then
  echo 'Seems i2c-tools is installed already, skip this step.'
else
  apt-get install -y i2c-tools || ((ERR++))
fi

# make sure en_GB.UTF-8 locale is installed
echo '>>> Make sure en_GB.UTF-8 locale is installed'
locale_commentout=$(sed -n 's/\(#\).*en_GB.UTF-8 UTF-8/1/p' /etc/locale.gen)
if [[ $locale_commentout -ne 1 ]]; then
	echo 'Seems en_GB.UTF-8 locale has been installed, skip this step.'
else
	sed -i.bak 's/^.*\(en_GB.UTF-8[[:blank:]]\+UTF-8\)/\1/' /etc/locale.gen
	locale-gen
fi

# check if it is Raspberry Pi 4
isRpi4=$(cat /proc/device-tree/model | sed -n 's/.*\(Raspberry Pi 4\).*/1/p')

# install wiringPi
if [ $ERR -eq 0 ]; then
  echo '>>> Install wiringPi'
  ver=0;
  if hash gpio 2>/dev/null; then
  	ver=$(gpio -v | sed -n '1 s/.*\([0-9]\+\.[0-9]\+\).*/\1/p')
  	echo "wiringPi version: $ver"
 	else
 		apt-get -y install wiringpi
 		ver=$(gpio -v | sed -n '1 s/.*\([0-9]\+\.[0-9]\+\).*/\1/p')
  fi
	if [[ $isRpi4 -eq 1 ]] && (( $(awk "BEGIN {print ($ver < 2.52)}") )); then
 		wget https://project-downloads.drogon.net/wiringpi-latest.deb || ((ERR++))
		dpkg -i wiringpi-latest.deb || ((ERR++))
		rm wiringpi-latest.deb
  fi
fi

# install wittyPi
if [ $ERR -eq 0 ]; then
  echo '>>> Install wittypi'
  if [ -d "wittypi" ]; then
    echo 'Seems wittypi is installed already, skip this step.'
  else
    wget http://www.uugear.com/repo/WittyPi3/LATEST -O wittyPi.zip || ((ERR++))
    unzip wittyPi.zip -d wittypi || ((ERR++))
    cd wittypi
    chmod +x wittyPi.sh
    chmod +x daemon.sh
    chmod +x syncTime.sh
    chmod +x runScript.sh
    chmod +x afterStartup.sh
    chmod +x beforeShutdown.sh
    sed -e "s#/home/pi/wittypi#$DIR#g" init.sh >/etc/init.d/wittypi
    chmod +x /etc/init.d/wittypi
    update-rc.d wittypi defaults || ((ERR++))
    touch wittyPi.log
    touch schedule.log
    cd ..
    chown -R $(logname):$(id -g -n $(logname)) wittypi || ((ERR++))
    sleep 2
    rm wittyPi.zip
  fi
fi

echo
if [ $ERR -eq 0 ]; then
  echo '>>> All done. Please reboot your Pi :-)'
else
  echo '>>> Something went wrong. Please check the messages above :-('
fi
