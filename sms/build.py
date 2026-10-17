"""Construit la cartouche : python sms/build.py [--nogen] -> sms/build/dkjr.sms (512 Ko).
Régénère d'abord sms/gen/ (OS7 adapté, code du jeu relocalisé) sauf --nogen,
puis assemble et écrit la somme de contrôle de l'en-tête TMR SEGA ($7FFA)."""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'build', 'dkjr.sms')


def data_pages(rom):
    """Pages « données » (fenêtres) : page 3 = $0000-$1FFF de la page 0 + données d'origine
    $2000-$3FFF ; page 4 = $4000-$7FFF d'origine (fichiers 6, 7, 8), $6F00-$77FF vides,
    $7800-$7FFF = ceux de la page 1. (Page des records, fichiers 9 et 10 : abandonnée.)"""
    sys.path.insert(0, os.path.join(HERE, 'tools'))
    import gen_game
    sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
    import extract
    from sources import DDP
    img = gen_game.game_image()
    ddp = open(DDP, 'rb').read()
    tab = {f['n']: f for f in extract.file_table(ddp)}

    def load(im, n):
        f = tab[n]
        d = ddp[f['block'] * 1024:(f['block'] + f['count']) * 1024]
        im[f['addr']:f['addr'] + len(d)] = d

    gfx = open(os.path.join(HERE, 'gen', 'gfx.bin'), 'rb').read()   # décor converti (gfx_build.py)
    assert 6 * 0x4000 + len(gfx) <= len(rom), 'données du décor trop grandes'
    rom[6 * 0x4000:6 * 0x4000 + len(gfx)] = gfx
    a = bytearray(img)
    load(a, 8)
    P = 0x4000
    rom[3 * P:3 * P + 0x2000] = rom[0:0x2000]
    rom[3 * P + 0x2000:4 * P] = img[0x2000:0x4000]
    for page, im in ((4, a),):
        blk = bytearray(im[0x4000:0x8000])
        blk[0x2F00:0x3800] = bytes([0xFF]) * 0x900          # ancienne RAM et zone inutilisée
        blk[0x3800:0x4000] = rom[P + 0x3800:2 * P]      # $7800-$7FFF : comme la page 1
        rom[page * P:(page + 1) * P] = blk


def main():
    sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
    import sources
    err = sources.check()
    if err:
        sys.exit(err)
    os.makedirs(os.path.join(HERE, 'build'), exist_ok=True)
    if '--nogen' not in sys.argv:
        for t in ('gen_os7.py', 'gen_game.py'):
            subprocess.run([sys.executable, os.path.join(HERE, 'tools', t)], check=True)
    asm = os.path.join(HERE, '..', 'tools', 'sjasmplus', 'sjasmplus.exe')   # fourni (Windows)
    if os.name != 'nt' or not os.path.exists(asm):
        asm = shutil.which('sjasmplus')
    if not asm:
        sys.exit('sjasmplus introuvable : tools/sjasmplus/sjasmplus.exe (Windows) ou dans le PATH')
    r = subprocess.run([asm, '--nologo', '--msg=war', '--sym=../build/dkjr.sym', '--lst=../build/dkjr.lst',
                        '-Wno-fileorg', 'dkjr.asm'], cwd=os.path.join(HERE, 'src'), capture_output=True, text=True)
    print(r.stdout[-3000:], r.stderr[-2000:], end='')
    if r.returncode:
        sys.exit('échec de l\'assemblage')
    rom = bytearray(open(OUT, 'rb').read())
    assert len(rom) == 512 * 1024, len(rom)
    data_pages(rom)
    assert rom[0x7FF0:0x7FF8] == b'TMR SEGA'
    s = sum(rom[:0x7FF0]) & 0xFFFF
    rom[0x7FFA], rom[0x7FFB] = s & 0xFF, s >> 8
    open(OUT, 'wb').write(rom)
    print(f'cartouche {OUT} : {len(rom) // 1024} Ko, somme ${s:04X}')


if __name__ == '__main__':
    main()
