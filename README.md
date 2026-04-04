# PureBasic GUI for GRBL v1.1

Desktop controller written in PureBasic for communicating with GRBL v1.1 CNC firmware over serial.

## What this project does

This application provides a multi-tab GUI for common GRBL operations:

- Serial port discovery and connection
- Live console for manual commands
- Real-time status polling (`?`) and machine state display
- Jog controls (X/Y/Z), homing, WCS zeroing, feed hold, cycle start, soft reset
- Settings read/write (`$$`, `$x=value`) and file import/export
- Basic probing helpers (`G38.2`)
- Real-time overrides (feed, rapid, spindle, coolant)
- G-code file loading and streaming with progress display
- In-app log window and log export

## Repository layout

- `GRBL_V1.pb`: Main PureBasic source file (single-file app)
- `README.md`: Project documentation

## Requirements

- PureBasic compiler with thread-safe build option enabled
- A GRBL v1.1 compatible controller
- Serial access to controller at 115200 baud
- OS support:
	- Windows path is implemented for COM scan
	- Linux/macOS path is marked but currently not fully implemented in `COMGetAvailablePorts()`

## Build and run

1. Open `GRBL_V1.pb` in PureBasic IDE.
2. Enable thread-safe compilation (required by code guard):
	 - The source contains `CompilerIf #PB_Compiler_Thread = 0` and will fail if disabled.
3. Compile and run.
4. In the app:
	 - Click `Refresh`
	 - Select a serial port
	 - Click `Connect`

## Quick usage guide

### Connection

- `Refresh` scans serial ports.
- Background scan attempts to identify GRBL-capable ports.
- Status indicator colors:
	- Red: disconnected
	- Orange: connected, GRBL not confirmed
	- Green: connected and GRBL detected

### Console tab

- Send direct GRBL and G-code commands.
- View raw responses from firmware.

### Jog / Motion tab

- Set jog step and feed.
- Jog axes with `$J=` commands.
- Use `STOP` for jog cancel (real-time command).
- Home and WCS zero helpers are available.

### Settings tab

- `Read ($$)` loads GRBL settings.
- Edit selected value and write with `$x=value`.
- Save/load settings snapshots to text files.

### Probing tab

- Sends `G38.2` probing commands.
- Optional auto-zero for Z after probing.

### Overrides tab

- Uses GRBL v1.1 real-time override bytes for:
	- Feed
	- Rapid
	- Spindle
	- Flood/Mist coolant

### Info / EEPROM tab

- Queries firmware data (`$I`, `$N`, `$G`, `$#`, `$B`, `$C`).

### GCode tab

- Load `.nc`, `.gcode`, `.tap`, or text files.
- Start streaming to GRBL with progress updates.
- Optional check-mode toggle before stream (`$C`).

## Important safety notes

- This software can move real machinery. Test with spindle off and clear workspace first.
- Validate travel limits, coordinate systems, and feed rates before production runs.
- Keep an accessible hardware emergency stop in reach.
- Confirm controller state after soft reset and unlock (`$X`) only when safe.

## Current known limitations

- Linux/macOS serial enumeration code path is not implemented in this source.
- G-code sender uses a simplified acknowledgment/buffer tracking model.
- No formal automated tests are included.
- Some handlers and comments indicate in-progress cleanup/refactor work.

## Recommended next tasks

1. Implement Linux/macOS serial port enumeration in `COMGetAvailablePorts()`.
2. Fix Enter-key handling in console input event logic.
3. Harden G-code streaming buffer accounting using per-line length queue.
4. Add error code lookup/help text for `error:` and `ALARM:` responses.
5. Refactor large single-file source into modules (serial, parser, UI, streaming).
6. Add a small simulation mode or loopback test path for safer verification.
7. Expand documentation with screenshots and a troubleshooting matrix.

## Troubleshooting

- Port does not open:
	- Close other software that may hold the serial port.
	- Re-scan ports and reconnect device.
- No GRBL banner:
	- Verify 115200 baud.
	- Check USB cable/data support.
	- Try soft reset and reconnect.
- Machine stuck in alarm:
	- Review limit switch state and homing settings.
	- Unlock with `$X` only after root cause is resolved.

## License

No license file is currently included. Add a `LICENSE` file to define usage terms.
