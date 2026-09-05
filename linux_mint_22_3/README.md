# Linux Mint 22.3

Compatibilidade confirmada para:
- Linux Mint 22.3 Zena, baseado no Ubuntu 24.04 Noble

## Scripts disponíveis
1. `flatpak-install.sh`
2. `flameshot-install.sh`
3. `ftp-setup.sh`
4. `nfs-client.sh`
5. `nfs-server.sh`
6. `nvidia-install.sh`
7. `plex-firewall-config.sh`
8. `samba-config.sh`
9. `samba-share.sh`
10. `signal-install.sh`
11. `swap-config.sh`
12. `transmission-config.sh`

## Uso rápido

```bash
chmod +x *.sh
./flatpak-install.sh
./flameshot-install.sh
```

Os scripts de servidores, compartilhamentos, swap e firewall exigem `sudo`:

```bash
sudo ./samba-config.sh
sudo ./nfs-server.sh
```

## Observações

- Baseado em Ubuntu 24.04 Noble e `apt`.
- O script FTP solicita a senha durante a execução; ela não fica gravada no arquivo.
- Os serviços de FTP, NFS, Samba, Plex e Transmission devem ser habilitados somente quando necessários.
- O driver NVIDIA não se aplica ao Lenovo IdeaPad registrado em `current-config/casa-lenovo.md`, que utiliza GPU Intel.
