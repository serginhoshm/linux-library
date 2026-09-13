# Lenovo IdeaPad 1 15IGL7

Uso doméstico. Estado verificado em 2026-09-12.
System:
  Host: lenovo-casa Kernel: 6.12.107+deb13-amd64 arch: x86_64 bits: 64
  Desktop: GNOME 48.7 (Wayland)
  Distro: Debian GNU/Linux 13.6 (Trixie)
Machine:
  Type: Laptop System: LENOVO product: 82VX v: IdeaPad 1 15IGL7
  Mobo: LENOVO model: LNVNB161216 v: SDK0T76468 WIN
  UEFI: LENOVO v: KKCN24WW date: 07/15/2024
Battery:
  ID-1: BAT0 condition: 39.9/42.0 Wh (95.0%) cycles: 52
CPU:
  Info: dual core model: Intel Celeron N4020 bits: 64 cache: L2: 4 MiB
  Speed: min/max: 800/2800 MHz
Graphics:
  Device-1: Intel GeminiLake [UHD Graphics 600] driver: i915
  Display: Wayland resolution: 1366x768 at 59.8 Hz
  API: Mesa 25.0.7 renderer: Intel UHD Graphics 600
Audio:
  Device-1: Intel Celeron/Pentium Silver Processor High Definition Audio
    driver: snd_hda_intel
  Server-1: PipeWire 1.4.2 status: active
Network:
  Device-1: Realtek RTL8822CE 802.11ac PCIe Wireless Network Adapter
    driver: rtw_8822ce
Bluetooth:
  Device-1: Realtek Bluetooth Radio driver: btusb
Drives:
  Local Storage: total: 119.24 GiB used: 17.43 GiB
  ID-1: /dev/nvme0n1 vendor: SSSTC model: CL1-4D128 size: 119.24 GiB
Partition:
  ID-1: / size: 112.37 GiB used: 17.42 GiB (17%) fs: ext4
    dev: /dev/nvme0n1p2
  ID-2: /boot/efi size: 974.08 MiB used: 9.03 MiB (1%) fs: vfat
    dev: /dev/nvme0n1p1
Swap:
  ID-1: swap type: partition size: 3.56 GiB dev: /dev/nvme0n1p3
  ID-2: swap type: zram size: 4.00 GiB dev: /dev/zram0
Info:
  Memory: total: 4 GiB available to system: 3.38 GiB

## Auditoria pós-instalação

- Nenhuma atualização pendente na lista local do APT e nenhuma reinicialização pendente.
- Flatpak e Flathub configurados, sem aplicativos Flatpak instalados.
- Google Chrome, Vivaldi e Insync instalados via pacote Debian.
- Driver gráfico Intel `i915` carregado corretamente.
- Nenhum firewall gerenciado por UFW ou firewalld instalado.
- Nenhum servidor Samba, NFS ou FTP instalado ou habilitado.
- Transmission, Flameshot e Signal não instalados.
- Opcionais conforme necessidade: menu disponível em `linux-setup.sh`.
