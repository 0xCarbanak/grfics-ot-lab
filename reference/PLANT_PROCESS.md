# Tennessee Eastman Chemical Process — GRFICSv3

## What This Plant Does

The Tennessee Eastman (TE) process is a well-known benchmark in process control.
Two feed streams bring reactants into a reactor vessel. The reaction happens
under pressure, product drains through a product valve, and waste gas is vented
through a purge valve. An analyzer measures composition in the purge stream.

The 3D visualisation at `http://localhost` shows it all in real time — you can
also walk around the plant in first person (WASD + mouse) and look for physical
security vulnerabilities.


## Normal Operating Parameters

| Variable            | Normal     | Danger Zone                        |
|---------------------|------------|------------------------------------|
| Reactor Pressure    | ~2700 kPa  | >2900 override, >3200 vessel max  |
| Tank Level          | ~44%       | Too high = overflow, too low = dry |
| Composition (A)     | ~47%       | Off-spec product                   |
| Product Flow        | ~100 units | Varies with control                |


## Process Diagram

```
  Feed 1 ──► [F1 Valve] ──┐
                           ├──► REACTOR ──► [Product Valve] ──► Product Out
  Feed 2 ──► [F2 Valve] ──┘      │
                                  │
                            [Purge Valve] ──► Purge Gas Out
                                  │
                             [Analyzer] ──► Composition readings
                                  │
                              [Tank] ──► Pressure + Level readings
```


## PLC Control Loops (20ms scan cycle)

1. **Feed 1 valve** → controls product flow rate to setpoint
2. **Feed 2 valve** → controls composition (% A in purge) to setpoint
3. **Purge valve** → controls reactor pressure to setpoint
4. **Product valve** → controls tank level to setpoint
5. **Pressure override** → if pressure > ~2900 kPa, increases product outflow


## How Loss of Control Happens

**Pressure runaway**: Close purge + keep feeds open → pressure climbs.
Override kicks in at 2900 kPa. Defeat the override (manual_mode + close
product valve) and pressure heads toward 3200 kPa.

**Level excursion**: Close product + open feeds → overflow. Or open product +
close feeds → dry tank.

**Composition drift**: Change feed ratios → off-spec product. Less dramatic
but matters in a real plant.


## Safety Mechanisms and How to Defeat Them

**Auto control loops**: Fight your changes every 20ms.
→ Defeat with manual_mode coil (%QX0.0 = TRUE)

**Pressure override**: Auto-increases product outflow above 2900 kPa.
→ Defeated when manual_mode is TRUE (override logic is bypassed)

**run_bit (%QX5.0)**: E-stop. When FALSE, feeds close, purge/product open.
→ Keep it TRUE while manipulating other values

**manual_mode + manual valve SPs**: Once manual_mode is TRUE, write
%QW10-13 to set whatever valve positions you want. The PLC obeys.


## Access Points

| System                  | URL                    | Credentials          |
|-------------------------|------------------------|---------------------|
| 3D Plant Visualisation  | http://localhost       | —                   |
| PLC (OpenPLC)           | http://localhost:8080  | openplc / openplc   |
| HMI (ScadaLTS)          | http://localhost:6081  | admin / admin       |
| Engineering Workstation | http://localhost:6080  | (noVNC desktop)     |
| Kali Attacker           | http://localhost:6088  | kali / kali         |
| MITRE Caldera           | http://localhost:8888  | red / fortiphyd-red |
| Wazuh SIEM              | http://localhost:5601  | (siem profile)      |
