#!/bin/bash

# Cores para o terminal
GREEN='\033[0;32m'
NC='\033[0m' # Sem cor

echo -e "${GREEN}[1/4] Atualizando a lista de pacotes...${NC}"
sudo apt update

echo -e "${GREEN}[2/4] Instalando o Samba e dependências essenciais...${NC}"
sudo apt install -y samba samba-common-bin wsdd

echo -e "${GREEN}[3/4] Configurando o seu usuário no grupo do Samba...${NC}"
# Adiciona o usuário atual ao grupo 'sambashare' para permitir compartilhamento sem root
sudo usermod -aG sambashare $USER

# Define uma senha do Samba para o seu usuário atual
echo -e "${GREEN}Defina uma senha para os seus compartilhamentos de rede do Samba:${NC}"
sudo smbpasswd -a $USER

echo -e "${GREEN}[4/4] Identificando o ambiente e instalando a extensão do gerenciador de arquivos...${NC}"

# Verifica se é LMDE (geralmente usa Nemo) ou Zorin (usa Nautilus)
if dpkg -l | grep -q "nemo"; then
    echo -e "${GREEN}Detectado gerenciador de arquivos Nemo (LMDE). Instalando nemo-share...${NC}"
    sudo apt install -y nemo-share
    # Reinicia o Nemo para aplicar as alterações
    nemo -q
elif dpkg -l | grep -q "nautilus"; then
    echo -e "${GREEN}Detectado gerenciador de arquivos Nautilus (Zorin OS). Instalando nautilus-share...${NC}"
    sudo apt install -y nautilus-share
    # Reinicia o Nautilus para aplicar as alterações
    nautilus -q
else
    echo "Gerenciador de arquivos padrão não identificado automaticamente."
    echo "Por favor, tente instalar 'nautilus-share' ou 'nemo-share' manualmente conforme seu sistema."
fi

echo -e "${GREEN}¡Todo listo! Reiniciando os serviços do Samba...${NC}"
sudo systemctl restart smbd nmbd

echo -e "${GREEN}Configuração concluída com sucesso!${NC}"
echo "Recomendamos fazer Logoff (Sair da sessão) e entrar novamente para que as permissões de grupo façam efeito."