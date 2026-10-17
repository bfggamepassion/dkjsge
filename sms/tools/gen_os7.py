"""Page 0 de la cartouche : BIOS ColecoVision (OS7) aux mêmes adresses, adapté.

  python sms/tools/gen_os7.py   -> sms/gen/os7.asm

On garde l'OS7 pour sa LOGIQUE (minuteries, aléa, lecture des manettes, pilote du
son) : mêmes calculs, mêmes résultats que l'original. Adaptations :
- vecteurs : $0000 démarrage, $0030 lecture des manettes Coleco (voir plus bas),
  $0038 interruption de trame SMS, $0066 bouton Pause -> moteur ;
- RAM $7000-$73FF -> RAM SMS (+RAM_SHIFT) dans les instructions exécutées ;
- son : out ($FF) -> port PSG ($7F) (même puce SN76489) ;
- manettes : les 10 accès aux ports Coleco ($FC/$FF/$80/$C0) deviennent « rst $30 / nop » ;
  le moteur répond au format Coleco à partir de la manette SMS (eng_colport) ;
- table de sauts : les entrées d'affichage (VDP) vont au moteur natif.
Les octets non exécutés (affichage, police…) sont recopiés tels quels, inutilisés.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import disasm  # noqa: E402
from sources import OS7_ROM  # noqa: E402

VECTORS = {0x0000: 'jp eng_start', 0x0030: 'jp eng_colport', 0x0038: 'jp eng_irq', 0x0066: 'jp eng_nmi',
           # registres du VDP : aussi appelés en interne par l'OS7 (MODE_1...), donc détournés à la source
           0x1CCA: 'jp eng_write_register', 0x1D57: 'jp eng_read_register',
           # écritures en VRAM (étape 2) : WRITE_VRAM et FILL_VRAM internes (PUT_VRAM passe par $1D01)
           0x1D01: 'jp eng_vram_write', 0x18D4: 'jp eng_vram_fill',
           # envoi de la table des sprites (étape 3)
           0x1C82: 'jp eng_spr_table'}
# entrées d'affichage de la table de sauts -> moteur (étape 2 ; vide = routines OS7 gardées,
# leurs accès VDP envoyés au port inerte $C1 : seuls leurs effets en RAM restent)
NATIVE_DISPLAY = os.environ.get('NATIVE_DISPLAY', '0') == '1'
DISPLAY_ALL = {0x1F7F: 'eng_load_ascii', 0x1F82: 'eng_fill_vram', 0x1F85: 'eng_mode_1', 0x1FB8: 'eng_init_table',
           0x1FBE: 'eng_put_vram', 0x1FC4: 'eng_wr_spr_nm_tbl', 0x1FD9: 'eng_write_register',
           0x1FDC: 'eng_read_register', 0x1FDF: 'eng_write_vram'}
DISPLAY = DISPLAY_ALL if NATIVE_DISPLAY else {}
# toujours : registres du VDP (NMI du TMS9918 : indicateur de trame et autorisation)
DISPLAY = {**DISPLAY, 0x1FD9: 'eng_write_register', 0x1FDC: 'eng_read_register'}
# TEST_SIGNAL : la routine d'origine ($10CB), puis le moteur (NMI différée, engine.asm)
DISPLAY[0x1FD0] = 'eng_test_signal'
INERT = {'out ($BE),a': 'out ($C1),a', 'out ($BF),a': 'out ($C1),a', 'in a,($BF)': 'in a,($C1)', 'ld c,$BE': 'ld c,$C1'}
# trou libre de l'OS7 (ni exécuté ni lu dans aucune partie relevée) : code du moteur appelé
# sous interruption et fenêtres de données (présent à l'identique dans les pages 0 et « données »)
FREE0 = (0x08DF, 0x0F37)
COLPORT_SITES = (0x1142, 0x1146, 0x114A, 0x1150, 0x1156, 0x115B, 0x1161, 0x1167, 0x11AA, 0x11B0)


def main():
    os7 = open(OS7_ROM, 'rb').read()[:0x2000]
    mod = {'name': 'os7', 'addr': 0, 'data': os7, 'block': 0, 'count': 0, 'kind': 'code'}
    names, flags, _ = disasm.load_names()
    mem, ins_at, kind, executed = disasm.analyse(mod, disasm.load_cov('os7', mod), names, flags)
    out = ['; Généré par sms/tools/gen_os7.py -- ne pas éditer', '        ORG $0000']
    sites = []
    a = 0
    while a < 0x2000:
        if a == FREE0[0]:
            out.append('ENGINE0_START:')
            out.append('        INCLUDE "engine0.asm"')
            out.append(f'        ASSERT $ <= ${FREE0[1]:04X}, "engine0 trop grand"')
            out.append(f'        ds ${FREE0[1]:04X} - $, $FF')
            a = FREE0[1]
            continue
        if a in VECTORS:
            out.append(f'        {VECTORS[a]:30}; {a:04X} vecteur')
            a += 3
            continue
        if a in DISPLAY:
            out.append(f'        jp {DISPLAY[a]:27}; {a:04X} entrée d\'affichage -> moteur')
            a += 3
            continue
        if a in COLPORT_SITES:
            code = {'in a,($FC)': 'ld b,b', 'in a,($FF)': 'ld c,c', 'out ($80),a': 'ld d,d', 'out ($C0),a': 'ld e,e'}[ins_at[a].text]
            out.append(f'        rst $30                       ; {a:04X} {ins_at[a].text} (port Coleco)')
            out.append(f'        {code:29} ; action lue par eng_colport, puis exécutée (sans effet)')
            sites.append((a, ins_at[a].text))
            a += 2
            continue
        ins = ins_at.get(a)
        if ins:                          # instructions exécutées ou atteintes par descente
            t = ins.text
            if t == 'out ($FF),a':
                t = 'out (PSG),a'
            t = INERT.get(t, t)
            vals = [int(v, 16) for v in re.findall(r'\{W:([0-9A-F]{4})\}', t)]
            if any(0x7000 <= v < 0x7400 for v in vals) or t != ins.text:
                t = re.sub(r'\{W:([0-9A-F]{4})\}',
                           lambda m: (f'${int(m.group(1), 16):04X}+RAM_SHIFT' if 0x7000 <= int(m.group(1), 16) < 0x7400
                                      else f'${int(m.group(1), 16):04X}'), t)
                out.append(f'        {t:30}; {a:04X} adapté')
                a += ins.size
                continue
        b = a + 1
        while b < 0x2000 and b - a < 16 and b != FREE0[0] and b not in VECTORS and b not in DISPLAY and b not in COLPORT_SITES \
                and b not in ins_at:
            b += 1
        if ins:
            b = a + ins.size
        out.append('        db ' + ','.join('$%02X' % c for c in os7[a:b]) + f'   ; {a:04X}')
        a = b
    open(os.path.join(ROOT, 'sms', 'gen', 'os7.asm'), 'w', encoding='utf-8', newline=chr(10)).write('\n'.join(out) + '\n')
    t = ["; sites des ports Coleco dans l'OS7 : octet bas de (site + 1), action",
         '; 0 lire $FC (manette 1), 1 lire $FF (manette 2), 2 mode pavé ($80), 3 mode joystick ($C0)',
         'colport_sites:']
    for a, txt in sites:
        code = {'in a,($FC)': 0, 'in a,($FF)': 1, 'out ($80),a': 2, 'out ($C0),a': 3}[txt]
        t.append(f'        db ${(a + 1) & 0xFF:02X}, {code}          ; {a:04X} {txt}')
    t.append('        db 0, $FF')
    open(os.path.join(ROOT, 'sms', 'gen', 'os7_sites.asm'), 'w', encoding='utf-8', newline=chr(10)).write('\n'.join(t) + '\n')
    print(f'OS7 : {len(executed)} instructions exécutées, {len(sites)} sites de ports Coleco')


if __name__ == '__main__':
    main()
