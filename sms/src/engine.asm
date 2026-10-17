; engine.asm - moteur Master System (page 1, après le code relocalisé)
; Étape 1 : démarrage, interruption de trame = NMI d'origine, ports Coleco des manettes,
; cassette simulée (fichiers déjà en ROM). Affichage : routines OS7 inertes (port $C1).

eng_start:
        di
        im 1
        ld sp,STACK_TOP
        xor a
        ld (MAP_SLOT0),a
        inc a
        ld (MAP_SLOT1),a
        inc a
        ld (MAP_SLOT2),a
        ld hl,$C000                 ; RAM à zéro
        ld de,$C001
        ld bc,$1FEF
        ld (hl),0
        ldir
        ld hl,ram_init              ; RAM du jeu telle que l'original la trouve à son entrée
        ld de,GAME_RAM              ; (laissée par l'EOS ; ex. graine de RAND_GEN en $73C8)
        ld bc,$0500
        ldir
        call vdp_init
        call pal_detect
        call title_show             ; écran de titre jusqu'à un bouton (VRAM refaite par gx_init)
        call gx_init                ; décor : VRAM, palettes, cases de tuiles
        xor a                       ; palettes noires : écran ADAM caché (title_show, adam_show)
        out (VDP_CTRL),a
        ld a,$C0
        out (VDP_CTRL),a
        ld b,32
        xor a
.k:     out (VDP_DATA),a
        djnz .k
        ld a,$FF
        ld hl,col_raw
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        ld a,8
        ld (V_FD6F),a
        ld hl,V_8563_INIT           ; valeur d'origine du mot $8563 dans le code
        ld (V_8563),hl
        ld a,PAGE_DATA1A
        ld (data_page1),a
        ; Même moment dans l'image que l'original quand il arrive en $8108 (7 382 T avant le
        ; retour de trame, mesuré dans le simulateur Adam) : le déroulé par image est le même.
.v1:    in a,($7E)
        cp 191
        jr nz,.v1
.v2:    in a,($7E)
        cp 159
        jr nz,.v2
        ld b,START_DELAY
.d:     djnz .d
        ld b,8                      ; B = unité de démarrage, comme après l'amorce
        ei
        jp $8108                    ; game_entry

; Écran de titre (gfx_build.py emit_title : logo de l'écran de chargement de l'Adam, texte du
; portage) : écran éteint et interruptions coupées en entrée ; montré jusqu'à l'appui puis le
; relâchement du bouton 1 ou 2 (manette 1 ou 2), ou title_skip non nul (outils de test).
title_show:
        ld a,TITLE_PAGE
        ld (MAP_SLOT2),a
        ld hl,VRAM_NAME | $4000     ; table des noms
        call title_addr
        ld hl,TITLE_ADDR
        ld de,768 * 2
        call title_copy
        ld hl,$4000                 ; tuiles
        call title_addr
        ld hl,TITLE_ADDR + 768 * 2
        ld de,TITLE_TILES * 32
        call title_copy
        ld hl,VRAM_SAT | $4000      ; aucun sprite
        call title_addr
        ld a,$D0
        out (VDP_DATA),a
        xor a                       ; palette du décor, couleur 0 noire (fond)
        out (VDP_CTRL),a
        ld a,$C0
        out (VDP_CTRL),a
        xor a
        out (VDP_DATA),a
        ld hl,gfx_palette + 1
        ld b,15
.p:     ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz .p
        ld a,2
        ld (MAP_SLOT2),a
        ld a,R1_OFF | $40           ; écran allumé
        ld c,1
        call vdp_reg
title_wait:
        call title_btn
        jr z,title_wait
.up:    ld a,(title_skip)
        or a
        jr nz,.off
        call title_btn
        jr nz,.up
.off:   ld a,R1_OFF
        ld c,1
        call vdp_reg
        xor a
        ld (pause_req),a            ; (Pause pendant le titre : sans effet)
        inc a                       ; écran ADAM (chargement de l'Adam) caché : palette noire après
        ld (adam_hide),a            ; gx_init (eng_start), rendue au menu (adam_show)
        ret

adam_show:                          ; (sp_display_on, adam_hide = 2) : palettes 1-15 et 17-31 rendues
        xor a                       ; (couleur 0 : fond, tenue par eng_backdrop)
        ld (adam_hide),a
        ld a,(irq_busy)
        or a
        push af
        jr nz,.w
        di
.w:     ld a,1
        out (VDP_CTRL),a
        ld a,$C0
        out (VDP_CTRL),a
        ld hl,gfx_palette + 1
        call .o
        ld a,17
        out (VDP_CTRL),a
        ld a,$C0
        out (VDP_CTRL),a
        ld hl,gfx_palette_spr + 1
        call .o
        pop af
        ret nz
        ei
        ret
.o:     ld b,15
.l:     ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz .l
        ret
title_btn:
        ld a,(title_skip)           ; NZ : bouton appuyé (ou titre passé)
        or a
        ret nz
        in a,(PAD1)
        and $30
        cp $30
        jr nz,.yes
        in a,(PAD2)                 ; manette 2 : boutons 1 et 2 = bits 2 et 3 du port $DD
        and $0C
        cp $0C
        ret z
.yes:   or $FF
        ret
title_addr:
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        out (VDP_CTRL),a
        ret
title_copy:
        ld a,(hl)
        out (VDP_DATA),a
        inc hl
        dec de
        ld a,d
        or e
        jr nz,title_copy
        ret

; Écran de fin de partie (records_page $8188, à la place de la page des records de l'original,
; abandonnée) : logo du titre, GAME OVER, scores (2UP : à deux joueurs) ; 5 s (300 images) ou un
; bouton ; puis la VRAM est remise comme le moteur la connaît (tuiles des cases, table des noms,
; tables des sprites) et le jeu continue (retour au menu). Interruptions coupées, son coupé.
; Comparaison avec l'original (nmi_fixed) : rien ; outils de test (title_skip) : sans attente.
eng_gameover:
        ld a,(nmi_fixed)
        or a
        ret nz
        push ix
        push iy
        ld a,i                      ; P/V : interruptions autorisées avant
        push af
        di
        ld a,1
        ld (irq_busy),a             ; (gx_upload : pas de EI)
        ld hl,go_psg                ; son coupé (le jeu le refait)
        ld bc,4 * 256 + PSG
        otir
        ld a,(lay_cur)              ; couche du décor : quittée (cases et palettes du jeu), reprise
        or a                        ; d'après les repères à la prochaine opération
        call nz,lay_switch0
        ld a,R1_OFF
        ld c,1
        call vdp_reg
        ld hl,VRAM_SAT              ; tables des sprites : premier octet gardé, puis fin de table
        call go_rd
        ld (go_sat),a
        ld hl,VRAM_SAT2
        call go_rd
        ld (go_sat + 1),a
        ld hl,VRAM_SAT | $4000
        ld a,$D0
        call go_wr
        ld hl,VRAM_SAT2 | $4000
        ld a,$D0
        call go_wr
        ld a,GO_PAGE
        ld (MAP_SLOT2),a
        ld hl,VRAM_NAME | $4000
        call title_addr
        ld hl,GO_ADDR
        ld de,768 * 2
        call title_copy
        ld hl,$4000
        call title_addr
        ld hl,GO_ADDR + 768 * 2
        ld de,GO_TILES * 32
        call title_copy             ; HL = tuiles des chiffres
        ld (go_dig),hl
        ld hl,(VRAM_NAME | $4000) + 2 * (GO_LINE1 + 4)
        ld de,P1_SCORE + RAM_SHIFT
        call go_score
        ld a,(NB_PLAYERS + RAM_SHIFT)
        cp 2
        jr nz,.one
        ld hl,(VRAM_NAME | $4000) + 2 * (GO_LINE2 + 4)
        ld de,P2_SCORE + RAM_SHIFT
        call go_score
        jr .on
.one:   ld hl,(VRAM_NAME | $4000) + 2 * GO_LINE2    ; un joueur : ligne 2UP effacée
        call title_addr
        ld b,10
.b:     ld a,GO_BLANK
        out (VDP_DATA),a
        xor a
        out (VDP_DATA),a
        djnz .b
.on:    ld a,2
        ld (MAP_SLOT2),a
        ld a,R1_OFF | $40           ; écran allumé
        ld c,1
        call vdp_reg
        ld de,300
.w:     call title_btn              ; (NZ aussi si title_skip)
        jr nz,.up
        in a,(VDP_CTRL)             ; image finie ?
        rlca
        jr nc,.w
        dec de
        ld a,d
        or e
        jr nz,.w
        jr .x
.up:    ld a,(title_skip)
        or a
        jr nz,.x
        call title_btn
        jr nz,.up
.x:     ld a,R1_OFF
        ld c,1
        call vdp_reg
        ld hl,bi_slot               ; tuiles : chaque case reprend le contenu de sa tuile
.t:     ld a,(hl)
        cp GX_FREE
        jr z,.tn
        push hl
        ld a,h
        add a,high cc_lo - high bi_slot
        ld d,a
        ld e,l
        ld a,(de)
        ld c,a
        ld a,d
        add a,high cc_hi - high cc_lo
        ld d,a
        ld a,(de)
        ld b,a
        ld a,(hl)
        call gx_upload
        pop hl
.tn:    inc hl
        ld a,h
        cp high bi_slot + 3
        jr nz,.t
        call gx_end
        ld hl,VRAM_NAME | $4000     ; table des noms : celle que le moteur a appliquée
        call title_addr
        ld hl,name_applied
.n:     ld e,(hl)
        ld a,h
        add a,high bi_slot - high name_applied
        ld d,a
        ld a,(de)
        cp GX_FREE
        jr nz,.nk
        xor a
.nk:    out (VDP_DATA),a
        xor a
        out (VDP_DATA),a
        inc hl
        ld a,h
        cp high name_applied + 3
        jr nz,.n
        ld hl,VRAM_SAT | $4000
        ld a,(go_sat)
        call go_wr
        ld hl,VRAM_SAT2 | $4000
        ld a,(go_sat + 1)
        call go_wr
        ld a,$FF                    ; adresse du VDP : inconnue
        ld (gx_vnext + 1),a
        ld a,($73C4+RAM_SHIFT)      ; registre 1 du jeu : écran, interruption de trame
        and $60
        or R1_SMS
        ld c,1
        call vdp_reg
        xor a
        ld (irq_busy),a
        pop af
        pop iy
        pop ix
        ret po
        ei
        ret
go_rd:  ld a,l                      ; HL = adresse VRAM -> A = octet
        out (VDP_CTRL),a
        ld a,h
        out (VDP_CTRL),a
        nop
        nop
        in a,(VDP_DATA)
        ret
go_wr:  push af                     ; HL = adresse VRAM | $4000, A = octet
        call title_addr
        pop af
        out (VDP_DATA),a
        ret
go_score:                           ; HL = entrée de la table des noms | $4000, DE = 6 chiffres ASCII
        call title_addr
        ld b,6
.d:     ld a,(de)
        sub '0'
        cp 10
        ld c,GO_BLANK
        jr nc,.o
        ld hl,(go_dig)
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld c,(hl)
.o:     ld a,c
        out (VDP_DATA),a
        xor a
        out (VDP_DATA),a
        inc de
        djnz .d
        ret
go_psg: db $9F, $BF, $DF, $FF

; PAL ou NTSC : le compteur de lignes ($7E) saute de $F2 à $BA en PAL, de $DA à $D5 en NTSC.
pal_detect:
.w:     in a,($7E)
        cp $C0
        jr nz,.w
.l:     ld b,a
        in a,($7E)
        cp b
        jr nc,.l                    ; tant qu'il ne redescend pas
        cp $C0                      ; après le saut : < $C0 en PAL
        ld a,0
        rla
        ld (pal_on),a
        ret

; --- NMI différée : aucun tour perdu ---------------------------------------------------------
; La boucle du jeu ($C829) teste à chaque passe la minuterie du tour (TICK_TIMER, $C834) ; une
; passe longue (jeu + OS7 + moteur) peut voir passer deux NMI : la seconde trouve la minuterie
; encore échue, et l'OS7 perd cette échéance (un tour de moins). Le moteur coûte plus que l'envoi
; de l'original : sans rien faire, le portage perdrait des tours là où l'original n'en perd pas,
; et davantage en PAL (écart de 192 lignes). Donc : une NMI qui ferait perdre l'échéance est
; différée jusqu'à ce que la boucle consomme la minuterie (eng_test_signal : une NMI différée à
; chaque test) ; au plus 3 à la fois (une passe de plusieurs images, quand le jeu redessine un
; écran). Mêmes NMI, quelques images plus tard au plus.
; Peut aussi se déclencher quand le jeu vient de quitter sa boucle (fin de manche) : une NMI
; retardée d'au plus une image, sans effet sur la logique.
NMI_OWED_MAX equ 3                  ; NMI différées au plus (passes de plusieurs images : redessins)

nmi_defer:                          ; (sous interruption) Z : NMI délivrée ; NZ : différée
        ld a,(nmi_fixed)            ; NMI imposées par un outil de test (lockstep) : délivrées
        or a
        jr nz,.go
        ld a,(tick_age)             ; (minuterie suivie : celle du tour, écrans 0 à 3 ; écran 4 :
        dec a                       ; celle du moteur d'animation, où se fait tout le jeu ; voir
        jr nz,.go                   ; tick_timer) pas testée depuis la dernière NMI délivrée :
        call tick_timer             ; la boucle du jeu est ailleurs (menus, pause...) : rien à différer
        ld a,(hl)
        ld hl,($73D3+RAM_SHIFT)     ; entrée de la minuterie (3 octets)
        push bc
        ld c,a
        add a,a
        add a,c
        pop bc
        add a,l
        ld l,a
        jr nc,.e
        inc h
.e:     bit 7,(hl)                  ; échue et pas encore vue ?
        jr z,.go
        bit 3,(hl)                  ; (minuterie longue : jamais vue pour le tour)
        jr nz,.go
        inc hl
        ld a,(hl)                   ; échoit encore à cette NMI ?
        dec a
        jr nz,.go
        ld a,(nmi_owed)
        cp NMI_OWED_MAX
        jr nc,.go
        inc a                       ; différée
        ld (nmi_owed),a
        ret
.go:    ld a,(nmi_owed)             ; NMI délivrée ; s'il en reste de différées alors que la boucle
        or a                        ; du jeu ne teste plus la minuterie (elle est ailleurs) : une
        jr z,.g2                    ; de plus, juste après celle-ci (fin de eng_irq)
        ld a,(tick_age)
        cp 2
        jr c,.g2
        ld a,(pal_owed)
        or a
        jr nz,.g2
        ld hl,nmi_owed
        dec (hl)
        inc a
        ld (pal_owed),a
.g2:    ld hl,tick_age
        inc (hl)
        jr nz,.z
        dec (hl)
.z:     xor a
        ret

pal_rd1:                             ; l'indicateur de trame vient d'être lu par le jeu : son
                                    ; interruption est perdue (le gestionnaire du jeu a duré plus
        ld a,(nmi_fixed)            ; d'une image ; l'original aurait reçu cette NMI, imbriquée).
        or a                        ; NMI due ; en PAL, l'image est aussi programmée ici
        jr nz,.x
        ld a,(pal_on)
        or a
        jr z,.nt
        call pal_frame
        jr nz,.x
        jr .o
.nt:    ld a,($73C4+RAM_SHIFT)      ; (NTSC : NMI du jeu autorisée)
        and $20
        jr z,.x
.o:     ld a,1
        ld (pal_owed),a
.x:     ret

nmi_drop:                           ; (sous interruption) NMI sans front : le jeu n'a pas relu
        ld a,(nmi_fixed)            ; l'indicateur, son gestionnaire ayant été retardé par son
        or a                        ; verrou ($70D4) pendant un appel d'affichage, que le moteur fait
        ret nz                      ; plus lentement que l'OS7 : l'original l'aurait eue. Rendue
        ld a,$FF                    ; le jeu est en retard : la prochaine table des sprites attend
        ld (sp_heavy),a             ; (sprite.asm, demande suivante sautée) pour lui laisser le temps
        ld a,(tick_age)             ; plus tard comme une NMI différée (boucle du jeu en cours :
                                    ; minuterie suivie testée depuis la dernière NMI)
        cp 2
        ret nc
        ld a,(nmi_owed)
        cp NMI_OWED_MAX
        ret nc
        inc a
        ld (nmi_owed),a
        ret

tick_timer:                         ; HL = numéro de la minuterie suivie : celle du tour ($7126),
        ld hl,$7126+RAM_SHIFT       ; écran 4 : celle du moteur d'animation ($7145, ANIM_SIGNAL),
        push af                     ; testée par sa boucle ($8879), où se fait tout le jeu (garde AF)
        ld a,($70FD+RAM_SHIFT)
        cp 4
        jr nz,.t
        ld l,low ($7145+RAM_SHIFT)
.t:     pop af
        ret

eng_test_signal:                    ; = OS7 $1FD0 : A = minuterie -> NZ si échue (mêmes registres)
        push hl                     ; autre minuterie que celle suivie : l'original directement
        call tick_timer             ; (indicateurs d'entrée sans effet : refaits par $10D3)
        cp (hl)
        pop hl
        jp nz,$10CB
        ld (ts_timer),a             ; test et suivi de la minuterie du tour sans interruption au
        ld a,i                      ; milieu (sinon une NMI entre les deux serait vue « avant » le
        jp pe,.i                    ; test) ; P/V = interruptions autorisées avant (relu si 0 : une
        ld a,i                      ; interruption acceptée pendant « ld a,i » le met à 0, Z80 NMOS)
.i:     di
        push af
        ld a,(ts_timer)
        call $10CB                  ; TEST_SIGNAL d'origine : A = 0 ou 1, BC DE HL comme l'original
        ld (ts_res),a
        push hl
        xor a                       ; minuterie du tour testée par la boucle du jeu
        ld (tick_age),a
        ld a,(nmi_owed)             ; une NMI différée : maintenant (une par test : la suivante au
        or a                        ; prochain test, quand la boucle aura pris ce tour), si le jeu
        jr z,.x                     ; a relu l'indicateur de la précédente (sinon : plus tard)
        ld a,(tms_flag)
        or a
        jr nz,.x
        ld a,(nmi_owed)
        dec a
        ld (nmi_owed),a
        call nmi_now
.x:     pop hl
        pop af
        ld a,(ts_res)
        jp po,.d
        or a                        ; mêmes indicateurs que la fin de l'original ($10F3 : or a)
        ei
        ret
.d:     or a
        ret

; --- VDP minimal (étape 1) ---------------------------------------------------------------
vdp_reg:
        out (VDP_CTRL),a
        ld a,c
        or $80
        out (VDP_CTRL),a
        ret

vdp_init:
        ld hl,vdp_regs
        ld c,0
.r:     ld a,(hl)
        call vdp_reg
        inc hl
        inc c
        ld a,c
        cp 11
        jr nz,.r
        ret

vdp_regs:
        db VDP_R0, R1_OFF, $FF, $FF, $FF, $FF, $FF, $F0, $00, $00, $FF

; Ordre des écrans voulu (écart à l'original, demandé le 2026-10-07) : 0 lianes, 2 tremplin, 3 tapis,
; 4 machine, 1 clés, puis de nouveau 0. Les numéros d'étape d'origine sont gardés (le jeu y lit ses
; paramètres : table $E85C, sections, cinématiques) : étapes 0 -> 3 -> 7 -> 8 -> 1 -> 0 (premières
; étapes de chaque écran). Comparaison avec l'original (nmi_fixed, lockstep) : ordre d'origine.
eng_next_stage:                     ; next_stage ($CA16) : A = étape suivante
    IF ORDRE_PORTAGE
        ld a,(nmi_fixed)
        or a
        jr nz,.orig
    ELSE
        jr .orig                    ; ordre d'origine
    ENDIF
        push hl
        push de
        ld a,($70FE+RAM_SHIFT)
        ld e,a
        ld d,0
        ld hl,eng_stage_next
        add hl,de
        ld a,(hl)
        pop de
        pop hl
        ret
.orig:  ld a,($70F8+RAM_SHIFT)      ; original : +1, 0 après 11 (cycle de 12) ou après 7
        or a
        ld a,($70FE+RAM_SHIFT)
        jr z,.c8
        cp 11
        jr .w
.c8:    cp 7
.w:     jr nz,.inc
        xor a
        ret
.inc:   inc a
        ret
eng_stage_next:                     ; étape -> suivante (autres étapes : comme l'original)
        db 3, 0, 3, 7, 5, 6, 7, 8, 1, 10, 11, 0

eng_stage_cut:                      ; next_stage ($CA00) : Z si la cinématique 7 suit cette étape :
        push bc                     ; étape 6 dans l'original, étape 1 (écran 1, fin du tour) ici
        ld b,6
    IF ORDRE_PORTAGE
        ld a,(nmi_fixed)
        or a
        jr nz,.o
        ld b,1
    ENDIF
.o:     ld a,($70FE+RAM_SHIFT)
        cp b
        pop bc
        ret

eng_sect_hl:                        ; section_start ($825B) : HL = table des sections ($831F) ; ici,
        push af                     ; l'étape 1 suit la machine : son entrée remet les sprites
        cp $0F                      ; (dernière section du chargement : l'écran ADAM caché prend fin
        jr nz,.k                    ; quand le menu rallume l'écran, adam_show)
        ld a,(adam_hide)
        or a
        jr z,.k
        ld a,2
        ld (adam_hide),a
.k:
    IF ORDRE_PORTAGE
        ld a,(nmi_fixed)            ; normaux ($40), comme l'étape 9 de l'original après l'étape 8
        or a
        ld hl,eng_sect_tab
        jr z,.n
    ENDIF
        ld hl,$831F
.n:     pop af
        ret
eng_sect_tab:                       ; copie de la table $831F, entrée 1 changée
        dw $82C6, eng_sect_1, $82D0, $82D4, $82D8, $82DC, $82E0, $82E4, $82E8, $82EF, $82F4, $82F8, $82FF, $8303, $8307, $830B, $8310, $8312, $8316, $8319, $831C
eng_sect_1:
        db $01, $40, $20, $81, $FF

; Menus (en page 1 : jamais appelé pendant une fenêtre ni une interruption) : le jeu attend une touche du pavé ($9199 : « ld bc,($7162) », B/C = bornes et pavés
; acceptés) ; noté pour input.asm (choix à la croix). Instruction de 4 octets : retour après.
eng_menu:
        push af
        push hl
        ld hl,(menu_bc)             ; autre menu (bornes ou pavés) : repartir du premier choix
        ld bc,($7162+RAM_SHIFT)
        ld (menu_bc),bc
        or a
        sbc hl,bc
        jr z,.same
        xor a
        ld (menu_was),a
.same:  pop hl
        push bc
        ld a,b
        and $7F
        ld (menu_lo),a              ; touches acceptées : de B à C - 1 (bits 0-6)
        ld a,c
        and $7F
        ld (menu_hi),a
        ld a,b                      ; pavé 1 accepté si B bit 7 = 0, pavé 2 si C bit 7 = 0
        rlca
        cpl
        and 1
        ld b,a
        ld a,c
        rlca
        cpl
        and 1
        add a,a
        or b
        ld (menu_pads),a
        ld a,3
        ld (menu_on),a
        pop bc
        pop af
        ex (sp),hl
        inc hl
        ex (sp),hl
        ret

; (données lues par les ldir du démarrage : sous $6F00, que le garde-fou réserve aux anciennes variables)
; = mémoire de l'Adam $6F00-$73FF à l'entrée du jeu ($8108) : tout à 0 sauf $73A7-$73C8
ram_init:
        ds $73A7 - $6F00, 0
        db $08,$00,$44,$08,$D8,$FA,$EE,$FE,$00,$94,$08,$00,$00,$00,$10,$C9
        db $28,$C8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        db $00,$33
        ds $7400 - $73C9, 0
; octets d'origine $D171-$D573 (table $D171 et le code qui la suit, lu par $D288 quand l'index
; dépasse la table : le portage a relocalisé des mots dans ce code)
orig_D171:
        INCBIN "../gen/orig_D171.bin"

        INCLUDE "display.asm"
        INCLUDE "sprite.asm"
        INCLUDE "input.asm"
