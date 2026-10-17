"""Désassemblage Z80 d'un module (OS7 ou code du jeu), utilisé par sms/tools/gen_*.py.

Entrées :
- names.txt (le SEUL fichier de noms) ;
- cov/<module>.txt : adresses exécutées relevées sur l'original pendant des parties
  enregistrées (os7.txt : BIOS, jeu.txt : code du jeu $7800-$F2D9).

Code = adresses exécutées + descente récursive depuis elles et depuis les
points d'entrée de names.txt marqués « entry ». Le reste est en « db ».
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
import z80dis  # noqa: E402

NAMES = os.path.join(ROOT, 'names.txt')


# --- noms ---------------------------------------------------------------------
def load_names():
    """names.txt : « portée adresse nom [entry|data|code] ; commentaire ».
    portée : * (global : RAM, OS7, EOS, ports, constantes) ou un module (f04, boot...)."""
    names = {}
    flags = {}
    comments = {}
    for line in open(NAMES, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        body, _, com = line.partition(';')
        parts = body.split()
        scope, addr, name = parts[0], int(parts[1].lstrip('$'), 16), parts[2]
        names[(scope, addr)] = name
        flags[(scope, addr)] = set(parts[3:])
        comments[(scope, addr)] = com.strip()
    return names, flags, comments

def load_cov(name, mod):
    """cov/<name>.txt -> {adresse: {octets de l'instruction}} pour analyse() ; les octets
    sont ceux du module lui-même (relus dans le fichier d'origine)."""
    base, data = mod['addr'], mod['data']
    sig = {}
    for line in open(os.path.join(ROOT, 'cov', name + '.txt')):
        if line.strip():
            pc = int(line, 16)
            sig[pc] = {bytes(data[pc - base:pc - base + 4])}
    return sig


# --- analyse d'un module ------------------------------------------------------
def analyse(mod, sig, names, flags):
    base, data = mod['addr'], mod['data']
    end = base + len(data)
    mem = bytearray(65536)
    for k, b in enumerate(data):
        mem[(base + k) & 0xFFFF] = b

    def inside(a):
        return base <= a < end

    executed = set()
    for pc, ss in sig.items():
        if inside(pc):
            for s in ss:
                n = min(4, end - pc)
                ins = z80dis.decode(bytes(s) + b'\0' * 4, 0)
                m = min(ins.size, n)
                if bytes(s[:m]) == bytes(data[pc - base:pc - base + m]) and ins.size <= end - pc:
                    executed.add(pc)
                    break
    starts = set(executed)
    for (sc, a), fl in flags.items():
        if sc == mod['name'] and 'entry' in fl and inside(a):
            starts.add(a)
    kind = {}            # adresse -> 'x' exécuté, 'd' descente, 'c' octet suite d'instruction
    ins_at = {}
    todo = sorted(starts)
    while todo:
        a = todo.pop()
        while inside(a) and a not in ins_at:
            ins = z80dis.decode(mem, a)
            if a + ins.size > end or any(a + k in ins_at or kind.get(a + k) == 'c' for k in range(1, ins.size)):
                break
            ins_at[a] = ins
            kind[a] = 'x' if a in executed else 'd'
            for k in range(1, ins.size):
                kind[a + k] = 'c'
            for t in ins.targets:
                if inside(t) and t not in ins_at:
                    todo.append(t)
            if ins.flow in ('jp', 'ret', 'halt') or ins.text.startswith(('jp (', 'reti', 'retn')):
                break
            if ins.flow in ('call', 'rst') and (a + ins.size) not in executed and a in executed:
                # retour jamais vu : peut-être des données en ligne
                break
            a += ins.size
    return mem, ins_at, kind, executed
