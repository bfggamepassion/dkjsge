"""Fichiers d'origine (dossier « Rom Sources », non fournis) lus par la construction."""
import hashlib
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..'))

SRC = os.path.join(ROOT, 'Rom Sources')
DDP = os.path.join(SRC, 'Donkey Kong Jr (Coleco Adam)', 'Donkey Kong Jr (Coleco Adam).ddp')
OS7_ROM = os.path.join(SRC, 'adam', 'os7.u2')

MD5 = {DDP: 'cc6687924b0e33fb394191584f6afd13',        # jeu : cassette DDP de l'Adam (256 Ko)
       OS7_ROM: '2c66f5911e5b42b8ebe113403548eee7'}    # BIOS ColecoVision OS7 (8 Ko)


def check():
    """Message d'erreur si un fichier manque ou n'est pas le bon (None si tout va bien)."""
    err = []
    for path, md5 in MD5.items():
        rel = os.path.relpath(path, ROOT)
        if not os.path.exists(path):
            err.append(f'fichier absent : {rel}')
        elif hashlib.md5(open(path, 'rb').read()).hexdigest() != md5:
            err.append(f'mauvais fichier (MD5 attendu {md5}) : {rel}')
    return '\n'.join(err + ['(voir README.md, « Fichiers d\'origine à ajouter »)']) if err else None
