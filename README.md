# GRFICS OT Security Lab

A lightweight OT/ICS security lab for learning industrial control system attack and defence. Based on [GRFICSv3](https://github.com/Fortiphyd/GRFICSv3) by Fortiphyd Logic, modified to run on **WSL2** with a leaner footprint — no Kali VM, no Caldera, attack from your own box.

The lab simulates a **Tennessee Eastman chemical plant** with a real PLC (OpenPLC), SCADA HMI, 3D walkable visualisation, network segmentation with a firewall/IDS router, and a full SIEM stack (Wazuh + Zeek). All running in Docker.

## What's Running

| Service | URL | Credentials | Purpose |
|---------|-----|-------------|---------|
| 3D Plant | `http://localhost` | — | Unity WebGL visualisation. Walk the plant in first person, find physical security vulns. |
| PLC (OpenPLC) | `http://localhost:8080` | `openplc / openplc` | Software PLC running the control program. 4 control loops, 20ms scan cycle. |
| PLC Modbus | `localhost:502` | **none** | Modbus TCP — your primary attack surface. No authentication. |
| HMI (ScadaLTS) | `http://localhost:6081` | `admin / admin` | Operator display. What a real plant operator would be watching. |
| Engineering Workstation | `http://localhost:6080` | — (noVNC) | Ubuntu desktop with OpenPLC Editor. |
| Router | internal | — | iptables firewall + Suricata IDS + ARP monitoring between ICS and DMZ networks. |
| Wazuh SIEM | `http://localhost:5601` | — | Kibana-style dashboard. Suricata alerts, Modbus detections, the blue-team view. |
| Zeek | internal | — | Passive network monitor feeding Wazuh. |

## Network Architecture

```
  ICS Network (192.168.95.0/24) — plant floor
    .2    PLC (OpenPLC)
    .5    Engineering Workstation
    .10   Remote I/O: Feed 1       ┐
    .11   Remote I/O: Feed 2       │
    .12   Remote I/O: Purge        │  Modbus TCP, port 502, slave ID 247
    .13   Remote I/O: Product      │
    .14   Remote I/O: Tank         │
    .15   Remote I/O: Analyzer     ┘
    .45   Simulation controller
    .200  Router
                    │
             [ Router ]
           iptables + Suricata IDS
                    │
  DMZ Network (192.168.90.0/24) — corporate side
    .107  HMI (ScadaLTS)
    .20   Wazuh SIEM
    .30   Zeek
    .200  Router
```

## Prerequisites

- **WSL2** (Windows) or any **Linux** distro
- **Native Docker Engine** (not Docker Desktop — see why below)
- At least **8 GB RAM** and **~6 GB** disk for images
- **Python 3** with `pymodbus` for attacking: `pip install pymodbus`

### Why native Docker Engine, not Docker Desktop

Docker Desktop runs the Docker daemon inside its own lightweight VM, so the
lab's networks (`192.168.95.0/24`, `192.168.90.0/24`) are hidden from your
shell — you can't scan or ARP-spoof them, only reach services through
`localhost` port mappings. That is not a realistic OT assessment.

Running Docker Engine **natively** in WSL2 (or on real Linux) puts the bridge
networks directly in your network namespace. You scan `192.168.95.0/24`, run
MITM, and pivot exactly like you would against a real plant floor. This is how
GRFICS is designed to be used.

## Quick Start

### Step 0: Disable Docker Desktop WSL Integration (if installed)

If you have Docker Desktop on Windows, it hijacks the Docker socket inside WSL
and routes everything through its own VM — the OT subnets won't be routable
from your shell. You **must** disable it:

1. Open **Docker Desktop** on Windows
2. Go to **Settings → Resources → WSL Integration**
3. **Toggle OFF** your WSL distro (e.g. Ubuntu)
4. Open **PowerShell** and run: `wsl --shutdown`
5. Reopen your WSL terminal

If you don't have Docker Desktop installed at all, skip this.

### Step 1: Enable systemd in WSL2

Edit `/etc/wsl.conf` (create it if it doesn't exist):

```ini
[boot]
systemd=true
```

Then restart WSL (`wsl --shutdown` in PowerShell, reopen terminal).

### Step 2: Run the setup script

```bash
git clone https://github.com/0xCarbanak/grfics-ot-lab.git
cd grfics-ot-lab
sudo ./scripts/setup-wsl.sh
```

The script installs native Docker Engine + Compose v2 plugin, starts the full
lab, and prints the routable subnets. One command from zero to a working lab.

### Step 3: Verify the subnets are routable

```bash
ip addr | grep -E 'br-|192.168.9'     # Docker bridge interfaces
nmap -sn 192.168.95.0/24              # discover the ICS plant floor
nmap -sn 192.168.90.0/24              # discover the DMZ
```

If you see the bridge interfaces and nmap finds hosts, you're good. Attack from
your own box — `pymodbus`, `scapy`, `nmap`, Wireshark, whatever you want.

### Manual setup (if you already have native Docker Engine)

```bash
docker compose --profile siem pull
docker compose --profile siem up -d
```

Wait ~1 minute, then open `http://localhost` (3D plant) and
`http://localhost:5601` (Wazuh SIEM).

## Start Attacking

You'll see the PLC (`.2`), engineering workstation (`.5`), all six remote I/O
devices (`.10`–`.15`), the simulation (`.45`), and the router (`.200`). Go
deeper with `nmap -sV`, Wireshark, `pymodbus`, `scapy`, MITM — whatever you
want:

```python
from pymodbus.client import ModbusTcpClient

# The PLC — straight to its real IP, no port tricks
client = ModbusTcpClient("192.168.95.2", port=502)
client.connect()
print(client.read_input_registers(address=100, count=13).registers)
client.close()

# A remote I/O device directly (the Tank)
client = ModbusTcpClient("192.168.95.14", port=502)
client.connect()
r = client.read_input_registers(1, count=2)
print(f"Pressure: {r.registers[0]}, Level: {r.registers[1]}")
client.close()
```

No login. No token. Figure out the rest.

Web UIs are reachable from your Windows browser on `localhost` (WSL auto-forwards
published ports): `:80` (3D plant), `:8080` (OpenPLC), `:6081` (HMI), `:6080`
(EWS), `:5601` (Wazuh).

Reference docs in `reference/` explain the protocol, register map, and plant
process. Missions in `missions/` guide your learning from recon through to
building defences.

## Missions

7 CTF-style missions progressing from easy to hard. No hand-holding — objectives and things to think about, not step-by-step instructions.

| # | Title | Difficulty | Focus |
|---|-------|-----------|-------|
| 01 | Network Reconnaissance | Easy | Discover the OT network and its services |
| 02 | Understanding the Process | Easy | Read Modbus registers, map the plant |
| 03 | Your First Write | Medium | Manipulate valves, learn the PLC fights back |
| 04 | Defeating the Safety Logic | Medium | Override manual_mode, defeat pressure override |
| 05 | Blinding the Operator | Hard | MITM Modbus traffic, forge HMI readings |
| 06 | Killing the Controller | Medium | Availability attack — stop the PLC, watch physics win |
| 07 | Switch Sides: Build Defences | Hard | Write firewall rules, build detection, replay attacks |

Each mission has a blue-team check — after attacking, look at the Wazuh dashboard to see what the defenders saw.

## Key Attack Vectors

- **`%QX0.0` (manual_mode coil)** — set TRUE and the PLC stops auto control, obeys your manual setpoints
- **`%QX5.0` (run_bit)** — set FALSE for emergency stop
- **Remote I/O devices** (192.168.95.10-15) — write directly to valve setpoints, bypassing the PLC
- **PLC web interface** (port 8080) — upload malicious PLC programs
- **HMI traffic** — MITM between HMI and PLC to forge sensor readings

## Lab Management

```bash
# Check status
docker compose --profile siem ps

# Stop everything
docker compose --profile siem down

# Full reset (wipes all data)
docker compose --profile siem down -v
docker compose --profile siem up -d

# View router Suricata logs
docker exec router cat /var/log/suricata/fast.log

# View Wazuh alerts
docker exec wazuh tail -50 /var/ossec/logs/alerts/alerts.json
```

## What We Changed From GRFICSv3

This lab is based on [GRFICSv3](https://github.com/Fortiphyd/GRFICSv3) by [Fortiphyd Logic](https://fortiphyd.com/). We made the following changes to optimise it for self-study on WSL2:

### Removed

| Component | Why |
|-----------|-----|
| **Kali attacker container** (~4 GB image) | Attack from your own machine. With native Docker Engine the OT subnets are directly routable, so you use your own nmap, Wireshark, pymodbus and scapy against `192.168.95.0/24` — no bundled attacker VM needed. |
| **MITRE Caldera** (~40 MB + container) | Automated C2/adversary-emulation framework — overkill for learning ICS fundamentals by hand. |

### Modified

| Change | Why |
|--------|-----|
| **Networks: macvlan → bridge** | The original uses macvlan with 802.1Q VLAN sub-interfaces (`eth0.95`, `eth0.90`), which require a VLAN-capable parent NIC that WSL2 doesn't provide. Bridge networks use the same subnets and IPs, and — crucially — on native Docker they are routable from your host so you can scan and attack them directly. Trade-off: no true L2 VLAN isolation between ICS and DMZ (they share a broadcast domain); the router still routes between zones, but cross-zone ARP spoofing works where it wouldn't on real VLANs. |

### Added

| Addition | What it is |
|----------|-----------|
| `scripts/setup-wsl.sh` | One-shot bootstrap: installs native Docker Engine + Compose v2, handles the Docker Desktop handoff, starts the full lab, and prints the routable subnet. Takes a fresh WSL2/Linux box to a working lab in one command. |
| `reference/MODBUS_PROTOCOL.md` | Modbus TCP protocol reference — function codes, data model, the lab's full register map, pymodbus examples. |
| `reference/PLANT_PROCESS.md` | Tennessee Eastman process explained — how the plant works, normal parameters, safety mechanisms, what each attack target does. |
| `missions/` (7 JSON files) | CTF-style learning missions. Recon → enumeration → process manipulation → safety override → MITM → DoS → defence. Each has objectives, learning points, things to think about, flags, and blue-team checks. No pre-made attack scripts. |

## Credits

- **[GRFICSv3](https://github.com/Fortiphyd/GRFICSv3)** by [Fortiphyd Logic](https://fortiphyd.com/) — the simulation, PLC, HMI, router, Wazuh, and Zeek Docker images are theirs. This project wouldn't exist without their work.
- Tennessee Eastman process model based on the [TE benchmark](https://depts.washington.edu/control/LARRY/TE/download.html) by Downs and Vogel (1993).

## License

This project includes modified configuration from GRFICSv3, which is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.
