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
      "url": "https://downloads.slack-edge.com/desktop-releases/linux/x64/4.52.155/slack-desktop-4.52.155-amd64.deb",
      "version": "",
      "sha256": "",
      "checksum_url": "",
      "checked_at": "2026-09-15T11:24:21Z",
      "status": "FOUND"
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
      "checked_at": "2026-09-15T11:24:21Z",
      "status": "NOT_FOUND"
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
