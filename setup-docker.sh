#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
# Setup Samba Otimizado — Ubuntu Server
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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
# Variáveis globais
# ─────────────────────────────────────────────
SAMBA_WORKGROUP="WORKGROUP"
SAMBA_SERVERNAME=""
SAMBA_SHARES=()          # array de "nome:caminho:descricao:somente_leitura:usuarios"
SAMBA_USERS=()           # array de "usuario:senha"
SMB_CONF="/etc/samba/smb.conf"
SMB_CONF_BACKUP="/etc/samba/smb.conf.backup.$(date +%Y%m%d_%H%M%S)"

# ─────────────────────────────────────────────
# INSTALAR SAMBA
# ─────────────────────────────────────────────
instalar_samba() {
    print_status "Instalando Samba e utilitários..."

    apt-get update
    apt-get install -y \
        samba \
        samba-common-bin \
        samba-vfs-modules \
        attr \
        acl \
        winbind \
        libnss-winbind \
        libpam-winbind

    # Fazer backup do smb.conf original se existir
    if [ -f "$SMB_CONF" ]; then
        cp "$SMB_CONF" "$SMB_CONF_BACKUP"
        print_info "Backup do smb.conf original: $SMB_CONF_BACKUP"
    fi

    print_status "Samba instalado com sucesso!"
}

# ─────────────────────────────────────────────
# COLETAR CONFIGURAÇÕES
# ─────────────────────────────────────────────
coletar_configuracoes() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           CONFIGURAÇÃO DO SERVIDOR SAMBA                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Nome do servidor
    HOSTNAME_ATUAL=$(hostname -s 2>/dev/null || echo "servidor")
    read -p "Nome do servidor Samba [${HOSTNAME_ATUAL}]: " INPUT_SERVER
    SAMBA_SERVERNAME="${INPUT_SERVER:-$HOSTNAME_ATUAL}"

    # Workgroup
    read -p "Workgroup/Domínio [WORKGROUP]: " INPUT_WG
    SAMBA_WORKGROUP="${INPUT_WG:-WORKGROUP}"

    echo ""
    print_info "Servidor: $SAMBA_SERVERNAME | Workgroup: $SAMBA_WORKGROUP"
    echo ""

    # ── Usuários Samba ──────────────────────────────────────────────
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    print_info "USUÁRIOS SAMBA"
    print_info "Usuários Samba são separados do sistema. Informe quais criar."
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    while true; do
        read -p "Nome do usuário Samba (Enter para pular): " SMB_USER
        [ -z "$SMB_USER" ] && break

        read -s -p "Senha para '$SMB_USER': " SMB_PASS
        echo ""
        read -s -p "Confirme a senha: " SMB_PASS2
        echo ""

        if [ "$SMB_PASS" != "$SMB_PASS2" ]; then
            print_error "Senhas não conferem. Tente novamente."
            continue
        fi

        SAMBA_USERS+=("${SMB_USER}:${SMB_PASS}")
        print_status "Usuário '$SMB_USER' adicionado."

        read -p "Adicionar outro usuário? (s/N): " MAIS_USERS
        [[ ! $MAIS_USERS =~ ^[Ss]$ ]] && break
    done

    # ── Compartilhamentos ──────────────────────────────────────────
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    print_info "COMPARTILHAMENTOS"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    while true; do
        read -p "Nome do compartilhamento (ex: dados, backup, fotos): " SHARE_NAME
        [ -z "$SHARE_NAME" ] && break

        read -p "Caminho completo do diretório (ex: /mnt/disco/dados): " SHARE_PATH
        if [ -z "$SHARE_PATH" ]; then
            print_error "Caminho não pode ser vazio."
            continue
        fi

        read -p "Descrição do compartilhamento: " SHARE_DESC
        SHARE_DESC="${SHARE_DESC:-$SHARE_NAME}"

        read -p "Somente leitura? (s/N): " SHARE_RO
        if [[ $SHARE_RO =~ ^[Ss]$ ]]; then
            SHARE_READONLY="yes"
        else
            SHARE_READONLY="no"
        fi

        read -p "Acesso público (sem senha)? (s/N): " SHARE_PUBLIC
        if [[ $SHARE_PUBLIC =~ ^[Ss]$ ]]; then
            SHARE_GUEST="yes"
            SHARE_USERS="nobody"
        else
            SHARE_GUEST="no"
            # Listar usuários criados
            if [ ${#SAMBA_USERS[@]} -gt 0 ]; then
                print_info "Usuários disponíveis:"
                for u in "${SAMBA_USERS[@]}"; do
                    echo "  - ${u%%:*}"
                done
            fi
            read -p "Usuários com acesso (separados por vírgula, vazio = todos): " SHARE_USERS
        fi

        # Criar diretório se não existir
        mkdir -p "$SHARE_PATH"
        chmod 0770 "$SHARE_PATH"

        SAMBA_SHARES+=("${SHARE_NAME}:${SHARE_PATH}:${SHARE_DESC}:${SHARE_READONLY}:${SHARE_GUEST}:${SHARE_USERS}")
        print_status "Compartilhamento '$SHARE_NAME' → '$SHARE_PATH' adicionado."

        read -p "Adicionar outro compartilhamento? (s/N): " MAIS_SHARES
        [[ ! $MAIS_SHARES =~ ^[Ss]$ ]] && break
    done
}

# ─────────────────────────────────────────────
# CRIAR smb.conf OTIMIZADO
# ─────────────────────────────────────────────
criar_smb_conf() {
    print_status "Gerando smb.conf otimizado..."

    # Detectar total de RAM para ajustar cache
    RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    RAM_MB=$(( RAM_KB / 1024 ))

    # socket_options e cache proporcional à RAM
    if [ "$RAM_MB" -ge 8192 ]; then
        READ_RAW_SIZE=65536
        WRITE_RAW_SIZE=65536
        MAX_XMIT=65536
        SOCKET_OPTS="TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072"
    elif [ "$RAM_MB" -ge 4096 ]; then
        READ_RAW_SIZE=65536
        WRITE_RAW_SIZE=65536
        MAX_XMIT=65536
        SOCKET_OPTS="TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=65536 SO_SNDBUF=65536"
    else
        READ_RAW_SIZE=32768
        WRITE_RAW_SIZE=32768
        MAX_XMIT=32768
        SOCKET_OPTS="TCP_NODELAY IPTOS_LOWDELAY"
    fi

    # Número de CPUs para asyncio
    NCPUS=$(nproc 2>/dev/null || echo 2)
    ASYNREAD=$(( NCPUS * 4 ))
    ASYNWRITE=$(( NCPUS * 4 ))

    cat > "$SMB_CONF" << EOF
# ═══════════════════════════════════════════════════════════════════════════════
#  smb.conf — Servidor: ${SAMBA_SERVERNAME}
#  Gerado automaticamente em: $(date)
#  RAM detectada: ${RAM_MB}MB | CPUs: ${NCPUS}
# ═══════════════════════════════════════════════════════════════════════════════

[global]

# ── Identidade ────────────────────────────────────────────────────────────────
    workgroup             = ${SAMBA_WORKGROUP}
    server string         = ${SAMBA_SERVERNAME} Samba Server
    netbios name          = ${SAMBA_SERVERNAME}
    server role           = standalone server

# ── Protocolo e segurança ─────────────────────────────────────────────────────
    # Usar apenas SMB2 e SMB3 (SMB1 é inseguro e lento — desabilitado)
    server min protocol   = SMB2
    server max protocol   = SMB3
    client min protocol   = SMB2
    client max protocol   = SMB3

    # Autenticação
    security              = user
    passdb backend        = tdbsam
    map to guest          = Bad User
    guest account         = nobody

    # NTLMv2 apenas (mais seguro)
    ntlm auth             = ntlmv2-only
    lanman auth           = no
    client NTLMv2 auth    = yes

# ── Performance ───────────────────────────────────────────────────────────────
    # I/O assíncrono — melhora throughput em discos lentos/rotativos
    aio read size         = 1
    aio write size        = 1
    aio write behind      = yes

    # Fila de I/O assíncrono proporcional às CPUs
    async smb echo handler = yes

    # Buffer e tamanho de transferência
    max xmit              = ${MAX_XMIT}
    read raw              = yes
    write raw             = yes
    read size             = ${READ_RAW_SIZE}

    # Socket otimizado para rede local
    socket options        = ${SOCKET_OPTS}

    # Keepalive e timeout de conexão
    keepalive             = 30
    deadtime              = 15

    # Cache de diretório (reduz stat() no disco)
    stat cache            = yes
    stat cache size       = 1024

    # Cache de ACL/atributos
    getwd cache           = yes

    # Número de processos smbd em stand-by (reduz tempo de conexão)
    prefork children      = 4

    # Oplocks: permite cache no cliente — MELHORA MUITO a performance
    # Desabilite apenas se tiver problemas de consistência entre clientes
    oplocks               = yes
    level2 oplocks        = yes
    kernel oplocks        = no

    # Lease mode (SMB3) — reduz round-trips de rede
    smb2 leases           = yes

    # Não verificar permissões POSIX desnecessariamente
    acl check permissions = yes

    # Sincronização de disco (desligar melhora write, mas pode perder dados em crash)
    # Mantenha "yes" para segurança, mude para "no" só em benchmarks
    strict sync           = no
    sync always           = no

    # Writeback delay — agrupa escritas pequenas (melhora SSD e HDD)
    write cache size      = 2097152

# ── Logging ───────────────────────────────────────────────────────────────────
    # Log mínimo em produção (log level 1 = erros apenas)
    log level             = 1
    log file              = /var/log/samba/log.%m
    max log size          = 5120
    logging               = file

# ── Misc ──────────────────────────────────────────────────────────────────────
    # Suporte a nomes longos e unicode
    unix charset          = UTF-8
    dos charset           = CP850

    # Não anunciar impressoras
    load printers         = no
    printing              = bsd
    printcap name         = /dev/null
    disable spoolss       = yes

    # Desabilitar CUPS e impressão
    cups options          = raw

    # Ocultar arquivos de sistema do Unix que o Windows não precisa ver
    veto files            = /.DS_Store/.Trash/.hidden/lost+found/

    # Não criar arquivos .DS_Store e thumbs.db
    delete veto files     = yes

    # Resolução de nomes via mDNS/Avahi (para macOS/Linux)
    multicast dns register = yes

    # Tempo de resposta de browse
    os level              = 20
    preferred master      = no
    local master          = yes
    domain master         = no

    # Detecção automática de interfaces de rede
    bind interfaces only  = no

EOF

    # ── Compartilhamentos dinâmicos ────────────────────────────────
    for share_entry in "${SAMBA_SHARES[@]}"; do
        IFS=':' read -r S_NAME S_PATH S_DESC S_READONLY S_GUEST S_USERS <<< "$share_entry"

        cat >> "$SMB_CONF" << EOF

# ─────────────────────────────────────────────
[${S_NAME}]
    comment               = ${S_DESC}
    path                  = ${S_PATH}
    browseable            = yes
    read only             = ${S_READONLY}
    guest ok              = ${S_GUEST}
    create mask           = 0664
    directory mask        = 0775
    force create mode     = 0664
    force directory mode  = 0775

    # Performance por share
    oplocks               = yes
    level2 oplocks        = yes
    aio read size         = 1
    aio write size        = 1

EOF

        # Adicionar usuários se definidos
        if [ -n "$S_USERS" ] && [ "$S_USERS" != "nobody" ]; then
            echo "    valid users           = ${S_USERS}" >> "$SMB_CONF"
            echo "    write list            = ${S_USERS}" >> "$SMB_CONF"
        fi

        # Se readonly, não adicionar write list
        if [ "$S_READONLY" = "yes" ]; then
            sed -i "/write list.*${S_USERS}/d" "$SMB_CONF" 2>/dev/null || true
        fi
    done

    # Validar o smb.conf gerado
    if testparm -s "$SMB_CONF" &>/dev/null; then
        print_status "✅ smb.conf validado com sucesso pelo testparm"
    else
        print_warning "⚠️  testparm reportou avisos — verifique com: testparm $SMB_CONF"
    fi
}

# ─────────────────────────────────────────────
# CRIAR USUÁRIOS SAMBA
# ─────────────────────────────────────────────
criar_usuarios() {
    if [ ${#SAMBA_USERS[@]} -eq 0 ]; then
        return
    fi

    print_status "Criando usuários Samba..."

    for user_entry in "${SAMBA_USERS[@]}"; do
        SMB_U="${user_entry%%:*}"
        SMB_P="${user_entry#*:}"

        # Criar usuário do sistema se não existir (sem shell de login)
        if ! id "$SMB_U" &>/dev/null; then
            useradd -M -s /sbin/nologin "$SMB_U"
            print_step "Usuário de sistema '$SMB_U' criado (sem login)."
        fi

        # Adicionar/atualizar no banco Samba
        echo -e "${SMB_P}\n${SMB_P}" | smbpasswd -a -s "$SMB_U"
        smbpasswd -e "$SMB_U"
        print_status "Usuário Samba '$SMB_U' configurado."
    done
}

# ─────────────────────────────────────────────
# AJUSTAR PERMISSÕES DOS COMPARTILHAMENTOS
# ─────────────────────────────────────────────
ajustar_permissoes() {
    print_status "Ajustando permissões dos compartilhamentos..."

    for share_entry in "${SAMBA_SHARES[@]}"; do
        IFS=':' read -r S_NAME S_PATH S_DESC S_READONLY S_GUEST S_USERS <<< "$share_entry"

        if [ ! -d "$S_PATH" ]; then
            mkdir -p "$S_PATH"
        fi

        if [ "$S_GUEST" = "yes" ]; then
            chmod 0777 "$S_PATH"
            chown nobody:nogroup "$S_PATH" 2>/dev/null || chown nobody:nobody "$S_PATH" 2>/dev/null || true
        else
            chmod 0770 "$S_PATH"
            # Atribuir grupo samba se existir, senão root
            if getent group sambashare &>/dev/null; then
                chgrp sambashare "$S_PATH" 2>/dev/null || true
            fi
        fi

        print_step "Permissões aplicadas em: $S_PATH"
    done
}

# ─────────────────────────────────────────────
# CONFIGURAR E INICIAR SERVIÇOS
# ─────────────────────────────────────────────
configurar_servicos() {
    print_status "Configurando e iniciando serviços Samba..."

    systemctl daemon-reload

    for svc in smbd nmbd; do
        systemctl enable "$svc"
        systemctl restart "$svc"
        if systemctl is-active --quiet "$svc"; then
            print_status "✅ $svc está rodando"
        else
            print_error "❌ $svc falhou ao iniciar — verifique: journalctl -u $svc"
        fi
    done

    # Ajustar kernel para melhor I/O de rede com Samba
    print_step "Ajustando parâmetros de kernel para Samba..."
    cat > /etc/sysctl.d/99-samba.conf << 'SYSCTL'
# Otimizações de rede para Samba
net.core.rmem_max          = 16777216
net.core.wmem_max          = 16777216
net.core.rmem_default      = 1048576
net.core.wmem_default      = 1048576
net.ipv4.tcp_rmem          = 4096 1048576 16777216
net.ipv4.tcp_wmem          = 4096 1048576 16777216
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps    = 1
net.ipv4.tcp_sack          = 1
net.ipv4.tcp_no_metrics_save = 1
SYSCTL
    sysctl -p /etc/sysctl.d/99-samba.conf 2>/dev/null

    # Abrir portas no UFW se ativo
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        print_step "Abrindo portas Samba no UFW..."
        ufw allow samba
        print_status "Regras UFW para Samba adicionadas"
    fi
}

# ─────────────────────────────────────────────
# RESUMO FINAL
# ─────────────────────────────────────────────
mostrar_resumo() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                  RESUMO DO SAMBA                        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    print_info "Versão: $(smbd --version 2>/dev/null)"
    print_info "Servidor: $SAMBA_SERVERNAME | Workgroup: $SAMBA_WORKGROUP"
    echo ""

    print_info "Compartilhamentos configurados:"
    for share_entry in "${SAMBA_SHARES[@]}"; do
        IFS=':' read -r S_NAME S_PATH S_DESC S_READONLY S_GUEST S_USERS <<< "$share_entry"
        ACESSO="privado"
        [ "$S_GUEST" = "yes" ] && ACESSO="público"
        RW="leitura/escrita"
        [ "$S_READONLY" = "yes" ] && RW="somente leitura"
        echo "  \\\\${SAMBA_SERVERNAME}\\${S_NAME}  →  ${S_PATH}  [${RW}, ${ACESSO}]"
    done

    echo ""
    print_info "Usuários Samba criados:"
    for user_entry in "${SAMBA_USERS[@]}"; do
        echo "  - ${user_entry%%:*}"
    done

    echo ""
    print_info "Status dos serviços:"
    systemctl is-active smbd && echo "  smbd: ✅ rodando" || echo "  smbd: ❌ parado"
    systemctl is-active nmbd && echo "  nmbd: ✅ rodando" || echo "  nmbd: ❌ parado"

    echo ""
    print_info "Para verificar compartilhamentos ativos:"
    echo "  smbclient -L localhost -U%"
    echo ""
    print_info "Para testar acesso:"
    echo "  smbclient //localhost/<share> -U <usuario>"
    echo ""
    print_info "Para ver performance em tempo real:"
    echo "  smbstatus"
    echo ""
    print_info "Configuração completa em: $SMB_CONF"
    echo ""
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
main() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        Ubuntu Server — Setup Samba Otimizado             ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Atualizar sistema
    print_status "Atualizando lista de pacotes..."
    apt-get update

    # Instalar Samba
    instalar_samba

    # Coletar configurações interativamente
    coletar_configuracoes

    # Gerar smb.conf otimizado
    criar_smb_conf

    # Criar usuários
    criar_usuarios

    # Ajustar permissões
    ajustar_permissoes

    # Iniciar serviços + ajustes de kernel
    configurar_servicos

    # Resumo
    mostrar_resumo

    print_status "✅ Samba instalado e otimizado com sucesso!"
    print_warning "Execute 'testparm' a qualquer momento para validar o smb.conf"
}

main "$@"
