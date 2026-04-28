#!/usr/bin/env bash
# configure-mikrotik.sh — Configura el Mikrotik CHR un cop la VM està en marxa.
#
# Aquest script és d'una sola execució: estableix el password inicial de l'admin,
# crea l'usuari salvadorrueda amb clau SSH, deshabilita admin, canvia el port SSH
# a 2222, deshabilita la resta de serveis i programa que SSH només estigui actiu
# els primers 10 minuts després de cada arrencada.
#
# Si falla a mig camí, recupera-ho destruint i recreant la VM (./setup-vm.sh).
set -euo pipefail

readonly VM_NAME="m00"
readonly SYSTEM_IDENTITY="m00"
readonly NEW_USER="salvadorrueda"
readonly NEW_SSH_PORT="2222"

err()  { echo "Error: $*" >&2; exit 1; }
info() { echo ">> $*"; }

# 1. Comprovar dependències
for cmd in VBoxManage nmap ssh scp sshpass expect ssh-keygen openssl ip awk sed tr; do
    command -v "$cmd" >/dev/null 2>&1 || err "$cmd no està instal·lat"
done

# 2. Localitzar la clau pública SSH (id_rsa primer, després ed25519, sinó preguntar)
if   [[ -f "$HOME/.ssh/id_rsa.pub"     ]]; then pubkey="$HOME/.ssh/id_rsa.pub"
elif [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then pubkey="$HOME/.ssh/id_ed25519.pub"
else
    echo "No s'ha trobat ~/.ssh/id_rsa.pub ni ~/.ssh/id_ed25519.pub"
    read -r -p "Ruta a una clau pública existent (ENTER per generar-ne una de nova ed25519): " custom
    if [[ -z "$custom" ]]; then
        ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
        pubkey="$HOME/.ssh/id_ed25519.pub"
    else
        [[ -f "$custom" ]] || err "$custom no existeix"
        pubkey="$custom"
    fi
fi
privkey="${pubkey%.pub}"
[[ -f "$privkey" ]] || err "No s'ha trobat la clau privada $privkey"
info "Utilitzant clau SSH: $pubkey"

# 3. Localitzar la IP del Mikrotik a partir de la MAC de nic1
mac_raw=$(VBoxManage showvminfo "$VM_NAME" --machinereadable \
          | awk -F= '/^macaddress1=/ {gsub(/"/,"",$2); print $2}')
[[ -n "$mac_raw" ]] || err "No s'ha pogut llegir la MAC de la VM '$VM_NAME'"
mac=$(echo "$mac_raw" | sed 's/../&:/g; s/:$//' | tr 'A-F' 'a-f')
info "MAC de la VM: $mac"

subnet=$(ip -4 route | awk '/proto kernel/ && /src/ {print $1; exit}')
[[ -n "$subnet" ]] || err "No s'ha pogut determinar la subxarxa local"
info "Cercant a la subxarxa $subnet (això pot trigar uns minuts)..."

ip_addr=""
for attempt in $(seq 1 12); do
    nmap -sn "$subnet" >/dev/null 2>&1 || true
    ip_addr=$(ip -4 neigh | awk -v m="$mac" 'tolower($5) == m {print $1; exit}')
    [[ -n "$ip_addr" ]] && break
    info "Intent $attempt/12: la VM encara no respon, esperant 5s..."
    sleep 5
done
[[ -n "$ip_addr" ]] || err "No s'ha trobat la IP del Mikrotik. Comprova que la VM ha arrencat."
info "Mikrotik trobat a $ip_addr"

# Neteja host keys antics per a aquest IP
ssh-keygen -R "$ip_addr"                 >/dev/null 2>&1 || true
ssh-keygen -R "[$ip_addr]:$NEW_SSH_PORT" >/dev/null 2>&1 || true

# 4. Primer accés: la CHR força a establir un nou password per a admin
TEMP_PASSWORD=$(openssl rand -base64 18 | tr -d '=+/' | head -c 20)
info "Establint el password inicial de l'admin..."
expect <<EOF
log_user 0
set timeout 30
spawn ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR admin@$ip_addr
expect {
    -re {[Pp]assword: $} { send "\r"; exp_continue }
    -re {\[[^]]*\]: $}   { send "n\r"; exp_continue }
    "new password> "     { send "$TEMP_PASSWORD\r" }
    timeout { puts stderr "Timeout esperant 'new password>'"; exit 1 }
}
expect "repeat new password> "
send "$TEMP_PASSWORD\r"
expect "] > "
send "/quit\r"
expect eof
EOF

# Helpers de connexió
ssh_admin() {
    sshpass -p "$TEMP_PASSWORD" ssh \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p 22 "admin@$ip_addr" "$@"
}
scp_admin() {
    sshpass -p "$TEMP_PASSWORD" scp -O \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -P 22 "$@"
}
ssh_user() {
    local port="$1"; shift
    ssh -i "$privkey" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -o BatchMode=yes -p "$port" \
        "$NEW_USER@$ip_addr" "$@"
}

# 5. Fase A — admin@22: identitat + creació d'usuari + import de clau
info "Establint la identitat del sistema i creant l'usuari $NEW_USER..."
ssh_admin "/system identity set name=$SYSTEM_IDENTITY; /user add name=$NEW_USER group=full password=\"\""

info "Pujant la clau pública al router..."
scp_admin "$pubkey" "admin@$ip_addr:$NEW_USER.pub"

info "Important la clau pública per a $NEW_USER..."
ssh_admin "/user ssh-keys import public-key-file=$NEW_USER.pub user=$NEW_USER"

# 6. Verificar accés per clau abans d'inhabilitar admin
info "Verificant l'accés per clau de $NEW_USER..."
ssh_user 22 "/system identity print" >/dev/null \
    || err "L'autenticació per clau de $NEW_USER no funciona. Aborto sense inhabilitar admin."

# 7. Fase B — salvadorrueda@22: inhabilitar admin i canviar port SSH
info "Inhabilitant admin i canviant el port SSH a $NEW_SSH_PORT..."
ssh_user 22 "/user disable admin; /ip service set ssh port=$NEW_SSH_PORT" || true

# Pausa breu perquè el servei SSH es reiniciï al port nou
sleep 3

# 8. Fase C — salvadorrueda@2222: deshabilitar altres serveis + scheduler
info "Deshabilitant els altres serveis IP..."
ssh_user "$NEW_SSH_PORT" "/ip service disable telnet,ftp,www,api,winbox,api-ssl,www-ssl"

info "Programant el tall del SSH 10 min després de cada arrencada..."
ssh_user "$NEW_SSH_PORT" \
    '/system scheduler add name=ssh-timeout start-time=startup on-event="/ip service enable ssh; :delay 10m; /ip service disable ssh"'

info "Configuració completada."
info "Accés: ssh -p $NEW_SSH_PORT $NEW_USER@$ip_addr"
info "Recorda: el SSH només acceptarà connexions els primers 10 min després d'arrencar el router."
