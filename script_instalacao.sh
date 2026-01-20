#!/bin/bash

# ==============================================================================
# SCRIPT DE INSTALAÇÃO AUTOMATIZADA
# Aplicativos: AnyDesk, Chrome, DBeaver, Docker, Node.js, Postman, VS Code, Rider
# Essenciais: Git, Vim, .NET SDK 8.0, Wget, Curl
# ==============================================================================

# Interrompe a execução em caso de erro
set -e

# --- Cores para o terminal ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # Sem cor

# --- Verificação de Root ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${YELLOW}Este script precisa ser executado como root (sudo).${NC}"
   exit 1
fi

# --- Funções Utilitárias ---

update_system_full() {
    echo -e "${BLUE}>> Iniciando atualização completa do sistema...${NC}"
    apt update
    apt upgrade -y
    echo -e "${GREEN}>> Sistema atualizado com sucesso!${NC}\n"
}

update_apt_cache() {
    echo -e "${BLUE}>> Atualizando índices de pacotes...${NC}"
    apt update
}

# --- Funções de Instalação ---

install_essentials() {
    echo -e "${GREEN}>> Instalando pacotes essenciais (Git, Vim, .NET 8, Wget, Curl)...${NC}"
    apt update
    apt install -y git vim dotnet-sdk-8.0 wget curl
}

install_anydesk() {
    echo -e "${GREEN}>> Instalando AnyDesk...${NC}"
    apt install -y ca-certificates curl apt-transport-https
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY -o /etc/apt/keyrings/keys.anydesk.com.asc
    chmod a+r /etc/apt/keyrings/keys.anydesk.com.asc
    echo "deb [signed-by=/etc/apt/keyrings/keys.anydesk.com.asc] https://deb.anydesk.com all main" | tee /etc/apt/sources.list.d/anydesk-stable.list > /dev/null
    update_apt_cache
    apt install -y anydesk
}

install_chrome( ) {
    echo -e "${GREEN}>> Instalando Google Chrome...${NC}"
    apt install -y wget gpg apt-transport-https
    wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | tee /usr/share/keyrings/google-chrome.gpg > /dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
    update_apt_cache
    apt install -y google-chrome-stable
}

install_dbeaver( ) {
    echo -e "${GREEN}>> Instalando DBeaver CE...${NC}"
    wget -O /usr/share/keyrings/dbeaver.gpg.key https://dbeaver.io/debs/dbeaver.gpg.key
    echo "deb [signed-by=/usr/share/keyrings/dbeaver.gpg.key] https://dbeaver.io/debs/dbeaver-ce /" | tee /etc/apt/sources.list.d/dbeaver.list
    update_apt_cache
    apt install -y dbeaver-ce
}

install_docker( ) {
    echo -e "${GREEN}>> Instalando Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    echo -e "${BLUE}>> Configurando Docker para o usuário $SUDO_USER...${NC}"
    groupadd -f docker
    usermod -aG docker "$SUDO_USER"
    systemctl start docker
    systemctl enable docker
    echo -e "${YELLOW}Aviso: Reinicie sua sessão para usar o Docker sem sudo.${NC}"
}

install_nodejs( ) {
    echo -e "${GREEN}>> Instalando Node.js 24.x...${NC}"
    apt install -y curl
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
    apt install -y nodejs
}

install_postman( ) {
    echo -e "${GREEN}>> Instalando Postman via Snap...${NC}"
    snap install postman
}

install_vscode() {
    echo -e "${GREEN}>> Instalando Visual Studio Code...${NC}"
    apt install -y wget gpg apt-transport-https
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
    install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg
    rm -f microsoft.gpg
    echo "Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg" | tee /etc/apt/sources.list.d/vscode.sources > /dev/null
    update_apt_cache
    apt install -y code
}

install_rider( ) {
    echo -e "${GREEN}>> Instalando JetBrains Rider via Snap...${NC}"
    if ! command -v snap &> /dev/null; then
        apt update && apt install -y snapd
    fi
    snap install rider --classic
}

# --- Menu Principal ---
show_menu() {
    clear
    echo -e "${BLUE}======================================"
    echo "   INSTALADOR DE APLICATIVOS LINUX"
    echo -e "======================================${NC}"
    echo "1) Instalar Essenciais (Git, Vim, .NET 8, etc)"
    echo "2) Instalar AnyDesk"
    echo "3) Instalar Google Chrome"
    echo "4) Instalar DBeaver"
    echo "5) Instalar Docker"
    echo "6) Instalar Node.js"
    echo "7) Instalar Postman"
    echo "8) Instalar VS Code"
    echo "9) Instalar JetBrains Rider"
    echo "10) Instalar TODOS"
    echo "0) Sair"
    echo -e "${BLUE}======================================${NC}"
    read -p "Escolha uma opção: " choice

    case $choice in
        1) install_essentials ;;
        2) install_anydesk ;;
        3) install_chrome ;;
        4) install_dbeaver ;;
        5) install_docker ;;
        6) install_nodejs ;;
        7) install_postman ;;
        8) install_vscode ;;
        9) install_rider ;;
        10) 
            install_essentials
            install_anydesk
            install_chrome
            install_dbeaver
            install_docker
            install_nodejs
            install_postman
            install_vscode
            install_rider
            ;;
        0) exit 0 ;;
        *) echo -e "${YELLOW}Opção inválida!${NC}"; sleep 2; show_menu ;;
    esac
    
    echo -e "\n${GREEN}Processo concluído!${NC}"
    read -p "Pressione Enter para voltar ao menu..."
    show_menu
}

# --- Início do Script ---

echo -e "${BLUE}Deseja atualizar o sistema (update & upgrade) antes de começar? (s/n)${NC}"
read -p "> " update_choice
if [[ "$update_choice" =~ ^[Ss]$ ]]; then
    update_system_full
fi

show_menu
