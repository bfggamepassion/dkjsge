"""Lecture du fichier DDP d'origine (cassette numérique de l'Adam).

Conteneur :
- DDP Adam : 256 blocs de 1 Ko, lus un par un par l'EOS (DCB AdamNet).
- Bloc 0 : amorce chargée en $C800 par l'EOS ; elle lit le fichier 1
  (blocs 1-7 -> $7800-$93FF), écrit $1111 en $8000 et saute à ($800A) = $8108.
- Le jeu charge ensuite lui-même ses fichiers (table de 10 entrées de 5 octets
  en $7DD6 : adresse, bloc de départ, nombre de blocs), pendant la NMI.
"""

FILE_TABLE = 0x7DD6
NFILES = 10


def file_table(ddp):
    """La table est dans le bloc 2 (chargé en $7C00)."""
    b2 = ddp[2 * 1024:3 * 1024]
    t = []
    for i in range(NFILES):
        o = FILE_TABLE - 0x7C00 + 5 * i
        e = b2[o:o + 5]
        t.append({'n': i + 1, 'addr': e[0] | (e[1] << 8), 'block': e[2] | (e[3] << 8), 'count': e[4]})
    return t
