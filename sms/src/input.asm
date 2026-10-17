; input.asm - manettes de la SMS -> octets des manettes Coleco (page 1)
;
; Une fois par image, dans l'interruption de trame, avant le gestionnaire du jeu (qui lit les
; manettes par POLLER -> eng_colport -> col_raw) :
; - joystick Coleco (col_raw 0 et 2) : bits 0 haut, 1 droite, 2 bas, 3 gauche, 6 bouton gauche
;   (0 = appuyé) ; pavé (col_raw 1 et 3) : bits 0-3 touche ($F : aucune), 6 bouton droit ;
; - boutons 1 et 2 de la SMS = bouton gauche du Coleco (saut) ; le bouton droit n'est pas lu par le jeu ;
; - bouton Pause = touche « * » sur les deux pavés (le jeu lit celui du joueur courant) ;
; - menus : quand le jeu attend une touche du pavé ($9199, eng_menu), la croix choisit le chiffre
;   (il clignote à l'écran), un bouton le valide (touche tenue IN_HOLD images).
; Manette 2 : haut/bas = port $DC bits 6-7, gauche/droite/1/2 = port $DD bits 0-3.

IN_HOLD     equ 4                   ; images où une touche produite reste appuyée
IN_NONE     equ $0F

in_frame:
        ld hl,frames
        inc (hl)
        in a,(PAD1)                 ; manette 1 : bits 0 haut, 1 bas, 2 gauche, 3 droite, 4 b1, 5 b2
        ld c,a
        in a,(PAD2)
        ld b,a
        ld a,c                      ; manette 2 ramenée au même format
        rlca
        rlca
        and 3                       ; haut, bas
        ld e,a
        ld a,b
        and $0F                     ; gauche, droite, b1, b2
        add a,a
        add a,a
        or e
        or $C0
        ld (in_n2),a
        ld a,c
        or $C0
        ld (in_n1),a
        ld a,(in_n1)                ; octets Coleco
        call in_joy
        ld (col_raw),a
        ld a,(in_n1)
        call in_pad
        ld (col_raw + 1),a
        ld a,(in_n2)
        call in_joy
        ld (col_raw + 2),a
        ld a,(in_n2)
        call in_pad
        ld (col_raw + 3),a
        ; --- Pause : « * » sur les deux pavés pendant IN_HOLD images
        ld a,(pause_req)
        or a
        jr z,.np
        xor a
        ld (pause_req),a
        ld a,IN_HOLD
        ld (in_pause),a
.np:    ld a,(in_pause)
        or a
        jr z,.menu
        dec a
        ld (in_pause),a
        ld c,$09                    ; « * »
        call in_key1
        call in_key2
        ; --- menus
.menu:  call in_menu
        ld a,(in_n1)                ; état précédent (fronts)
        ld (in_prev1),a
        ld a,(in_n2)
        ld (in_prev2),a
        jp gx_end

in_joy:                             ; A = manette (0 = appuyé : haut, bas, gauche, droite, b1, b2) -> joystick
        ld c,$FF
        rra
        jr c,$+4
        res 0,c                     ; haut
        rra
        jr c,$+4
        res 2,c                     ; bas
        rra
        jr c,$+4
        res 3,c                     ; gauche
        rra
        jr c,$+4
        res 1,c                     ; droite
        rra
        jr c,$+4
        res 6,c                     ; bouton 1 -> bouton gauche (saut)
        rra
        jr c,$+4
        res 6,c                     ; bouton 2 -> bouton gauche aussi
        ld a,c
        ret

in_pad:                             ; pavé : aucune touche, bouton droit jamais appuyé
        ld a,$FF
        ret

in_key1:                            ; C = code brut de la touche -> pavé 1
        ld a,(col_raw + 1)
        and $F0
        or c
        ld (col_raw + 1),a
        ret
in_key2:
        ld a,(col_raw + 3)
        and $F0
        or c
        ld (col_raw + 3),a
        ret

; --- menus ---------------------------------------------------------------------------------
in_digit:   db $0A, $0D, $07, $0C, $02, $03, $0E, $05, $01, $0B   ; codes bruts des chiffres 0-9

in_menu:
        ld a,(menu_on)              ; images restantes où le jeu attend une touche (eng_menu)
        or a
        jr nz,.act
        ld a,(menu_was)             ; menu fini : chiffre réaffiché, une fois
        or a
        ret z
        xor a
        ld (menu_was),a
        call in_show0
        ld hl,$FFFF
        ld (menu_cell),hl
        ret
.act:   dec a
        ld (menu_on),a
        ld a,(menu_was)             ; début d'un menu : premier choix
        or a
        jr nz,.on
        inc a
        ld (menu_was),a
        ld a,(menu_lo)
        ld (menu_sel),a
        call in_find
.on:    ld a,(menu_hold)            ; validation en cours : touche tenue
        or a
        jr z,.sel
        dec a
        ld (menu_hold),a
        jr in_out
.sel:   ld bc,$FFFF                 ; manettes des pavés acceptés, combinées (0 = appuyé) :
        ld a,(menu_pads)            ; B maintenant, C avant
        ld e,a
        rr e
        jr nc,.q1
        ld a,(in_n1)
        ld b,a
        ld a,(in_prev1)
        ld c,a
.q1:    rr e
        jr nc,.q2
        ld a,(in_n2)
        and b
        ld b,a
        ld a,(in_prev2)
        and c
        ld c,a
.q2:    ld a,c
        cpl                         ; fronts : appuyé maintenant (0), pas avant (1)
        or b
        cpl                         ; 1 = nouvel appui : bits haut, bas, gauche, droite, b1, b2
        ld c,a
        and $30                     ; un bouton : validation
        jr nz,.ok
        ld a,c
        and $05                     ; haut ou gauche : chiffre précédent
        jr z,.dn
        ld a,(menu_sel)
        ld b,a
        ld a,(menu_lo)
        cp b
        jr z,.dn
        push bc
        call in_show0
        ld hl,menu_sel
        dec (hl)
        call in_find
        pop bc
.dn:    ld a,c
        and $0A                     ; bas ou droite : chiffre suivant
        jr z,.bl
        ld a,(menu_sel)
        inc a
        ld b,a
        ld a,(menu_hi)
        cp b
        jr z,.bl
        call in_show0
        ld hl,menu_sel
        inc (hl)
        call in_find
.bl:    ld a,(frames)               ; clignotement : 16 images sur 32
        and $10
        jp in_show
.ok:    call in_show0
        ld a,IN_HOLD
        ld (menu_hold),a
in_out:                             ; touche du chiffre choisi sur les pavés acceptés
        ld a,(menu_sel)
        ld e,a
        ld d,0
        ld hl,in_digit
        add hl,de
        ld c,(hl)
        ld a,(menu_pads)
        rra
        push af
        call c,in_key1
        pop af
        rra
        call c,in_key2
        ret

in_find:                            ; cellule du chiffre choisi : « chiffre, espace, = » dans les noms
        ld hl,$FFFF
        ld (menu_cell),hl
        ld a,(menu_sel)
        add a,$30
        ld d,a
        ld hl,name_shadow
        ld bc,766
.l:     ld a,(hl)
        cp d
        jr nz,.n
        inc hl
        ld a,(hl)
        dec hl
        cp $20
        jr nz,.n
        inc hl
        inc hl
        ld a,(hl)
        dec hl
        dec hl
        cp $3D
        jr z,.f
.n:     inc hl
        dec bc
        ld a,b
        or c
        jr nz,.l
        ret
.f:     ld de,name_shadow
        or a
        sbc hl,de
        ld (menu_cell),hl
        ret

in_show0:                           ; chiffre visible
        xor a
in_show:                            ; A = 0 : chiffre, sinon espace, dans la cellule menu_cell
        ld e,a
        ld hl,(menu_cell)
        ld a,h
        and l
        inc a
        ret z                       ; pas trouvé
        ld a,h                      ; tuile : (banque, chiffre) ou (banque, espace)
        add a,high bi_slot
        ld d,a
        ld a,e
        or a
        ld a,(menu_sel)
        jr z,.d
        ld a,$20 - $30
.d:     add a,$30
        ld e,a
        ld a,(de)                   ; case SMS
        cp GX_FREE
        ret z
        ld c,a
        add hl,hl                   ; entrée de la table des noms SMS
        ld de,VRAM_NAME | $4000
        add hl,de
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        out (VDP_CTRL),a
        ld a,c
        out (VDP_DATA),a
        ex (sp),hl
        ex (sp),hl
        xor a
        out (VDP_DATA),a
        ret
