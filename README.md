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
- **Docker Desktop** with WSL2 integration enabled (Windows), or Docker Engine (Linux)
- At least **8 GB RAM** allocated to Docker
- **~6 GB** disk space for Docker images
- **Python 3** with `pymodbus` for attacking: `pip install pymodbus`

### WSL2 Setup (Windows)

1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/)
2. Open Docker Desktop > **Settings > Resources > WSL Integration** > enable for your distro
3. Restart WSL: open PowerShell and run `wsl --shutdown`, then reopen your terminal
4. Add your user to the docker group (one-time):
   ```bash
   sudo usermod -aG docker $USER
   ```
5. Restart WSL again, then verify:
   ```bash
   docker ps
   ```

### Linux Setup

1. Install Docker Engine: https://docs.docker.com/engine/install/
2. Add your user to the docker group:
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker
   ```

## Quick Start

```bash
git clone https://github.com/0xCarbanak/grfics-ot-lab.git
cd grfics-ot-lab

# Pull prebuilt images and start the core lab
docker compose pull
docker compose up -d

# Start the SIEM stack (Wazuh + Zeek) — optional but recommended
docker compose --profile siem pull
docker compose --profile siem up -d
```

Wait about a minute for everything to initialise, then open:
- `http://localhost` — 3D plant visualisation
- `http://localhost:5601` — Wazuh SIEM dashboard

## Start Attacking

All Modbus devices are accessible from your WSL/Linux machine via localhost. A `modbus-proxy` container handles port forwarding into the Docker networks.

### Modbus Port Map

| Port | Device | What you'll read |
|------|--------|-----------------|
| `localhost:502` | PLC | Control registers, coils, setpoints |
| `localhost:10502` | Feed 1 | Valve position, flow rate |
| `localhost:11502` | Feed 2 | Valve position, flow rate |
| `localhost:12502` | Purge | Valve position, flow rate |
| `localhost:13502` | Product | Valve position, flow rate |
| `localhost:14502` | Tank | Pressure, level |
| `localhost:15502` | Analyzer | Composition A, B, C |

### Quick test

```bash
pip install pymodbus
python3
```

```python
from pymodbus.client import ModbusTcpClient

# Talk to the PLC
client = ModbusTcpClient("localhost", port=502)
client.connect()
result = client.read_input_registers(address=100, count=13)
print(result.registers)
client.close()

# Talk directly to the Tank
client = ModbusTcpClient("localhost", port=14502)
client.connect()
result = client.read_input_registers(1, count=2)
print(f"Pressure: {result.registers[0]}, Level: {result.registers[1]}")
client.close()
```

No login. No token. Figure out the rest.

Web UIs are accessible via your browser at the ports listed in the table above.

Reference docs in `reference/` explain the protocol, register map, and plant process. Missions in `missions/` guide your learning from recon through to building defences.

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
| **Kali attacker container** (~4 GB image) | Replaced with a ~5 MB socat proxy container that forwards all Modbus ports to localhost. Attack from your own machine with your own tools. |
| **MITRE Caldera** (~40 MB + container) | C2 framework — overkill for learning ICS fundamentals. |

### Modified

| Change | Why |
|--------|-----|
| **Networks: macvlan → bridge** | WSL2 doesn't support VLAN sub-interfaces (`eth0.95`, `eth0.90`) that macvlan needs. Bridge networks use the same subnets and IPs so everything still works. Trade-off: no true L2 VLAN isolation between ICS and DMZ — both share a broadcast domain. The router still routes between them, but ARP spoofing across zones works where it wouldn't on real VLANs. |
| **PLC: added port 502 mapping** | Original only exposed the web dashboard (8080). We added `502:502` so you can hit Modbus TCP directly from the host. |

### Added

| Addition | What it is |
|----------|-----------|
| `reference/MODBUS_PROTOCOL.md` | Modbus TCP protocol reference — function codes, data model, the lab's full register map, pymodbus examples. |
| `reference/PLANT_PROCESS.md` | Tennessee Eastman process explained — how the plant works, normal parameters, safety mechanisms, what each attack target does. |
| `modbus-proxy` container | Socat-based port forwarder exposing all 6 remote I/O Modbus devices to localhost (10502-15502). Needed because WSL2 can't route into Docker bridge networks. |
| `missions/` (7 JSON files) | CTF-style learning missions. Recon → enumeration → process manipulation → safety override → MITM → DoS → defence. Each has objectives, learning points, things to think about, flags, and blue-team checks. No pre-made attack scripts. |

## Credits

- **[GRFICSv3](https://github.com/Fortiphyd/GRFICSv3)** by [Fortiphyd Logic](https://fortiphyd.com/) — the simulation, PLC, HMI, router, Wazuh, and Zeek Docker images are theirs. This project wouldn't exist without their work.
- Tennessee Eastman process model based on the [TE benchmark](https://depts.washington.edu/control/LARRY/TE/download.html) by Downs and Vogel (1993).

## License

This project includes modified configuration from GRFICSv3, which is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.
