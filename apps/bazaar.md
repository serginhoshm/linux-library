# Bazaar

Loja de aplicativos Flatpak

```json
{
  "schema_version": 1,
  "order": 16,
  "key": "bazaar",
  "name": "Bazaar",
  "description": "Loja de aplicativos Flatpak",
  "aliases": [
    "bazaar"
  ],
  "packages": {
    "apt": "bazaar",
    "dnf": "",
    "zypper": ""
  },
  "deb": {
    "discovery": {
      "type": "github",
      "source": "kolunmi/bazaar"
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
      "type": "github",
      "source": "kolunmi/bazaar"
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
    "id": "io.github.kolunmi.Bazaar",
    "source_type": "remote",
    "remote_name": "flathub",
    "repository_url": "https://dl.flathub.org/repo/flathub.flatpakrepo",
    "ref_or_url": "io.github.kolunmi.Bazaar"
  }
}
```
