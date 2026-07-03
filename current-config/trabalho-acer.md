System:
  Host: sergio85-Nitro-AN515-55 Kernel: 6.17.0-35-generic arch: x86_64
    bits: 64
  Desktop: GNOME v: 46.0 Distro: Zorin OS 18.1 noble
Machine:
  Type: Laptop System: Acer product: Nitro AN515-55 v: V2.06
    serial: <superuser required>
  Mobo: CML model: Stonic_CMS v: V2.06 serial: <superuser required>
    UEFI: Insyde v: 2.06 date: 08/20/2021
Battery:
  ID-1: BAT1 charge: 43.9 Wh (100.0%) condition: 43.9/57.5 Wh (76.4%)
CPU:
  Info: quad core model: Intel Core i5-10300H bits: 64 type: MT MCP cache:
    L2: 1024 KiB
  Speed (MHz): avg: 4147 min/max: 800/4500 cores: 1: 4300 2: 4238 3: 4289
    4: 4213 5: 4290 6: 3339 7: 4282 8: 4226
Graphics:
  Device-1: Intel CometLake-H GT2 [UHD Graphics] driver: i915 v: kernel
  Device-2: NVIDIA TU117M [GeForce GTX 1650 Mobile / Max-Q] driver: nvidia
    v: 580.173.02
  Device-3: Logitech Logi Webcam C920e driver: uvcvideo type: USB
  Device-4: Chicony HD User Facing driver: uvcvideo type: USB
  Display: x11 server: X.Org v: 21.1.11 with: Xwayland v: 23.2.6 driver: X:
    loaded: modesetting,nvidia unloaded: fbdev,nouveau,vesa dri: iris gpu: i915
    resolution: 1: 1920x1080~60Hz 2: 1920x1080~60Hz
  API: EGL v: 1.5 drivers: iris,nvidia,swrast
    platforms: gbm,x11,surfaceless,device
  API: OpenGL v: 4.6.0 compat-v: 4.5 vendor: intel mesa
    v: 25.2.8-0ubuntu0.24.04.2 renderer: Mesa Intel UHD Graphics (CML GT2)
Audio:
  Device-1: Intel Comet Lake PCH cAVS driver: snd_hda_intel
  Device-2: NVIDIA driver: snd_hda_intel
  Device-3: Plantronics Plantronics Calisto 3200
    driver: plantronics,snd-usb-audio,usbhid type: USB
  API: ALSA v: k6.17.0-35-generic status: kernel-api
  Server-1: PipeWire v: 1.0.5 status: active
Network:
  Device-1: Intel Comet Lake PCH CNVi WiFi driver: iwlwifi
  IF: wlp0s20f3 state: up mac: dc:21:48:42:86:5a
  Device-2: Realtek Killer E2600 GbE driver: r8169
  IF: enp7s0 state: down mac: 70:69:79:af:1f:67
Bluetooth:
  Device-1: Intel AX201 Bluetooth driver: btusb type: USB
  Report: hciconfig ID: hci0 state: up address: DC:21:48:42:86:5E bt-v: 5.2
Drives:
  Local Storage: total: 1.14 TiB used: 214.64 GiB (18.3%)
  ID-1: /dev/nvme0n1 vendor: A-Data model: IM2P33F8ABR1-256GB
    size: 238.47 GiB
  ID-2: /dev/sda vendor: Western Digital model: WD10SPZX-21Z10T0
    size: 931.51 GiB
Partition:
  ID-1: / size: 229.63 GiB used: 67.29 GiB (29.3%) fs: ext4 dev: /dev/dm-1
  ID-2: /boot size: 1.61 GiB used: 228.6 MiB (13.9%) fs: ext4
    dev: /dev/nvme0n1p2
  ID-3: /boot/efi size: 511 MiB used: 6.1 MiB (1.2%) fs: vfat
    dev: /dev/nvme0n1p1
Swap:
  ID-1: swap-1 type: partition size: 1.91 GiB used: 1.1 MiB (0.1%)
    dev: /dev/dm-2
Sensors:
  System Temperatures: cpu: 59.0 C pch: 55.0 C mobo: N/A
  Fan Speeds (rpm): N/A
Info:
  Memory: total: 32 GiB available: 31.18 GiB used: 17.36 GiB (55.7%)
  Processes: 471 Uptime: 13h 0m Shell: Bash inxi: 3.3.34