[ -z $BASH ] && { exec bash "$0" "$@" || exit; }
#!/bin/bash
# file: wittyPi.sh
#
# Run this application to interactly configure your Witty Pi
#

# check if sudo is used
#if [ "$(id -u)" != 0 ]; then
#  echo 'Sorry, you need to run this script with sudo'
#  exit 1
#fi

echo '================================================================================'
echo '|                                                                              |'
echo '|   Witty Pi - Realtime Clock + Power Management for Raspberry Pi              |'
echo '|                                                                              |'
echo '|                   < Version 3.11 >     by UUGear s.r.o.                      |'
echo '|                                                                              |'
echo '================================================================================'

# include utilities script in same directory
my_dir="`dirname \"$0\"`"
my_dir="`( cd \"$my_dir\" && pwd )`"
if [ -z "$my_dir" ] ; then
  exit 1
fi
. $my_dir/utilities.sh

hash gpio 2>/dev/null
if [ $? -ne 0 ]; then
  echo ''
  echo 'Seems your wiringPi is not installed properly (missing "gpio" command). Quitting...'
  echo ''
  exit
fi

if ! is_rtc_connected ; then
  echo ''
  log 'Seems Witty Pi board is not connected? Quitting...'
  echo ''
  exit
fi

if one_wire_confliction ; then
	echo ''
	log 'Confliction detected:'
	log "1-Wire interface is enabled on GPIO-$HALT_PIN, which is also used by Witty Pi."
	log 'You may solve this confliction by moving 1-Wire interface to another GPIO pin.'
	echo ''
	exit
fi

# interactive actions
synchronize_time()
{
  log '  Running syncTime.sh ...'
  . "$my_dir/syncTime.sh"
}

schedule_startup()
{
  local startup_time=$(get_local_date_time "$(get_startup_time)")
  local size=${#startup_time}
  if [ $size == '3' ]; then
    echo '  Auto startup time is not set yet.'
  else
    echo "  Auto startup time is currently set to \"$startup_time\""
  fi
  if [ -f "$my_dir/schedule.wpi" ]; then
      echo '  [WARNING] Your manual schedule may disturb the schedule script running!'
  fi
  read -p '  When do you want your Raspberry Pi to auto startup? (dd HH:MM:SS, ?? as wildcard) ' when
  if [[ $when =~ ^[0-3\?][0-9\?][[:space:]][0-2\?][0-9\?]:[0-5\?][0-9\?]:[0-5\?][0-9\?]$ ]]; then
    IFS=' ' read -r date timestr <<< "$when"
    IFS=':' read -r hour minute second <<< "$timestr"
    wildcard='??'
    if [ $date != $wildcard ] && ([ $((10#$date>31)) == '1' ] || [ $((10#$date<1)) == '1' ]); then
      echo '  Day value should be 01~31.'
    elif [ $hour != $wildcard ] && [ $((10#$hour>23)) == '1' ]; then
      echo '  Hour value should be 00~23.'
    else
      local updated='0'
      if [ $hour == '??' ] && [ $date != '??' ]; then
        date='??'
        updated='1'
      fi
      if [ $minute == '??' ] && ([ $hour != '??' ] || [ $date != '??' ]); then
        hour='??'
        date='??'
        updated='1'
      fi
      if [ $second == '??' ]; then
        second='00'
        updated='1'
      fi
      if [ $updated == '1' ]; then
        when="$date $hour:$minute:$second"
        echo "  ...not supported pattern, but I can do \"$when\" for you..."
      fi
      log "  Seting startup time to \"$when\""
      when=$(get_utc_date_time $date $hour $minute $second)
      IFS=' ' read -r date timestr <<< "$when"
      IFS=':' read -r hour minute second <<< "$timestr"
      set_startup_time $date $hour $minute $second
      log '  Done :-)'
    fi
  else
    echo "  Sorry I don't recognize your input :-("
  fi
}

schedule_shutdown()
{
  local off_time=$(get_local_date_time "$(get_shutdown_time)")
  local size=${#off_time}
  if [ $size == '3' ]; then
    echo  '  Auto shutdown time is not set yet.'
  else
    echo -e "  Auto shutdown time is currently set to \"$off_time\b\b\b\"  "
  fi
  if [ -f "$my_dir/schedule.wpi" ]; then
      echo '  [WARNING] Your manual schedule may disturb the schedule script running!'
  fi
  read -p '  When do you want your Raspberry Pi to auto shutdown? (dd HH:MM, ?? as wildcard) ' when
  if [[ $when =~ ^[0-3\?][0-9\?][[:space:]][0-2\?][0-9\?]:[0-5\?][0-9\?]$ ]]; then
    IFS=' ' read -r date timestr <<< "$when"
    IFS=':' read -r hour minute <<< "$timestr"
    wildcard='??'
    if [ $date != $wildcard ] && ([ $((10#$date>31)) == '1' ] || [ $((10#$date<1)) == '1' ]); then
      echo '  Day value should be 01~31.'
    elif [ $hour != $wildcard ] && [ $((10#$hour>23)) == '1' ]; then
      echo '  Hour value should be 00~23.'
    else
      local updated='0'
      if [ $hour == '??' ] && [ $date != '??' ]; then
        date='??'
        updated='1'
      fi
      if [ $minute == '??' ] && ([ $hour != '??' ] || [ $date != '??' ]); then
        hour='??'
        date='??'
        updated='1'
      fi
      if [ $updated == '1' ]; then
        when="$date $hour:$minute"
        echo "  ...not supported pattern, but I can do \"$when\" for you..."
      fi
      log "  Seting shutdown time to \"$when\""
      when=$(get_utc_date_time $date $hour $minute '00')
      IFS=' ' read -r date timestr <<< "$when"
      IFS=':' read -r hour minute second <<< "$timestr"
      set_shutdown_time $date $hour $minute
      log '  Done :-)'
    fi
  else
    echo "  Sorry I don't recognize your input :-("
  fi
}

choose_schedule_script()
{
  local files=($my_dir/schedules/*.wpi)
  local count=${#files[@]}
  echo "  I can see $count schedule scripts in the \"schedules\" directory:"
  for (( i=0; i<$count; i++ ));
  do
    echo "  [$(($i+1))] ${files[$i]##*/}"
  done
  read -p "  Which schedule script do you want to use? (1~$count) " index
  if [[ $index =~ [0-9]+ ]] && [ $(($index >= 1)) == '1' ] && [ $(($index <= $count)) == '1' ] ; then
    local script=${files[$((index-1))]};
    log "  Copying \"${script##*/}\" to \"schedule.wpi\"..."
    cp ${script} "$my_dir/schedule.wpi"
    log '  Running the script...'
    . "$my_dir/runScript.sh" | tee -a "$my_dir/schedule.log"
    log '  Done :-)'
  else
    echo "  \"$index\" is not a good choice, I need a number from 1 to $count"
  fi
}

set_low_voltage_threshold()
{
  read -p 'Input low voltage (2.0~25.0: value in volts, 0=Disabled): ' threshold
  if (( $(awk "BEGIN {print ($threshold >= 2.0 && $threshold <= 25.0)}") )); then
    local t=$(calc $threshold*10)
    i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_LOW_VOLTAGE ${t%.*}
    local ts=$(printf 'Low voltage threshold set to %.1fV!\n' $threshold)
    log "$ts" && sleep 2
  elif (( $(awk "BEGIN {print ($threshold == 0)}") )); then
    i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_LOW_VOLTAGE 0xFF
    log 'Disabled low voltage threshold!' && sleep 2
  else
    echo 'Please input from 2.0 to 25.0 ...' && sleep 2
  fi
}

set_recovery_voltage_threshold()
{
  read -p 'Input recovery voltage (2.0~25.0: value in volts, 0=Disabled): ' threshold
  if (( $(awk "BEGIN {print ($threshold >= 2.0 && $threshold <= 25.0)}") )); then
    local t=$(calc $threshold*10)
    i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_RECOVERY_VOLTAGE ${t%.*}
    local ts=$(printf 'Recovery voltage threshold set to %.1fV!\n' $threshold)
    log "$ts" && sleep 2
  elif (( $(awk "BEGIN {print ($threshold == 0)}") )); then
    i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_RECOVERY_VOLTAGE 0xFF
    log 'Disabled recovery voltage threshold!' && sleep 2
  else
    echo 'Please input from 2.0 to 25.0 ...' && sleep 2
  fi
}

set_default_state()
{
  read -p 'Input new default state (1 or 0: 1=ON, 0=OFF): ' state
  case $state in
    0) i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_DEFAULT_ON 0x00 && log 'Set to "Default OFF"!' && sleep 2;;
    1) i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_DEFAULT_ON 0x01 && log 'Set to "Default ON"!' && sleep 2;;
    *) echo 'Please input 1 or 0 ...' && sleep 2;;
  esac
}

set_power_cut_delay()
{
	read -p 'Input new delay (0.0~8.0: value in seconds): ' delay
  if (( $(awk "BEGIN {print ($delay >= 0 && $delay <= 8.0)}") )); then
    local d=$(calc $delay*10)
    i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_POWER_CUT_DELAY ${d%.*}
    log "Power cut delay set to $delay seconds!" && sleep 2
  else
    echo 'Please input from 0.0 to 8.0 ...' && sleep 2
  fi
}

set_pulsing_interval()
{
	read -p 'Input new interval (1,2,4 or 8: value in seconds): ' interval
  case $interval in
    1) i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_PULSE_INTERVAL 0x06 && log 'Pulsing interval set to 1 second!' && sleep 2;;
    2) i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_PULSE_INTERVAL 0x07 && log 'Pulsing interval set to 2 seconds!' && sleep 2;;
    4) i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_PULSE_INTERVAL 0x08 && log 'Pulsing interval set to 4 seconds!' && sleep 2;;
    8) i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_PULSE_INTERVAL 0x09 && log 'Pulsing interval set to 8 seconds!' && sleep 2;;
    *) echo 'Please input 1,2,4 or 8 ...' && sleep 2;;
  esac
}

set_white_led_duration()
{
	read -p 'Input new duration for white LED (0~255): ' duration
	if [ $duration -ge 0 ] && [ $duration -le 255 ]; then
		i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_BLINK_LED $duration
		log "White LED duration set to $duration!" && sleep 2
	else
	  echo 'Please input from 0 to 255' && sleep 2
	fi
}

set_dummy_load_duration()
{
	read -p 'Input new duration for dummy load (0~255): ' duration
	if [ $duration -ge 0 ] && [ $duration -le 255 ]; then
		i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_DUMMY_LOAD $duration
		log "Dummy load duration set to $duration!" && sleep 2
	else
	  echo 'Please input from 0 to 255' && sleep 2
	fi
}

set_vin_adjustment()
{
	read -p 'Input Vin adjustment (-1.27~1.27: value in volts): ' vinAdj
  if (( $(awk "BEGIN {print ($vinAdj >= -1.27 && $vinAdj <= 1.27)}") )); then
    local adj=$(calc $vinAdj*100)
    if (( $(awk "BEGIN {print ($adj < 0)}") )); then
    	adj=$((128-$adj))
    fi
    i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_ADJ_VIN ${adj%.*}  
    local setting=$(printf 'Vin adjustment set to %.2fV!\n' $vinAdj)
    log "$setting" && sleep 2
  else
    echo 'Please input from -1.27 to 1.27 ...' && sleep 2
  fi
}

set_vout_adjustment()
{
	read -p 'Input Vout adjustment (-1.27~1.27: value in volts): ' voutAdj
  if (( $(awk "BEGIN {print ($voutAdj >= -1.27 && $voutAdj <= 1.27)}") )); then
    local adj=$(calc $voutAdj*100)
    if (( $(awk "BEGIN {print ($adj < 0)}") )); then
    	adj=$((128-$adj))
    fi
    i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_ADJ_VOUT ${adj%.*}  
    local setting=$(printf 'Vout adjustment set to %.2fV!\n' $voutAdj)
    log "$setting" && sleep 2
  else
    echo 'Please input from -1.27 to 1.27 ...' && sleep 2
  fi
}

set_iout_adjustment()
{
	read -p 'Input Iout adjustment (-1.27~1.27: value in amps): ' ioutAdj
  if (( $(awk "BEGIN {print ($ioutAdj >= -1.27 && $ioutAdj <= 1.27)}") )); then
    local adj=$(calc $ioutAdj*100)
    if (( $(awk "BEGIN {print ($adj < 0)}") )); then
    	adj=$((128-$adj))
    fi
    i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_ADJ_IOUT ${adj%.*}  
    local setting=$(printf 'Iout adjustment set to %.2fA!\n' $ioutAdj)
    log "$setting" && sleep 2
  else
    echo 'Please input from -1.27 to 1.27 ...' && sleep 2
  fi
}

other_settings()
{
  echo 'Here you can set:'
  echo -n '  [1] Default state when powered'
  local ds=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_DEFAULT_ON)
  if [[ $ds -eq 0 ]]; then
    echo ' [default OFF]'
	else
    echo ' [default ON]'
  fi
  echo -n '  [2] Power cut delay after shutdown'
  local pcd=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_POWER_CUT_DELAY)
  pcd=$(calc $(($pcd))/10)
  printf ' [%.1f Seconds]\n' "$pcd"
  echo -n '  [3] Pulsing interval during sleep'
  local pi=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_PULSE_INTERVAL)
  if [ $pi == '0x09' ]; then
    pi=8
  elif [ $pi == '0x07' ]; then
	  pi=2
	elif [ $pi == '0x06' ]; then
	  pi=1
	else
	  pi=4
  fi
  echo " [$pi Seconds]"  
  echo -n '  [4] White LED duration'
  local led=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_BLINK_LED)
  printf ' [%d]\n' "$led"
  echo -n '  [5] Dummy load duration'
  local dload=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_DUMMY_LOAD)
  printf ' [%d]\n' "$dload"
  echo -n '  [6] Vin adjustment'
  local vinAdj=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_ADJ_VIN)
  if [[ $vinAdj -gt 127 ]]; then
  	vinAdj=$(calc $((128-$vinAdj))/100)
 	else
 		vinAdj=$(calc $(($vinAdj))/100)
  fi
  printf ' [%.2fV]\n' "$vinAdj"
  echo -n '  [7] Vout adjustment'
  local voutAdj=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_ADJ_VOUT)
  if [[ $voutAdj -gt 127 ]]; then
  	voutAdj=$(calc $((128-$voutAdj))/100)
 	else
 		voutAdj=$(calc $(($voutAdj))/100)
  fi
  printf ' [%.2fV]\n' "$voutAdj"
  echo -n '  [8] Iout adjustment'
  local ioutAdj=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_ADJ_IOUT)
  if [[ $ioutAdj -gt 127 ]]; then
  	ioutAdj=$(calc $((128-$ioutAdj))/100)
 	else
 		ioutAdj=$(calc $(($ioutAdj))/100)
  fi
  printf ' [%.2fA]\n' "$ioutAdj"
  read -p "Which parameter to set? (1~8) " action
  case $action in
      [1]* ) set_default_state;;
      [2]* ) set_power_cut_delay;;
      [3]* ) set_pulsing_interval;;
      [4]* ) set_white_led_duration;;
      [5]* ) set_dummy_load_duration;;
      [6]* ) set_vin_adjustment;;
      [7]* ) set_vout_adjustment;;
      [8]* ) set_iout_adjustment;;
      * ) echo 'Please choose from 1 to 8';;
  esac
}

reset_startup_time()
{
  log '  Clearing auto startup time...' '-n'
  clear_startup_time
  log ' done :-)'
}

reset_shutdown_time()
{
  log '  Clearing auto shutdown time...' '-n'
  clear_shutdown_time
  log ' done :-)'
}

delete_schedule_script()
{
  log '  Deleting "schedule.wpi" file...' '-n'
  if [ -f "$my_dir/schedule.wpi" ]; then
    rm "$my_dir/schedule.wpi"
    log ' done :-)'
  else
    log ' file does not exist'
  fi
}

reset_low_voltage_threshold()
{
  log '  Clearing low voltage threshold...' '-n'
  clear_low_voltage_threshold
  log ' done :-)'
}

reset_recovery_voltage_threshold()
{
  log '  Clearing recovery voltage threshold...' '-n'
  clear_recovery_voltage_threshold
  log ' done :-)'
}

reset_all()
{
  reset_startup_time
  reset_shutdown_time
  delete_schedule_script
  reset_low_voltage_threshold
  reset_recovery_voltage_threshold
}

reset_data()
{
  echo 'Here you can reset some data:'
  echo '  [1] Clear scheduled startup time'
  echo '  [2] Clear scheduled shutdown time'
  echo '  [3] Stop using schedule script'
  echo '  [4] Clear low voltage threshold'
  echo '  [5] Clear recovery voltage threshold'
  echo '  [6] Perform all actions above'
  read -p "Which action to perform? (1~6) " action
  case $action in
      [1]* ) reset_startup_time;;
      [2]* ) reset_shutdown_time;;
      [3]* ) delete_schedule_script;;
      [4]* ) reset_low_voltage_threshold;;
      [5]* ) reset_recovery_voltage_threshold;;
      [6]* ) reset_all;;
      * ) echo 'Please choose from 1 to 6';;
  esac
}

# ask user for action
while true; do
  # output temperature
  temperature='>>> Current temperature: '
  temperature+="$(get_temperature)"
  echo "$temperature"

  # output system time
  systime='>>> Your system time is: '
  systime+="$(get_sys_time)"
  echo "$systime"

  # output RTC time
  rtctime='>>> Your RTC time is:    '
  rtctime+="$(get_rtc_time)"
  echo "$rtctime"
  
  # voltages report
  if is_mc_connected ; then
    vin=$(get_input_voltage)
    vout=$(get_output_voltage)
    iout=$(get_output_current)
    voltages=">>> "
    if [ $(get_power_mode) -eq 1 ]; then
		  voltages+="Vin=$(printf %.02f $vin)V, "
		fi
    voltages+="Vout=$(printf %.02f $vout)V, Iout=$(printf %.02f $iout)A"
    echo "$voltages"
  fi

  # let user choose action
  echo 'Now you can:'
  echo '  1. Write system time to RTC'
  echo '  2. Write RTC time to system'
  echo '  3. Synchronize time'
  echo -n '  4. Schedule next shutdown'
  shutdown_time=$(get_local_date_time "$(get_shutdown_time)")
  if [ ${#shutdown_time} == '3' ]; then
    echo ''
  else
    echo " [$shutdown_time]";
  fi
  echo -n '  5. Schedule next startup'
  startup_time=$(get_local_date_time "$(get_startup_time)")
  if [ ${#startup_time} == '3' ]; then
    echo ''
  else
    echo "  [$startup_time]";
  fi
  echo -n '  6. Choose schedule script'
  if [ -f "$my_dir/schedule.wpi" ]; then
    echo ' [in use]'
  else
    echo ''
  fi
  echo -n '  7. Set low voltage threshold'
	lowVolt=$(get_low_voltage_threshold)
  if [ ${#lowVolt} == '8' ]; then
    echo ''
  else
    echo "  [$lowVolt]";
  fi
  echo -n '  8. Set recovery voltage threshold'
  recVolt=$(get_recovery_voltage_threshold)
  if [ ${#recVolt} == '8' ]; then
    echo ''
  else
    echo "  [$recVolt]";
  fi
  echo '  9. View/change other settings...'
  echo ' 10. Reset data...'
  echo ' 11. Exit'
  read -p 'What do you want to do? (1~11) ' action
  case $action in
      1 ) system_to_rtc;;
      2 ) rtc_to_system;;
      3 ) synchronize_time;;
      4 ) schedule_shutdown;;
      5 ) schedule_startup;;
      6 ) choose_schedule_script;;
      7 ) set_low_voltage_threshold;;
      8 ) set_recovery_voltage_threshold;;
      9 ) other_settings;;
      10 ) reset_data;;
      11 ) exit;;
      * ) echo 'Please choose from 1 to 11';;
  esac
  echo ''
  echo '================================================================================'
done
