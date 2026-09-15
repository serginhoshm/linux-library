# Deezer

Streaming de musica

```json
{
  "schema_version": 1,
  "order": 11,
  "key": "deezer",
  "name": "Deezer",
  "description": "Streaming de musica",
  "aliases": [
    "deezer-desktop",
    "deezer",
    "deezer-linux"
  ],
  "packages": {
    "apt": "deezer-desktop",
    "dnf": "deezer-desktop",
    "zypper": "deezer-desktop"
  },
  "deb": {
    "discovery": {
      "type": "github",
      "source": "aunetx/deezer-linux"
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
      "source": "aunetx/deezer-linux"
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
    "id": "dev.aunetx.deezer",
    "source_type": "remote",
    "remote_name": "flathub",
    "repository_url": "https://dl.flathub.org/repo/flathub.flatpakrepo",
    "ref_or_url": "dev.aunetx.deezer"
  }
}
```
