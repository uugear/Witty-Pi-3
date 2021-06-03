# Witty-Pi-3
Witty Pi 3 is the third generation of Witty Pi, which adds RTC and power management to your Raspberry Pi, and can define complex ON/OFF sequence with simple script.

After installing the software on your Raspberry Pi, you can enjoy these amazing new features:

* You can power your Raspberry Pi with higher voltage.
* You can gracefully turn on/off Raspberry Pi with single tap on the switch.
* After shutdown, Raspberry Pi and all its USB peripherals’ power are fully cut.
* Raspberry Pi knows the correct time, even without accessing the Internet.
* Raspberry Pi knows the temperature thanks to the sensor in RTC chip.
* You can schedule the startup/shutdown of your Raspberry Pi.
* You can even write a script to define complex ON/OFF sequence.
* Shutdown Raspberry Pi when input voltage is lower than pre-set value.
* Turn on Raspberry Pi when input voltage raise to pre-set value.
* When the OS loses response, you can long hold the switch to force power cut.

Witty Pi 3 supports all Raspberry Pi models with 40-pin header, including A+, B+, 2B, Zero, Zero W and 3B, 3B+ and 4B.

Default Scheduled file: /etc/wittypi/schedules/schedule.wpi

Build with: dpkg-buildpackage -us -uc
