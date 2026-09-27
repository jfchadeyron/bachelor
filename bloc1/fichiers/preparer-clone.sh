#!/bin/bash
# Généralise un clone Debian : nouvel identifiant de machine, nouvelles clés SSH, nouveau nom.
# Usage : sudo ./preparer-clone.sh <nouveau-nom>      exemple : sudo ./preparer-clone.sh srv-lnx-01
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Ce script doit être lancé avec sudo." >&2
  exit 1
fi

NOUVEAU="$1"
if [ -z "$NOUVEAU" ]; then
  echo "Usage : sudo $0 <nouveau-nom>" >&2
  exit 1
fi
ANCIEN="$(hostname)"

echo "[1/4] Nouvel identifiant de machine"
rm -f /etc/machine-id /var/lib/dbus/machine-id
systemd-machine-id-setup

echo "[2/4] Nouvelles clés d'hôte SSH"
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A

echo "[3/4] Nouveau nom : $ANCIEN -> $NOUVEAU"
hostnamectl set-hostname "$NOUVEAU"
sed -i "s/\b${ANCIEN}\b/${NOUVEAU}/g" /etc/hosts

echo "[4/4] Oubli des baux DHCP du modèle"
rm -f /var/lib/dhcpcd/*.lease* /var/lib/dhcpcd/duid /var/lib/dhcp/*.leases 2>/dev/null || true

echo
echo "Clone généralisé. Redémarrez maintenant : sudo reboot"
