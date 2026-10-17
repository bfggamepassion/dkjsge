"""Génère le code du jeu pour la Master System depuis le DDP d'origine.

  python sms/tools/gen_game.py   -> sms/gen/game_lo.asm, sms/gen/game_hi.asm, sms/gen/game.sym.txt

Image du jeu = fichiers 1, 2, 6, 3, 4, 7, 5 chargés dans l'ordre (comme le fait le jeu),
$8000-$8001 = $1111 (posé par l'amorce). Code/données : couverture de l'original
(cov/*.cov) + descente récursive (tools/disasm.py).
Seules transformations (le reste est octet pour octet) :
- variables $6F00-$73FF -> RAM SMS (+RAM_SHIFT) ;
- code $C000-$F2D9 -> $2000-$52D9 (ORG différent, références par étiquettes) ;
- $8563 (pointeur d'état du chargeur, écrit par le jeu) et $FD6F (unité EOS) -> RAM moteur ;
- appels EOS ($FC30-$FD5F) -> remplaçants du moteur (eos_XXXX) ;
- mots de données listés dans sms/reloc_words.txt -> « dw étiquette » ;
- remplacements de la frontière listés dans PATCHES ;
- $7FF0-$7FFF (remplissage jamais lu) : en-tête TMR SEGA.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import disasm  # noqa: E402
import extract  # noqa: E402
import z80dis  # noqa: E402
from sources import DDP  # noqa: E402

GEN = os.path.join(ROOT, 'sms', 'gen')
LO, HI_END = 0x7800, 0xF2DA
RELOC = (0xC000, 0xF2DA)            # -> $2000
RELOC_SHIFT = -0xA000
RAM_OLD = (0x6F00, 0x7400)
SPECIAL = {0x8563: 'V_8563', 0x8564: 'V_8563+1', 0xFD6F: 'V_FD6F'}
HEADER = (0x7FF0, 0x8000)
# tables de sauts (adresse, nombre d'entrées) : entrées = points d'entrée de code, mots relocalisés
JUMP_TABLES = {0x8936: 32, 0x8976: 32,           # interpréteur des cinématiques (opcode & $1F)
               0xDD31: 5,                        # $DD2D : selon SCREEN
               0xE09E: 9,                        # $E09A : selon le type d'objet
               0xEFFB: 6}                        # $EFF7 : écran 4, selon l'état
# tables de pointeurs de données (adresse, nombre de mots) : chaque mot relocalisé selon sa valeur
POINTER_TABLES = {
    0xCF64: 5, 0xCFEE: 5, 0xD027: 5, 0xD0A8: 5, 0xD114: 5,    # $D233 : listes par écran, index DE = 0..8
    0xDB59: 4,                                                # $D484 : trajectoires de saut de Junior ($6F89)
    0xDB23: 5, 0xDB2D: 5,                                     # $D8E6, $D974 : listes par écran (via $CF34)
}
# Listes de zones lues par $D1FE (une par écran, via les tables $CF64-$D114) : entrées de 3 octets
# (valeur, borne basse, borne haute) ; $FE + mot = l'entrée est ailleurs (mot -> 3 octets), la liste
# continue après ; $FD = cas particulier ($D282) puis fin ; $FF = fin.
ZONE_LIST_TABLES = (0xCF64, 0xCFEE, 0xD027, 0xD0A8, 0xD114)


def zone_list_words(img):
    out = set()
    for t in ZONE_LIST_TABLES:
        for i in range(POINTER_TABLES[t]):
            a = img[t + 2 * i] | (img[t + 2 * i + 1] << 8)
            for _ in range(256):
                b = img[a]
                if b in (0xFF, 0xFD):
                    break
                if b == 0xFE:
                    out.add(a + 1)
                a += 3
    return out


# Morceaux du pilote son OS7 (table $B0BE : 58 x (données, canal)). Note spéciale ((octet & $3C) = 4) :
# mot = routine du jeu appelée par le pilote ($03AA de l'OS7) -> à relocaliser.
SONG_TABLE = (0xB0BE, 58)


def song_words(img):
    t, n = SONG_TABLE
    out = set()
    for k in range(n):
        a = img[t + 4 * k] | (img[t + 4 * k + 1] << 8)
        for _ in range(500):
            b = img[a]
            if b & 0x20:
                a += 1
                continue
            if b & 0x10:
                break
            if (b & 0x3C) == 4:
                out.add(a + 1)
                break
            a += {0: 4, 1: 6, 2: 6 if b & 0xC0 else 5, 3: 8}[b & 3]
    return out


# Scripts des cinématiques ($88D8) : octets-codes $E0-$FF, opcode = octet & $1F, suivi de N octets.
SCRIPT_TABLE = (0x9ECE, 9)                       # table des scripts (via $8847/$8854)
SCRIPT_NARG = {0: 2, 1: 2, 2: 2, 3: 9, 4: 9, 5: 0, 6: 2, 15: 5, 16: 2, 17: 4, 18: 0, 19: 2, 20: 0, 21: 1,
               22: 3, 23: 1, 24: 1, 25: 0, 26: 3, 27: 3, 28: 2, 29: 4, 30: 3, 31: 6,
               **{k: 0 for k in range(7, 15)}}
# mots-adresses dans les arguments (décalage dans les arguments) : relocalisés selon leur valeur
SCRIPT_WORDS = {0: (0,), 1: (0,), 2: (0,), 3: (0, 2, 4, 6), 4: (0, 2, 4, 6), 6: (0,), 16: (0,), 17: (2,), 22: (1,),
                28: (0,), 29: (2,), 31: (0,)}   # 17/29 ($8A75) : X, Y puis trajectoire
SCRIPT_END = (18, 25)
# arguments qui pointent une table de trajectoire ($8C45) : entrées de 3 octets (dx, dy, pose),
# $80 = fin, $7F + mot = suite de la trajectoire ailleurs ($8C39)
SCRIPT_PATHS = {3: (4, 6), 4: (4, 6), 16: (0,), 17: (2,), 28: (0,), 29: (2,)}   # 3/4 ($F108) : trajectoires 4 et 6


def code_scripts(img):
    """Scripts lancés par le code : « ld hl,script / ld (objet+4),hl » ($CA76, $CAB3, $E549 :
    pointeur de script de l'objet $7195 posé directement)."""
    out = []
    for a in range(0x7800, HI_END - 6):
        if img[a] == 0x21 and img[a + 3] == 0x22:
            v, d = img[a + 1] | (img[a + 2] << 8), img[a + 4] | (img[a + 5] << 8)
            if RAM_OLD[0] <= d < RAM_OLD[1] and RELOC[0] <= v < RELOC[1] and img[v] >= 0xE0:
                out.append(v)
    return out


def script_words(img):
    """Parcourt les scripts depuis la table (et les scripts lancés par l'opcode 22) ; rend les
    positions des mots-adresses et l'ensemble des octets de script."""
    t, n = SCRIPT_TABLE
    todo = [img[t + 2 * i] | (img[t + 2 * i + 1] << 8) for i in range(n)]
    todo += code_scripts(img)
    seen, words, paths = set(), set(), []
    while todo:
        a = todo.pop()
        while a not in seen:
            seen.add(a)
            op = img[a]
            if op < 0xE0:
                break
            o = op & 0x1F
            for off in SCRIPT_WORDS.get(o, ()):
                words.add(a + 1 + off)
            if o == 22:
                todo.append(img[a + 2] | (img[a + 3] << 8))
            for off in SCRIPT_PATHS.get(o, ()):
                paths.append(img[a + 1 + off] | (img[a + 2 + off] << 8))
            a += 1 + SCRIPT_NARG[o]
            if o in SCRIPT_END:
                break
    pseen = set()
    while paths:
        a = paths.pop()
        if not (0x7800 <= a < 0xF2DA):
            continue
        for _ in range(256):
            if a in pseen:
                break
            pseen.add(a)
            b = img[a]
            if b == 0x80:
                break
            if b == 0x7F:
                words.add(a + 1)
                paths.append(img[a + 1] | (img[a + 2] << 8))
                break
            a += 3
    return words


# routines d'affichage qui lisent les données d'origine ($2000-$6EFF) : appelées par une fenêtre
WINDOWED = {0x8376: 'win_8376', 0x83A0: 'win_83A0', 0x8CED: 'win_8CED', 0x8D10: 'win_8D10'}
WIN_INTERNAL = ((0x8376, 0x8422), (0x8CED, 0x8D30))
# remplacements de la frontière : adresse d'origine -> (taille, texte asm)
PATCHES = {
    # $7917 : « ld hl,-$6F81 / add hl,sp » = longueur à effacer de $6F81 jusqu'à la pile
    0x7917: (3, 'ld hl,-($6F81+RAM_SHIFT)'),
    # $D288 : table $D171 (4 octets par entrée) indexée par ($7167)-$17 sur 8 bits : l'original lit
    # au-delà de la table, dans son propre code ($D171-$D573), dont le portage a relocalisé des
    # octets -> copie des octets d'origine dans le moteur (orig_D171)
    0xD288: (3, 'ld hl,orig_D171'),
    # décompresseur RLE vers la VRAM $83A0 : entrée (« ld ($7137),bc » fait par le moteur) et
    # sortie (« jp z,$8422 » -> moteur, qui finit par le « ret » de $8422) : un flot entier vers
    # les tables de motifs/couleurs = une seule transition du décor (display.asm)
    0x83A0: (4, 'call eng_rle_in : nop'),
    0x83B4: (3, 'jp z,eng_rle_out'),
    # attente d'une touche du pavé dans un menu ($9199 « ld bc,($7162) ») : notée par le moteur
    # (menus pilotés à la manette, input.asm) ; eng_menu revient après les 4 octets
    0x9199: (4, 'call eng_menu : db 0'),
    # page des records abandonnée (décision du 2026-10-06) : en fin de partie ($8183), au lieu de
    # charger le fichier 9 (séquence $13), préparer ses paramètres ($F284) et l'exécuter
    # (call $4F00), on va directement à la suite ($8196) avec A = 0 (pas « rejouer ») :
    # séquences $12 et $14, puis retour au titre ($8122)
    0x8188: (14, 'call eng_gameover : xor a : jp $8196 : ds 7, 0'),     # écran de fin (engine.asm)
    # ordre des écrans 0, 2, 3, 4, 1 (écart voulu, 2026-10-07 ; engine.asm eng_next_stage ; ordre
    # d'origine pendant une comparaison avec l'original) : étape suivante ($CA16-$CA2A), étape suivie
    # de la cinématique 7 ($CA00 « ld a,($70FE) : cp 6 »), table des sections ($825B « ld hl,$831F »)
    0xCA16: (21, 'call eng_next_stage : ds 18, 0'),
    0xCA00: (5, 'call eng_stage_cut : ds 2, 0'),
    0x825B: (3, 'call eng_sect_hl'),
}
# points d'entrée de code jamais exécutés dans les parties relevées, rendus atteignables
EXTRA_ENTRIES = (0x8196,)             # suite de la page des records (voir PATCHES $8188)
# octets d'origine recopiés tels quels pour le moteur (adresse, longueur) -> sms/gen/orig_XXXX.bin
ORIG_COPIES = {0xD171: 0x403}


def game_image():
    ddp = open(DDP, 'rb').read()
    tab = {f['n']: f for f in extract.file_table(ddp)}
    img = bytearray(65536)
    for n in (1, 2, 6, 3, 4, 7, 5):
        f = tab[n]
        d = ddp[f['block'] * 1024:(f['block'] + f['count']) * 1024]
        a = f['addr']
        img[a:a + len(d)] = d[:65536 - a]
    img[0x8000:0x8002] = b'\x11\x11'
    return img


def reloc_words():
    p = os.path.join(ROOT, 'sms', 'reloc_words.txt')
    out = set()
    if os.path.exists(p):
        for line in open(p, encoding='utf-8'):
            line = line.split('#')[0].strip()
            if line:
                out.add(int(line, 16))
    return out


def main():
    os.makedirs(GEN, exist_ok=True)
    img = game_image()
    mod = {'name': 'g', 'addr': LO, 'data': bytes(img[LO:HI_END]), 'block': 0, 'count': 0, 'kind': 'code'}
    names, flags, comments = disasm.load_names()
    flags = dict(flags)
    words = reloc_words()
    for a_ in EXTRA_ENTRIES:
        flags[('g', a_)] = {'entry'}
    for t, n in JUMP_TABLES.items():
        for i in range(n):
            words.add(t + 2 * i)
            flags[('g', img[t + 2 * i] | (img[t + 2 * i + 1] << 8))] = {'entry'}
    for t, n in POINTER_TABLES.items():
        for i in range(n):
            w = t + 2 * i
            v = img[w] | (img[w + 1] << 8)
            if RELOC[0] <= v < RELOC[1] or RAM_OLD[0] <= v < RAM_OLD[1]:
                words.add(w)
    words |= song_words(img)
    for a, n in ORIG_COPIES.items():
        with open(os.path.join(GEN, f'orig_{a:04X}.bin'), 'wb') as f:
            f.write(bytes(img[a:a + n]))
    words |= zone_list_words(img)
    import glob
    for pth in glob.glob(os.path.join(ROOT, 'sms', 'cov', '*.pcs')):   # couverture du portage
        for line in open(pth):
            if line.strip():
                flags[('g', int(line, 16))] = {'entry'}
    for w in script_words(img):
        v = img[w] | (img[w + 1] << 8)
        if RELOC[0] <= v < RELOC[1] or RAM_OLD[0] <= v < RAM_OLD[1]:
            words.add(w)
    sig = disasm.load_cov('jeu', mod)
    mem, ins_at, kind, executed = disasm.analyse(mod, sig, names, flags)
    # tables de pointeurs repérées automatiquement : adresse de données citée par une instruction
    # (ld rr,nn) dont les premiers mots (au moins 2 de suite) pointent dans la zone relocalisée
    code_b = set()
    for a_, i_ in ins_at.items():
        code_b.update(range(a_, a_ + i_.size))
    auto = []
    for a_, i_ in ins_at.items():
        t = i_.imm16
        if t is None or not (LO <= t < HI_END) or t in code_b:
            continue
        run_ = []
        first_target = HI_END
        for k in range(16):
            w = t + 2 * k
            if w + 1 >= HI_END or w in code_b or w + 1 in code_b:
                break
            if w >= first_target:              # la table s'arrête là où commencent ses données
                break                          # (ex. $EB7C : 6 pointeurs, puis $C6 $C7 = données)
            v = img[w] | (img[w + 1] << 8)
            if not (RELOC[0] <= v < RELOC[1]):
                break
            run_.append(w)
            if v > t:
                first_target = min(first_target, v)
        if len(run_) >= 2:
            words.update(run_)
            auto.append((t, len(run_)))
    with open(os.path.join(GEN, 'auto_tables.txt'), 'w', newline=chr(10)) as f:
        for t, n in sorted(set(auto)):
            f.write(f'{t:04X} {n}\n')

    def in_game(v):
        return LO <= v < HI_END

    # adresses référencées -> étiquettes
    refs = set()
    for a, ins in ins_at.items():
        for v in list(ins.targets) + [ins.ref, ins.imm16]:
            if v is not None and in_game(v) and v not in SPECIAL:
                refs.add(v)
    for w in words:
        v = img[w] | (img[w + 1] << 8)
        if in_game(v):
            refs.add(v)
    starts = set()
    a = LO
    while a < HI_END:
        starts.add(a)
        a += ins_at[a].size if a in ins_at else 1
    gname = {}
    for (sc, ad), n in names.items():
        if sc != '*' and in_game(ad):
            gname[ad] = n
    label = {}
    equ = {}
    for v in sorted(refs):
        base = v
        while base not in starts:
            base -= 1
        if base == v or base not in ins_at:      # données : on coupe la ligne là
            label[v] = gname.get(v, f'g_{v:04X}')
        else:
            label.setdefault(base, gname.get(base, f'g_{base:04X}'))
            equ[v] = (label[base], v - base)
    for ad, n in gname.items():
        if ad in starts:
            label[ad] = n

    def ref(v, ins_text=''):
        if v in SPECIAL:
            return SPECIAL[v]
        if in_game(v):
            if v in label:
                return label[v]
            if v in equ:
                return f'{equ[v][0]}+{equ[v][1]}'
        if RAM_OLD[0] <= v < RAM_OLD[1]:
            n = names.get(('*', v))
            return f'{n}+RAM_SHIFT' if n else f'${v:04X}+RAM_SHIFT'
        if 0xFC30 <= v < 0xFD60:
            return f'eos_{v:04X}'
        n = names.get(('*', v))
        return n if n and v < 0x2000 else f'${v:04X}'

    def emit(lo, hi, path, org):
        out = [f'; Généré par sms/tools/gen_game.py -- ne pas éditer. Original ${lo:04X}-${hi - 1:04X}',
               f'        ORG ${org:04X}']
        a = lo
        while a < hi:
            if a in label:
                out.append(f'{label[a]}:')
            if HEADER[0] <= a < HEADER[1]:
                out.append('        db "TMR SEGA", $FF, $FF, 0, 0, 0, 0, 0, $4C   ; en-tête SMS (remplissage jamais lu)')
                a = HEADER[1]
                continue
            if a in PATCHES:
                size, text = PATCHES[a]
                out.append(f'        {text:34}; {a:04X} remplacement frontière')
                a += size
                continue
            if a in words:
                v = img[a] | (img[a + 1] << 8)
                out.append(f'        dw {ref(v):30}; {a:04X} mot relocalisé')
                a += 2
                continue
            if a in ins_at:
                ins = ins_at[a]
                internal = any(lo_ <= a < hi_ for lo_, hi_ in WIN_INTERNAL)

                def rf(m):
                    v = int(m.group(1), 16)
                    if v in WINDOWED and not internal and ins.text.split()[0] in ('call', 'jp'):
                        return WINDOWED[v]
                    return ref(v)
                text = re.sub(r'\{W:([0-9A-F]{4})\}', rf, ins.text)
                # valeurs immédiates 16 bits hors {W:} (ld rr,nn) : pas de relocalisation ici
                tag = '' if a in executed else '   ; ?'
                out.append(f'        {text:34}; {a:04X} ' + img[a:a + ins.size].hex() + tag)
                a += ins.size
            else:
                b = a
                while b < hi and (b == a or (b not in label and b not in ins_at and b not in words
                                              and b not in PATCHES and not HEADER[0] <= b < HEADER[1])) and b - a < 16:
                    b += 1
                out.append('        db ' + ','.join('$%02X' % c for c in img[a:b]) + f'   ; {a:04X}')
                a = b
        for v, (lab, k) in sorted(equ.items()):
            if lo <= v < hi:
                out.append(f'g_{v:04X} EQU {lab}+{k}')
        open(path, 'w', encoding='utf-8', newline=chr(10)).write('\n'.join(out) + '\n')

    emit(RELOC[0], RELOC[1], os.path.join(GEN, 'game_lo.asm'), RELOC[0] + RELOC_SHIFT)
    with open(os.path.join(GEN, 'game_lo.asm'), 'a', encoding='utf-8') as f:
        v = img[0x8563] | (img[0x8564] << 8)
        f.write(f"V_8563_INIT EQU {ref(v)}       ; contenu d'origine du mot $8563\n")
    emit(LO, RELOC[0], os.path.join(GEN, 'game_hi.asm'), LO)
    # adresses des sites « ld a,r » et des points de tour, pour les outils
    with open(os.path.join(GEN, 'game_map.txt'), 'w', newline=chr(10)) as f:
        for a in sorted(ins_at):
            if ins_at[a].text == 'ld a,r':
                f.write(f'ldar {a:04X}\n')
    n_exec = sum(1 for a in ins_at if a in executed)
    print(f'{len(ins_at)} instructions ({n_exec} exécutées), {len(label)} étiquettes, {len(equ)} EQU, '
          f'{len(words)} mots relocalisés')


if __name__ == '__main__':
    main()
