# Environmental sensor node

Design a compact indoor air-quality sensor node.

## Requirements

- ESP32-C3 module as the main controller (Wi-Fi built in).
- SHT41 temperature/humidity sensor and an SGP40 VOC air-quality sensor, both on I2C.
- Powered over USB-C (5 V); onboard 3.3 V regulation for the module and sensors.
- Single-cell Li-ion battery backup with onboard charging from USB power, and a
  simple battery-voltage sense divider to an ADC pin.
- One RGB status LED (addressable is fine) and one user button in addition to
  the boot/reset circuitry the module needs.
- USB-C data lines wired to the module's native USB for flashing and logs.
- Keep the sensors away from heat sources in layout intent; note it in the docs.

Target: hobbyist-assembly friendly, mostly 0603 passives, single 4-layer board.
