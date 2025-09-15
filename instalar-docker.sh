#!/bin/bash
set -e

echo "[INFO] Instalando Docker e Docker Compose..."

# Variável para o novo local do data-root (edite se quiser mudar)
DATA_ROOT="/mnt/docker"

# Dependências
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

# Chave GPG
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Repositório Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalação Docker Engine + Compose
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Ativar serviço
sudo systemctl enable docker
sudo systemctl start docker

# Criar grupo docker
sudo groupadd docker || true
sudo usermod -aG docker $USER

# Configurar data-root
echo "[INFO] Configurando Docker para usar data-root em: $DATA_ROOT"
sudo mkdir -p $DATA_ROOT
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

# Reiniciar serviço para aplicar configs
sudo systemctl daemon-reexec
sudo systemctl restart docker

# Teste de instalação
echo "[INFO] Testando Docker..."
docker --version
docker compose version || docker-compose --version

echo "[INFO] Instalação concluída!"
echo "⚠️ Reinicie o sistema ou faça logout/login para usar o Docker sem sudo."
echo "⚡ O data-root do Docker está configurado em: $DATA_ROOT"
