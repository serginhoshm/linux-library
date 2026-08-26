# linux-kb
# 🗺️ Logbook para distros Linux

Este repositório reúne scripts e rotinas de pós-instalação organizados por distribuição. A ideia é manter cada ambiente separado e pronto para reutilização em novas instalações.

## Estrutura

- [debian_trixie](debian_trixie/) — Debian Trixie
- [fedora_44](fedora_44/) — Fedora 44
- [zorin_os_pro_18_1](zorin_os_pro_18_1/) — Zorin OS Pro 18.1
- [opensuse_leap_16_0](opensuse_leap_16_0/) — openSUSE Leap 16.0
- [current-config](current-config/) — configuração ativa dos hosts em uso

## Configuração atual

- [current-config/casa-lenovo.md](current-config/casa-lenovo.md) — Lenovo IdeaPad 1 com openSUSE Leap 16.0
- [current-config/trabalho-acer.md](current-config/trabalho-acer.md) — Acer Nitro em uso como laboratório de testes e experimentação

## Convenção de nomes

- Os scripts usam nomes em padrão `ferramenta-acao.sh`.
- A referência à distro foi removida do nome do arquivo.
- Cada pasta representa uma distribuição e versão compatível específicas.
- A pasta raiz foi mantida apenas para documentação e índices gerais.

## Compatibilidade por versão

| Pasta | Distribuição e versão | Compatível com |
|---|---|---|
| [debian_trixie](debian_trixie/) | Debian Trixie | Debian 13 / Trixie |
| [fedora_44](fedora_44/) | Fedora 44 | Fedora 44 |
| [zorin_os_pro_18_1](zorin_os_pro_18_1/) | Zorin OS Pro 18.1 | Zorin OS Pro 18.1 |
| [opensuse_leap_16_0](opensuse_leap_16_0/) | openSUSE Leap 16.0 | openSUSE Leap 16.0 |

## Índice por distro

| Pasta | Scripts principais | Observações |
|---|---|---|
| [debian_trixie](debian_trixie/) | `samba-config.sh`, `flatpak-install.sh`, `ftp-setup.sh`, `signal-install.sh`, `flameshot-install.sh`, `nfs-client.sh`, `nfs-server.sh`, `plex-firewall-config.sh`, `swap-config.sh`, `transmission-config.sh` | base para Debian Trixie com `apt` |
| [fedora_44](fedora_44/) | `samba-config.sh`, `flatpak-install.sh`, `ftp-setup.sh`, `signal-install.sh`, `flameshot-install.sh`, `nfs-client.sh`, `nfs-server.sh`, `nvidia-install.sh`, `plex-firewall-config.sh`, `swap-config.sh`, `transmission-config.sh` | foco em Fedora 44 com `dnf` |
| [zorin_os_pro_18_1](zorin_os_pro_18_1/) | `samba-config.sh`, `flatpak-install.sh`, `ftp-setup.sh`, `signal-install.sh`, `flameshot-install.sh`, `nfs-client.sh`, `nfs-server.sh`, `nvidia-install.sh`, `plex-firewall-config.sh`, `swap-config.sh`, `transmission-config.sh` | compatível com Zorin OS Pro 18.1 |
| [opensuse_leap_16_0](opensuse_leap_16_0/) | `samba-config.sh`, `flatpak-install.sh`, `ftp-setup.sh`, `signal-install.sh`, `flameshot-install.sh`, `nfs-client.sh`, `nfs-server.sh`, `plex-firewall-config.sh`, `swap-config.sh`, `transmission-config.sh` | compatível com openSUSE Leap 16.0 |

## Como usar

1. Entre na pasta da sua distro.
2. Escolha o script desejado.
3. Dê permissão de execução:

```bash
chmod +x nome-do-script.sh
```

4. Execute com sudo quando necessário:

```bash
sudo ./nome-do-script.sh
```

## Histórico

- [x] Zorin OS Pro
- [x] Fedora
- [x] Debian/Ubuntu
- [x] OpenSUSE Leap 16.0

---

*“Linux é uma aventura de distribuição em distribuição.”* 🐧
