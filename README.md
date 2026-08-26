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

### [debian_trixie](debian_trixie/)
- `samba-config.sh` — instala e configura um compartilhamento Samba público com acesso anônimo/guest e regras de firewall.
- `flatpak-install.sh` — instala Flatpak e apps essenciais para o ambiente desktop.
- `ftp-setup.sh` — prepara um servidor FTP local com ajustes de segurança e permissões.
- `signal-install.sh` — instala o Signal Desktop no ambiente Debian.
- `flameshot-install.sh` — instala o Flameshot para captura de tela.
- `nfs-client.sh` — configura o cliente NFS para montar volumes remotos.
- `nfs-server.sh` — habilita e configura um servidor NFS local.
- `plex-firewall-config.sh` — abre as portas necessárias do Plex no firewall.
- `swap-config.sh` — cria e configura uma área de swap adequada.
- `transmission-config.sh` — instala e ajusta o Transmission para downloads via torrent.

### [fedora_44](fedora_44/)
- `samba-config.sh` — instala e configura o Samba para compartilhamento público com guest access e firewall.
- `samba-share.sh` — cria um diretório compartilhado e configura a seção do Samba para acesso local.
- `flatpak-install.sh` — instala Flatpak e aplicativos compatíveis com o Fedora.
- `ftp-setup.sh` — instala e ajusta um servidor FTP local.
- `signal-install.sh` — instala o Signal Desktop no Fedora.
- `flameshot-install.sh` — instala a ferramenta de captura de tela Flameshot.
- `nfs-client.sh` — configura o cliente NFS do Fedora.
- `nfs-server.sh` — habilita e configua um servidor NFS.
- `nvidia-install.sh` — instala e configura drivers NVIDIA quando necessário.
- `plex-firewall-config.sh` — ajusta a rede e o firewall para o Plex.
- `swap-config.sh` — configura a partição de swap ou arquivo de swap.
- `transmission-config.sh` — instala e ajusta o Transmission para download de torrents.

### [zorin_os_pro_18_1](zorin_os_pro_18_1/)
- `samba-config.sh` — instala e configura o Samba com compartilhamento anônimo e validação do smb.conf.
- `samba-share.sh` — cria um diretório público para compartilhamento SMB.
- `flatpak-install.sh` — instala suporte Flatpak e apps desktop.
- `ftp-setup.sh` — prepara um servidor FTP local.
- `signal-install.sh` — instala o Signal Desktop.
- `flameshot-install.sh` — instala o Flameshot.
- `nfs-client.sh` — configura cliente NFS para montagem remota.
- `nfs-server.sh` — habilita um servidor NFS local.
- `nvidia-install.sh` — instala drivers NVIDIA para esta base.
- `plex-firewall-config.sh` — abre o firewall para o Plex.
- `swap-config.sh` — cria a configuração de swap necessária.
- `transmission-config.sh` — prepara o Transmission para downloads.

### [opensuse_leap_16_0](opensuse_leap_16_0/)
- `samba-config.sh` — instala Samba no openSUSE e configura compartilhamento público com guest account.
- `flatpak-install.sh` — instala Flatpak e software adicional.
- `ftp-setup.sh` — configura FTP local com ajustes mínimos de segurança.
- `signal-install.sh` — instala o Signal Desktop.
- `flameshot-install.sh` — instala o Flameshot.
- `nfs-client.sh` — configura cliente NFS para uso em rede.
- `nfs-server.sh` — habilita servidor NFS local.
- `plex-firewall-config.sh` — ajusta as portas do Plex no firewall.
- `swap-config.sh` — cria e ajusta swap para o sistema.
- `transmission-config.sh` — instala e prepara o Transmission.

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
