# Slack

Comunicacao de equipes

```json
{
  "schema_version": 1,
  "order": 4,
  "key": "slack",
  "name": "Slack",
  "description": "Comunicacao de equipes",
  "aliases": [
    "slack-desktop"
  ],
  "packages": {
    "apt": "slack-desktop",
    "dnf": "",
    "zypper": ""
  },
  "deb": {
    "discovery": {
      "type": "page-deb",
      "source": "https://slack.com/downloads/instructions/linux?ddl=1&build=deb"
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
    "id": "com.slack.Slack",
    "source_type": "remote",
    "remote_name": "flathub",
    "repository_url": "https://dl.flathub.org/repo/flathub.flatpakrepo",
    "ref_or_url": "com.slack.Slack"
  }
}
```
