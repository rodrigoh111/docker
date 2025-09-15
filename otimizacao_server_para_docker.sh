#!/bin/bash

# Script de Otimização para Servidor Docker
# Descrição: Instala Docker, Docker Compose e otimiza o sistema para containers
# Autor: Rodrigoh
# Versão: 2.0
# Aviso: Para servidores Ubuntu 20.04/22.04 LTS

set -euo pipefail

# Cores para output
VERMELHO='\033[0;31m'
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
AZUL='\033[0;34m'
NC='\033[0m' # No Color

# Verificar se está executando como root
if [ "$EUID" -ne 0 ]; then
    echo -e "${VERMELHO}Por favor, execute como root usando sudo!${NC}"
    exit 1
fi

# Informações do sistema
echo -e "${AZUL}=== Otimização para Servidor Docker ===${NC}"
echo -e "Hostname: $(hostname)"
echo -e "Versão do Ubuntu: $(lsb_release -d | cut -f2)"
echo -e "Kernel: $(uname -r)"
echo -e "Memória: $(free -h | awk '/^Mem:/ {print $2}')"
echo -e "CPU: $(nproc) cores"
echo

# Confirmar execução
read -p "Deseja continuar com a instalação e otimização para Docker? (s/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo -e "${AMARELO}Operação cancelada.${NC}"
    exit 0
fi

# Atualizar sistema
echo -e "${AZUL}Atualizando sistema...${NC}"
apt update
apt upgrade -y

# Instalar dependências básicas
echo -e "${AZUL}Instalando dependências...${NC}"
apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    gnupg \
    lsb-release \
    git \
    htop \
    iotop \
    nethogs \
    jq

# Remover versões antigas do Docker
echo -e "${AZUL}Removendo versões antigas do Docker...${NC}"
apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Adicionar repositório oficial do Docker
echo -e "${AZUL}Adicionando repositório do Docker...${NC}"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker Engine
echo -e "${AZUL}Instalando Docker Engine...${NC}"
apt update
apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Instalar Docker Compose standalone (compatibilidade)
echo -e "${AZUL}Instalando Docker Compose...${NC}"
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Configurar usuário para usar Docker sem sudo
echo -e "${AZUL}Configurando usuário para Docker...${NC}"
usermod -aG docker $SUDO_USER

# Configurar daemon do Docker para melhor performance
echo -e "${AZUL}Otimizando daemon do Docker...${NC}"
mkdir -p /etc/docker

cat > /etc/docker/daemon.json << 'EOL'
{
  "data-root": "/var/lib/docker",
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  },
  "live-restore": true,
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "experimental": false,
  "debug": false,
  "metrics-addr": "127.0.0.1:9323",
  "exec-opts": ["native.cgroupdriver=systemd"],
  "dns": ["8.8.8.8", "1.1.1.1"],
  "dns-opts": ["timeout:2", "attempts:2"]
}
EOL

# Configurar otimizações de kernel para Docker
echo -e "${AZUL}Configurando otimizações de kernel...${NC}"

cat > /etc/sysctl.d/99-docker-optimizations.conf << 'EOL'
# ============================================================================
# OTIMIZAÇÕES PARA DOCKER/CONTAINERS
# ============================================================================

# Networking
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.tcp_tw_reuse = 1
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_fin_timeout = 30

# Memory and File Systems
vm.swappiness = 10
vm.overcommit_memory = 1
vm.overcommit_ratio = 50
vm.max_map_count = 262144
fs.file-max = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
fs.aio-max-nr = 1048576

# Container-specific optimizations
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.nf_conntrack_max = 131072

# Security
kernel.keys.maxkeys = 2000
kernel.keys.maxbytes = 20000
EOL

# Configurar limites do sistema para containers
echo -e "${AZUL}Configurando limites do sistema...${NC}"

cat > /etc/security/limits.d/99-docker.conf << 'EOL'
# Limites para containers Docker
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65536
* hard nproc 65536
* soft memlock unlimited
* hard memlock unlimited
root soft nofile 1048576
root hard nofile 1048576
EOL

# Configurar cgroups v2 (se necessário)
echo -e "${AZUL}Configurando cgroups...${NC}"
if [ ! -f /etc/default/grub.d/cgroup.cfg ]; then
    echo 'GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1 cgroup_enable=memory swapaccount=1"' > /etc/default/grub.d/cgroup.cfg
    update-grub
fi

# Configurar swapiness para containers
echo -e "${AZUL}Configurando memória swap...${NC}"
echo 'vm.swappiness=10' >> /etc/sysctl.conf

# Criar diretórios para volumes Docker
echo -e "${AZUL}Criando diretórios para volumes...${NC}"
mkdir -p /docker/volumes
mkdir -p /docker/compose
chmod -R 775 /docker
chown -R $SUDO_USER:docker /docker

# Configurar logging do Docker
echo -e "${AZUL}Configurando sistema de logs...${NC}"
mkdir -p /var/log/docker
cat > /etc/logrotate.d/docker << 'EOL'
/var/log/docker/*.log {
  rotate 7
  daily
  compress
  size=100M
  missingok
  delaycompress
  copytruncate
}
EOL

# Configurar monitoramento
echo -e "${AZUL}Instalando ferramentas de monitoramento...${NC}"
apt install -y \
    prometheus-node-exporter \
    ctop

# Instalar lazydocker (terminal UI para Docker)
LAZYDOCKER_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | jq -r ".tag_name")
curl -L "https://github.com/jesseduffield/lazydocker/releases/download/${LAZYDOCKER_VERSION}/lazydocker_${LAZYDOCKER_VERSION#v}_Linux_x86_64.tar.gz" \
    | tar -xz -C /usr/local/bin lazydocker

# Reiniciar serviços
echo -e "${AZUL}Reiniciando serviços...${NC}"
systemctl daemon-reload
systemctl restart docker
systemctl enable docker
sysctl -p /etc/sysctl.d/99-docker-optimizations.conf

# Limpeza final
echo -e "${AZUL}Limpando sistema...${NC}"
apt autoremove -y
apt clean

# Verificar instalação
echo -e "${AZUL}Verificando instalação...${NC}"
docker --version
docker-compose --version
docker info | grep -E "Storage Driver|Data Root"

# Testar funcionamento
echo -e "${AZUL}Testando Docker...${NC}"
docker run --rm hello-world

# Informações finais
echo -e "${VERDE}
=== INSTALAÇÃO DO DOCKER CONCLUÍDA ===

✅ Docker Engine instalado
✅ Docker Compose instalado  
✅ Sistema otimizado para containers
✅ Configurações de kernel aplicadas
✅ Limites do sistema ajustados

📊 Informações:
- Docker: $(docker --version)
- Docker Compose: $(docker-compose --version)
- Storage Driver: overlay2
- Data Root: /var/lib/docker

🔧 Comandos úteis:
- docker ps                          # Listar containers
- docker-compose up -d               # Subir stack compose
- docker stats                       # Estatísticas em tempo real
- ctop                               # Monitoramento de containers
- lazydocker                         # Interface terminal para Docker

📋 Próximos passos:
1. Faça logout e login para usar Docker sem sudo
2. Crie seus docker-compose.yml em /docker/compose/
3. Configure backups dos volumes em /docker/volumes/

⚡ Reinicie o sistema para aplicar todas as otimizações!
${NC}"

# Perguntar sobre reinicialização
read -p "Deseja reiniciar o sistema agora? (s/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    echo -e "${AZUL}Reiniciando sistema...${NC}"
    reboot
else
    echo -e "${AMARELO}Lembre-se de reiniciar para aplicar todas as otimizações.${NC}"
fi
