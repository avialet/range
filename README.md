<div align="center">

# Range

**Les téléchargements se rangent tout seuls.**

[![Dernière version](https://img.shields.io/github/v/release/avialet/range?color=B26B2E&label=version)](https://github.com/avialet/range/releases/latest)
[![macOS 26](https://img.shields.io/badge/macOS-26%20Tahoe-F0A020)](#installation)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-2E9D6E)](LICENSE)

[**Télécharger le DMG**](https://github.com/avialet/range/releases/latest) · [Site](https://range.vialet.app)

</div>

## Ce que fait Range

Range vide le dossier Téléchargements à votre place : factures dans Documents, images et captures
dans Images, vidéos dans Vidéos, installeurs et doublons à la corbeille.

- **Des règles prêtes.** Installeurs de plus de 7 jours, doublons « nom (1) » identiques à l'original,
  archives déjà décompressées, factures, captures d'écran, images, vidéos. Chacune s'éteint ou se règle
  (destination, sous-dossier par année ou par mois, âge minimal).
- **Un aperçu d'abord.** Le premier ménage se fait à la main, ligne par ligne ; le rangement
  automatique ne s'allume que si vous le voulez.
- **Rien ne se perd.** Jamais de suppression : la corbeille seulement. Chaque rangement se défait
  d'un clic depuis le Journal, fichier par fichier ou lot entier, avec le nom d'origine exact.
  Un téléchargement en cours n'est jamais touché.
- **Rester chez vous.** Tout est stocké sur votre Mac. Aucun compte, aucun serveur, aucune télémétrie.
  Aucune IA : l'extension, le nom, l'origine du téléchargement et la date suffisent.

## Installation

**Prérequis :** un Mac Apple Silicon sous macOS 26 (Tahoe) ou plus récent.

1. Téléchargez `Range-X.Y.Z.dmg` depuis la [dernière version](https://github.com/avialet/range/releases/latest).
2. Ouvrez le DMG et glissez **Range** dans **Applications**, puis double-cliquez.
3. Au premier lancement, macOS indique qu'il n'a pas pu vérifier l'app (elle est signée
   sans certificat Apple Developer). Cliquez **Terminé** (pas « Placer dans la corbeille »),
   ouvrez **Réglages Système › Confidentialité et sécurité**, descendez jusqu'à
   « Range a été bloqué… », cliquez **Ouvrir quand même**, authentifiez-vous, puis **Ouvrir**.
   Cette étape n'a lieu qu'une fois par téléchargement. Dans le Terminal :

   ```bash
   xattr -d com.apple.quarantine /Applications/Range.app
   ```

Pour vérifier le fichier téléchargé, comparez son empreinte avec celle publiée dans la même version :

```bash
shasum -a 256 -c Range-X.Y.Z.dmg.sha256
```

### Mises à jour

Range consulte une fois par jour la dernière version publiée sur GitHub. S'il en
existe une plus récente, un clic la télécharge, **vérifie son empreinte SHA-256**, contrôle
l'application qu'elle contient, la remplace et relance l'app. Si une étape échoue, l'app
installée n'est pas touchée. La recherche automatique se désactive dans **Réglages › Mises à jour**.

Le seul échange réseau de Range est cette lecture de la version publiée. Aucune donnée n'est envoyée.

## Notice

- **Premier lancement** : Range demande à ouvrir Téléchargements (puis Documents, pour les factures).
  macOS affiche son invite. Range analyse, puis montre **À ranger** : ce qu'il ferait, groupé par règle.
  Décochez ce qui doit rester, puis **Ranger**. Range propose ensuite le rangement automatique.
- **Automatique** : chaque nouveau fichier attend le délai de grâce (10 min par défaut, dans les
  Réglages) pour que le lien « Ouvrir » du navigateur marche encore, et d'être stable (même taille,
  même date à 15 s d'écart). Les fichiers `.download`, `.crdownload`, `.part`, `.partial`, cachés ou
  vides depuis moins de 10 min sont ignorés, comme les images disque montées.
- **Journal** : « Annuler ce lot » ou « Annuler » sur un fichier. Un fichier remis en place n'est plus
  rangé automatiquement (« Ranger quand même » dans À ranger). Une ligne grisée ne peut plus être
  défaite (corbeille vidée, fichier déplacé depuis).
- **Conflits** : si le même fichier, octet pour octet, est déjà à destination, la copie va à la
  corbeille ; sinon le nouveau est renommé « nom 2.ext ». Rien n'est jamais écrasé.
- **Autorisations et mises à jour** : Range est signé sans certificat Apple Developer, donc chaque
  nouvelle version est une nouvelle app aux yeux de macOS, qui redemande l'accès à Téléchargements.
  Range le détecte, suspend le rangement et l'affiche ; rien n'échoue en silence.
- **Barre des menus** : état, « Ranger maintenant… », « Annuler le dernier rangement », « Suspendre ».
  L'icône se masque quand l'app [Vialet](https://vialet.app) est installée.
- **Raccourci global** (⌃⌥⌘R, éteint par défaut, à activer dans les Réglages) : ouvre ou masque la fenêtre.
- Fermer la fenêtre ne quitte pas l'app : Range continue de surveiller Téléchargements. **⌘Q** quitte vraiment.
- Liens : `range://ranger` (aperçu), `range://annuler` (dernier rangement), `range://pause` (suspendre ou reprendre).
- **À propos de Range** (menu de l'app ou de la barre des menus) : version, licence MIT, liens vers le site et le code source.

### Vos données

```text
~/Library/Application Support/Range/range.sqlite
```

Le journal d'annulation, les règles et les fichiers gardés en place y vivent. Pour sauvegarder,
copiez ce dossier. Pour repartir de zéro, quittez l'app et supprimez-le.

## Compiler depuis les sources

Il faut Swift 6.3 ou plus récent (les Command Line Tools suffisent, Xcode n'est pas nécessaire).

```bash
git clone https://github.com/avialet/range.git
cd range
make test      # tests du noyau
make run       # construit et lance l'app
make install   # installe dans /Applications
make release   # fabrique build/Range-X.Y.Z.dmg et son empreinte
```

Essais sans toucher à vos vrais dossiers : `RANGE_DOWNLOADS_PATH` (dossier surveillé),
`RANGE_HOME_PATH` (racine des destinations `~/...`), `RANGE_TRASH_PATH` (corbeille de substitution)
et `RANGE_DB_PATH` (base). L'outil `range-essai` du noyau fait la même chose en ligne de commande
(aperçu, rangement, annulation complète) sur un clone jetable :

```bash
cp -cRp ~/Downloads /tmp/essai/dl      # clone APFS, sans place disque
cd Packages/RangeCore && swift run range-essai ranger --dossier /tmp/essai/dl \
  --maison /tmp/essai/home --corbeille /tmp/essai/Trash --base /tmp/essai/essai.sqlite --dates-de ~/Downloads
swift run range-essai annuler-tout --dossier /tmp/essai/dl --maison /tmp/essai/home \
  --corbeille /tmp/essai/Trash --base /tmp/essai/essai.sqlite
```

L'icône et l'habillage du DMG viennent de l’outillage commun des apps vialet.app
(`scripts/plaque.swift`), cloné à côté de l'app (sinon `VIALETAPPS_PATH=<chemin>`) :

```bash
make icon         # icône : plaque aux teintes de App/Brand.swift, son glyphe (initiale s'il est vide)
make dmg-layout   # fond et disposition de la fenêtre du DMG, dans scripts/dmg (à committer)
```

| Dossier | Contenu |
|---|---|
| `Packages/RangeCore` | Noyau sans interface : lecture du dossier, règles, plan, application, annulation, journal SQLite ([GRDB](https://github.com/groue/GRDB.swift)) |
| `Range` | L'application SwiftUI ; `App/Brand.swift` porte son identité |
| `scripts` | Assemblage de l'app et du DMG ; `scripts/dmg` : fond et disposition de sa fenêtre |
| `docs` | [Publier une version](docs/publier-une-version.md), [tests](docs/tests.md), notes de version |

Le socle commun (mises à jour, thème, raccourci global, panneau flottant) vient de
[VialetKit](https://github.com/avialet/vialetkit). Publier une version ne demande que de
modifier `VERSION` puis de pousser un tag `vX.Y.Z` : la CI construit et publie le DMG, et
les utilisateurs reçoivent la mise à jour dans l'app.

## Confidentialité

Range ne collecte rien. Vos données ne quittent jamais votre Mac. La seule requête
réseau est la lecture de la dernière version publiée sur GitHub, que vous pouvez désactiver.

## Licence

[MIT](LICENSE) © 2026 Aurélien Vialet
