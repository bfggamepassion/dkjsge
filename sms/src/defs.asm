; defs.asm - Master System : ports, carte mémoire du portage (VDP_DATA/VDP_CTRL : names.inc)
PSG         equ $7F
PAD1        equ $DC
PAD2        equ $DD
MAP_SLOT0   equ $FFFD
MAP_SLOT1   equ $FFFE
MAP_SLOT2   equ $FFFF
STACK_TOP   equ $DFF0

; RAM ($C000-$DFFF)
GAME_RAM    equ $C000           ; variables du jeu, ex-$6F00-$73FF (décalage +$5100)
RAM_SHIFT   equ GAME_RAM - $6F00
ENG_RAM     equ $C500           ; moteur
VDP_R0      equ $04             ; registre 0 : mode 4
R1_OFF      equ $82             ; écran éteint, sprites 8x16
R1_ON_IRQ   equ $E2             ; écran allumé, interruption de trame, sprites 8x16
R1_SMS      equ $82             ; registre 1 SMS (hors bit 5 recopié du TMS) : écran éteint, sprites 8x16
; pages de la cartouche
PAGE_DATA0  equ 3               ; $0000-$1FFF = page 0 ; $2000-$3FFF = données d'origine
PAGE_DATA1A equ 4               ; $4000-$7FFF d'origine, fichiers 6, 7, 8 chargés
START_DELAY equ 7
ORDRE_PORTAGE equ 0             ; 1 : écrans 0, 2, 3, 4, 1 (eng_next_stage...) ; 0 : ordre d'origine
                                ; (0, 1, 0, 2, 1, 0, 1, 3, 4, 2, 3, 4), comme pendant le lockstep               ; réglage fin du départ (voir eng_start), mesuré dans smssim
