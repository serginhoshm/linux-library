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
- [current-config/trabalho-acer.md](current-config/trabalho-acer.md) — Acer Nitro usado como máquina de trabalho profissional e gestão de produtos

## Convenção de nomes

- Os scripts seguem o padrão `ferramenta-acao.sh`.
- A referência à distro foi removida do nome do arquivo.
- Cada pasta representa uma distribuição e versão compatíveis.
- A pasta raiz serve como índice geral e documentação.

## Compatibilidade por versão

| Pasta | Distribuição e versão | Compatível com |
|---|---|---|
| [debian_trixie](debian_trixie/) | Debian Trixie | Debian 13 / Trixie |
| [fedora_44](fedora_44/) | Fedora 44 | Fedora 44 |
| [zorin_os_pro_18_1](zorin_os_pro_18_1/) | Zorin OS Pro 18.1 | Zorin OS Pro 18.1 |
| [opensuse_leap_16_0](opensuse_leap_16_0/) | openSUSE Leap 16.0 | openSUSE Leap 16.0 |

## Índice por distro

### [debian_trixie](debian_trixie/)
- `samba-config.sh` — configura compartilhamento Samba público com guest access, permissões e firewall.
- `flatpak-install.sh` — prepara Flatpak e aplicações essenciais.
- `ftp-setup.sh` — monta um servidor FTP local para transferência simples.
- `signal-install.sh` — instala o Signal Desktop.
- `flameshot-install.sh` — habilita captura de tela rápida e eficiente.
- `nfs-client.sh` — conecta a volumes remotos via NFS.
- `nfs-server.sh` — disponibiliza um servidor NFS local.
- `plex-firewall-config.sh` — abre portas necessárias para o Plex.
- `swap-config.sh` — ajusta área de swap do sistema.
- `transmission-config.sh` — prepara um cliente de torrents leve.

### [fedora_44](fedora_44/)
- `samba-config.sh` — configura Samba público com mapeamento de guest e validação do smb.conf.
- `samba-share.sh` — cria um diretório compartilhado para uso local em rede.
- `flatpak-install.sh` — instala Flatpak e utilitários gerais.
- `ftp-setup.sh` — configura um servidor FTP local.
- `signal-install.sh` — instala o Signal Desktop.
- `flameshot-install.sh` — instala o Flameshot.
- `nfs-client.sh` — configura montagem de volumes NFS do cliente.
- `nfs-server.sh` — habilita um servidor NFS local.
- `nvidia-install.sh` — instala drivers NVIDIA e ajustes do sistema.
- `plex-firewall-config.sh` — abre portas do Plex no firewall.
- `swap-config.sh` — cria ou ajusta swap no Fedora.
- `transmission-config.sh` — prepara o Transmission para downloads via torrent.

### [zorin_os_pro_18_1](zorin_os_pro_18_1/)
- `samba-config.sh` — instala Samba e configura acesso público por guest.
- `samba-share.sh` — cria um compartilhamento SMB público.
- `flatpak-install.sh` — instala Flatpak e apps do desktop.
- `ftp-setup.sh` — prepara um FTP local para uso básico.
- `signal-install.sh` — instala o Signal Desktop.
- `flameshot-install.sh` — instala o Flameshot.
- `nfs-client.sh` — configura ponto de montagem NFS.
- `nfs-server.sh` — habilita servidor NFS local.
- `nvidia-install.sh` — instala drivers NVIDIA para desktop.
- `plex-firewall-config.sh` — ajusta firewall para o Plex.
- `swap-config.sh` — configura swap do sistema.
- `transmission-config.sh` — instala e ajusta o Transmission.

### [opensuse_leap_16_0](opensuse_leap_16_0/)
- `samba-config.sh` — instala Samba e configura compartilhamento público no openSUSE.
- `flatpak-install.sh` — instala Flatpak e utilitários relevantes.
- `ftp-setup.sh` — configura FTP e permissões locais.
- `signal-install.sh` — instala o Signal Desktop.
- `flameshot-install.sh` — instala o Flameshot.
- `nfs-client.sh` — configura cliente NFS em rede local.
- `nfs-server.sh` — habilita servidor NFS local.
- `plex-firewall-config.sh` — ajusta portas e firewall do Plex.
- `swap-config.sh` — cria swap para a base openSUSE.
- `transmission-config.sh` — prepara o Transmission para downloads.

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
