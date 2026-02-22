# netmon

`netmon` ist ein schnelles, interaktives CLI-Netzwerkmonitoring-Tool für macOS.

## Features

- Live-Bandbreite pro Interface (In/Out) mit CLI-Graph
- Alle lokalen Interfaces (Ethernet, Wi-Fi, Loopback, Tunnel, Virtual)
- Interface-Auswahl per Pfeiltasten
- IP- und MAC-Anzeige (wenn verfügbar) pro Interface
- Einheiten umschaltbar (`Kbit/s`, `Mbit/s`, `Gbit/s`, `KB/s`, `MB/s`)
- Weitere Metriken: Pakete, Errors, Drops, Collisions
- Wi-Fi-Details (wenn verfügbar): SSID, RSSI, Noise, SNR, TX-Rate
- Mini-Graph oben + Maxi-Graph unten mit Zeitfenster-Toggle (`live`, `5s`, `10s`, `30s`, `5m`)
- Maxi-Graph mit fixer Referenz-Skalierung (`1 Gbit/s` Standard, höher nur bei erkanntem Link-Speed)
- Steuerbare Peak-Labels im Maxi-Graph (`5s`, `10s`, `15s`)

## Steuerung

- `↑` / `↓`: Interface auswählen
- `u`: Einheit wechseln
- `g`: Graph-Zeitfenster wechseln
- `1`..`5`: Graph-Zeitfenster direkt wählen (`live`, `5s`, `10s`, `30s`, `5m`)
- `p`: Peak-Label-Intervall wechseln
- `6`..`8`: Peak-Label-Intervall direkt wählen (`5s`, `10s`, `15s`)
- `d`: Detailansicht ein/aus
- `h`: Hilfe-Popup ein/aus
- `q`: Beenden

## Build

```bash
swift build --disable-sandbox
```

Falls in deiner Umgebung SwiftPM-Cache-Rechte eingeschränkt sind, funktioniert dieser Aufruf robust:

```bash
HOME="$PWD/.home" \
SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
swift build --disable-sandbox --scratch-path .build --cache-path .swiftpm-cache
```

## Start

```bash
swift run --disable-sandbox netmon
```

oder direkt:

```bash
./.build/debug/netmon
```

## Hinweise

- `CRC` wird aktuell als Näherung über Input-Errors dargestellt.
- Wi-Fi-Daten kommen über macOS-Systemtools und sind nur für erkannte Wi-Fi-Interfaces verfügbar.
