# Brave Browser

Navegador web

```json
{
  "schema_version": 1,
  "order": 5,
  "key": "brave",
  "name": "Brave Browser",
  "description": "Navegador web",
  "aliases": [
    "brave-browser",
    "brave-browser-stable"
  ],
  "packages": {
    "apt": "brave-browser",
    "dnf": "brave-browser",
    "zypper": ""
  },
  "deb": {
    "discovery": {
      "type": "github",
      "source": "brave/brave-browser"
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
      "source": "brave/brave-browser"
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
    "id": "com.brave.Browser",
    "source_type": "remote",
    "remote_name": "flathub",
    "repository_url": "https://dl.flathub.org/repo/flathub.flatpakrepo",
    "ref_or_url": "com.brave.Browser"
  }
}
```
