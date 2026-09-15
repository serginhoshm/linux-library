# Steam

Plataforma de jogos

```json
{
  "schema_version": 1,
  "order": 13,
  "key": "steam",
  "name": "Steam",
  "description": "Plataforma de jogos",
  "aliases": [
    "steam",
    "steam-installer"
  ],
  "packages": {
    "apt": "steam",
    "dnf": "steam",
    "zypper": "steam"
  },
  "deb": {
    "discovery": {
      "type": "direct",
      "source": "https://repo.steampowered.com/steam/archive/stable/steam_latest.deb"
    },
    "resolved": {
      "url": "https://repo.steampowered.com/steam/archive/stable/steam_latest.deb",
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
    "id": "com.valvesoftware.Steam",
    "source_type": "remote",
    "remote_name": "flathub",
    "repository_url": "https://dl.flathub.org/repo/flathub.flatpakrepo",
    "ref_or_url": "com.valvesoftware.Steam"
  }
}
```
