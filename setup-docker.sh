#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_status()  { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error()   { echo -e "${RED}[✗]${NC} $1"; }
print_info()    { echo -e "${BLUE}[i]${NC} $1"; }
print_step()    { echo -e "${CYAN}[→]${NC} $1"; }

# ─────────────────────────────────────────────
# Verificar root
# ─────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    print_error "Este script precisa ser executado como root ou com sudo"
    exit 1
fi

# ─────────────────────────────────────────────
# Variável global do data-root
# ─────────────────────────────────────────────
DOCKER_DATA_ROOT=""

# ─────────────────────────────────────────────
# Pacotes desnecessários para remover
# ─────────────────────────────────────────────
PACOTES_SEGUROS=(
    "gnome-mahjongg" "gnome-mines" "gnome-sudoku" "aisleriot"
    "thunderbird" "rhythmbox" "simple-scan" "cheese"
    "example-content" "popularity-contest" "apport"
    "whoopsie" "ubuntu-report" "deja-dup" "gnome-orca"
    "gnome-chess" "snapd" "snap-confine" "gnome-software-plugin-snap"
    "transmission-common" "gnome-user-docs" "yelp" "totem"
    "gnome-software" "update-notifier" "zeitgeist"
    "speech-dispatcher" "brltty"
)

remover_pacotes() {
    print_status "Removendo pacotes desnecessários..."
    for pacote in "${PACOTES_SEGUROS[@]}"; do
        if dpkg -l 2>/dev/null | grep -q "^ii  $pacote "; then
            print_step "Removendo: $pacote"
            apt-get remove --purge -y "$pacote" 2>/dev/null
        fi
    done
    apt-get autoremove -y
    apt-get autoclean -y
}

# ─────────────────────────────────────────────
# SELECIONAR E VALIDAR O DISCO/CAMINHO
# ─────────────────────────────────────────────
selecionar_data_root() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         CONFIGURAÇÃO DO DISCO PARA O DOCKER              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    print_info "Discos e partições disponíveis no sistema:"
    echo ""
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL 2>/dev/null || fdisk -l 2>/dev/null | grep "^Disk "
    echo ""
    print_info "Espaço em disco atual:"
    df -h --output=target,size,avail,pcent | grep -v "tmpfs\|udev\|cgr" | head -20
    echo ""

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    print_info "TODA a estrutura do Docker será criada dentro deste caminho:"
    print_info "  <SEU_CAMINHO>/containers"
    print_info "  <SEU_CAMINHO>/volumes"
    print_info "  <SEU_CAMINHO>/overlay2  (rootfs dos containers)"
    print_info "  <SEU_CAMINHO>/buildkit"
    print_info "  <SEU_CAMINHO>/network"
    print_info "  <SEU_CAMINHO>/plugins"
    print_info "  <SEU_CAMINHO>/swarm"
    print_info "  <SEU_CAMINHO>/tmp"
    print_info "  ... (nada vai para /var/lib/docker)"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    while true; do
        read -p "$(echo -e ${GREEN})Digite o caminho completo para instalar o Docker (ex: /mnt/dados/docker): $(echo -e ${NC})" INPUT_PATH

        if [ -z "$INPUT_PATH" ]; then
            print_error "O caminho não pode ser vazio. Tente novamente."
            continue
        fi

        # Normalizar caminho (remover barra final)
        INPUT_PATH="${INPUT_PATH%/}"

        # Verificar se o ponto de montagem pai existe ou é acessível
        PARENT_DIR=$(dirname "$INPUT_PATH")
        if [ ! -d "$PARENT_DIR" ]; then
            print_warning "Diretório pai '$PARENT_DIR' não existe."
            read -p "Deseja criar toda a estrutura de diretórios? (s/N): " CRIAR_TUDO
            if [[ ! $CRIAR_TUDO =~ ^[Ss]$ ]]; then
                continue
            fi
        fi

        # Criar diretório
        if mkdir -p "$INPUT_PATH" 2>/dev/null; then
            print_status "Diretório '$INPUT_PATH' criado/verificado."
        else
            print_error "Não foi possível criar '$INPUT_PATH'. Verifique permissões ou se o disco está montado."
            continue
        fi

        # Verificar espaço disponível (mínimo 10GB recomendado)
        ESPACO_DISPONIVEL=$(df "$INPUT_PATH" 2>/dev/null | awk 'NR==2 {print $4}')
        ESPACO_GB=$(( ESPACO_DISPONIVEL / 1024 / 1024 ))
        if [ "$ESPACO_GB" -lt 10 ]; then
            print_warning "Atenção: apenas ${ESPACO_GB}GB disponíveis em '$INPUT_PATH'."
            print_warning "Recomendamos pelo menos 10GB para o Docker."
            read -p "Continuar mesmo assim? (s/N): " CONTINUAR
            if [[ ! $CONTINUAR =~ ^[Ss]$ ]]; then
                continue
            fi
        else
            print_status "Espaço disponível: ${ESPACO_GB}GB ✅"
        fi

        DOCKER_DATA_ROOT="$INPUT_PATH"
        echo ""
        print_status "Data-root definido: ${DOCKER_DATA_ROOT}"
        break
    done
}

# ─────────────────────────────────────────────
# INSTALAR DOCKER (apontando para o data-root)
# ─────────────────────────────────────────────
instalar_docker() {
    print_status "Instalando Docker..."

    # Remover versões antigas
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Instalar dependências
    apt-get update
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common

    # Adicionar repositório oficial do Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # ── Parar o Docker antes de configurar o data-root ──────────────
    print_step "Parando Docker para configurar data-root..."
    systemctl stop docker docker.socket 2>/dev/null || true
    sleep 2

    # ── Garantir que /var/lib/docker NÃO será usado ──────────────────
    # Remover diretório padrão se estiver vazio (recém-criado pelo pacote)
    if [ -d "/var/lib/docker" ]; then
        ARQUIVOS_DENTRO=$(find /var/lib/docker -mindepth 1 2>/dev/null | wc -l)
        if [ "$ARQUIVOS_DENTRO" -eq 0 ]; then
            rm -rf /var/lib/docker
            print_step "Diretório padrão /var/lib/docker removido (estava vazio)."
        else
            BACKUP_DIR="/var/lib/docker.backup.$(date +%Y%m%d_%H%M%S)"
            mv /var/lib/docker "$BACKUP_DIR"
            print_warning "Dados existentes movidos para backup: $BACKUP_DIR"
        fi
    fi

    # ── Criar link simbólico: /var/lib/docker → data-root ────────────
    # Isso garante que QUALQUER coisa que tente usar /var/lib/docker
    # será redirecionada automaticamente para o seu disco
    mkdir -p "$DOCKER_DATA_ROOT"
    chmod 711 "$DOCKER_DATA_ROOT"
    ln -sf "$DOCKER_DATA_ROOT" /var/lib/docker
    print_status "Symlink criado: /var/lib/docker → $DOCKER_DATA_ROOT"

    # ── Criar daemon.json com data-root explícito ─────────────────────
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
  "data-root": "$DOCKER_DATA_ROOT",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
    print_status "daemon.json configurado com data-root: $DOCKER_DATA_ROOT"

    # ── Iniciar Docker ────────────────────────────────────────────────
    print_step "Iniciando Docker com data-root personalizado..."
    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker
    sleep 5

    # ── Verificar ────────────────────────────────────────────────────
    DOCKER_ROOT_ATUAL=$(docker info 2>/dev/null | grep 'Docker Root Dir' | awk -F': ' '{print $2}' | tr -d ' ')

    if [ "$DOCKER_ROOT_ATUAL" = "$DOCKER_DATA_ROOT" ]; then
        print_status "✅ Docker instalado e configurado em: $DOCKER_DATA_ROOT"
    else
        print_error "❌ Docker Root Dir reportado: '$DOCKER_ROOT_ATUAL'"
        print_error "   Esperado: '$DOCKER_DATA_ROOT'"
        print_error "   Verifique /etc/docker/daemon.json e reinicie: systemctl restart docker"
        exit 1
    fi

    # Mostrar estrutura criada no disco
    echo ""
    print_info "Estrutura criada no disco ($DOCKER_DATA_ROOT):"
    ls -la "$DOCKER_DATA_ROOT" 2>/dev/null
    echo ""
}

# ─────────────────────────────────────────────
# INSTALAR DOCKER COMPOSE (plugin v2)
# ─────────────────────────────────────────────
instalar_docker_compose() {
    print_status "Verificando Docker Compose..."

    # O docker-compose-plugin já foi instalado junto com o Docker acima
    if docker compose version &>/dev/null; then
        print_status "Docker Compose (plugin v2): $(docker compose version)"
    fi

    # Instalar também o binário standalone para compatibilidade com scripts antigos
    print_step "Instalando docker-compose standalone (compatibilidade)..."
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

    if docker-compose --version &>/dev/null; then
        print_status "docker-compose standalone: $(docker-compose --version)"
    else
        print_warning "Falha ao instalar docker-compose standalone. O plugin v2 ainda funciona via 'docker compose'."
    fi
}

# ─────────────────────────────────────────────
# OTIMIZAR SISTEMA
# ─────────────────────────────────────────────
otimizar_sistema() {
    print_status "Otimizando sistema para Docker..."

    cat > /etc/sysctl.d/99-docker.conf << EOF
# Otimizações para Docker
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.ip_local_port_range = 1024 65535
vm.swappiness = 10
vm.overcommit_memory = 1
EOF
    sysctl -p /etc/sysctl.d/99-docker.conf 2>/dev/null

    # Limites de arquivos
    grep -qxF "* soft nofile 65536" /etc/security/limits.conf || echo "* soft nofile 65536" >> /etc/security/limits.conf
    grep -qxF "* hard nofile 65536" /etc/security/limits.conf || echo "* hard nofile 65536" >> /etc/security/limits.conf
    grep -qxF "* soft nproc 65536"  /etc/security/limits.conf || echo "* soft nproc 65536"  >> /etc/security/limits.conf
    grep -qxF "* hard nproc 65536"  /etc/security/limits.conf || echo "* hard nproc 65536"  >> /etc/security/limits.conf

    # Adicionar usuário ao grupo docker
    REAL_USER="${SUDO_USER:-$USER}"
    if id "$REAL_USER" &>/dev/null && [ "$REAL_USER" != "root" ]; then
        usermod -aG docker "$REAL_USER"
        print_status "Usuário '$REAL_USER' adicionado ao grupo docker"
    fi
}

# ─────────────────────────────────────────────
# RESUMO FINAL
# ─────────────────────────────────────────────
mostrar_resumo() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                  RESUMO DA INSTALAÇÃO                   ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    print_info "Docker:          $(docker --version 2>/dev/null || echo 'Não instalado')"
    print_info "Docker Compose:  $(docker compose version 2>/dev/null || echo 'Não instalado')"
    print_info "Data-root:       $(docker info 2>/dev/null | grep 'Docker Root Dir' | awk -F': ' '{print $2}')"
    print_info "Symlink:         /var/lib/docker → $DOCKER_DATA_ROOT"
    echo ""
    print_info "Estrutura no disco:"
    ls -lh "$DOCKER_DATA_ROOT" 2>/dev/null
    echo ""
    print_info "Uso do disco:"
    df -h "$DOCKER_DATA_ROOT"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    print_warning "⚠️  Faça logout/login (ou execute 'newgrp docker') para usar Docker sem sudo"
    print_warning "⚠️  Reiniciar o sistema é recomendado para aplicar todos os limites"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
main() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Ubuntu Server — Setup Docker com disco customizado   ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # 1. Selecionar disco/caminho ANTES de qualquer instalação
    selecionar_data_root

    # 2. Atualizar sistema
    print_status "Atualizando sistema..."
    apt-get update
    apt-get upgrade -y

    # 3. Remover pacotes desnecessários
    remover_pacotes

    # 4. Instalar Docker já apontando para o data-root escolhido
    instalar_docker

    # 5. Instalar Docker Compose
    instalar_docker_compose

    # 6. Otimizar sistema
    otimizar_sistema

    # 7. Limpar cache
    print_status "Limpando cache APT..."
    apt-get clean
    docker system prune -f 2>/dev/null || true

    # 8. Resumo
    mostrar_resumo

    print_status "✅ Instalação concluída! Tudo o que o Docker gravar irá para: $DOCKER_DATA_ROOT"
}

main "$@"
