# USB-C bench power module

Design a small adjustable bench power supply module powered from USB-C.

## Requirements

- Input: USB-C with Power Delivery sink controller negotiating 20 V
  (fall back to 5 V when PD is unavailable).
- Output: adjustable buck converter, 1.5 V to 12 V at up to 3 A, set by a
  rotary encoder read by the MCU; output on screw terminals.
- STM32G0 (or similar small Cortex-M0+) MCU supervising the supply.
- INA226 current/voltage monitor on the output rail over I2C.
- Header for a 128x64 I2C OLED to display setpoint, measured voltage and current.
- Output enable via a high-side load switch controlled by the MCU, with a
  dedicated output-on LED.
- Protection: input fuse, reverse-polarity protection on the output terminals,
  and TVS on the USB input.

Target: 2- or 4-layer board, parts orderable from major distributors.
