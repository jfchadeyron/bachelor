#!/bin/bash
# Installe l'intranet d'Hexalog sur SRV-LNX-01 (BLOC 2, TP 1).
# nginx + PHP-FPM + MariaDB, une petite application de suivi des expéditions,
# une page de santé (/sante.php) et les pages d'état utilisées par la supervision.
# Usage : sudo bash installer-intranet.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "À lancer avec sudo : sudo bash $0" >&2
    exit 1
fi

PHPV=8.4
WEB=/var/www/intranet
BASE=intranet
COMPTE=intranet

echo "== 1/5 Installation des paquets (quelques minutes)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q nginx "php${PHPV}-fpm" "php${PHPV}-mysql" mariadb-server curl

echo "== 2/5 Base de données"
systemctl enable --now mariadb
if [ -f "$WEB/config.php" ]; then
    MDP=$(sed -n "s/.*'motdepasse' => '\(.*\)'.*/\1/p" "$WEB/config.php")
else
    MDP=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)
fi
mariadb <<SQL
CREATE DATABASE IF NOT EXISTS ${BASE} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${COMPTE}'@'localhost' IDENTIFIED BY '${MDP}';
ALTER USER '${COMPTE}'@'localhost' IDENTIFIED BY '${MDP}';
GRANT SELECT, INSERT, UPDATE, DELETE ON ${BASE}.* TO '${COMPTE}'@'localhost';
FLUSH PRIVILEGES;
USE ${BASE};
CREATE TABLE IF NOT EXISTS expeditions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    reference VARCHAR(20) NOT NULL UNIQUE,
    client VARCHAR(80) NOT NULL,
    destination VARCHAR(80) NOT NULL,
    statut VARCHAR(30) NOT NULL,
    date_prevue DATE NOT NULL
);
INSERT IGNORE INTO expeditions (reference, client, destination, statut, date_prevue) VALUES
 ('EXP-27-0001', 'Brasserie Corrézienne', 'Brive-la-Gaillarde', 'livrée', CURDATE() - INTERVAL 3 DAY),
 ('EXP-27-0002', 'Meubles Delpech', 'Tulle', 'livrée', CURDATE() - INTERVAL 2 DAY),
 ('EXP-27-0003', 'Pharmacie du Centre', 'Ussel', 'en transit', CURDATE()),
 ('EXP-27-0004', 'Coopérative Limousine', 'Limoges', 'en transit', CURDATE()),
 ('EXP-27-0005', 'Garage Martinie', 'Objat', 'en préparation', CURDATE() + INTERVAL 1 DAY),
 ('EXP-27-0006', 'Librairie Les Mots', 'Périgueux', 'en préparation', CURDATE() + INTERVAL 1 DAY),
 ('EXP-27-0007', 'Fromagerie des Monts', 'Égletons', 'à planifier', CURDATE() + INTERVAL 2 DAY),
 ('EXP-27-0008', 'Électricité Veyssière', 'Malemort', 'à planifier', CURDATE() + INTERVAL 3 DAY);
SQL

echo "== 3/5 Application"
mkdir -p "$WEB"
cat > "$WEB/config.php" <<PHP
<?php
// Connexion de l'intranet à sa base de données
return [
    'hote' => 'localhost',
    'base' => '${BASE}',
    'utilisateur' => '${COMPTE}',
    'motdepasse' => '${MDP}',
];
PHP

cat > "$WEB/db.php" <<'PHP'
<?php
function connexion() {
    $c = require __DIR__ . '/config.php';
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    $db = new mysqli($c['hote'], $c['utilisateur'], $c['motdepasse'], $c['base']);
    $db->set_charset('utf8mb4');
    return $db;
}
PHP

cat > "$WEB/index.php" <<'PHP'
<?php
require __DIR__ . '/db.php';
$lignes = [];
$erreur = null;
try {
    $db = connexion();
    $res = $db->query('SELECT reference, client, destination, statut, date_prevue FROM expeditions ORDER BY date_prevue, reference');
    $lignes = $res->fetch_all(MYSQLI_ASSOC);
} catch (Throwable $e) {
    // La page reste servie (code 200) avec un message : seul un test du contenu voit la panne
    $erreur = 'Base de données indisponible';
    error_log('intranet : ' . $e->getMessage());
}
?><!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><title>Intranet Hexalog</title>
<style>body{font-family:Arial,sans-serif;margin:2em;color:#1d2530}h1{color:#1f3a5f}
table{border-collapse:collapse}td,th{border:1px solid #c8cfd8;padding:4px 10px}th{background:#e8eef6}
.erreur{color:#b42318;font-weight:bold}</style></head>
<body>
<h1>Intranet Hexalog</h1>
<p>Suivi des expéditions, serveur <?= htmlspecialchars(gethostname()) ?>.</p>
<?php if ($erreur): ?>
<p class="erreur"><?= $erreur ?></p>
<?php else: ?>
<table><tr><th>Référence</th><th>Client</th><th>Destination</th><th>Statut</th><th>Date prévue</th></tr>
<?php foreach ($lignes as $l): ?>
<tr><?php foreach ($l as $v): ?><td><?= htmlspecialchars($v) ?></td><?php endforeach; ?></tr>
<?php endforeach; ?>
</table>
<p><?= count($lignes) ?> expéditions.</p>
<?php endif; ?>
</body></html>
PHP

cat > "$WEB/sante.php" <<'PHP'
<?php
// Page de santé pour la supervision : BASE-OK (code 200) ou BASE-KO (code 500)
require __DIR__ . '/db.php';
header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store');
try {
    $db = connexion();
    $n = $db->query('SELECT COUNT(*) FROM expeditions')->fetch_row()[0];
    echo "BASE-OK expeditions=$n\n";
} catch (Throwable $e) {
    http_response_code(500);
    echo "BASE-KO\n";
    error_log('sante : ' . $e->getMessage());
}
PHP
chown -R root:www-data "$WEB"
chmod 750 "$WEB"
chmod 640 "$WEB"/*.php

echo "== 4/5 PHP-FPM et nginx"
# pages d'état de PHP-FPM (utilisées par Zabbix)
sed -i 's|^;pm.status_path = /status|pm.status_path = /status|; s|^;ping.path = /ping|ping.path = /ping|' \
    "/etc/php/${PHPV}/fpm/pool.d/www.conf"

cat > /etc/nginx/sites-available/intranet <<NGINX
# Intranet Hexalog
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name intranet.hexalog.local srv-lnx-01.hexalog.local _;
    root ${WEB};
    index index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }
    location ~ ^/(config|db)\.php\$ {
        deny all;
    }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHPV}-fpm.sock;
    }
    # Pages d'état, lisibles depuis la machine elle-même (agent de supervision)
    location = /basic_status {
        stub_status;
        allow 127.0.0.1;
        allow ::1;
        deny all;
    }
    location ~ ^/(status|ping)\$ {
        allow 127.0.0.1;
        allow ::1;
        deny all;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$fastcgi_script_name;
        fastcgi_pass unix:/run/php/php${PHPV}-fpm.sock;
    }
}
NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/intranet /etc/nginx/sites-enabled/intranet
nginx -t
systemctl enable "php${PHPV}-fpm" nginx
systemctl restart "php${PHPV}-fpm" nginx

echo "== 5/5 Vérifications"
sleep 1
curl -s http://127.0.0.1/sante.php || true
curl -s -o /dev/null -w "Page d'accueil : code HTTP %{http_code}\n" http://127.0.0.1/ || true
curl -s http://127.0.0.1/basic_status | head -1 || true
echo "Intranet installé : http://$(hostname -I | awk '{print $1}')/"
