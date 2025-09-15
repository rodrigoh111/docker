#!/bin/bash
set -e

echo "[INFO] Aplicando otimizações no Ubuntu para uso com Docker..."

# Habilitar encaminhamento de pacotes (necessário para redes Docker)
cat <<EOF | sudo tee /etc/sysctl.d/99-docker.conf
# Habilitar forwarding IPv4 e IPv6
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Melhorar performance de conexões TCP
net.core.somaxconn = 1024
net.ipv4.tcp_tw_reuse = 1

# Aumentar limites de arquivos (importante para containers pesados)
fs.file-max = 2097152
EOF
sudo sysctl --system

echo "[INFO] Ajustando limites de processos e arquivos para containers..."
cat <<EOF | sudo tee /etc/security/limits.d/99-docker.conf
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
EOF

# Ajustar journald para não lotar o disco
echo "[INFO] Configurando journald para limitar logs..."
sudo mkdir -p /etc/systemd/journald.conf.d
cat <<EOF | sudo tee /etc/systemd/journald.conf.d/99-docker.conf
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=200M
EOF
sudo systemctl restart systemd-journald

# Ajustar swappiness para containers (usar menos swap)
echo "[INFO] Ajustando swappiness para reduzir uso de swap..."
sudo sysctl -w vm.swappiness=10
echo "vm.swappiness=10" | sudo tee /etc/sysctl.d/99-swappiness.conf

# Garantir que cgroups estejam ativados (essencial para Docker)
echo "[INFO] Garantindo cgroups habilitados..."
if ! grep -q "systemd.unified_cgroup_hierarchy" /etc/default/grub; then
  sudo sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 systemd.unified_cgroup_hierarchy=1"/' /etc/default/grub
  sudo update-grub
  echo "[INFO] Reinicie o servidor para aplicar cgroups unificados."
fi

echo "[INFO] Otimizações aplicadas com sucesso!"
