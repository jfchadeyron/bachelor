/* Accès au site du Bachelor : réservé aux étudiants.
   Le mot de passe est demandé une seule fois par navigateur, puis mémorisé
   (stockage du navigateur et cookie) pour toutes les pages du site : accueil,
   blocs 1, 2 et 3, évaluations.
   Copie ouverte depuis le disque (file://) : pas de mot de passe.

   Changer le mot de passe : remplacer EMPREINTE par l'empreinte SHA-256 du nouveau
   mot de passe écrit en minuscules, obtenue sous Linux par :
       printf '%s' 'nouveaumotdepasse' | sha256sum
   Chaque étudiant devra alors saisir le nouveau mot de passe, une fois. */
(function () {
  "use strict";
  if (location.protocol === "file:") return;

  var EMPREINTE = "c5945582fce381301264f2d1441b3105ba2ebcd67d9f6dfbc803236e21cdfbf2";
  var NOM = "bachelor-acces";
  var DUREE = 400 * 24 * 3600; // durée maximale d'un cookie, prolongée à chaque visite

  // dossier du site (là où se trouve ce script), pour le cookie
  var script = document.currentScript;
  var chemin = "/";
  try {
    chemin = new URL(".", script && script.src ? script.src : location.href).pathname;
  } catch (e) {}

  function dejaSaisi() {
    try {
      if (localStorage.getItem(NOM) === EMPREINTE) return true;
    } catch (e) {}
    return (document.cookie || "").split(/;\s*/).indexOf(NOM + "=" + EMPREINTE) !== -1;
  }

  function memoriser() {
    try { localStorage.setItem(NOM, EMPREINTE); } catch (e) {}
    document.cookie = NOM + "=" + EMPREINTE + "; max-age=" + DUREE + "; path=" + chemin +
      "; SameSite=Lax" + (location.protocol === "https:" ? "; Secure" : "");
  }

  if (dejaSaisi()) {
    memoriser();
    return;
  }

  // Page masquée tant que le mot de passe n'a pas été saisi
  var racine = document.documentElement;
  racine.classList.add("acces-ferme");
  var style = document.createElement("style");
  style.textContent = [
    "html.acces-ferme body > :not(#acces-porte) { display: none !important; }",
    "html.acces-ferme body { background: #f5f6f8 !important; }",
    "#acces-porte { position: fixed; inset: 0; z-index: 2147483000; display: flex; align-items: flex-start; justify-content: center;",
    "  padding: 12vh 16px 24px; overflow-y: auto; background: #f5f6f8; color: #1d2530;",
    "  font-family: \"Segoe UI\", \"Helvetica Neue\", Arial, \"Liberation Sans\", sans-serif; font-size: 16px; line-height: 1.55; }",
    "#acces-porte * { box-sizing: border-box; }",
    "#acces-porte .acces-boite { width: 100%; max-width: 400px; margin: 0; padding: 0; background: #fff; border: 1px solid #d3d9e0;",
    "  border-top: 4px solid #1f3a5f; border-radius: 3px; box-shadow: 0 1px 3px rgba(29, 37, 48, 0.08); }",
    "#acces-porte .acces-entete { margin: 0; padding: 10px 22px; background: #1f3a5f; color: #fff; font-weight: 600; font-size: 0.95rem;",
    "  border-bottom: 3px solid #b8912a; }",
    "#acces-porte .acces-corps { padding: 20px 22px 22px; }",
    "#acces-porte h1 { margin: 0 0 8px; padding: 0; border: 0; font-size: 1.3rem; line-height: 1.3; color: #1f3a5f; font-weight: 600; }",
    "#acces-porte p { margin: 0 0 14px; font-size: 0.95rem; color: #4a5563; }",
    "#acces-porte label { display: block; margin: 0 0 4px; font-weight: 600; font-size: 0.9rem; color: #1d2530; }",
    "#acces-porte input { display: block; width: 100%; margin: 0 0 12px; padding: 8px 10px; font: inherit; color: #1d2530;",
    "  background: #fff; border: 1px solid #9aa5b4; border-radius: 3px; }",
    "#acces-porte input:focus { outline: 2px solid #1a4f8b; outline-offset: 1px; border-color: #1a4f8b; }",
    "#acces-porte input[aria-invalid=true] { border-color: #a12a2a; }",
    "#acces-porte button { display: inline-block; margin: 0; padding: 8px 20px; font: inherit; font-weight: 600; font-size: 0.95rem;",
    "  color: #fff; background: #1f3a5f; border: 1px solid #1f3a5f; border-radius: 3px; cursor: pointer; }",
    "#acces-porte button:hover { background: #16304f; }",
    "#acces-porte .acces-erreur { margin: -4px 0 12px; color: #a12a2a; font-size: 0.9rem; font-weight: 600; }",
    "#acces-porte .acces-note { margin: 14px 0 0; font-size: 0.85rem; color: #6b7684; }"
  ].join("\n");
  (document.head || racine).appendChild(style);

  function hex(tampon) {
    var octets = new Uint8Array(tampon), s = "";
    for (var i = 0; i < octets.length; i++) s += ("0" + octets[i].toString(16)).slice(-2);
    return s;
  }

  function ouvrir(porte) {
    memoriser();
    racine.classList.remove("acces-ferme");
    if (porte && porte.parentNode) porte.parentNode.removeChild(porte);
    if (style.parentNode) style.parentNode.removeChild(style);
    if (location.hash) {
      var cible = document.getElementById(decodeURIComponent(location.hash.slice(1)));
      if (cible) cible.scrollIntoView();
    }
  }

  function afficher() {
    var porte = document.createElement("div");
    porte.id = "acces-porte";
    porte.innerHTML =
      '<form class="acces-boite" novalidate>' +
      '<div class="acces-entete">Bachelor Informatique</div>' +
      '<div class="acces-corps">' +
      '<h1 id="acces-titre">Accès réservé</h1>' +
      '<p>Ces supports de cours sont réservés aux étudiants du Bachelor. ' +
      'Saisissez le mot de passe donné en cours.</p>' +
      '<label for="acces-mdp">Mot de passe</label>' +
      '<input id="acces-mdp" name="mdp" type="password" autocomplete="current-password" autocapitalize="off" spellcheck="false">' +
      '<p class="acces-erreur" role="alert" hidden></p>' +
      '<button type="submit">Entrer</button>' +
      '<p class="acces-note">Il ne vous sera plus demandé sur ce navigateur.</p>' +
      '</div></form>';
    porte.setAttribute("role", "dialog");
    porte.setAttribute("aria-labelledby", "acces-titre");
    document.body.insertBefore(porte, document.body.firstChild);

    var form = porte.querySelector("form");
    var champ = porte.querySelector("input");
    var erreur = porte.querySelector(".acces-erreur");
    champ.focus();

    function signaler(message) {
      erreur.textContent = message;
      erreur.hidden = false;
      champ.setAttribute("aria-invalid", "true");
      champ.select();
    }

    form.addEventListener("submit", function (ev) {
      ev.preventDefault();
      var saisie = champ.value.trim().toLowerCase();
      if (!saisie) { signaler("Saisissez le mot de passe."); return; }
      if (!window.crypto || !crypto.subtle || !window.TextEncoder) {
        signaler("Ce navigateur est trop ancien : utilisez une version récente de Firefox, Chrome ou Edge.");
        return;
      }
      crypto.subtle.digest("SHA-256", new TextEncoder().encode(saisie)).then(function (t) {
        if (hex(t) === EMPREINTE) ouvrir(porte);
        else signaler("Mot de passe incorrect.");
      }, function () {
        signaler("Vérification impossible dans ce navigateur.");
      });
    });
  }

  if (document.body) afficher();
  else document.addEventListener("DOMContentLoaded", afficher);
})();
