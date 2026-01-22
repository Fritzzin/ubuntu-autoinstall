#!/bin/bash

# ==============================================================================
# SCRIPT DE PÓS INSTALAÇÃO V1
# Author: Augusto Fritz
# Date: 2026 01 22
#
# Rodar script como sudo.
#
# Uma opção instalará todas as aplicações, já a outra, irá configurar todos os
# arquivos necessários para conectar no AD e montar as pastas do servidor
# dentro de /mnt/servidor_toshyro
#
# O login necessário para ingressar no domínio, é um login de algum usuário com
# permissões elevadas, geralmente admin/root, no nosso caso, Carlos ou Toshyro
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
	apt install -y \
		git \
		vim \
		dotnet-sdk-8.0 \
		wget \
		curl \
		wireguard \
		apt-transport-https \
		ca-certificates \
		gnupg
}

install_anydesk() {
	echo -e "${GREEN}>> Instalando AnyDesk...${NC}"
	apt install -y ca-certificates curl apt-transport-https
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY -o /etc/apt/keyrings/keys.anydesk.com.asc
	chmod a+r /etc/apt/keyrings/keys.anydesk.com.asc
	echo "deb [signed-by=/etc/apt/keyrings/keys.anydesk.com.asc] https://deb.anydesk.com all main" | tee /etc/apt/sources.list.d/anydesk-stable.list >/dev/null
	update_apt_cache
	apt install -y anydesk
}

install_chrome() {
	echo -e "${GREEN}>> Instalando Google Chrome...${NC}"
	apt install -y wget gpg apt-transport-https
	wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | tee /usr/share/keyrings/google-chrome.gpg >/dev/null
	echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
	update_apt_cache
	apt install -y google-chrome-stable
}

install_dbeaver() {
	echo -e "${GREEN}>> Instalando DBeaver CE...${NC}"
	wget -O /usr/share/keyrings/dbeaver.gpg.key https://dbeaver.io/debs/dbeaver.gpg.key
	echo "deb [signed-by=/usr/share/keyrings/dbeaver.gpg.key] https://dbeaver.io/debs/dbeaver-ce /" | tee /etc/apt/sources.list.d/dbeaver.list
	update_apt_cache
	apt install -y dbeaver-ce
}

install_docker() {
	echo -e "${GREEN}>> Instalando Docker...${NC}"
	curl -fsSL https://get.docker.com -o get-docker.sh
	sh get-docker.sh
	rm get-docker.sh

	echo -e "${BLUE}>> Configurando Docker para o usuário $USER...${NC}"
	groupadd -f docker
	usermod -aG docker "$USER"
	systemctl start docker
	systemctl enable docker
	echo -e "${YELLOW}Aviso: Reinicie sua sessão para usar o Docker sem sudo.${NC}"
}

install_nodejs() {
	echo -e "${GREEN}>> Instalando Node.js 24.x...${NC}"
	apt install -y curl
	curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
	apt install -y nodejs
}

install_postman() {
	echo -e "${GREEN}>> Instalando Postman via Snap...${NC}"
	if ! command -v snap &>/dev/null; then
		apt update && apt install -y snapd
	fi
	snap install postman
}

install_vscode() {
	echo -e "${GREEN}>> Instalando Visual Studio Code...${NC}"
	apt install -y wget gpg apt-transport-https
	wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor >microsoft.gpg
	install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg
	rm -f microsoft.gpg
	echo "Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg" | tee /etc/apt/sources.list.d/vscode.sources >/dev/null
	update_apt_cache
	apt install -y code
}

install_rider() {
	echo -e "${GREEN}>> Instalando JetBrains Rider via Snap...${NC}"
	if ! command -v snap &>/dev/null; then
		apt update && apt install -y snapd
	fi
	snap install rider --classic
}

# Função para criar o script de logon
criar_script_logon() {
	# Criar diretório /home/scripts se não existir
	if [ ! -d "/home/scripts" ]; then
		mkdir -p /home/scripts
	fi

	# Criar o script logon.sh
	cat <<'EOF' >/home/scripts/logon.sh
#!/bin/bash
#
# Nome da interface WireGuard
INTERFACE="wg0"

# Verificar se o usuário está no grupo netdev, se não estiver, adicionar
if ! id -nG "$PAM_USER" | grep -qw "netdev"; then
    sudo usermod -aG netdev "$PAM_USER"
fi

# Verificar se o grupo docker existe
if getent group docker > /dev/null 2>&1; then
    # Se o grupo docker existir, verificar se o usuário está no grupo docker
    if ! id -nG "$PAM_USER" | grep -qw "docker"; then
        sudo usermod -aG docker "$PAM_USER"
    fi
fi
EOF

	# Garantir que o script seja executável
	chmod +x /home/scripts/logon.sh
}

# Função para configurar o PAM para chamar o script de logon
configurar_pam() {
	# Verificar se a linha já existe no arquivo /etc/pam.d/common-session
	if ! grep -q "session optional pam_exec.so /home/scripts/logon.sh" /etc/pam.d/common-session; then
		echo "session optional pam_exec.so /home/scripts/logon.sh" | sudo tee -a /etc/pam.d/common-session
	fi
}

# Função para configurar o NetworkManager
configurar_networkmanager() {
	# Modificar ou adicionar a configuração no arquivo /etc/NetworkManager/NetworkManager.conf
	# Verificar se a linha managed=true existe e substituir por managed=false
	if grep -q "managed=false" /etc/NetworkManager/NetworkManager.conf; then
		sudo sed -i 's/managed=false/managed=true/' /etc/NetworkManager/NetworkManager.conf
	fi

	# Garantir que o grupo netdev esteja configurado no [policy]
	if ! grep -q "group=netdev" /etc/NetworkManager/NetworkManager.conf; then
		echo -e "\n[policy]\ngroup=netdev" | sudo tee -a /etc/NetworkManager/NetworkManager.conf
	fi

	# Reiniciar o NetworkManager para aplicar as mudanças
	sudo systemctl restart NetworkManager
}

# Função para verificar e adicionar uma entrada no /etc/sudoers
function adicionar_no_sudoers() {
	local entrada="$1"
	local sudoers_file="/etc/sudoers"

	if sudo grep -qF "$entrada" "$sudoers_file"; then
		echo "A entrada '$entrada' já existe no $sudoers_file."
	else
		echo "$entrada" | sudo tee -a "$sudoers_file" >/dev/null
		echo "A entrada '$entrada' foi adicionada ao $sudoers_file."
	fi
}

# Função para ingressar no domínio
function ingressar_dominio() {
	DOMINIO="TOSHYRO.LOCAL"
	read -p -r "Digite o usuário com permissões para ingressar: " usuario
	read -s -p -r "Digite a senha: " senha
	echo
	echo "Ingressando no domínio $DOMINIO..."

	# Passos para ingressar no domínio
	echo "Passo 1: Atualizando pacotes..."
	sudo apt update

	echo "Passo 2: Instalando pacotes necessários..."
	sudo apt install -y krb5-user samba sssd sssd-tools libnss-sss libpam-sss ntpdate realmd adcli

	echo "Passo 3: Configurando o NTP..."
	sudo ntpdate pool.ntp.org

	echo "Passo 4: Descobrindo o domínio..."
	sudo realm discover $DOMINIO

	echo "Passo 5: Ingressando no domínio..."
	echo "$senha" | sudo realm join --user="$usuario" $DOMINIO

	echo "Passo 6: Alterando configuração do SSSD..."
	sudo sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/' /etc/sssd/sssd.conf

	echo "Passo 7: Adicionando configuração PAM..."
	echo "session required pam_mkhomedir.so skel=/etc/skel/ umask=0077" | sudo tee -a /etc/pam.d/common-session

	echo "Passo 8: Atualizando o sudoers..."
	adicionar_no_sudoers "\"%domain admins\" ALL=(ALL:ALL) ALL"
	adicionar_no_sudoers "%linux_sudo ALL=(ALL:ALL) ALL"

	echo "Passo 9: Reiniciando o serviço SSSD..."
	sudo systemctl restart sssd

	echo "Passo 10: Criando script de logon, configurar pam e network manager"
	criar_script_logon
	configurar_pam
	configurar_networkmanager

	echo "Máquina ingressada no domínio, configuração do SSSD, PAM e sudoers atualizadas."

	echo "Começando configuração AutoFS"
	instalar_pacotes_ad
	habilitar_servicoes_ad
	configurar_autofs

	echo
	echo "=============================================="
	echo "CONFIGURAÇÃO FINALIZADA COM SUCESSO "
	echo
	echo "REINICIE A MÁQUINA"
	echo "Testes recomendados:"
	echo
	echo "1) Login com usuário do domínio"
	echo "2) Verificar ticket Kerberos:"
	echo "     klist"
	echo
	echo "3) Testar montagem manual:"
	echo "     cd /mnt/Arquivos"
	echo "     ls"
	echo
	echo "4) Testar link na home:"
	echo "     cd ~/Arquivos"
	echo "     ls"
	echo "=============================================="
}

function instalar_pacotes_ad() {
	apt update
	apt install -y \
		autofs \
		cifs-utils \
		sssd \
		sssd-tools \
		krb5-user \
		adcli \
		samba-common-bin
	echo "Pacotes instalados com sucesso!"
}

function habilitar_servicoes_ad() {
	echo "==> Habilitando serviços autofs e sssd..."

	systemctl enable autofs
	systemctl enable sssd

	systemctl restart sssd
	systemctl restart autofs

	echo "Serviços ativos."
	echo
}

function configurar_autofs() {
	DC="toshyro-dc1.toshyro.local"
	PATH_SHARE="//${DC}/Data/share"
	PATH_USERS="//${DC}/users/&"
	PONTO_MONTAGEM="/mnt/servidor_toshyro"

	sudo mkdir -p "$PONTO_MONTAGEM"
	sudo chown root:"domain users" "$BASE_DIR"
	sudo chmod 1770 "$BASE_DIR"

	echo "==> Configurando autofs..."

	# Backup de segurança
	cp -n /etc/auto.master /etc/auto.master.bak || true

	#
	# /etc/auto.master
	# Diz ao autofs que tudo em /mnt/servidor_toshyro será controlado pelo arquivo /etc/auto.mnt
	#
	# --ghost faz a pasta aparecer visivelmente mesmo antes de montar
	#

	cat >/etc/auto.master <<EOF
${PONTO_MONTAGEM}		/etc/auto.mnt	--ghost
${PONTO_MONTAGEM}/users	/etc/auto.users	--ghost
EOF

	#
	# /etc/auto.mnt
	# Aqui definimos o ponto de montagem:
	#
	#   /mnt/servidor_toshyro/Arquivos  ->  //toshyro-dc1.toshyro.local/Data
	#
	# Opções importantes:
	#   sec=krb5        -> autenticação Kerberos
	#   vers=3.1.1     -> SMB moderno
	#   cruid=\${UID}  -> usa o UID do usuário logado (ESSENCIAL)
	#   multiuser      -> múltiplos usuários simultâneos
	#   serverino      -> evita problemas com inode
	#   cache=none     -> evita cache inconsistente
	#

	cat >/etc/auto.mnt <<EOF
Arquivos -fstype=cifs,sec=krb5,vers=3.1.1,cruid=\${UID},multiuser,serverino,cache=none :${PATH_SHARE}
EOF

	#
	# /etc/auto.users
	# Aqui definimos o ponto de montagem:
	#
	#   /mnt/servidor_toshyro/users/*  ->  //toshyro-dc1.toshyro.local/users/*
	# 	* = nome.usuario
	#
	cat >/etc/auto.users <<EOF
* -fstype=cifs,sec=krb5,vers=3.1.1,cruid=\${UID},multiuser,cache=none :${PATH_USERS}
EOF

	echo "Arquivos do autofs configurados."
	echo

	echo "Configurando Kerberos para usar keyring como cache..."
	if ! grep -q "default_ccache_name" /etc/krb5.conf; then
		sudo tee -a /etc/krb5.conf >/dev/null <<EOF

[libdefaults]
    default_ccache_name = KEYRING:persistent:%{uid}
EOF
		echo "Alteração adicionada em /etc/krb5.conf"
	else
		echo "Kerberos já possui configuração de default_ccache_name."
	fi

	echo "Reiniciando autofs..."
	systemctl restart autofs
}

criar_links_simbolicos() {
	echo "==> Configurando links simbólicos para todos os usuários..."

	cat >/etc/profile.d/links_simbolicos.sh <<EOF
#!/bin/bash
# Cria link simbólico ~/Arquivos -> /mnt/Arquivos se não existir
if [ ! -e "\$HOME/Arquivos" ]; then
    ln -s ${PONTO_MONTAGEM}/Arquivos "\$HOME/Arquivos"
fi


# Link para home remoto individual
if [ -n "\$HOME" ] && [ ! -e "\$HOME/HomeRemoto" ]; then
    ln -s ${PONTO_MONTAGEM}/users/\$USER" "\$HOME/HomeRemoto"
fi

EOF

	chmod +x /etc/profile.d/links_simbolicos.sh

	echo "Links simbólicos configurados."
	echo
}

# --- Menu Principal ---
show_menu() {
	clear
	echo -e "${BLUE}======================================"
	echo "   POS INSTALAÇÃO TOSHYRO"
	echo -e "======================================${NC}"
	echo "1) Instalar Programas"
	echo "2) Ingressar no domínio (AD)"
	echo "0) Sair"
	echo -e "${BLUE}======================================${NC}"
	read -p -r "Escolha uma opção: " choice

	case $choice in
	1)
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
	2) ingressar_dominio ;;
	0) exit 0 ;;
	*)
		echo -e "${YELLOW}Opção inválida!${NC}"
		sleep 2
		show_menu
		;;
	esac

	echo -e "\n${GREEN}Processo concluído!${NC}"
	read -p -r "Pressione Enter para voltar ao menu..."
	show_menu
}

# --- Início do Script ---

echo -e "${BLUE}Deseja atualizar o sistema (update & upgrade) antes de começar? (s/n)${NC}"
read -p -r "> " update_choice
if [[ "$update_choice" =~ ^[Ss]$ ]]; then
	update_system_full
fi

show_menu
