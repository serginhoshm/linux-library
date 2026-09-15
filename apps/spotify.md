# Spotify

Streaming de musica

```json
{
  "schema_version": 1,
  "order": 6,
  "key": "spotify",
  "name": "Spotify",
  "description": "Streaming de musica",
  "aliases": [
    "spotify-client",
    "spotify"
  ],
  "packages": {
    "apt": "spotify-client",
    "dnf": "",
    "zypper": ""
  },
  "deb": {
    "discovery": {
      "type": "apt-index",
      "source": "https://repository.spotify.com/dists/stable/non-free/binary-amd64/Packages;https://repository.spotify.com/"
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
    "id": "com.spotify.Client",
    "source_type": "remote",
    "remote_name": "flathub",
    "repository_url": "https://dl.flathub.org/repo/flathub.flatpakrepo",
    "ref_or_url": "com.spotify.Client"
  }
}
```
