; dkjr.asm - cartouche Master System de Donkey Kong Junior (512 Ko, mappeur Sega)
; Page 0 : OS7 adapté ($0000-$1FFF) + code d'origine $C000-$DFFF relocalisé ($2000-$3FFF)
; Page 1 : suite du code relocalisé ($4000-$52D9), moteur, code d'origine $7800-$7FFF
; Page 2 : code d'origine $8000-$BFFF (à ses adresses)
        INCLUDE "defs.asm"
        INCLUDE "../../src/names.inc"
        OUTPUT "../build/dkjr.sms"
        INCLUDE "../gen/os7.asm"
        INCLUDE "../gen/game_lo.asm"
ENGINE_START:
        INCLUDE "engine.asm"
ENGINE_END:
        ASSERT ENGINE_END <= $7800, "moteur trop grand pour la page 1"
        ds $7800 - $, $FF
        INCLUDE "../gen/game_hi.asm"
        ASSERT $ == $C000
        REPT 29
        ORG $8000
        ds $4000, $FF
        ENDR
        OUTEND
        INCLUDE "vars.asm"
        ASSERT ENG_RAM_END <= $DF80     ; (au-dessus : pile du démarrage ; le jeu prend la sienne en $810C)
