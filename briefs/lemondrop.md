# Pocket granular synthesizer module

Design a compact, USB-powered polyphonic granular synthesizer module in the
spirit of the 1010music nanobox lemondrop.

## Requirements

- Microcontroller capable of 4-voice stereo granular DSP at 24-bit / 48 kHz
  (STM32H7-class, e.g. STM32H743), with external QSPI flash for sample
  streaming buffers.
- Stereo audio codec at 24-bit / 48 kHz with:
  - 3.5 mm TRS stereo line input
  - 3.5 mm TRS stereo line/headphone output with adequate drive for headphones
- MIDI over 3.5 mm TRS (Type-B wiring): one input (opto-isolated) and one
  output.
- One 3.5 mm TS analog clock input into a GPIO, protected against overvoltage
  and mis-plugged audio signals.
- microSD card slot on SDMMC (4-bit) for samples and presets.
- Connector (FPC or header) for a 2" SPI TFT display with I2C capacitive touch
  controller; touch interrupt line to the MCU.
- Two rotary encoders with push switches and four tactile buttons on GPIO.
- USB-C for power and USB-MIDI device data; onboard 3.3 V regulation with a
  separate clean analog supply for the codec.
- Standard support circuitry: crystal, reset and boot buttons, SWD debug
  header.

Target: 4-layer board fitting a 94 x 76.2 mm enclosure footprint; 3.5 mm jacks
and USB-C edge-mounted; parts orderable from major distributors.
