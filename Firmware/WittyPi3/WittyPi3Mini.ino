/**
 * Firmware for WittyPi 3 Mini
 * 
 * Version: 1.04
 */
#include <core_timers.h>
#include <avr/sleep.h>
#include <EEPROM.h>
#include <WireS.h>

#define PIN_SYS_UP      0             // pin to listen to SYS_UP
#define PIN_BUTTON      1             // pin to button
#define PIN_LED         2             // pin to drive white LED
#define PIN_CTRL        3             // pin to control output
#define PIN_RTC_ALARM   5             // pin to listen to RTC alarm
#define PIN_TX_UP       10            // pin to listen to Raspberry Pi's TXD
#define PIN_VIN         A1            // pin to ADC1
#define PIN_VOUT        A2            // pin to ADC2
#define PIN_VK          A3            // pin to ADC3
#define PIN_SDA         4             // pin to SDA for I2C
#define PIN_SCL         6             // pin to SCL for I2C

#define I2C_ID              0         // firmware id
#define I2C_VOLTAGE_IN_I    1         // integer part for input voltage
#define I2C_VOLTAGE_IN_D    2         // decimal part (x100) for input voltage
#define I2C_VOLTAGE_OUT_I   3         // integer part for output voltage
#define I2C_VOLTAGE_OUT_D   4         // decimal part (x100) for output voltage
#define I2C_CURRENT_OUT_I   5         // integer part for output current
#define I2C_CURRENT_OUT_D   6         // decimal part (x100) for output current
#define I2C_POWER_MODE      7         // 1 if Witty Pi is powered via the LDO, 0 if direclty use 5V input
#define I2C_LV_SHUTDOWN     8         // 1 if system was shutdown by low voltage, otherwise 0

#define I2C_CONF_ADDRESS          9   // I2C slave address: defaul=0x69
#define I2C_CONF_DEFAULT_ON       10  // turn on RPi when power is connected: 1=yes, 0=no
#define I2C_CONF_PULSE_INTERVAL   11  // pulse interval (for LED and dummy load): 9=8s,8=4s,7=2s,6=1s
#define I2C_CONF_LOW_VOLTAGE      12  // low voltage threshold (x10), 255=disabled
#define I2C_CONF_BLINK_LED        13  // 0 if white LED should not blink. The bigger value, the longer time to light up LED 
#define I2C_CONF_POWER_CUT_DELAY  14  // the delay (x10) before power cut: default=50 (5 sec)
#define I2C_CONF_RECOVERY_VOLTAGE 15  // voltage (x10) that triggers recovery, 255=disabled
#define I2C_CONF_DUMMY_LOAD       16  // 0 if dummy load is off. The bigger value, the longer time to draw current
#define I2C_CONF_ADJ_VIN          17  // adjustment for measured Vin (x100), range from -127 to 127
#define I2C_CONF_ADJ_VOUT         18  // adjustment for measured Vout (x100), range from -127 to 127
#define I2C_CONF_ADJ_IOUT         19  // adjustment for measured Iout (x100), range from -127 to 127

#define I2C_REG_COUNT             20  // number of I2C registers

volatile byte i2cReg[I2C_REG_COUNT];

volatile char i2cIndex = 0;

volatile boolean buttonPressed = false;

volatile boolean powerIsOn = false;

volatile boolean listenToTxd = false;

volatile boolean turningOff = false;

volatile boolean forcePowerCut = false;

volatile boolean wakeupByWatchdog = false;

volatile unsigned long buttonStateChangeTime = 0;

volatile unsigned long voltageQueryTime = 0;

volatile unsigned int powerCutDelay = 0;

void setup() {

  // initialize pin states and make sure power is cut
  pinMode(PIN_SYS_UP, INPUT);
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  pinMode(PIN_LED, OUTPUT);
  pinMode(PIN_CTRL, OUTPUT);
  pinMode(PIN_RTC_ALARM, INPUT_PULLUP);
  pinMode(PIN_TX_UP, INPUT);
  pinMode(PIN_VIN, INPUT);
  pinMode(PIN_VOUT, INPUT);
  pinMode(PIN_VK, INPUT);
  pinMode(PIN_SDA, INPUT_PULLUP);
  pinMode(PIN_SCL, INPUT_PULLUP);
  cutPower();

  // use internal 1.1V reference
  analogReference(INTERNAL1V1);

  // initlize registers
  initializeRegisters();

  // i2c initialization
  TinyWireS.begin((i2cReg[I2C_CONF_ADDRESS] <= 0x07 || i2cReg[I2C_CONF_ADDRESS] >= 0x78) ? 0x69 : i2cReg[I2C_CONF_ADDRESS]);
  TinyWireS.onAddrReceive(addressEvent);
  TinyWireS.onReceive(receiveEvent);
  TinyWireS.onRequest(requestEvent);

  // disable global interrupts
  cli();

  // enable pin change interrupts 
  GIMSK = _BV (PCIE0) | _BV (PCIE1);
  PCMSK1 = _BV (PCINT8) | _BV (PCINT9); 
  PCMSK0 = _BV (PCINT0) | _BV (PCINT5);

  // enable Timer1
  timer1_enable();
  
  // enable all interrupts
  sei();

  // power on or sleep
  bool defaultOn = (i2cReg[I2C_CONF_DEFAULT_ON] == 1);
  if (defaultOn) {
    powerOn();  // power on directly
  } else {
    sleep();    // sleep and wait for button action
  }
}


void loop() {
  unsigned long curTime = micros();
  if (voltageQueryTime > curTime || curTime - voltageQueryTime >= 1000000) {
    voltageQueryTime = curTime;

    // if input voltage is not fixed 5V, detect low voltage
    if (i2cReg[I2C_POWER_MODE] == 1 && powerIsOn && listenToTxd && i2cReg[I2C_LV_SHUTDOWN] == 0 && i2cReg[I2C_CONF_LOW_VOLTAGE] != 255) {
      float vin = getInputVoltage();
      float vlow = ((float)i2cReg[I2C_CONF_LOW_VOLTAGE]) / 10;
      if (vin < vlow) {  // input voltage is below the low voltage threshold
        updateRegister(I2C_LV_SHUTDOWN, 1);
        emulateButtonClick();
      }
    }
  }
}


// initialize the registers and synchronize with EEPROM
void initializeRegisters() {
  i2cReg[I2C_ID] = 0x22;
  i2cReg[I2C_VOLTAGE_IN_I] = 0;
  i2cReg[I2C_VOLTAGE_IN_D] = 0;
  i2cReg[I2C_VOLTAGE_OUT_I] = 0;
  i2cReg[I2C_VOLTAGE_OUT_D] = 0;
  i2cReg[I2C_CURRENT_OUT_I] = 0;
  i2cReg[I2C_CURRENT_OUT_D] = 0;
  i2cReg[I2C_POWER_MODE] = 0;
  i2cReg[I2C_LV_SHUTDOWN] = 0;
  
  i2cReg[I2C_CONF_ADDRESS] = 0x69;
  i2cReg[I2C_CONF_DEFAULT_ON] = 0;
  i2cReg[I2C_CONF_PULSE_INTERVAL] = 8;
  i2cReg[I2C_CONF_LOW_VOLTAGE] = 255;
  i2cReg[I2C_CONF_BLINK_LED] = 100;
  i2cReg[I2C_CONF_POWER_CUT_DELAY] = 50;
  i2cReg[I2C_CONF_RECOVERY_VOLTAGE] = 255;
  i2cReg[I2C_CONF_DUMMY_LOAD] = 0;
  i2cReg[I2C_CONF_ADJ_VIN] = 20;
  i2cReg[I2C_CONF_ADJ_VOUT] = 20;
  i2cReg[I2C_CONF_ADJ_IOUT] = 0;

  // make sure product name is stored
  EEPROM.update(0, 'W');
  EEPROM.update(1, 'P');
  EEPROM.update(2, '3');
  EEPROM.update(3, 'M');
  EEPROM.update(4, 0);

  // synchronize configuration with EEPROM
  for (int i = I2C_CONF_ADDRESS; i < I2C_REG_COUNT; i ++) {
    byte val = EEPROM.read(i);
    if (val == 255) {
      EEPROM.update(i, i2cReg[i]);
    } else {
      i2cReg[i] = val;
    } 
  }
}


void watchdog_enable() {
  cli();
  WDTCSR |= _BV(WDIE);
  byte wdp = (i2cReg[I2C_CONF_PULSE_INTERVAL] > 9 ? 8 : i2cReg[I2C_CONF_PULSE_INTERVAL]);
  wdp = (((wdp & B00001000) << 2) | (wdp & B11110111));
  WDTCSR |= wdp;
  sei();
}


void watchdog_disable() {
  WDTCSR = 0;
}


void timer1_enable() {
  // set entire TCCR1A and TCCR1B register to 0
  TCCR1A = 0;
  TCCR1B = 0;
  
  // set 1024 prescaler
  bitSet(TCCR1B, CS12);
  bitSet(TCCR1B, CS10);

  // clear overflow interrupt flag
  bitSet(TIFR1, TOV1);

  // set timer counter
  TCNT1 = getPowerCutPreloadTimer(true);

  // enable Timer1 overflow interrupt
  bitSet(TIMSK1, TOIE1);
}


void timer1_disable() {
  // disable Timer1 overflow interrupt
  bitClear(TIMSK1, TOIE1);
}


void sleep() {
  timer1_disable();                       // disable Timer1
  ADCSRA &= ~_BV(ADEN);                   // ADC off
  set_sleep_mode(SLEEP_MODE_PWR_DOWN);    // power-down mode 
  watchdog_enable();                      // enable watchdog
  sleep_enable();                         // sets the Sleep Enable bit in the MCUCR Register (SE BIT)
  sei();                                  // enable interrupts

  wakeupByWatchdog = true;
  do {
    sleep_cpu();                          // sleep
    if (wakeupByWatchdog) {               // wake up by watch dog

      // process RTC alarm, if it has previously occured
      processAlarmIfNeeded();
      
      // blink white LED
      if (i2cReg[I2C_CONF_BLINK_LED] > 0) {
        int counter = (int)i2cReg[I2C_CONF_BLINK_LED] * 100;
        ledOn(counter);
        ledOff();
      }

      // dummy load
      if (i2cReg[I2C_CONF_DUMMY_LOAD] > 0) {
        int counter = (int)i2cReg[I2C_CONF_DUMMY_LOAD] * 10;
        for(int i = 0; i < counter; i ++) digitalWrite(PIN_CTRL, 1);
        cutPower();
      }

      // check input voltage if shutdown because of low voltage, and recovery voltage has been set
      // will skip checking I2C_LV_SHUTDOWN if I2C_CONF_LOW_VOLTAGE is set to 0xFF
      if (i2cReg[I2C_POWER_MODE] == 1 && (i2cReg[I2C_LV_SHUTDOWN] == 1 || i2cReg[I2C_CONF_LOW_VOLTAGE] == 255) && i2cReg[I2C_CONF_RECOVERY_VOLTAGE] != 255) {     
        ADCSRA |= _BV(ADEN);
        float vin = getInputVoltage();
        ADCSRA &= ~_BV(ADEN);
        float vrec = ((float)i2cReg[I2C_CONF_RECOVERY_VOLTAGE]) / 10;
        if (vin >= vrec) {
          wakeupByWatchdog = false;       // recovery from low voltage shutdown
        }
      }
    }
  } while (wakeupByWatchdog);             // quit sleeping if wake up by button

  cli();                                  // disable interrupts
  sleep_disable();                        // clear SE bit
  watchdog_disable();                     // disable watchdog
  ADCSRA |= _BV(ADEN);                    // ADC on
  timer1_enable();                        // enable Timer1
  sei();                                  // enable interrupts
  
  pinMode(PIN_SDA, INPUT_PULLUP);         // explicitly specify SDA pin mode before waking up
  pinMode(PIN_SCL, INPUT_PULLUP);         // explicitly specify SCL pin mode before waking up

  // tap the button to wake up
  listenToTxd = false;
  turningOff = false;
  buttonPressed = true;
  powerOn();
  TCNT1 = getPowerCutPreloadTimer(true);
}


void cutPower() {
  powerIsOn = false;
  digitalWrite(PIN_CTRL, 0);
}


void powerOn() {
  powerIsOn = true;
  digitalWrite(PIN_CTRL, 1);
  updatePowerMode();
}


void ledOn(int counter) {
  for(int i = 0; i < counter; i ++) {
    digitalWrite(PIN_LED, 1);
  }
}


void ledOff() {
  digitalWrite(PIN_LED, 0);
}


void updatePowerMode() {
  float vin = 0.061290322580645 * analogRead(PIN_VIN);    // 57*1.1/1023~=0.06129
  float vout = 0.061290322580645 * analogRead(PIN_VOUT);  // 57*1.1/1023~=0.06129
  updateRegister(I2C_POWER_MODE, (vin > vout) ? 1 : 0);
}


float getInputVoltage() {
  float v = 0.061290322580645 * analogRead(PIN_VIN);  // 57*1.1/1023~=0.06129
  float adj = i2cReg[I2C_CONF_ADJ_VIN];
  if (adj > 127) {
    adj = 128 - adj;
  }
  v += adj / 100;
  updateRegister(I2C_VOLTAGE_IN_I, getIntegerPart(v));
  updateRegister(I2C_VOLTAGE_IN_D, getDecimalPart(v));
  return v;
}


float getOutputVoltage() {
  float v = 0.061290322580645 * analogRead(PIN_VOUT);  // 57*1.1/1023~=0.06129
  float vk = 0.001075268817204 * analogRead(PIN_VK);   // 1.1/1023~=0.001075
  float adj = i2cReg[I2C_CONF_ADJ_VOUT];
  if (adj > 127) {
    adj = 128 - adj;
  }
  v = v - vk + adj / 100;
  updateRegister(I2C_VOLTAGE_OUT_I, getIntegerPart(v));
  updateRegister(I2C_VOLTAGE_OUT_D, getDecimalPart(v));
  return v;
}


float getCathodeVoltage() {
  float v = 0.001075268817204 * analogRead(PIN_VK);    // 1.1/1023~=0.001075
  float adj = i2cReg[I2C_CONF_ADJ_IOUT];
  if (adj > 127) {
    adj = 128 - adj;
  }
  float i = v / 0.05 + adj / 100;
  updateRegister(I2C_CURRENT_OUT_I, getIntegerPart(i));
  updateRegister(I2C_CURRENT_OUT_D, getDecimalPart(i));
  return v;
}


int getIntegerPart(float v) {
  return (int)v;  
}


int getDecimalPart(float v) {
  return (int)((v - getIntegerPart(v)) * 100);
}


// get the preload timer value for power cut
unsigned int getPowerCutPreloadTimer(boolean reset) {
  if (reset) {
    powerCutDelay = i2cReg[I2C_CONF_POWER_CUT_DELAY];
  }
  unsigned int actualDelay = 0;
  if (powerCutDelay > 83) {
    actualDelay = 83;
  } else {
    actualDelay = powerCutDelay;
  }
  powerCutDelay -= actualDelay;
  return 65535 - 781 * actualDelay;
}


// receives a sequence of start|address|direction bit from i2c master
boolean addressEvent(uint16_t slaveAddress, uint8_t startCount) {
  if (startCount > 0 && TinyWireS.available()) {
    i2cIndex = TinyWireS.read();
  }
  return true;
}


// receives a sequence of data from i2c master (master writes to this device)
void receiveEvent(int count) {
  if (TinyWireS.available()) {
    i2cIndex = TinyWireS.read();
    if (TinyWireS.available()) {
      updateRegister(i2cIndex, TinyWireS.read());
    }
  }
}


// i2c master requests data from this device (master reads from this device)
void requestEvent() {
  float v = 0.0;
  switch (i2cIndex) {
    case I2C_VOLTAGE_IN_I:
      getInputVoltage();
      break;
    case I2C_VOLTAGE_OUT_I:
      getOutputVoltage();
      break;
    case I2C_CURRENT_OUT_I:
      getCathodeVoltage();
      break;
    case I2C_POWER_MODE:
      updatePowerMode();
      break;
  }
  TinyWireS.write(i2cReg[i2cIndex]);
}


// watchdog interrupt routine
ISR (WDT_vect) {
  // no need to do anything here
}


// pin state change interrupt routine for PCINT0_vect (PCINT0~7) 
ISR (PCINT0_vect) {
 if (listenToTxd && digitalRead(PIN_TX_UP) == 0) {  // PCINT0
    listenToTxd = false;
    turningOff = true;
    ledOff(); // turn off the white LED
    TCNT1 = getPowerCutPreloadTimer(true);
  }
  processAlarmIfNeeded(); // PCINT5
}


// pin state change interrupt routine for PCINT1_vect (PCINT8~15)
ISR (PCINT1_vect) {
  // debounce
  unsigned long prevTime = buttonStateChangeTime;
  buttonStateChangeTime = micros();
  if (buttonStateChangeTime - prevTime < 10) {
    return;
  }
  
  if (forcePowerCut) {
    forcePowerCut = false;
    sleep();
  } else {
    if (digitalRead(PIN_BUTTON) == 0) {   // button is pressed, PCINT9
      
      // restore from RTC alarm processing
      digitalWrite(PIN_BUTTON, 1);
      pinMode(PIN_BUTTON, INPUT_PULLUP);
      
      // turn on the white LED
      ledOn(1);

      wakeupByWatchdog = false; // will quit sleeping
      
      if (!buttonPressed) {
        buttonPressed = true;
        powerOn();
      }
      TCNT1 = getPowerCutPreloadTimer(true);
    } else {  // button is released
      buttonPressed = false;
    }
    
    if (digitalRead(PIN_SYS_UP) == 1)  {  // system is up, PCINT8
      // clear the low-voltage shutdown flag when sys_up signal arrives
      if (listenToTxd == false) {
        updateRegister(I2C_LV_SHUTDOWN, 0);
      }
      
      // start listen to TXD pin
      listenToTxd = true;
      
      // turn off the white LED
      ledOff();
    }
  }
}


// timer1 overflow interrupt routine
ISR (TIM1_OVF_vect) {
  if (powerCutDelay == 0) {
    // cut the power after delay
    TCNT1 = getPowerCutPreloadTimer(true);
    forcePowerCutIfNeeded();
    if (turningOff) {
      if (digitalRead(PIN_TX_UP) == 1) {  // if it is rebooting
        turningOff = false;
        ledOn(1);
      } else {  // cut the power and enter sleep
        cutPower();
        sleep();
      }
    }
  } else {
    TCNT1 = getPowerCutPreloadTimer(false);
    forcePowerCutIfNeeded();
  }
}


// update I2C register, save to EEPROM if it is configuration
void updateRegister(int index, byte value) {
  i2cReg[index] = value;
  if (index >= I2C_CONF_ADDRESS) {
    EEPROM.update(index, value);
  }
}


// emulate button clicking
void emulateButtonClick() {
  pinMode(PIN_BUTTON, OUTPUT);
  digitalWrite(PIN_BUTTON, 0);  
}


// process the alarm from RTC, if exists
void processAlarmIfNeeded() {  
  if (digitalRead(PIN_RTC_ALARM) == 0) {
    if (powerIsOn || i2cReg[I2C_POWER_MODE] == 0) {
      emulateButtonClick();
    } else {
      byte bk = ADCSRA;
      ADCSRA |= _BV(ADEN);
      float vin = getInputVoltage();
      ADCSRA = bk;
      float vlow = ((float)i2cReg[I2C_CONF_LOW_VOLTAGE]) / 10;
      if (i2cReg[I2C_LV_SHUTDOWN] == 1) {
        if (vin > vlow) {
          float vrec = ((float)i2cReg[I2C_CONF_RECOVERY_VOLTAGE]) / 10;
          if (i2cReg[I2C_CONF_RECOVERY_VOLTAGE] == 255 || vin > vrec) {
            emulateButtonClick();
          }
        }
      } else {
        if (vin > vlow || i2cReg[I2C_CONF_RECOVERY_VOLTAGE] == 255) {
          emulateButtonClick();
        } else {
          updateRegister(I2C_LV_SHUTDOWN, 1);
        }
      }
    }
  }
}


// Force power cut, if button is pressed and hold for a few seconds
void forcePowerCutIfNeeded() {
 if (buttonPressed && digitalRead(PIN_BUTTON) == 0) {
    forcePowerCut = true;
    cutPower();
    ledOff();
  }
}
