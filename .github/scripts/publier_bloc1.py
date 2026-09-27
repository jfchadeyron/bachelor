#!/usr/bin/env python3
"""Met en ligne le cours et le TP des séances du BLOC 1 dont la date est arrivée.

Lancé chaque matin par le workflow « Publication BLOC 1 ».
- .github/bloc1/calendrier.json : date de mise en ligne de chaque séance ;
- .github/bloc1/paquets/sNN.enc  : supports de la séance NN, chiffrés, en attente ;
- bloc1/assets/publie.json       : liste des séances en ligne (lue par les pages).

Variables d'environnement :
- BLOC1_CLE : clé de déchiffrement (secret du dépôt) ;
- JUSQUA    : publier tout de suite jusqu'à la séance indiquée (lancement manuel) ;
- ESSAI     : "true" pour vérifier la clé sans rien publier.
"""
import datetime
import io
import json
import os
import subprocess
import sys
import tarfile
from pathlib import Path
from zoneinfo import ZoneInfo

RACINE = Path(__file__).resolve().parents[2]
CALENDRIER = RACINE / ".github" / "bloc1" / "calendrier.json"
PAQUETS = RACINE / ".github" / "bloc1" / "paquets"
SITE = RACINE / "bloc1"
PUBLIE = SITE / "assets" / "publie.json"


def dechiffrer(paquet):
    res = subprocess.run(
        ["openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-iter", "200000",
         "-in", str(paquet), "-pass", "env:BLOC1_CLE"],
        capture_output=True)
    if res.returncode != 0:
        raise RuntimeError(f"déchiffrement impossible de {paquet.name} : clé BLOC1_CLE incorrecte ?")
    return tarfile.open(fileobj=io.BytesIO(res.stdout), mode="r:gz")


def membres_surs(archive):
    for m in archive.getmembers():
        chemin = Path(m.name)
        if chemin.is_absolute() or ".." in chemin.parts or chemin.parts[0] not in ("cours", "tp"):
            raise RuntimeError(f"chemin inattendu dans l'archive : {m.name}")
        if not (m.isfile() or m.isdir()):
            raise RuntimeError(f"élément inattendu dans l'archive : {m.name}")
    return archive.getmembers()


def seances_en_ligne():
    nums = set()
    for f in (SITE / "cours").glob("s[0-9][0-9]-*.html"):
        nums.add(int(f.name[1:3]))
    return sorted(nums)


def main():
    essai = os.environ.get("ESSAI", "").strip().lower() == "true"
    jusqua = os.environ.get("JUSQUA", "").strip()
    jusqua = int(jusqua) if jusqua.isdigit() else 0
    cle = os.environ.get("BLOC1_CLE", "")

    calendrier = json.loads(CALENDRIER.read_text(encoding="utf-8"))
    aujourdhui = datetime.datetime.now(ZoneInfo("Europe/Paris")).date()
    print(f"Date du jour (Paris) : {aujourdhui.isoformat()}")

    if essai:
        paquets = sorted(PAQUETS.glob("s*.enc"))
        if not cle:
            sys.exit("ERREUR : le secret BLOC1_CLE n'est pas défini dans le dépôt.")
        for p in paquets:
            with dechiffrer(p) as archive:
                noms = [m.name for m in membres_surs(archive) if m.isfile()]
            print(f"{p.name} : OK ({', '.join(noms)})")
        print(f"Test terminé : {len(paquets)} séance(s) en attente, clé correcte. Rien n'a été publié.")
        return

    a_publier = []
    for s in calendrier["seances"]:
        n = int(s["numero"])
        date = datetime.date.fromisoformat(s["date"])
        paquet = PAQUETS / f"s{n:02d}.enc"
        if paquet.exists() and (date <= aujourdhui or n <= jusqua):
            a_publier.append((n, paquet))

    if a_publier and not cle:
        sys.exit("ERREUR : le secret BLOC1_CLE n'est pas défini dans le dépôt : "
                 "impossible de publier les séances " + ", ".join(str(n) for n, _ in a_publier) + ".")

    for n, paquet in a_publier:
        with dechiffrer(paquet) as archive:
            membres = membres_surs(archive)
            if hasattr(tarfile, "data_filter"):
                archive.extractall(SITE, members=membres, filter="data")
            else:
                archive.extractall(SITE, members=membres)
        paquet.unlink()
        print(f"Séance {n} mise en ligne.")

    en_ligne = seances_en_ligne()
    contenu = json.dumps({"seances": en_ligne}) + "\n"
    if not PUBLIE.exists() or PUBLIE.read_text(encoding="utf-8") != contenu:
        PUBLIE.write_text(contenu, encoding="utf-8")
    print("Séances en ligne :", ", ".join(str(n) for n in en_ligne) or "aucune")
    if not a_publier:
        print("Aucune nouvelle séance à publier aujourd'hui.")


if __name__ == "__main__":
    main()
