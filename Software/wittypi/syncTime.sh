#!/bin/bash
# file: syncTime.sh
#
# This script can syncronize the time between system and RTC
#

# delay if first argument exists
if [ ! -z "$1" ]; then
  sleep $1
fi

# include utilities script in same directory
my_dir="`dirname \"$0\"`"
my_dir="`( cd \"$my_dir\" && pwd )`"
if [ -z "$my_dir" ] ; then
  exit 1
fi
. $my_dir/utilities.sh


# if RTC presents
log 'Synchronizing time between system and Witty Pi...'

# get RTC time
rtctime="$(get_rtc_time)"
  
# if RTC time is OK, write RTC time to system first
if [[ $rtctime != *"1999"* ]] && [[ $rtctime != *"2000"* ]]; then
  rtc_to_system
fi

# if internet is not accessible, wait a moment
if ! $(has_internet) ; then
	sleep 10
fi

if $(has_internet) ; then
  # now take new time from NTP
  log 'Internet detected, apply network time to system and Witty Pi...'
  net_to_system
  system_to_rtc
else
  # get system year
  sysyear="$(date +%Y)"
  if [[ $rtctime == *"1999"* ]] || [[ $rtctime == *"2000"* ]]; then
    # if you never set RTC time before
    log 'RTC time has not been set before (stays in year 1999/2000).'
    if [[ $sysyear != *"1969"* ]] && [[ $sysyear != *"1970"* ]]; then
      # your Raspberry Pi has a decent time
      system_to_rtc
    else
      log 'Neither system nor Witty Pi contains correct time.'
    fi
  fi
fi
