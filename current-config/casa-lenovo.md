# Lenovo IdeaPad 1 15IGL7

Uso doméstico. Estado verificado em 2026-09-04 após a reinstalação.
System:
  Host: lenovo-casa Kernel: 7.0.0-31-generic arch: x86_64 bits: 64
  Desktop: Cinnamon 6.6.9 (X11)
  Distro: Linux Mint 22.3 Zena base: Ubuntu 24.04 noble
Machine:
  Type: Laptop System: LENOVO product: 82VX v: IdeaPad 1 15IGL7
  Mobo: LENOVO model: LNVNB161216 v: SDK0T76468 WIN
  UEFI: LENOVO v: KKCN24WW date: 07/15/2024
Battery:
  ID-1: BAT0 condition: 39.9/42.0 Wh (95.0%) cycles: 49
CPU:
  Info: dual core model: Intel Celeron N4020 bits: 64 cache: L2: 4 MiB
  Speed: min/max: 800/2800 MHz
Graphics:
  Device-1: Intel GeminiLake [UHD Graphics 600] driver: i915
  Display: X11 resolution: 1366x768 at 60 Hz
  API: OpenGL 4.6 renderer: Mesa Intel UHD Graphics 600 (GLK 2)
Audio:
  Device-1: Intel Celeron/Pentium Silver Processor High Definition Audio
    driver: snd_hda_intel
  Server-1: PipeWire 1.0.5 status: active
Network:
  Device-1: Realtek RTL8822CE 802.11ac PCIe Wireless Network Adapter
    driver: rtw88_8822ce
Bluetooth:
  Device-1: Realtek Bluetooth Radio driver: btusb
Drives:
  Local Storage: total: 119.24 GiB used: 27.58 GiB (23.1%)
  ID-1: /dev/nvme0n1 vendor: SSSTC model: CL1-4D128 size: 119.24 GiB
Partition:
  ID-1: / size: 116.32 GiB used: 27.57 GiB (23.7%) fs: ext4
    dev: /dev/nvme0n1p2
  ID-2: /boot/efi size: 511 MiB used: 11.4 MiB (2.2%) fs: vfat
    dev: /dev/nvme0n1p1
Swap:
  ID-1: swap type: file size: 4.27 GiB file: /swapfile
Info:
  Memory: total: 4 GiB available to system: 3.38 GiB

## Auditoria pós-instalação

- Nenhuma atualização pendente na lista local do APT e nenhuma reinicialização pendente.
- Flatpak e Flathub configurados.
- Google Chrome, Vivaldi, Insync e Transmission GTK instalados.
- Driver gráfico Intel `i915` carregado corretamente.
- UFW habilitado e ativo.
- Nenhum servidor Samba, NFS ou FTP habilitado.
- Pendente: desabilitar `casper-md5check.service`, resíduo da mídia live que procura `/cdrom/md5sum.txt` em todo boot.
- Opcionais conforme necessidade: Flameshot, Signal e demais aplicativos listados em `linux_mint_22_3/flatpak-install.sh`.
