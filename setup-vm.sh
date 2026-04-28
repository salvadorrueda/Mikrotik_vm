#!/usr/bin/env bash
# setup-vm.sh — Descarrega, importa i configura la VM Mikrotik CHR a VirtualBox.
# Quan acabi, executa ./configure-mikrotik.sh per acabar de configurar el router.
set -euo pipefail

readonly CHR_VERSION="7.21.4"
readonly CHR_URL="https://download.mikrotik.com/routeros/${CHR_VERSION}/chr-${CHR_VERSION}.ova"
readonly VM_NAME="m00"
readonly INTERNAL_NET="m00"
readonly OVA_FILE="chr-${CHR_VERSION}.ova"

err()  { echo "Error: $*" >&2; exit 1; }
info() { echo ">> $*"; }

command -v VBoxManage >/dev/null 2>&1 || err "VBoxManage no està instal·lat"
command -v curl       >/dev/null 2>&1 || err "curl no està instal·lat"

# 1. Descàrrega de la .ova
if [[ -f "$OVA_FILE" ]]; then
    info "$OVA_FILE ja existeix, ometent descàrrega"
else
    info "Descarregant $OVA_FILE..."
    curl -L --fail -o "$OVA_FILE" "$CHR_URL"
fi

# 2. Importació de la VM
if VBoxManage list vms | grep -qE "^\"${VM_NAME}\""; then
    info "La VM '$VM_NAME' ja existeix, ometent importació"
else
    info "Important $OVA_FILE com a '$VM_NAME'..."
    VBoxManage import "$OVA_FILE" --vsys 0 --vmname "$VM_NAME"
fi

# 3. Segona NIC connectada a la xarxa interna 'm00' (LAN)
nic2=$(VBoxManage showvminfo "$VM_NAME" --machinereadable \
       | awk -F= '/^nic2=/ {gsub(/"/,"",$2); print $2}')
if [[ "$nic2" == "intnet" ]]; then
    info "La segona NIC ja està configurada com a intnet"
else
    info "Afegint segona NIC a la xarxa interna '$INTERNAL_NET'..."
    VBoxManage modifyvm "$VM_NAME" --nic2 intnet --intnet2 "$INTERNAL_NET"
fi

# 4. Iniciar la VM
state=$(VBoxManage showvminfo "$VM_NAME" --machinereadable \
        | awk -F= '/^VMState=/ {gsub(/"/,"",$2); print $2}')
if [[ "$state" == "running" ]]; then
    info "La VM '$VM_NAME' ja s'està executant"
else
    info "Iniciant la VM '$VM_NAME'..."
    VBoxManage startvm "$VM_NAME" --type headless
fi

info "Fet. Espera ~30s perquè el Mikrotik arrenqui i executa: ./configure-mikrotik.sh"
