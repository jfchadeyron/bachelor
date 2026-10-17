#!/bin/bash
# Simule l'activité de l'intranet d'Hexalog (BLOC 2, TP 10 et 11) :
# une nouvelle expédition est saisie toutes les 5 minutes, avec son heure de création.
# Elle sert à mesurer ce qu'une restauration fait perdre (RPO).
#
# Usage : sudo bash activite-intranet.sh          installe et démarre l'activité
#         sudo bash activite-intranet.sh arret    arrête l'activité
#         sudo bash activite-intranet.sh etat     affiche les dernières expéditions saisies
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "À lancer avec sudo : sudo bash $0" >&2
    exit 1
fi

case "${1:-}" in
    arret)
        systemctl disable --now hexalog-activite.timer
        echo "Activité simulée arrêtée."
        exit 0 ;;
    etat)
        mariadb intranet -e "SELECT reference, client, destination, cree_le FROM expeditions ORDER BY cree_le DESC, id DESC LIMIT 5"
        systemctl list-timers hexalog-activite.timer --no-pager
        exit 0 ;;
esac

echo "== 1/3 Horodatage des expéditions"
mariadb intranet -e "ALTER TABLE expeditions ADD COLUMN IF NOT EXISTS cree_le DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"

echo "== 2/3 Programme de saisie"
cat > /usr/local/sbin/hexalog-activite <<'EOF'
#!/bin/bash
# Saisit une expédition dans l'intranet d'Hexalog (activité simulée, TP 10 et 11)
CLIENTS=("Transports Lacoste" "Scierie du Lonzac" "Cave de Branceilles" "Imprimerie Bordas" "Pépinières Ribière" "Biscuiterie de Meymac")
VILLES=("Tulle" "Brive-la-Gaillarde" "Ussel" "Uzerche" "Argentat" "Objat" "Meymac")
C=${CLIENTS[$((RANDOM % ${#CLIENTS[@]}))]}
V=${VILLES[$((RANDOM % ${#VILLES[@]}))]}
mariadb intranet -e "INSERT IGNORE INTO expeditions (reference, client, destination, statut, date_prevue)
  VALUES (CONCAT('EXP-', DATE_FORMAT(NOW(), '%y%m%d-%H%i')), '$C', '$V', 'à planifier', CURDATE() + INTERVAL 2 DAY)"
EOF
chmod 755 /usr/local/sbin/hexalog-activite

cat > /etc/systemd/system/hexalog-activite.service <<'EOF'
[Unit]
Description=Hexalog : saisie d'une expédition (activité simulée)
After=mariadb.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hexalog-activite
EOF

cat > /etc/systemd/system/hexalog-activite.timer <<'EOF'
[Unit]
Description=Hexalog : une expédition toutes les 5 minutes (activité simulée)

[Timer]
OnCalendar=*:0/5
Persistent=false

[Install]
WantedBy=timers.target
EOF

echo "== 3/3 Démarrage"
systemctl daemon-reload
systemctl enable --now hexalog-activite.timer
/usr/local/sbin/hexalog-activite
mariadb intranet -e "SELECT reference, client, destination, cree_le FROM expeditions ORDER BY cree_le DESC, id DESC LIMIT 3"
echo "Activité simulée en place : une expédition toutes les 5 minutes."
