#!/bin/bash
# file: daemon.sh
#
# This script should be auto started, to support WittyPi hardware
#

# get current directory
cur_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# utilities
. "$cur_dir/utilities.sh"

log 'Witty Pi daemon (v3.13) is started.'

# log Raspberry Pi model
pi_model=$(cat /proc/device-tree/model)
log "Running on $pi_model"

# log wiringPi version number
wp_ver=$(gpio -v | sed -n '1 s/.*\([0-9]\+\.[0-9]\+\).*/\1/p')
log "Wiring Pi version: $wp_ver"

# log NOOBS version, if exists
if [[ ! -d "$cur_dir/tmp" ]]; then
  mkdir "$cur_dir/tmp"
fi
mount /dev/mmcblk0p1 "$cur_dir/tmp"
noobs_ver=$(cat "$cur_dir/tmp/BUILD-DATA" | grep 'NOOBS Version:')
if [ ! -z "$noobs_ver" ]; then
  log "$noobs_ver"
fi
umount "$cur_dir/tmp"

# check 1-wire confliction
if one_wire_confliction ; then
	log "Confliction: 1-Wire interface is enabled on GPIO-$HALT_PIN, which is also used by Witty Pi."
	log 'Witty Pi daemon can not work until you solve this confliction and reboot Raspberry Pi.'
	exit
fi

# make sure the halt pin is input with internal pull up
gpio -g mode $HALT_PIN up
gpio -g mode $HALT_PIN in

# make sure the sysup in is in output mode
gpio -g mode $SYSUP_PIN out

# wait for RTC ready
sleep 2

# if RTC presents
is_rtc_connected
has_rtc=$?  # should be 0 if RTC presents

# if micro controller presents
is_mc_connected
has_mc=$?	# should be 0 if micro controller presents

if [ $has_mc == 0 ] ; then
	# check if system was shut down because of low-voltage
	recovery=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_LV_SHUTDOWN)
	if [ $recovery == '0x01' ]; then
	  log 'System was previously shut down because of low-voltage.'
	fi
	# print out firmware ID
	firmwareID=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_ID)
	log "Firmware ID: $firmwareID"
	# print out current voltages and current
  vout=$(get_output_voltage)
  iout=$(get_output_current)
  if [ $(get_power_mode) -eq 0 ]; then
  	log "Current Vout=$vout, Iout=$iout"
  else
	  vin=$(get_input_voltage)
  	log "Current Vin=$vin, Vout=$vout, Iout=$iout"
  fi
fi

# indicates system is up
log "Send out the SYS_UP signal via GPIO-$SYSUP_PIN pin."
gpio -g write $SYSUP_PIN 1
sleep 0.5
gpio -g write $SYSUP_PIN 0

# check and clear alarm flags
if [ $has_rtc == 0 ] ; then
  # disable square wave and enable alarms
  i2c_write 0x01 $I2C_RTC_ADDRESS 0x0E 0x07

  byte_F=$(i2c_read 0x01 $I2C_RTC_ADDRESS 0x0F)

  if [ $((($byte_F&0x1) != 0)) == '1' ]; then
  	# woke up by alarm 1 (startup)
  	log 'System startup as scheduled.'
  elif [ $((($byte_F&0x2) != 0)) == '1' ] ; then
  	# woke up by alarm 2 (shutdown), turn it off immediately
    log 'Seems I was unexpectedly woken up by shutdown alarm, must go back to sleep...'
    do_shutdown $HALT_PIN $has_rtc
  fi

  # clear alarm flags
  clear_alarm_flags $byte_F
else
  log 'Witty Pi is not connected, skip I2C communications...'
fi

# synchronize time
if [ $has_rtc == 0 ] ; then
  "$cur_dir/syncTime.sh" &
else
  log 'Witty Pi is not connected, skip synchronizing time...'
fi

# wait for system time update
sleep 3

# delay until GPIO pin state gets stable
counter=0
while [ $counter -lt 5 ]; do  # increase this value if it needs more time
  if [ $(gpio -g read $HALT_PIN) == '1' ] ; then
    counter=$(($counter+1))
  else
    counter=0
  fi
  sleep 1
done

# run schedule script
if [ $has_rtc == 0 ] ; then
  "$cur_dir/runScript.sh" 0 revise >> "$cur_dir/schedule.log" &
else
  log 'Witty Pi is not connected, skip schedule script...'
fi

# run afterStartup.sh in background
"$cur_dir/afterStartup.sh" >> "$cur_dir/wittyPi.log" 2>&1 &

# wait for GPIO-4 (BCM naming) falling, or alarm B (shutdown)
log 'Pending for incoming shutdown command...'
alarm_shutdown=0
while true; do
  gpio -g wfi $HALT_PIN falling
  if [ $has_rtc == 0 ] ; then
    byte_F=$(i2c_read 0x01 $I2C_RTC_ADDRESS 0x0F)
    if [ $((($byte_F&0x2) != 0)) == '1' ] ; then
    	# alarm 2 (shutdown) occurs
    	alarm_shutdown=1
    	break;
    elif [ $((($byte_F&0x1) != 0)) == '1' ] ; then
      # alarm 1 (startup) occurs, clear flags and ignore
      log 'Startup alarm occurs in ON state, ignored'
      clear_alarm_flags
    else
    	# not shutdown by alarm
      break;
    fi
  else
    # power switch can still work without RTC
    break;
  fi
done

lv_shutdown=0
if [ $has_mc == 0 ]; then	
	lv=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_LV_SHUTDOWN)
	if [ $lv == '0x01' ]; then
		lv_shutdown=1
	fi
fi

if [ $alarm_shutdown -eq 1 ]; then
	log 'Shutting down system as scheduled'
elif [ $lv_shutdown -eq 1 ]; then
  log 'Shutting down system because the input voltage is too low:'
  vin=$(get_input_voltage)
  vout=$(get_output_voltage)
  iout=$(get_output_current)
  log "Vin=$vin, Vout=$vout, Iout=$iout"
  vlow=$(get_low_voltage_threshold)
  vrec=$(get_recovery_voltage_threshold)
  log "Low voltage threshold is $vlow, recovery voltage threshold is $vrec"
else
  log "Shutting down system because GPIO-$HALT_PIN pin is pulled down."
fi

# run beforeShutdown.sh
"$cur_dir/beforeShutdown.sh" >> "$cur_dir/wittyPi.log" 2>&1 &

# shutdown Raspberry Pi
do_shutdown $HALT_PIN $has_rtc
