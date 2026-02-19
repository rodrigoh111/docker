#!/bin/bash
set -e

echo "[INFO] Instalando Docker e Docker Compose..."

# ========= CONFIGURE AQUI =========
DATA_ROOT="/mnt/docker"
CONTAINERD_ROOT="$DATA_ROOT/containerd"
# ===================================

# Dependências
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

# Chave GPG
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Repositório Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instala Docker + containerd
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Criar diretórios antes de configurar
sudo mkdir -p $DATA_ROOT
sudo mkdir -p $CONTAINERD_ROOT

# ========= CONFIGURAR CONTAINERD =========
echo "[INFO] Configurando containerd root em: $CONTAINERD_ROOT"

sudo mkdir -p /etc/containerd

sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

sudo sed -i "s|root = \".*\"|root = \"$CONTAINERD_ROOT\"|" /etc/containerd/config.toml
sudo sed -i "s|state = \".*\"|state = \"/run/containerd\"|" /etc/containerd/config.toml

# ========= CONFIGURAR DOCKER =========
echo "[INFO] Configurando Docker data-root em: $DATA_ROOT"

cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "data-root": "$DATA_ROOT",
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# ========= REINICIAR SERVIÇOS =========
sudo systemctl daemon-reexec
sudo systemctl enable containerd
sudo systemctl enable docker

sudo systemctl restart containerd
sudo systemctl restart docker

# Criar grupo docker
sudo groupadd docker || true
sudo usermod -aG docker $USER

# ========= TESTE =========
echo "[INFO] Testando Docker..."
docker --version
docker compose version || docker-compose --version

echo ""
echo "[INFO] Instalação concluída!"
echo "⚠️ Reinicie o sistema ou faça logout/login para usar Docker sem sudo."
echo "⚡ Docker root: $DATA_ROOT"
echo "⚡ containerd root: $CONTAINERD_ROOT"
