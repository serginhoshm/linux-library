# Signal Desktop

Mensagens privadas

```json
{
  "schema_version": 1,
  "order": 3,
  "key": "signal",
  "name": "Signal Desktop",
  "description": "Mensagens privadas",
  "aliases": [
    "signal-desktop",
    "signal"
  ],
  "packages": {
    "apt": "signal-desktop",
    "dnf": "",
    "zypper": ""
  },
  "deb": {
    "discovery": {
      "type": "apt-index",
      "source": "https://updates.signal.org/desktop/apt/dists/xenial/main/binary-amd64/Packages;https://updates.signal.org/desktop/apt/"
    },
    "resolved": {
      "url": "",
      "version": "",
      "sha256": "",
      "checksum_url": "",
      "checked_at": "",
      "status": "UNKNOWN"
    }
  },
  "rpm": {
    "discovery": {
      "type": "none",
      "source": ""
    },
    "resolved": {
      "url": "",
      "version": "",
      "sha256": "",
      "checksum_url": "",
      "checked_at": "",
      "status": "UNKNOWN"
    }
  },
  "flatpak": {
    "id": "org.signal.Signal",
    "source_type": "remote",
    "remote_name": "flathub",
    "repository_url": "https://dl.flathub.org/repo/flathub.flatpakrepo",
    "ref_or_url": "org.signal.Signal"
  }
}
```
