# USB-MIDI foot controller

Design a four-switch USB-MIDI foot controller for musicians.

## Requirements

- RP2040 microcontroller with QSPI flash, running as a USB-MIDI class device
  over USB-C.
- Four heavy-duty momentary footswitches, each debounced in hardware (RC) and
  read on GPIO.
- One TRS expression-pedal input (6.35 mm stereo jack) into an ADC pin, with
  protection so a mis-wired pedal cannot damage the MCU.
- Four addressable RGB LEDs (one per footswitch) for patch/state feedback,
  driven from a single GPIO with proper level shifting to 5 V.
- Powered from USB only; 3.3 V regulation onboard.
- Standard RP2040 support circuitry: crystal, boot button, reset button,
  SWD debug header.

Target: single 2-layer board, through-hole footswitches and jacks, SMD
elsewhere; parts orderable from major distributors.
