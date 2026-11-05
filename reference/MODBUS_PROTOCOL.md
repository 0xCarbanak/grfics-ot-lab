# Modbus TCP Protocol Reference — GRFICSv3

## What is Modbus?

Modbus is a serial communications protocol from 1979, originally designed for
PLCs. Modbus TCP wraps it in TCP/IP on port 502. It has **no authentication,
no encryption, no authorisation** — if you can reach port 502, you have full
read/write access to the controller.


## Data Model

| Type              | Access     | Address Range | Size   | Purpose             |
|-------------------|------------|---------------|--------|---------------------|
| Coils             | Read/Write | 0–65535       | 1 bit  | Digital outputs     |
| Discrete Inputs   | Read Only  | 0–65535       | 1 bit  | Digital inputs      |
| Holding Registers | Read/Write | 0–65535       | 16 bit | Analog outputs      |
| Input Registers   | Read Only  | 0–65535       | 16 bit | Analog inputs       |


## Function Codes

| Code | Name                          | What it does                      |
|------|-------------------------------|-----------------------------------|
| 0x01 | Read Coils                    | Read digital outputs              |
| 0x02 | Read Discrete Inputs          | Read digital inputs               |
| 0x03 | Read Holding Registers        | Read writable 16-bit registers    |
| 0x04 | Read Input Registers          | Read sensor/read-only registers   |
| 0x05 | Write Single Coil             | Set one digital output            |
| 0x06 | Write Single Register         | Write one holding register        |
| 0x0F | Write Multiple Coils          | Set multiple digital outputs      |
| 0x10 | Write Multiple Registers      | Write multiple holding registers  |


## TCP Frame Structure

```
[Transaction ID: 2 bytes]     -- Matches request to response
[Protocol ID:    2 bytes]     -- Always 0x0000 for Modbus
[Length:         2 bytes]     -- Bytes following this field
[Unit ID:        1 byte]     -- Slave address (usually 1 or 0xFF)
[Function Code:  1 byte]     -- What operation to perform
[Data:           N bytes]    -- Depends on function code
```


## GRFICSv3 Architecture

The PLC polls **6 remote I/O devices** on the ICS network (192.168.95.0/24).
Each device runs a Modbus TCP server on port 502, slave ID 247, polled every 100ms.

### Remote I/O Devices

| Device   | IP             | Input Registers (sensors)        | Holding Registers (actuators) |
|----------|----------------|----------------------------------|-------------------------------|
| Feed 1   | 192.168.95.10  | IR[1] valve_pos, IR[2] flow      | HR[1] valve_sp                |
| Feed 2   | 192.168.95.11  | IR[1] valve_pos, IR[2] flow      | HR[1] valve_sp                |
| Purge    | 192.168.95.12  | IR[1] valve_pos, IR[2] flow      | HR[1] valve_sp                |
| Product  | 192.168.95.13  | IR[1] valve_pos, IR[2] flow      | HR[1] valve_sp                |
| Tank     | 192.168.95.14  | IR[1] pressure, IR[2] level      | —                             |
| Analyzer | 192.168.95.15  | IR[1] %A, IR[2] %B, IR[3] %C    | —                             |

Values are UINT16 (0–65535). Valve positions scale as (real%/100)*65535.

### PLC Internal Register Map

| Register  | Variable           | Description                            |
|-----------|--------------------|----------------------------------------|
| %IW100    | f1_valve_pos       | Feed 1 valve position (sensor)         |
| %IW101    | f1_flow            | Feed 1 flow rate                       |
| %IW102–103| f2 valve/flow      | Feed 2 sensors                         |
| %IW104–105| purge valve/flow   | Purge sensors                          |
| %IW106–107| product valve/flow | Product sensors                        |
| %IW108    | pressure           | Reactor pressure                       |
| %IW109    | level              | Tank level                             |
| %IW110–112| a/b/c_in_purge     | Composition (mol%)                     |
| %QW100–103| valve setpoints    | Feed1, Feed2, Purge, Product (outputs) |

### Control Coils

| Address   | Name           | What it does                               |
|-----------|----------------|--------------------------------------------|
| %QX0.0    | manual_mode    | TRUE = PLC uses manual valve SPs, not auto |
| %QX5.0    | run_bit        | FALSE = e-stop (safe valve positions)      |


## Using pymodbus

```python
from pymodbus.client import ModbusTcpClient

# Read from a remote I/O device directly (e.g. Tank)
client = ModbusTcpClient("192.168.95.14", port=502)
client.connect()
result = client.read_input_registers(address=1, count=2, slave=247)
pressure = result.registers[0]
level = result.registers[1]
client.close()
```

No login. No token. Connect, read, write, disconnect.


## Key Concepts

**Distributed I/O**: 6 separate Modbus devices — attack the PLC, the I/O
devices, or the traffic between them.

**manual_mode coil**: The key attack vector. Set it TRUE and the PLC stops
using auto control — it uses your manually-written valve positions instead.

**20ms scan cycle**: The PLC overwrites outputs every 20ms. Use manual_mode
rather than racing the scan cycle.

**Pressure override at ~2900 kPa**: Auto-increases product outflow. Defeat
it by enabling manual_mode and setting your own product valve position.
