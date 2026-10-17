# Donkey Kong Jr — version 5 écrans pour Sega Master System

Portage sur Sega Master System de *Donkey Kong Jr* pour Coleco Adam (version cassette DDP,
5 écrans). Le code du jeu d'origine est conservé et relocalisé tel quel. Il tourne sur un
moteur Master System qui remplace le matériel de l'Adam et de la ColecoVision : affichage avec
décor et sprites natifs, manette, son, PAL/NTSC.

Ce dépôt ne contient **pas** le jeu d'origine. Il contient le moteur, les outils et ce qui
permet de construire la cartouche `sms/build/dkjr.sms` (512 Ko) sous Windows, à partir de
votre propre copie du jeu.

## Prérequis

- **Python 3** (3.10 ou plus récent), à télécharger sur <https://www.python.org/downloads/>.
  Pendant l'installation, cocher **« Add python.exe to PATH »**. Aucun module supplémentaire
  n'est nécessaire.
- L'assembleur **sjasmplus** est fourni dans le dépôt (`tools/sjasmplus/sjasmplus.exe`,
  v1.24.0, licence BSD : `tools/sjasmplus/LICENSE.md`). Il n'y a rien à installer.
- Pour jouer, un émulateur Master System, par exemple **Mesen 2** (<https://www.mesen.ca/>).

## Fichiers d'origine à ajouter

Ces deux fichiers sont protégés par le droit d'auteur et ne sont pas fournis. Créez le dossier
`Rom Sources` à la racine du dépôt et placez-y les fichiers **exactement** à ces emplacements,
sous ces noms :

| Emplacement | Contenu | Taille | MD5 |
|---|---|---|---|
| `Rom Sources\Donkey Kong Jr (Coleco Adam)\Donkey Kong Jr (Coleco Adam).ddp` | *Donkey Kong Jr* pour Coleco Adam, image de la cassette numérique (DDP) | 262 144 octets | `cc6687924b0e33fb394191584f6afd13` |
| `Rom Sources\adam\os7.u2` | BIOS de la ColecoVision (OS7), présent aussi dans l'Adam | 8 192 octets | `2c66f5911e5b42b8ebe113403548eee7` |

Le BIOS se trouve aussi sous d'autres noms, par exemple `coleco.rom` ou `colecovision.rom`.
Il faut alors le renommer en `os7.u2`. Seul le MD5 compte.

Pour vérifier un MD5 dans une invite de commandes :

```bat
certutil -hashfile "Rom Sources\adam\os7.u2" MD5
```

La construction fait elle-même cette vérification. Si un fichier manque ou n'a pas le bon
MD5, elle s'arrête et indique lequel.

Le dossier `Rom Sources` est exclu de git (`.gitignore`) : ces fichiers ne seront jamais
envoyés sur le dépôt.

## Compiler

Double-cliquer sur **`compiler.bat`**, ou, depuis une invite de commandes ouverte dans le
dossier du dépôt :

```bat
python sms\build.py
```

La construction prend quelques secondes à une minute. Elle se termine par une ligne de ce type :

```
cartouche ...\sms\build\dkjr.sms : 512 Ko, somme $15DB
```

La cartouche obtenue doit avoir le MD5 `14b47c12ffb00bbc674139ee2bcd6252`.

## Jouer

Double-cliquer sur **`jouer.bat`**. Il ouvre la cartouche dans Mesen 2 s'il est installé à
l'emplacement par défaut (`%LOCALAPPDATA%\Mesen2\Mesen.exe`). Sinon, il l'ouvre avec le
programme associé aux fichiers `.sms`. On peut aussi charger `sms\build\dkjr.sms` dans
n'importe quel émulateur Master System, ou la lancer sur une vraie console avec une
cartouche flash.

Au démarrage, l'écran de titre reste affiché jusqu'à un appui sur le bouton 1 ou 2.

## Ce que fait la construction

`sms/build.py` enchaîne trois étapes :

1. **`sms/tools/gen_os7.py`** lit le BIOS (`os7.u2`) et produit `sms/gen/os7.asm` : l'OS7
   aux mêmes adresses, adapté à la Master System.
2. **`sms/tools/gen_game.py`** lit le jeu d'origine (le DDP), le désassemble et produit
   `sms/gen/game_lo.asm` et `sms/gen/game_hi.asm`, c'est-à-dire le code du jeu relocalisé pour
   la carte mémoire de la cartouche. Le désassembleur s'appuie sur :
   - `names.txt`, qui donne les noms des adresses ;
   - `cov/os7.txt`, `cov/jeu.txt` et `sms/cov/full.pcs`, qui sont les adresses exécutées
     relevées pendant des parties ;
   - `sms/reloc_words.txt`, la liste des mots à relocaliser.
3. **sjasmplus** assemble `sms/src/dkjr.asm` : le moteur Master System et le code généré.
   Le script ajoute ensuite les pages de données du jeu d'origine, relues dans le DDP, et
   écrit la somme de contrôle de l'en-tête `TMR SEGA`.

`python sms\build.py --nogen` saute les étapes 1 et 2 et réutilise les fichiers déjà générés
dans `sms/gen/`. Les fichiers d'origine restent nécessaires pour l'étape 3.

## Contenu du dépôt

| Chemin | Rôle |
|---|---|
| `compiler.bat`, `jouer.bat` | construire la cartouche, la lancer |
| `sms/build.py` | script de construction |
| `sms/src/` | moteur Master System en assembleur Z80 (affichage, sprites, manette, son) |
| `sms/gen/gfx.bin`, `gfx.inc`, `gfx_spr.inc` | décor, sprites et palettes au format Master System |
| `sms/tools/gen_os7.py`, `sms/tools/gen_game.py` | génération de l'OS7 adapté et du code du jeu |
| `tools/` | désassembleur Z80, lecture du DDP, fichiers d'origine attendus (`sources.py`), sjasmplus |
| `names.txt`, `src/names.inc`, `cov/`, `sms/cov/`, `sms/reloc_words.txt` | données du désassemblage |
