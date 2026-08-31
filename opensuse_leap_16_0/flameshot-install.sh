#Usar este comando para iniciar Flameshot em modo GUI com suporte para Wayland:
#Gnome keybinding
#Para usar este comando como atalho no Gnome, vá em Configurações -> Teclado -> Atalhos -> Personalizados e adicione um novo atalho com o comando abaixo.

bash -c "nohup env XDG_SESSION_TYPE=lxqt QT_QPA_PLATFORM=wayland /usr/bin/flameshot gui > /dev/null 2>&1 &"
