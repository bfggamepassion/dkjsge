; display.asm - décor natif (page 1, appelé par les remplaçants de l'OS7 dans engine0.asm)
;
; Table des noms : chaque écriture du jeu (cellule n, motif t) devient une entrée de la table des
; noms SMS. La tuile TMS (banque = n / 256, motif t) reçoit une case de tuile SMS à la demande
; (compteur de références : une case par tuile TMS affichée, au plus 177 mesurées) ; la case est
; chargée avec le contenu converti hors ligne (sms/tools/gfx_build.py) de cette tuile.
; Tables de motifs et de couleurs : chaque opération du jeu sur ces tables fait avancer
; l'automate relevé sur l'original (liste de l'état courant -> liste de l'état suivant + tuiles
; dont le contenu change) ; les cases des tuiles changées sont rechargées. Données de l'automate
; et tuiles : pages GFX_PAGE0..., lues par l'emplacement 2 ($8000-$BFFF), remis sur la page 2
; en sortie (gx_end).
; Tables en RAM alignées sur 256 octets (vars.asm), indexées par (banque, motif) ou cellule :
; name_shadow (table des noms écrite par le jeu), name_applied (ce que montre l'écran SMS),
; bi_slot, cc_lo/cc_hi (contenu actuel), ref_lo/ref_hi (références par case).
; Écritures de noms : recopiées dans name_shadow (engine0), puis gx_reconcile met l'écran
; d'accord, après chaque opération, ou à la fin d'un flot RLE vers la table des noms.

GX_FREE     equ $FF                 ; « aucune case »
VRAM_NAME   equ $3800
VRAM_SAT    equ $3F00
VRAM_SAT2   equ $3E00               ; seconde table des sprites (sprite.asm) : lignes 24-27 de la table des noms, jamais montrées

; --- initialisation (écran éteint, interruptions coupées) ------------------------------------
gx_init:
        xor a                       ; VRAM à zéro
        out (VDP_CTRL),a
        ld a,$40
        out (VDP_CTRL),a
        ld b,0                      ; 64 x 256 octets
        ld d,64
        ld c,VDP_DATA
        xor a
.z:     out (c),a
        djnz .z
        dec d
        jr nz,.z
        xor a                       ; palettes : couleurs du TMS (0 = fond, noir au départ)
        out (VDP_CTRL),a
        ld a,$C0
        out (VDP_CTRL),a
        ld hl,gfx_palette           ; palette du décor (CRAM 0-15) puis des sprites (16-31)
        ld b,16
.p:     ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz .p
        ld hl,gfx_palette_spr
        ld b,16
.p2:    ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz .p2
        ld a,low VRAM_SAT           ; aucun sprite (étape 3)
        out (VDP_CTRL),a
        ld a,high VRAM_SAT | $40
        out (VDP_CTRL),a
        ld a,$D0
        out (VDP_DATA),a
        ld hl,bi_slot               ; aucune tuile TMS n'a de case
        ld de,bi_slot + 1
        ld bc,767
        ld (hl),GX_FREE
        ldir
        xor a
        ld (gx_list),a              ; état des tables de motifs inconnu (jusqu'à l'effacement complet)
        ld (sq_list),a              ; idem pour les motifs des sprites
        ld a,2                      ; registres 0, 3 et 4 tels que supposés au départ (gfx_build.py)
        ld (tms_r0),a
        ld a,$FF
        ld (tms_r3),a
        ld a,3
        ld (tms_r4),a
        call sp_init
        ld a,2
        ld (cur_slot2),a
        ; cases 0, 1, 2 : motif 0 des banques 0, 1, 2 (toute la table des noms vaut 0 au départ)
        xor a
        ld (bi_slot),a
        inc a
        ld (bi_slot + 256),a
        ld (ref_hi),a               ; 256 références chacune
        ld (ref_hi + 1),a
        ld (ref_hi + 2),a
        inc a
        ld (bi_slot + 512),a
        ld hl,free_slots            ; cases libres 3..254 (la prochaine prise est la 3)
        ld b,252
        ld a,254
.f:     ld (hl),a
        inc hl
        dec a
        djnz .f
        ld a,252
        ld (free_top),a
        ld hl,VRAM_NAME | $4000     ; entrées de la table des noms SMS : banque b -> case b
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        out (VDP_CTRL),a
        ld c,0
.nb:    ld b,0                      ; 256 cellules par banque
.nc:    ld a,c
        out (VDP_DATA),a
        xor a
        out (VDP_DATA),a
        djnz .nc
        inc c
        ld a,c
        cp 3
        jr nz,.nb
        ret

        INCLUDE "../gen/gfx_spr.inc"     ; palette des sprites (éditeur graphique)

; --- emplacement 2 -------------------------------------------------------------------------
gx_map:                             ; A = page en $8000-$BFFF (cur_slot2 d'abord : voir eng_irq)
        ld (cur_slot2),a
        ld (MAP_SLOT2),a
        ret

gx_end:                             ; remet la page 2 (code du jeu) en $8000
        ld a,2
        ld (cur_slot2),a
        ld (MAP_SLOT2),a
        ret

; --- écritures dans la table des noms ------------------------------------------------------
gx_reconcile_e:                     ; depuis engine0 : gx_nlen cellules dès gx_ncell
        ld hl,(gx_ncell)
        ld bc,(gx_nlen)
gx_reconcile:                       ; HL = première cellule, BC = nombre : écran SMS = name_shadow
        ld a,$FF                    ; adresse du VDP : inconnue
        ld (gx_vnext + 1),a
        ld a,h
        add a,high name_shadow
        ld h,a                      ; HL = &name_shadow[cellule]
.l:     ld a,h
        add a,high name_applied - high name_shadow
        ld d,a
        ld e,l                      ; DE = &name_applied[cellule]
        ld a,(de)                   ; affiché
        cp (hl)                     ; demandé
        jr nz,.ch
.n:     inc hl
        dec bc
        ld a,b
        or c
        jr nz,.l
        jp lay_check_end
.ch:    push bc
        push hl
        ld b,a
        ld a,(lay_cur)
        or a
        ld a,b
        jr nz,.lc
        call gx_cell
        jr .cd
.lc:    call lay_cell
.cd:    pop hl
        pop bc
        jr .n

; Une cellule change : HL = &name_shadow[cellule], DE = &name_applied[cellule], A = ancienne
; tuile. Références des cases (ancienne -1, nouvelle +1, case libérée ou prise), puis entrée de
; la table des noms SMS ; cellules consécutives écrites à la suite (gx_vnext : cellule où en
; est le VDP, $FFxx : inconnue ; remis par eng_irq et gx_upload).
gx_cell:
        ld b,a                      ; B = ancienne tuile
        ld c,(hl)                   ; C = nouvelle
        ld a,c
        ld (de),a
        ld a,h
        add a,high bi_slot - high name_shadow
        ld h,a                      ; H = bi_slot de la banque, L = cellule (octet bas)
        ld d,h
        ld e,b
        ld a,(de)                   ; case de l'ancienne tuile
        cp GX_FREE
        jr z,.acq
        push hl
        ld l,a
        ld h,high ref_lo
        dec (hl)                    ; une référence de moins (16 bits)
        ld a,(hl)
        inc a
        jr nz,.nb
        inc h
        dec (hl)
        dec h
.nb:    ld a,(hl)
        inc h
        or (hl)
        jr nz,.kept
        ld a,GX_FREE                ; plus référencée : la case redevient libre
        ld (de),a
        ld a,(free_top)
        ld e,a
        inc a
        ld (free_top),a
        ld d,high free_slots
        ld a,l
        ld (de),a
.kept:  pop hl
.acq:   ld b,l                      ; B = cellule (octet bas)
        ld d,h
        ld e,c
        ld a,(de)                   ; case de la nouvelle tuile
        cp GX_FREE
        jr z,.new
        ld l,a
        ld h,high ref_lo
        inc (hl)                    ; une référence de plus
        jr nz,.w
        inc h
        inc (hl)
        jr .w
.new:   push bc
        call gx_new                 ; DE = &bi_slot[tuile] -> A = case prise et chargée
        pop bc
.w:     ld c,a                      ; C = case ; cellule = (D - bi_slot) : B
        ld a,d
        sub high bi_slot
        ld h,a
        ld l,b
        ld a,(irq_busy)             ; séquence VDP protégée de l'interruption
        or a
        jr nz,.o
        di
.o:     ld de,(gx_vnext)
        ld a,l
        cp e
        jr nz,.ad
        ld a,h
        cp d
        jr z,.dt
.ad:    push hl                     ; entrée $3800 + 2 x cellule
        add hl,hl
        ld de,VRAM_NAME | $4000
        add hl,de
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        out (VDP_CTRL),a
        pop hl
.dt:    ld a,c
        out (VDP_DATA),a
        inc hl                      ; (26 T au moins entre deux écritures, écran allumé)
        ld (gx_vnext),hl
        xor a
        out (VDP_DATA),a
        ld a,(irq_busy)
        or a
        ret nz
        ei
        ret

gx_new:                             ; DE = &bi_slot[tuile] (D = page de la banque) -> A = case
        ld a,(free_top)             ; case libre, une référence, chargée avec le contenu actuel
        or a
        jr z,.full
        dec a
        ld (free_top),a
        ld l,a
        ld h,high free_slots
        ld a,(hl)                   ; case libre
        ld (de),a                   ; bi_slot[tuile] = case
        ld l,a
        ld h,high ref_lo
        ld (hl),1
        inc h
        ld (hl),0
        push de
        ld a,d                      ; contenu actuel de la tuile -> chargé dans la case
        add a,high cc_lo - high bi_slot
        ld d,a
        ld a,(de)
        ld c,a
        inc d
        inc d
        inc d
        ld a,(de)
        ld b,a
        ld a,l
        push af
        call gx_upload
        pop af
        pop de
        ret
.full:  ld hl,(gx_err_full)         ; plus de case libre (non vu) : compté, case 0
        inc hl
        ld (gx_err_full),hl
        xor a
        ret

gx_upload:                          ; A = case, BC = contenu (numéro de tuile convertie)
        ld l,a
        ld a,$FF                    ; l'adresse du VDP change
        ld (gx_vnext + 1),a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        set 6,h                     ; écriture en VRAM, case * 32
        ld a,b
        and c
        inc a
        jr nz,.k
        ld bc,0                     ; contenu jamais affiché dans les relevés : tuile vide, compté
        push hl
        ld hl,(gx_err_none)
        inc hl
        ld (gx_err_none),hl
        pop hl
.k:     ld a,b                      ; page = GFX_PAGE0 + contenu / 512
        srl a
        add a,GFX_PAGE0
        call gx_map
        ld a,b                      ; adresse = $8000 + (contenu % 512) * 32
        and 1
        ld d,a
        ld e,c
        ex de,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        set 7,h
        ex de,hl                    ; DE = source, HL = adresse VRAM
        ld a,(irq_busy)
        or a
        jr nz,.w
        di
.w:     ld a,l
        out (VDP_CTRL),a
        ld a,h
        out (VDP_CTRL),a
        ex de,hl
        ld bc,32 * 256 + VDP_DATA
        ld a,($73C4+RAM_SHIFT)      ; écran éteint : à pleine vitesse
        and $40
        jr nz,.o
        otir
        jr .e
.o:     outi                        ; écran allumé : au moins 26 T entre deux écritures
        nop
        jp nz,.o
.e:
        ld a,(irq_busy)
        or a
        ret nz
        ei
        ret

; --- opération sur les tables de motifs / couleurs : automate -------------------------------
gx_pc:                              ; clé dans gx_kind (7 octets) ; liste de l'état : gx_list
        ld a,(gx_list)
        or a
        jr z,.any                   ; état inconnu : seul l'effacement complet est reconnu
        call gx_map
        ld hl,(gx_list + 1)
        call gx_find
        jr z,.found
.any:   ld a,GFX_ANY_PAGE
        call gx_map
        ld hl,GFX_ANY_ADDR
        call gx_find
        jp nz,gx_end                ; clé inconnue : opération sans effet sur le décor
.found: ld de,gx_list               ; liste de l'état suivant
        ldi
        ldi
        ldi
        ld a,(hl)                   ; tuiles changées : page, adresse, nombre
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        or a
        jp z,gx_end
        ld (gx_dpage),a
        ex de,hl
        ld a,(lay_cur)              ; couche : plus de LAY_BIG tuiles changées -> écran redessiné
        or a                        ; à la fin (lay_cur invalide), contenus seulement d'ici là
        jr z,.d
        push hl
        ld hl,LAY_BIG
        or a
        sbc hl,bc
        pop hl
        jr nc,.d
        ld a,$FF
        ld (lay_cur),a
.d:     ld a,b
        or c
        jp z,lay_check_end
        push bc
        ld a,(gx_dpage)
        call gx_map
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl
        push hl
        call gx_set_content
        pop hl
        pop bc
        dec bc
        jr .d

gx_set_content:                     ; DE = tuile (D banque, E motif), BC = nouveau contenu
        ld a,(lay_cur)
        or a
        jp nz,lay_setc
gx_set_cc:
        ld a,d
        add a,high cc_lo
        ld h,a
        ld l,e
        ld (hl),c
        add a,3                     ; cc_hi
        ld h,a
        ld (hl),b
        ld a,d
        add a,high bi_slot
        ld h,a
        ld a,(hl)
        cp GX_FREE
        ret z                       ; pas affichée : chargée à sa prochaine utilisation
        jp gx_upload

gx_find:                            ; HL = liste -> Z et HL après la clé si trouvée
        ld b,(hl)
        inc hl
        inc b
.n:     dec b
        jr z,.no
        push hl
        ld de,gx_kind
        ld c,7
.c:     ld a,(de)
        cp (hl)
        jr nz,.ne
        inc de
        inc hl
        dec c
        jr nz,.c
        pop af
        xor a
        ret
.ne:    pop hl
        ld de,15
        add hl,de
        jr .n
.no:    or 1
        ret

; --- couches du décor (sms/tools/couches.py) ------------------------------------------------
; Écran de jeu reconnu par ses cases repères (lay_check) : la tuile SMS d'une cellule dépend de la
; cellule et du contenu de sa tuile TMS (lay_find : liste de la cellule dans la page B de la
; couche). bi_slot sert alors de table « tuile de base -> case » (bases 0-767, puis bi_slot4 : 768-1023), mêmes références
; par case. Changement de couche (ou grosse transition des motifs) : palette éteinte, toutes les
; cases libérées, écran redessiné (lay_switch). lay_cur : 0 aucune, 1-n, $FF à redessiner.
LAY_BIG     equ 8                   ; transition des motifs de plus de LAY_BIG tuiles : redessin
LAY_NBUF    equ 16                  ; cellules d'une tuile changée reprises une à une (lay_buf)
LAY_SC_LEN  equ 3 + LAY_NBUF        ; liste du cache de lay_scan : banque, motif, nombre, cellules

lay_cid:                            ; H = banque, A = motif -> DE = contenu actuel (garde HL, BC)
        ld e,a
        ld a,h
        add a,high cc_lo
        ld d,a
        ld a,(de)
        push af
        ld a,d
        add a,high cc_hi - high cc_lo
        ld d,a
        ld a,(de)
        ld d,a
        pop af
        ld e,a
        ret

lay_find:                           ; HL = cellule, DE = contenu -> BC = base, A = octet haut du nom
        push de
        ld a,(lay_pb)               ; index (page B) : 3 octets par cellule (page, adresse de sa liste)
        call gx_map
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ld de,(lay_ab)
        add hl,de
        ld a,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl                    ; HL = liste de la cellule
        call gx_map
        pop de
        ld b,(hl)
        inc hl
        push hl                     ; première entrée : par défaut
.l:     ld a,(hl)
        cp e
        jr nz,.n
        inc hl
        ld a,(hl)
        dec hl
        cp d
        jr z,.f
.n:     inc hl
        inc hl
        inc hl
        inc hl
        djnz .l
        pop hl
        jr .g
.f:     pop af
.g:     inc hl
        inc hl
        ld c,(hl)
        inc hl
        ld a,(hl)
        and 3
        ld b,a
        ld a,(hl)
        rrca
        rrca
        and $0E
        ret

lay_bpage:                          ; A = octet haut d'une base (0-3) -> page de sa case (bi_slot, bi_slot4)
        cp 3
        jr c,.l
        ld a,high bi_slot4
        ret
.l:     add a,high bi_slot
        ret

lay_release:                        ; BC = base : une référence de moins à sa case
        ld a,b
        call lay_bpage
        ld d,a
        ld e,c
        ld a,(de)
        cp GX_FREE
        ret z
        ld l,a
        ld h,high ref_lo
        dec (hl)
        ld a,(hl)
        inc a
        jr nz,.nb
        inc h
        dec (hl)
        dec h
.nb:    ld a,(hl)
        inc h
        or (hl)
        ret nz
        ld a,GX_FREE                ; plus référencée : la case redevient libre
        ld (de),a
        ld a,(free_top)
        ld e,a
        inc a
        ld (free_top),a
        ld d,high free_slots
        ld a,l
        ld (de),a
        ret

lay_acquire:                        ; BC = base -> A = case (prise, chargée si nouvelle)
        ld a,b
        call lay_bpage
        ld d,a
        ld e,c
        ld a,(de)
        cp GX_FREE
        jr z,.new
        ld l,a
        ld h,high ref_lo
        inc (hl)
        ret nz
        inc h
        inc (hl)
        ret
.new:   ld a,(free_top)
        or a
        jr z,.full
        dec a
        ld (free_top),a
        ld l,a
        ld h,high free_slots
        ld a,(hl)
        ld (de),a
        ld l,a
        ld h,high ref_lo
        ld (hl),1
        inc h
        ld (hl),0
        push af
        ld h,b                      ; contenu global de la base : page A, après 21 octets
        ld l,c
        add hl,hl
        ld de,(lay_aa)
        add hl,de
        ld de,21
        add hl,de
        ld a,(lay_pa)
        call gx_map
        ld c,(hl)
        inc hl
        ld b,(hl)
        pop af
        push af
        call gx_upload
        pop af
        ret
.full:  ld hl,(gx_err_full)
        inc hl
        ld (gx_err_full),hl
        xor a
        ret

lay_put:                            ; HL = cellule, A = motif : case prise et entrée écrite
        push hl
        call lay_cid
        call lay_find
        ld (lay_hi),a
        call lay_acquire
        pop hl
lay_write:                          ; HL = cellule, A = case, lay_hi : entrée de la table des noms
        ld c,a
        ld a,(irq_busy)
        or a
        jr nz,.o
        di
.o:     ld de,(gx_vnext)
        ld a,l
        cp e
        jr nz,.ad
        ld a,h
        cp d
        jr z,.dt
.ad:    push hl
        add hl,hl
        ld de,VRAM_NAME | $4000
        add hl,de
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        out (VDP_CTRL),a
        pop hl
.dt:    ld a,c
        out (VDP_DATA),a
        inc hl                      ; (26 T au moins entre deux écritures, écran allumé)
        ld (gx_vnext),hl
        ld a,(lay_hi)
        out (VDP_DATA),a
        ld a,(irq_busy)
        or a
        ret nz
        ei
        ret

lay_cell:                           ; comme gx_cell (HL = &name_shadow[cellule], DE = &name_applied,
        ld b,a                      ; A = ancienne tuile), couche active
        ld a,(hl)
        ld (de),a
        ld c,a
        ld a,h
        sub high name_shadow
        ld h,a                      ; HL = cellule
        push bc
        push hl
        call lay_sc_drop
        pop hl
        pop bc
        push bc
        push hl
        ld a,b
        call lay_cid
        call lay_find
        call lay_release
        pop hl
        pop bc
        ld a,c
        jp lay_put

lay_setc:                           ; gx_set_content, couche active : DE = tuile, BC = contenu
        ld a,(lay_cur)
        inc a
        jr z,.cc                    ; écran redessiné à la fin : contenu seulement
        push bc
        push de
        call lay_scan               ; cellules de cette tuile (lay_buf), références rendues
        pop de
        pop bc
        call .cc
        ld hl,lay_buf               ; puis reprises avec le nouveau contenu
        ld a,(lay_nb)
        or a
        ret z
        ld b,a
.p:     push bc
        push hl
        push de
        ld l,(hl)
        ld h,d                      ; HL = cellule
        ld a,e
        call lay_put
        pop de
        pop hl
        pop bc
        inc hl
        djnz .p
        ret
.cc:    ld a,d
        add a,high cc_lo
        ld h,a
        ld l,e
        ld (hl),c
        add a,high cc_hi - high cc_lo
        ld h,a
        ld (hl),b
        ret

lay_scan:                           ; D = banque, E = motif : cellules de la banque qui montrent ce
        ld hl,lay_sc                ; motif -> lay_buf (octets bas), lay_nb ; références rendues.
        ld b,2                      ; Cache de 2 listes (lay_sc : banque, motif, nombre, cellules ;
.sc:    ld a,(hl)                   ; banque $FF : vide), oubliées quand une cellule de leur banque
        cp d                        ; prend ou perd leur motif (lay_cell) : le clignotement du
        jr nz,.sn                   ; « 1UP » (2 tuiles, toujours les mêmes cellules) sans cpir
        inc hl
        ld a,(hl)
        dec hl
        cp e
        jr z,.hit
.sn:    push de
        ld de,LAY_SC_LEN
        add hl,de
        pop de
        djnz .sc
        call .scan
        ld a,(lay_cur)              ; liste complète (pas de redessin) : gardée
        inc a
        ret z
        ld a,(lay_sc_next)
        xor 1
        ld (lay_sc_next),a
        ld hl,lay_sc
        jr z,.st
        ld hl,lay_sc + LAY_SC_LEN
.st:    ld (hl),d
        inc hl
        ld (hl),e
        inc hl
        ex de,hl
        ld hl,lay_nb
        ld bc,1 + LAY_NBUF
        ldir
        ret
.hit:   inc hl                      ; liste connue : lay_buf, puis références rendues
        inc hl
        push de
        ld de,lay_nb
        ld bc,1 + LAY_NBUF
        ldir
        pop de
        ld a,(lay_nb)
        or a
        ret z
        ld b,a
        ld hl,lay_buf
.hr:    push bc
        push hl
        push de
        ld l,(hl)
        ld h,d                      ; HL = cellule
        ld a,e
        call lay_cid
        call lay_find
        call lay_release
        pop de
        pop hl
        pop bc
        inc hl
        djnz .hr
        ret
.scan:  xor a                       ; parcours de la banque (cpir)
        ld (lay_nb),a
        ld a,d
        add a,high name_applied
        ld h,a
        ld l,0
        ld bc,256
.l:     ld a,e
        cpir
        ret nz                      ; plus aucune
        push bc
        push hl
        push de
        dec hl
        ld a,(lay_nb)               ; (au-delà de LAY_NBUF cellules : écran redessiné à la fin)
        cp LAY_NBUF
        jr c,.k
        ld a,$FF
        ld (lay_cur),a
        jr .x
.k:     ld c,a                      ; lay_buf[rang] = cellule (octet bas)
        inc a
        ld (lay_nb),a
        ld b,0
        ld a,l
        push hl
        ld hl,lay_buf
        add hl,bc
        ld (hl),a
        pop hl
        ld a,h
        sub high name_applied
        ld h,a                      ; HL = cellule
        ld a,e
        call lay_cid
        call lay_find
        call lay_release
.x:     pop de
        pop hl
        pop bc
        ld a,b
        or c
        jr nz,.l
        ret

lay_sc_drop:                        ; H = banque, B = ancien motif, C = nouveau : listes du cache de
        ld a,h                      ; cette banque qui ont l'un de ces motifs oubliées
        ld hl,lay_sc
        call .one
        ld hl,lay_sc + LAY_SC_LEN
.one:   cp (hl)                     ; A = banque, HL = liste
        ret nz
        inc hl
        push af
        ld a,(hl)
        cp b
        jr z,.dr
        cp c
        jr z,.dr
        pop af
        dec hl
        ret
.dr:    dec hl
        ld (hl),$FF
        pop af
        ret

lay_check_end:                      ; fin d'une opération : repères, puis page 2 remise
        call lay_check
        jp gx_end

lay_check:                          ; couche montrée d'après les cases repères ; autre -> lay_switch
    IF LAY_N == 0
        ret
    ELSE
        ld a,LAY_PAGE
        call gx_map
        ld hl,LAY_ADDR
        ld b,(hl)
        inc hl
        ld c,1
.c:     ld a,b
        or a
        jr z,.none
        push hl
        call .anch
        call z,.anch
        pop hl
        jr z,.found
        ld de,11
        add hl,de
        inc c
        dec b
        jr .c
.none:  ld c,0
.found: ld a,c                      ; couche désignée par les repères (aussi en lockstep : sprite.asm)
        ld (lay_seen),a
        ld a,(nmi_fixed)            ; outils de test (lockstep) : décor d'origine, comparé à l'original
        or a
        ret nz
        ld a,(lay_cur)
        cp c
        ret z
        ld a,c
        or a
        jr z,lay_switch
        ld de,8                     ; pointeur de l'enregistrement A
        add hl,de
        ld a,(hl)
        ld (lay_pa),a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (lay_aa),de
        ld a,c
        jr lay_switch
.anch:  ld e,(hl)                   ; HL = repère (cellule, contenu) -> Z si présent, HL après
        inc hl
        ld a,(hl)
        inc hl
        add a,high name_shadow
        ld d,a
        ld a,(de)                   ; motif à cette cellule
        ld e,a
        ld a,d
        add a,high cc_lo - high name_shadow
        ld d,a
        ld a,(de)
        cp (hl)
        inc hl
        jr nz,.a1
        ld a,d
        add a,high cc_hi - high cc_lo
        ld d,a
        ld a,(de)
        cp (hl)
.a1:    inc hl
        ret
    ENDIF

lay_switch0:
        xor a
lay_switch:                         ; A = couche (0 : aucune) : palettes, cases, écran redessiné
        ld (lay_cur),a
        or a
        jr z,.p0
        ld a,(lay_pa)               ; page A : pointeur de B
        call gx_map
        ld hl,(lay_aa)
        ld de,18
        add hl,de
        ld a,(hl)
        ld (lay_pb),a
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (lay_ab),de
.p0:    ld a,(irq_busy)             ; couleurs 1-15 et 17-31 éteintes pendant le redessin (rien de
        or a                        ; l'état du jeu n'est touché : le registre 1 reste le sien)
        jr nz,.k
        di
.k:     ld c,1
        call .zero
        ld c,17
        call .zero
        ld a,(irq_busy)
        or a
        jr nz,.r
        ei
.r:     ld a,$FF                    ; cache de lay_scan vidé
        ld (lay_sc),a
        ld (lay_sc + LAY_SC_LEN),a
        ld hl,bi_slot               ; toutes les cases libres (0-254)
        ld de,bi_slot + 1
        ld bc,767
        ld (hl),GX_FREE
        ldir
        ld hl,bi_slot4
        ld de,bi_slot4 + 1
        ld bc,255
        ld (hl),GX_FREE
        ldir
        ld hl,ref_lo
        ld de,ref_lo + 1
        ld bc,511
        ld (hl),0
        ldir
        ld hl,free_slots
        ld a,254
.f:     ld (hl),a
        inc hl
        dec a
        cp $FF
        jr nz,.f
        ld a,255
        ld (free_top),a
        ld a,$FF
        ld (gx_vnext + 1),a
        ld hl,name_shadow           ; chaque cellule reprise
        ld a,(lay_cur)
        or a
        jr nz,.ll0
.d:     ld a,h                      ; sans couche : prise de la case de la tuile (gx_cell)
        add a,high name_applied - high name_shadow
        ld d,a
        ld e,l
        ld a,(hl)
        ld (de),a
        push hl
        ld c,a
        ld a,h
        add a,high bi_slot - high name_shadow
        ld h,a
        call gx_cell.acq
        pop hl
        inc hl
        ld a,h
        cp high name_shadow + 3
        jr nz,.d
        jp .pal
.ll0:
.ll:    ld c,(hl)                   ; C = motif
        ld a,h
        add a,high name_applied - high name_shadow
        ld d,a
        ld e,l
        ld a,c
        ld (de),a
        ld a,h
        add a,high cc_lo - high name_shadow
        ld d,a
        ld e,c
        ld a,(de)
        ld (lay_cv),a               ; contenu
        inc d
        inc d
        inc d
        ld a,(de)
        ld (lay_cv + 1),a
        push hl
        ld a,h
        sub high name_shadow
        ld h,a
        ld (lay_cl),hl              ; cellule
        ld a,(lay_pb)               ; index (page B) : page et adresse de la liste
        call gx_map
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ld de,(lay_ab)
        add hl,de
        ld a,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl                    ; HL = liste de la cellule
        call gx_map
        ld b,(hl)
        inc hl
        ld d,h
        ld e,l                      ; DE = première entrée (défaut)
        ld a,(lay_cv)
        ld c,a
.ls:    ld a,(hl)
        cp c
        jr nz,.ln
        inc hl
        ld a,(lay_cv + 1)
        cp (hl)
        dec hl
        jr z,.lf
.ln:    inc hl
        inc hl
        inc hl
        inc hl
        djnz .ls
        ex de,hl
.lf:    inc hl
        inc hl
        ld e,(hl)                   ; base, octet bas
        inc hl
        ld a,(hl)
        and 3
        call lay_bpage
        ld d,a                      ; DE = &bi_slot[base] (bases 768-1023 : bi_slot4)
        ld a,(hl)
        rrca
        rrca
        and $0E
        ld (lay_hi),a
        ld a,(de)
        cp GX_FREE
        jr z,.lnew
        ld l,a                      ; une référence de plus (16 bits : un fond répété)
        ld h,high ref_lo
        inc (hl)
        jr nz,.lw
        inc h
        inc (hl)
        jr .lw
.lnew:  ld a,d
        ld b,3
        cp high bi_slot4
        jr z,.lb
        sub high bi_slot
        ld b,a
.lb:    ld c,e
        call lay_acquire            ; case prise, tuile envoyée (pages changées)
.lw:    ld hl,(lay_cl)
        call lay_write
        pop hl
        inc hl
        ld a,h
        cp high name_shadow + 3
        jp nz,.ll
.pal:   ld a,(irq_busy)             ; palettes : de la couche, ou celles du jeu
        or a
        jr nz,.q
        di
.q:     ld a,1
        out (VDP_CTRL),a
        ld a,$C0
        out (VDP_CTRL),a
        ld a,(lay_cur)
        or a
        jr z,.g0
        ld a,(lay_pa)
        call gx_map
        ld hl,(lay_aa)
        inc hl
        ld b,15
        call .out
        ld d,(hl)                   ; cases 5 et 9 des sprites : après la palette 0
        inc hl
        ld e,(hl)
        jr .s
.g0:    ld hl,gfx_palette + 1
        ld b,15
        call .out
        ld a,(gfx_palette_spr + 5)
        ld d,a
        ld a,(gfx_palette_spr + 9)
        ld e,a
.s:     ld a,17
        out (VDP_CTRL),a
        ld a,$C0
        out (VDP_CTRL),a
        ld hl,gfx_palette_spr + 1
        ld b,15
        ld c,1
.sp:    ld a,c
        cp 5
        ld a,d
        jr z,.so
        ld a,c
        cp 9
        ld a,e
        jr z,.so
        ld a,(hl)
.so:    out (VDP_DATA),a
        inc hl
        inc c
        djnz .sp
        call gx_end
        ld a,(irq_busy)
        or a
        ret nz
        ei
        ret
.out:   ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz .out
        ret
.zero:  ld a,c                      ; couleurs C à C + 14 : noir
        out (VDP_CTRL),a
        ld a,$C0
        out (VDP_CTRL),a
        ld b,15
        xor a
.zl:    out (VDP_DATA),a            ; (26 T au moins entre deux écritures, écran allumé)
        nop
        djnz .zl
        ret
