; sprite.asm - sprites natifs (page 1)
;
; Le TMS9918 a deux tables de sprites utilisées par le jeu ($1B00 et $1F00, la visible choisie par
; le registre 5). Pour chacune, ce qu'elle contient :
; - « vive » : écrite par l'envoi de l'OS7 (WR_SPR_NM_TBL $1C82, à chaque NMI, remplacé par
;   sp_table) = les entrées de la table des sprites du jeu ($704B) dans l'ordre own_xx relevé à
;   l'envoi (relues dans la table du jeu) ;
; - « remplie » : écrite directement par le jeu (vu : toute la table à $C3 pour cacher les
;   sprites, ou à 0) : toutes les entrées valent tab_fill.
; La table SMS est refaite depuis la table visible (sp_rebuild), selon la règle de
; sms/tools/sprite_groups.py : les sprites d'un même objet (table par écran, relevée hors ligne :
; sms/tools/sprite_looks.py), visibles ensemble et dans 32x32, forment une pose multicolore ; les
; autres sprites sont seuls. Chaque pose est cherchée en ROM (empreinte de sa clé : couches, motif,
; couleur, décalages) ; ses quarts 16x16 non vides (deux sprites SMS 8x16 chacun) prennent des
; cases du cache de tuiles (47 cases de 4 tuiles, $2000 + 128 k), leurs tuiles copiées de la ROM
; (dessinées dans l'éditeur, ou couches fusionnées) ; une pose absente de la ROM : chaque couche
; seule ; un sprite seul absent : tuiles calculées (sp_gen1). Chemin rapide : la clé de chaque
; objet (par son sprite de tête) et ses cases, vérifiées. Ordre : par plus petit numéro (priorité
; fixe), ou celui du jeu si une ligne aurait plus de 8 sprites SMS.
; Deux tables SMS ($3F00, $3E00) : la table est écrite dans la cachée, puis montrée (registre 5)
; aussitôt si l'écriture finit pendant le retour de trame, sinon à l'interruption de trame
; suivante (eng_irq) : jamais de table changée pendant que l'image se dessine.

SP_RANK     equ 0                   ; page spg (vars.asm, alignée) : rang d'envoi de chaque sprite du jeu
SP_BAND     equ 32                  ;   quarts par bande de 8 lignes (sp_order)
OB_OF       equ 64                  ;   sprite -> objet + 1 (objet valide de cet écran)
SP_CNT      equ 96                  ;   tri par rang (sp_order) : place de chaque rang
SP_TMP      equ 128                 ;   liste triée (4 x 32 octets)
                                    ; page spg2 : SF + 4 s : entrée rapide du sprite seul s
CK_VER      equ 0                   ; page ckp : version de chaque case (change quand elle est reprise)
CK_STAMP    equ 48                  ;   passe qui l'utilise
CK_LO       equ 96                  ;   identité : adresse de la pose en ROM (bas, haut), page x 4 +
CK_HI       equ 144                 ;   quart (sprite inconnu : 0, contenu, couleur | $80)
CK_PQ       equ 192
SP_PREV     equ 128                 ; page spg2 : table du jeu de la dernière passe (sp_same)
SP_HEAVY    equ 12                  ; table lourde (quarts) : la demande suivante est sautée (sp_rebuild)
SP_SLOTS    equ 47                  ; cases de 4 tuiles
SP_BLANK    equ 47                  ; case des tuiles vides (moitié droite hors de l'écran)
VRAM_SPR    equ $2000
        ASSERT VRAM_SPR + 128 * (SP_BLANK + 1) <= VRAM_NAME, "tuiles des sprites sur la table des noms"
        ASSERT VRAM_SAT2 >= VRAM_NAME + 768 * 2, "seconde table des sprites sur la table des noms montrée"
SPR_LO      equ low ($704B + RAM_SHIFT)
SPR_HI      equ high ($704B + RAM_SHIFT)    ; entrée s : SPR_HI, SPR_LO + 4s (sans retenue, s < 32)

sp_init:                            ; RAM déjà à zéro
        call sp_fast0               ; aucune entrée rapide
        ld hl,ckp + CK_PQ           ; cases sans identité
        ld b,SP_SLOTS
.k:     ld (hl),$7F
        inc l
        djnz .k
        ld a,high VRAM_SAT2         ; table SMS cachée (montrée : $3F00, registre 5 = $FF)
        ld (sat_back),a
        ld a,1                      ; tables « remplies » de 0 (VRAM effacée)
        ld (tab_mode),a
        ld (tab_mode + 1),a
        ret

sp_display_on:                      ; écran rallumé : table des sprites refaite si elle a attendu
        ld a,(adam_hide)            ; (menu après l'écran ADAM caché : palettes rendues)
        cp 2
        call z,adam_show
        ld a,(sp_pending)
        or a
        jp z,gx_end
        jp sp_rebuild

; --- registre 5 du TMS : table des sprites visible -------------------------------------------
sp_reg5:                            ; sat_reg5 = valeur écrite
        ld a,(sat_reg5)
        and $7F
        ld b,1
        cp $1B00 / $80
        jr z,.s
        ld b,2
        cp $1F00 / $80
        jr z,.s
        ld b,0
.s:     ld a,b
        ld (sat_act),a
        jp sp_rebuild

sp_which:                           ; HL = adresse VRAM d'une table -> A = 1 ($1B00), 2 ($1F00), 0 (autre)
        ld a,h
        cp high $1B00
        ld a,1
        ret z
        ld a,h
        cp high $1F00
        ld a,2
        ret z
        xor a
        ret

sp_tabvars:                         ; A = 1 ou 2 -> HL = propriétaires, DE = &tab_mode, BC = &tab_fill
        ld hl,own_1b
        ld de,tab_mode
        ld bc,tab_fill
        dec a
        ret z
        ld hl,own_1f
        inc de
        inc bc
        ret

; --- envoi de la table par l'OS7 ($1C82) : A = nombre d'entrées ---------------------------------
sp_table:
        ld a,(sp_count)             ; registres de sortie : IX = ordre + n, HL = dernière entrée + 4
        ld c,a
        ld b,0
        ld hl,($8004)
        add hl,bc
        ld (sp_out_ix),hl
        dec hl
        ld a,(hl)
        add a,a
        add a,a
        add a,SPR_LO + 4
        ld l,a
        ld h,SPR_HI
        ld (sp_out_hl),hl
        ld hl,($73F2 + RAM_SHIFT)   ; adresse de la table pour l'OS7
        call sp_which
        ld (sp_tab),a
        or a
        jp z,gx_end                 ; autre adresse (jamais vu) : sans effet
        call sp_tabvars
        xor a
        ld (de),a                   ; table « vive »
        ex de,hl                    ; propriétaires = ordre
        ld hl,($8004)
        ld a,(sp_count)
        ld c,a
        ld b,0
        ldir
        ld a,(sp_tab)
        ld b,a
        ld a,(sat_act)
        cp b
        jp z,sp_rebuild
        jp gx_end

; --- écriture directe du jeu dans une table de sprites (remplissage) ---------------------------
sp_sat_op:                          ; opération : gx_kind, gx_dest, gx_endx, gx_val
        ld a,(gx_kind)
        cp 2
        jr z,.f
        ld hl,(gx_err_sat)          ; copie (jamais vue) : comptée, sans effet
        inc hl
        ld (gx_err_sat),hl
        jp gx_end
.f:     xor a                       ; (table touchée = remplie entière : seuls remplissages vus)
        ld (sp_touch),a
        ld hl,$1B00
        ld de,$1B80
        call .one
        ld hl,$1F00
        ld de,$1F80
        call .one
        ld a,(sp_touch)
        ld b,a
        ld a,(sat_act)
        and b
        jp nz,sp_rebuild
        jp gx_end
.one:   push hl
        call gx_over                ; [gx_dest, gx_endx) recoupe [HL, DE) ?
        pop hl
        ret nc
        call sp_which
        push af
        call sp_tabvars
        ld a,1
        ld (de),a                   ; table « remplie »
        ld a,(gx_val)
        ld (bc),a
        pop af
        ld hl,sp_touch
        or (hl)
        ld (hl),a
        ret

; --- motifs des sprites ($3800-$3FFF) : automate ---------------------------------------------
sp_q:                               ; clé dans gx_kind (7 octets) ; liste de l'état : sq_list
        ld a,(sq_list)
        or a
        jr z,.any
        call gx_map
        ld hl,(sq_list + 1)
        call gx_find
        jr z,.found
.any:   ld a,SPR_ANY_PAGE
        call gx_map
        ld hl,SPR_ANY_ADDR
        call gx_find
        jp nz,gx_end
.found: ld de,sq_list
        ldi
        ldi
        ldi
        ld a,(hl)                   ; motifs changés : page, adresse, nombre
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
        call gx_map
        ex de,hl
.d:     ld a,b
        or c
        jr z,.r
        ld e,(hl)                   ; motif (0-63)
        inc hl
        inc hl
        push hl
        ld d,0
        ld hl,sp_cc
        add hl,de
        add hl,de
        ex de,hl
        pop hl
        ldi                         ; nouveau contenu (2 octets) ; BC -= 1
        inc bc
        ldi
        jr .d
.r:     call sp_fast0               ; entrées rapides périmées (motifs changés) ; table refaite
        jp sp_rebuild

sp_fast0:                           ; entrées rapides vides : sprites seuls (couleur $FF), objets
        xor a                       ; (motifs changés : la passe suivante est refaite)
        ld (sp_prev_ok),a
        ld hl,spg2 + 1
        ld b,32
.s:     ld (hl),$FF
        inc l
        inc l
        inc l
        inc l
        djnz .s
        ld hl,of_tab
        ld de,26
        ld b,8
.o:     ld (hl),$FF
        add hl,de
        djnz .o
        ret

; --- table SMS ($3F00) depuis la table visible ----------------------------------------------
; Table vive : trois passes sur ses entrées (dans la table du jeu, via own_xx) : cases des tuiles
; (refaites si le motif ou la couleur du sprite ont changé), Y (deux par entrée) en $3F00, X et
; tuiles en $3F80. Table remplie : toutes les entrées valent tab_fill, tuiles vides.
sp_same:                            ; Z : table du jeu (128 octets), table active, écran et motifs
        ld a,(sat_act)              ; comme à la passe précédente (sans tri) ; sinon NZ et cette
        ld b,a                      ; passe est notée pour la suivante
        call sp_screen
        ld c,a
        ld a,(sp_prev_ok)
        or a
        jr z,.diff
        ld a,(sp_prev_x)
        cp b
        jr nz,.diff
        ld a,(sp_prev_x + 1)
        cp c
        jr nz,.diff
        call sp_cmp
        ret z
.diff:  ld a,b
        ld (sp_prev_x),a
        ld a,c
        ld (sp_prev_x + 1),a
        ld hl,SPR_HI * 256 + SPR_LO
        ld de,spg2 + SP_PREV
        ld bc,128
        ldir
        ld a,1
        ld (sp_prev_ok),a
        or a                        ; NZ
        ret

sp_cmp:                             ; Z : table du jeu = SP_PREV (128 octets)
        ld hl,SPR_HI * 256 + SPR_LO
        ld de,spg2 + SP_PREV
        DUP 127
        ld a,(de)
        cp (hl)
        ret nz
        inc e
        inc l
        EDUP
        ld a,(de)
        cp (hl)
        ret

sp_late_nmi:                        ; (eng_irq, avant chaque NMI du jeu) table sautée (scène chargée)
        ld a,(sp_late)              ; et pas redemandée depuis deux NMI : refaite maintenant
        or a
        ret z
        inc a
        ld (sp_late),a
        cp 3
        ret c
        push bc
        push de
        push hl
        xor a
        ld (sp_heavy),a
        call sp_rebuild
        pop hl
        pop de
        pop bc
        ret

sp_rebuild:                         ; garde IX, IY (appelé aussi depuis WRITE_VRAM/FILL_VRAM du jeu)
        ld a,($73C4 + RAM_SHIFT)    ; écran éteint (registre 1, bit 6) : rien de visible, refait à
        and $40                     ; l'allumage (sp_display_on)
        jr nz,.on
        ld a,1
        ld (sp_pending),a
        jp gx_end
.on:    ld a,(nmi_fixed)            ; scène chargée (dernière table de SP_HEAVY quarts ou plus) : une
        or a                        ; demande sur deux, sinon le gestionnaire du jeu, qui la fait,
        jr nz,.do                   ; dépasserait l'image et le programme du jeu n'avancerait plus
        ld a,(sp_heavy)             ; (sprites à 30 images par seconde) ; sautée et pas redemandée :
        or a                        ; refaite deux NMI plus tard (sp_flush, eng_irq). Comparaison
        jr z,.do                    ; avec l'original (nmi_fixed) : toujours faite
        xor a
        ld (sp_heavy),a
        inc a
        ld (sp_late),a
        jp gx_end
.do:    xor a
        ld (sp_pending),a
        ld (sp_late),a
        push ix
        push iy
        call .r
        pop iy
        pop ix
        ld a,(sp_nq)
        cp SP_HEAVY
        ccf
        sbc a,a                     ; $FF : lourde
        ld (sp_heavy),a
        jp gx_end
.r:     ld a,(sat_act)
        or a
        jr nz,.go
        call sp_vdp_on              ; aucune table : aucun sprite
        ld l,0
        call sp_sat
        ld a,$D0
        out (VDP_DATA),a
        jp sp_show
.go:    call sp_tabvars
        ld a,(de)
        or a
        jr z,.ord
        xor a
        ld (sp_prev_ok),a
        jp sp_filled
.ord:   push hl
        call sp_same                ; même table que la passe précédente (sans tri) : même
        pop hl                      ; résultat, rien à refaire
        ret z
        ld a,(sp_stamp)             ; nouvelle passe : cases à garder marquées de ce numéro
        inc a
        jr nz,.st
        inc a                       ; (0 : jamais utilisé, cases jamais marquées)
.st:    ld (sp_stamp),a
        ld (sp_bstamp),a            ; passe de la table cachée
        ; passe 1 : rang d'envoi de chaque sprite du jeu visible (page spg, SP_RANK + s ; $FF :
        ; aucun). Omises : entrées cachées (Y de $BF à $E0 : sous l'écran) et couleur 0
        ex de,hl                    ; DE = propriétaires
        ld hl,spg + SP_RANK
        ld a,$FF
        DUP 32
        ld (hl),a
        inc l
        EDUP
        ld c,0                      ; rang
.c:     ld a,(de)                   ; propriétaire s
        inc de
        ld b,a
        add a,a
        add a,a
        add a,SPR_LO
        ld l,a
        ld h,SPR_HI
        ld a,(hl)                   ; Y
        cp $D0
        jr z,.g
        cp $BF
        jr c,.v
        cp $E1
        jr c,.n
.v:     inc l
        inc l
        inc l
        ld a,(hl)
        and 15
        jr z,.n
        ld h,high spg
        ld l,b                      ; (SP_RANK = 0)
        ld (hl),c
.n:     inc c
        ld a,c
        cp 32
        jr nz,.c
.g:     call sp_objects             ; objets de l'écran dont les membres visibles tiennent ensemble
        call sp_pass                ; -> sp_list : (Y, X, première tuile, rang) par quart affiché
        call sp_order               ; une ligne aurait plus de 8 sprites SMS : ordre du jeu
        ld a,(sp_nq)
        ld (sp_n),a
        call sp_vdp_on
        ; passe Y : deux sprites SMS par quart, puis fin de table
        ld l,0
        call sp_sat
        ld a,(sp_n)
        or a
        jr z,.ye
        ld b,a
        ld hl,sp_list
        ld c,VDP_DATA
.y:     ld a,(hl)
        out (c),a
        inc hl
        inc hl
        inc hl
        inc hl
        out (c),a
        djnz .y
.ye:    ld a,(sp_n)
        cp 32
        jr z,.xt
        ld a,$D0
        out (VDP_DATA),a
        ; passe X : X, tuile gauche, X + 8, tuile droite (vide si X >= 248)
.xt:    ld l,$80
        call sp_sat
        ld a,(sp_n)
        or a
        jr z,.done
        ld b,a
        ld hl,sp_list
.x:     inc hl
        ld a,(hl)                   ; X
        out (VDP_DATA),a
        ld c,a
        inc hl
        ld a,(hl)                   ; tuile gauche
        inc hl
        inc hl
        out (VDP_DATA),a
        ld e,a
        ld a,c
        add a,8
        nop                         ; (26 T au moins entre deux écritures, écran allumé)
        out (VDP_DATA),a
        ld a,c
        cp 248
        ld a,SP_BLANK * 4 + 2
        jr nc,.rt
        ld a,e
        add a,2
.rt:    out (VDP_DATA),a
        djnz .x
.done:  jp sp_show

sp_filled:                          ; BC = &tab_fill : 32 entrées toutes égales, tuiles vides
        ld a,(bc)
        ld (sp_y),a
        call sp_vdp_on
        ld l,0
        call sp_sat
        ld a,(sp_y)
        cp $D0
        jr z,.t
        ld b,64
.y:     out (VDP_DATA),a
        nop
        nop
        djnz .y
        ld l,$80
        call sp_sat
        ld b,64
.x:     ld a,(sp_y)
        out (VDP_DATA),a
        ld a,SP_BLANK * 4
        nop
        nop                         ; (26 T au moins entre deux écritures, écran allumé)
        out (VDP_DATA),a
        djnz .x
        jp sp_show
.t:     out (VDP_DATA),a            ; $D0 : fin de table dès la première entrée
        jp sp_show

sp_vdp_on:                          ; séquence VDP : pas d'interruption au milieu
        ld a,(irq_busy)
        or a
        ret nz
        di
        ret
sp_vdp_off:
        ld a,(irq_busy)
        or a
        ret nz
        ei
        ret
sp_sat:                             ; L = 0 ou $80 : adresse d'écriture dans la table cachée
        ld a,(sat_back)
        or $40
        ld h,a
        jr sp_addr

sp_show:                            ; table cachée écrite : montrée maintenant pendant le retour de
        ld a,(nmi_fixed)            ; trame (ou NMI imposées par un outil), sinon à l'interruption
        or a                        ; de trame suivante
        jr nz,.now
        call sp_vb
        jr nc,.now
        ld a,1
        ld (sat_pend),a
        jp sp_vdp_off
.now:   call sat_flip
        jp sp_vdp_off

sp_vb:                              ; NC : retour de trame, assez tôt pour écrire le registre 5
        in a,($7E)                  ; avant la ligne 0 : compteur $C0-$F7 (PAL : $BA-$BF ambigus,
        cp $C0                      ; laissés de côté)
        ret c
        cp $F8
        ccf
        ret

sat_flip_vb:                        ; (eng_irq, table prête) : montrée si l'interruption de trame
        call sp_vb                  ; est prise pendant le retour de trame, sinon à la suivante
        ret c                       ; (interruptions coupées longtemps : prise après la ligne 192)
sat_flip:                           ; montre la table cachée ; l'autre devient la cachée
        ld a,(sp_bstamp)            ; ses cases sont maintenant celles de la table montrée
        ld (sp_shown),a
        xor a
        ld (sat_pend),a
        ld a,(sat_back)
        add a,a
        and $7E
        or $81
        out (VDP_CTRL),a            ; registre 5 : adresse de la table des sprites
        ld a,$85
        out (VDP_CTRL),a
        ld a,(sat_back)
        xor high VRAM_SAT ^ high VRAM_SAT2
        ld (sat_back),a
        ret

sp_addr:                            ; HL = adresse VRAM (écriture)
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        out (VDP_CTRL),a
        ret

; écran des objets : SCREEN ($70FD), sauf écran 1 sans les repères d'une couche (cinématique : coup de
; pied à Mario, Donkey Kong qui descend) : écran virtuel SP_CINE (objets relevés par sprite_looks.py)
SP_CINE     equ 5
sp_screen:                          ; -> A (garde BC, DE, HL)
        ld a,($70FD+RAM_SHIFT)
        cp 1
        ret nz
    IF LAY_CLES == 0
        ld a,(lay_seen)             ; (repères d'une couche présents : écran de jeu)
        or a
        ld a,1
        ret nz
    ELSE
        push bc                     ; repères de l'écran des clés testés ici, à chaque passe (pendant
        push de                     ; un envoi de noms du jeu, lay_check ne passe qu'à la fin)
        push hl
        ld a,(cur_slot2)
        push af
        ld a,LAY_PAGE
        call gx_map
        ld hl,LAY_ADDR + 1 + 11 * (LAY_CLES - 1)
        call lay_check.anch
        call z,lay_check.anch
        pop bc                      ; (B = page d'avant)
        push af
        ld a,b
        call gx_map
        pop af
        pop hl
        pop de
        pop bc
        ld a,1
        ret z
    ENDIF
        ld a,SP_CINE
        ret

; --- objets, groupes, poses (règle : sms/tools/sprite_groups.py) ---------------------------------
sp_objects:                         ; objets de l'écran (table de gfx_build) dont les membres
        ld hl,spg + OB_OF           ; visibles (au moins deux) tiennent dans 32x32 : OB_OF + s =
        xor a                       ; objet + 1 ; ob_n, ob_m (membres visibles, croissants)
        DUP 32
        ld (hl),a
        inc l
        EDUP
        ld (ob_cnt),a
        call sp_screen              ; écran
        cp 8
        ret nc
        add a,a
        ld e,a
        ld d,0
        ld a,SPR_POSE_PAGE
        call gx_map
        ld hl,SPR_OBJ_ADDR
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld b,(hl)                   ; nombre d'objets
        inc hl
        ld a,b
        or a
        ret z
.o:     push bc
        ld b,(hl)                   ; membres
        inc hl
        ld de,ob_tmp
        ld c,0
.m:     ld a,(hl)
        inc hl
        push hl
        ld l,a
        ld h,high spg               ; (SP_RANK = 0)
        ld a,(hl)
        inc a
        jr z,.mn                    ; pas visible
        ld a,c
        cp 4
        jr nc,.mn
        ld a,l
        ld (de),a
        inc de
        inc c
.mn:    pop hl
        djnz .m
        ld a,c
        cp 2
        jr c,.nx
        push hl
        call ob_fits                ; Z : dans 32x32
        jr nz,.nf
        ld a,(ob_cnt)
        cp 8
        jr nc,.nf
        ld e,a                      ; objet valide n° ob_cnt : ses membres
        ld d,0
        ld hl,ob_n
        add hl,de
        ld (hl),c
        ld a,e
        add a,a
        add a,a
        ld e,a
        ld hl,ob_m
        add hl,de
        ex de,hl
        ld hl,ob_tmp
        ld b,c
.k:     ld a,(hl)
        ld (de),a
        inc hl
        inc de
        push hl
        add a,OB_OF
        ld l,a
        ld h,high spg
        ld a,(ob_cnt)
        inc a
        ld (hl),a                   ; OB_OF + s = objet + 1
        pop hl
        djnz .k
        ld hl,ob_cnt
        inc (hl)
.nf:    pop hl
.nx:    pop bc
        djnz .o
        ret

ob_fits:                            ; ob_tmp (C membres) : Z si les écarts de u (Y + 33) et de X
        ld de,33                    ; sont au plus 16 ; garde C
        call .sp
        ret nz
        ld de,$0100
.sp:    push bc                     ; D = 0 (Y) ou 1 (X), E = ajout
        ld hl,ob_tmp
        ld b,c
        ld c,$FF                    ; plus petit
        xor a
        ld (ob_max),a
.l:     push hl
        ld a,(hl)
        add a,a
        add a,a
        add a,SPR_LO
        add a,d
        ld l,a
        ld h,SPR_HI
        ld a,(hl)
        add a,e
        pop hl
        inc hl
        cp c
        jr nc,.a
        ld c,a
.a:     push hl
        ld hl,ob_max
        cp (hl)
        jr c,.b
        ld (hl),a
.b:     pop hl
        djnz .l
        ld a,(ob_max)
        sub c
        cp 17
        pop bc
        jr nc,.no
        xor a
        ret
.no:    or 1
        ret

sp_copy:                            ; HL = 128 octets (emplacement 2) -> case sp_k2
        push hl
        ld a,(sp_k2)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,VRAM_SPR | $4000
        add hl,de
        ld a,(irq_busy)
        or a
        jr nz,.w
        di
.w:     ld a,l
        out (VDP_CTRL),a
        ld a,h
        out (VDP_CTRL),a
        pop hl
        ld bc,128 * 256 + VDP_DATA
.o:     outi                        ; au moins 26 T entre deux écritures (écran allumé)
        nop
        jp nz,.o
        ld a,(irq_busy)
        or a
        ret nz
        ei
        ret

sp_rom:                             ; sp_fk -> sp_rk (clé de la ROM : n, (contenu bas, haut, couleur,
        ld hl,sp_fk                 ; du, dx) x n) ; Z si la pose est en ROM : sp_rec (enregistrement),
        ld de,sp_rk                 ; sp_qm, sp_data (tuiles du premier quart)
        ld a,(hl)
        ld (de),a
        ld b,a
        inc hl
        inc de
.l:     ld a,(hl)                   ; motif
        inc hl
        push hl
        rrca
        rrca
        and $3F
        add a,a
        ld l,a
        ld h,0
        push bc
        ld bc,sp_cc
        add hl,bc
        pop bc
        ld a,(hl)
        ld (de),a
        inc de
        inc hl
        ld a,(hl)
        ld (de),a
        inc de
        pop hl
        ld a,(hl)                   ; couleur, du, dx
        ld (de),a
        inc de
        inc hl
        ld a,(hl)
        ld (de),a
        inc de
        inc hl
        ld a,(hl)
        ld (de),a
        inc de
        inc hl
        djnz .l
        ld a,(sp_rk)                ; longueur 1 + 5n ; empreinte : h = rlc(h) xor octet
        ld b,a
        add a,a
        add a,a
        add a,b
        inc a
        ld (sp_klen),a
        ld b,a
        ld hl,sp_rk
        xor a
.h:     rlca
        xor (hl)
        inc hl
        djnz .h
        and 63
        ld e,a
        add a,a
        add a,e
        ld e,a
        ld d,0
        ld a,SPR_POSE_PAGE
        call gx_map
        ld hl,SPR_POSE_ADDR
        add hl,de
        ld a,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
.c:     or a
        jr z,.no
        ld (sp_rec),a
        ld (sp_rec + 1),de
        call gx_map
        ex de,hl                    ; HL = enregistrement
        push hl
        inc hl
        inc hl
        inc hl
        ld a,(sp_klen)
        cp (hl)
        jr nz,.nx
        inc hl
        ld de,sp_rk
        ld b,a
.k:     ld a,(de)
        cp (hl)
        jr nz,.nx
        inc de
        inc hl
        djnz .k
        ld a,(hl)
        ld (sp_qm),a
        inc hl
        ld (sp_data),hl
        pop hl
        xor a
        ret
.nx:    pop hl                      ; suivant
        ld a,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        jr .c
.no:    or 1
        ret

; --- sprites visibles -> sp_list (règle : sms/tools/sprite_groups.py) -------------------------
; sp_list : par élément (4 octets) Y, X, première tuile (4 x case), rang ; un élément = un quart
; 16x16 = deux sprites SMS 8x16. Entrées rapides : sprite seul (SF, page spg2 : motif, couleur,
; case, version de la case) ; objet (of_tab + 26 objet : clé, quarts, cases, versions). Une case
; reprise pour autre chose change de version (ckp + CK_VER) : l'entrée rapide ne vaut plus.
sp_pass:                            ; par numéro croissant : sprites seuls, objets (à leur tête)
        xor a
        ld (sp_nq),a
        ld hl,spg + SP_RANK
.s:     ld a,(hl)                   ; rang ($FF : pas visible)
        inc a
        jr nz,.vis
.nx:    inc l
        ld a,l
        cp 32
        jr nz,.s
        ret
.vis:   dec a
        ld (gp_rk),a
        ld a,l
        ld (gp_s),a
        push hl
        add a,OB_OF
        ld l,a
        ld a,(hl)
        or a
        jr nz,.o
        call sp_single
        jr .p
.o:     dec a
        call sp_object
.p:     pop hl
        jr .nx

sp_single:                          ; sprite gp_s (rang gp_rk) seul
        ld a,(gp_s)
        add a,a
        add a,a
        ld b,a                      ; 4 s
        add a,SPR_LO
        ld l,a
        ld h,SPR_HI
        ld a,(hl)
        ld (gq_y),a
        inc l
        ld a,(hl)
        ld (gq_x),a
        inc l
        ld d,(hl)                   ; motif
        inc l
        ld a,(hl)
        and 15
        ld e,a                      ; couleur
        ld l,b
        ld h,high spg2              ; SF + 4 s : motif, couleur, case, version
        ld a,(hl)
        cp d
        jr nz,.miss
        inc l
        ld a,(hl)
        cp e
        jr nz,.miss
        inc l
        ld a,(hl)                   ; case ($FF : pas de quart)
        cp $FF
        ret z
        inc l
        ld b,(hl)                   ; version
        ld l,a
        ld h,high ckp               ; (CK_VER = 0)
        ld a,(hl)
        cp b
        jr nz,.miss
        ld a,l
        call sp_use
        jp sp_item0
.miss:  push de                     ; D = motif, E = couleur ; clé : 1, motif, couleur, 0, 0
        ld a,1
        ld (sp_fk),a
        ld a,d
        ld (sp_fk + 1),a
        ld a,e
        ld (sp_fk + 2),a
        xor a
        ld (sp_fk + 3),a
        ld (sp_fk + 4),a
        call sp_rom
        jr nz,.unk
        ld a,(sp_qm)                ; pose vide (aucun point) : rien à montrer
        rrca
        ld e,$FF
        jr nc,.have
        ld a,(sp_rec)
        ld (sp_id),a
        ld hl,(sp_rec + 1)
        ld (sp_id + 1),hl
        xor a
        ld (sp_id + 3),a
        call sp_slotq               ; E = case ; retenue : nouvelle
        jr nc,.have
        ld a,e
        ld (sp_k2),a
        push de
        ld a,(sp_rec)
        call gx_map
        ld hl,(sp_data)
        call sp_copy
.cpd:   pop de
        jr .have
.unk:   xor a                       ; motif absent de la ROM : tuiles calculées
        ld (sp_id),a
        ld hl,(sp_rk + 1)
        ld (sp_id + 1),hl
        ld a,(sp_fk + 2)
        or $80
        ld (sp_id + 3),a
        call sp_slotq
        jr nc,.have
        ld a,e
        ld (sp_k2),a
        push de
        ld hl,sp_rk
        ld de,sp_kfull
        ld bc,4
        ldir
        call sp_gen1
        pop de
.have:  pop bc                      ; B = motif, C = couleur : entrée rapide
        ld a,(gp_s)
        add a,a
        add a,a
        ld l,a
        ld h,high spg2
        ld (hl),b
        inc l
        ld (hl),c
        inc l
        ld (hl),e                   ; case
        inc l
        ld a,e
        cp $FF
        ret z
        ld d,high ckp               ; sa version
        ld a,(de)
        ld (hl),a
        ld a,e
        call sp_use
        jp sp_item0

sp_use:                             ; A = case : marquée pour cette passe -> A = 4 x case
        ld h,high ckp
        ld b,a
        add a,CK_STAMP
        ld l,a
        ld a,(sp_stamp)
        ld (hl),a
        ld a,b
        add a,a
        add a,a
        ret

sp_item0:                           ; A = tuile ; Y = gq_y, X = gq_x, rang gp_rk
        ld c,a
        ld a,(gq_y)
        ld b,a
        ld a,(gq_x)
        ld e,a
sp_item:                            ; B = Y, E = X, C = tuile, rang gp_rk -> sp_list (Y caché : rien)
        ld a,b
        cp $BF
        jr c,.ok
        cp $E1
        ret c
.ok:    ld a,(sp_nq)
        cp 32
        ret nc
        ld l,a
        inc a
        ld (sp_nq),a
        ld h,0
        add hl,hl
        add hl,hl
        push de
        ld de,sp_list
        add hl,de
        pop de
        ld (hl),b
        inc hl
        ld (hl),e
        inc hl
        ld (hl),c
        inc hl
        ld a,(gp_rk)
        ld (hl),a
        ret

sp_object:                          ; A = objet ; à sa tête (gp_s = son premier membre visible)
        ld (ob_i),a
        ld e,a
        ld d,0
        ld hl,ob_n
        add hl,de
        ld b,(hl)                   ; membres visibles
        ld a,e
        add a,a
        add a,a
        ld e,a
        ld hl,ob_m
        add hl,de
        ld a,(gp_s)
        cp (hl)
        ret nz                      ; pas la tête
        ld (ob_p),hl
        push hl                     ; cadre (plus petits u, X) ; plus petit rang
        push bc
        ld a,$FF
        ld (gp_umin),a
        ld (gp_xmin),a
        ld (gp_rk),a
.m:     ld a,(hl)
        inc hl
        push hl
        ld e,a
        ld l,a
        ld h,high spg
        ld a,(hl)                   ; rang
        ld hl,gp_rk
        cp (hl)
        jr nc,.r
        ld (hl),a
.r:     ld a,e
        add a,a
        add a,a
        add a,SPR_LO
        ld l,a
        ld h,SPR_HI
        ld a,(hl)                   ; u = Y + 33
        add a,33
        ld d,a
        ld a,(gp_umin)
        cp d
        jr c,.u
        ld a,d
        ld (gp_umin),a
.u:     inc l
        ld d,(hl)                   ; X
        ld a,(gp_xmin)
        cp d
        jr c,.x
        ld a,d
        ld (gp_xmin),a
.x:     pop hl
        djnz .m
        pop bc
        pop hl
        ld de,sp_fk                 ; clé rapide : n, (motif, couleur, du, dx) x n
        ld a,b
        ld (de),a
        inc de
.k:     ld a,(hl)
        inc hl
        push hl
        add a,a
        add a,a
        add a,SPR_LO
        ld l,a
        ld h,SPR_HI
        ld a,(hl)
        add a,33
        ld c,a
        inc l
        ld a,(hl)
        ld (gp_tx),a
        inc l
        ld a,(hl)                   ; motif
        ld (de),a
        inc de
        inc l
        ld a,(hl)
        and 15
        ld (de),a
        inc de
        ld a,(gp_umin)
        ld h,a
        ld a,c
        sub h
        ld (de),a
        inc de
        ld a,(gp_xmin)
        ld h,a
        ld a,(gp_tx)
        sub h
        ld (de),a
        inc de
        pop hl
        djnz .k
        ld a,(ob_i)                 ; entrée rapide : of_tab + 26 objet
        call of_at
        push hl
        ld de,sp_fk
        ld a,(de)
        add a,a
        add a,a
        inc a
        ld b,a
.kc:    ld a,(de)
        cp (hl)
        jr nz,.miss
        inc de
        inc hl
        djnz .kc
        pop hl
        push hl
        ld de,17
        add hl,de
        ld a,(hl)                   ; quarts
        ld (sp_qm),a
        inc hl                      ; HL = cases, HL + 4 = versions
        ld c,a
        ld b,4
.vq:    rr c
        jr nc,.vn
        push hl
        ld e,(hl)
        inc hl
        inc hl
        inc hl
        inc hl
        ld a,(hl)                   ; version retenue
        ld l,e
        ld h,high ckp
        cp (hl)
        pop hl
        jr nz,.miss
.vn:    inc hl
        djnz .vq
        pop hl                      ; entrée -> ses cases
        ld de,18
        add hl,de
        jp ob_emit
.miss:  call sp_rom                 ; pose en ROM ? (pile : entrée rapide)
        jr z,.rom
        pop hl                      ; non : chaque couche seule
        ld hl,(ob_p)
        ld a,(sp_fk)
        ld b,a
.sp:    ld a,(hl)
        inc hl
        push hl
        push bc
        ld (gp_s),a
        ld l,a
        ld h,high spg
        ld a,(hl)
        ld (gp_rk),a
        call sp_single
        pop bc
        pop hl
        djnz .sp
        ret
.rom:   pop hl                      ; entrée rapide : clé, puis quarts, cases, versions
        push hl
        ex de,hl
        ld hl,sp_fk
        ld a,(hl)
        add a,a
        add a,a
        inc a
        ld c,a
        ld b,0
        ldir
        pop hl
        ld de,17
        add hl,de
        ld a,(sp_qm)
        ld (hl),a
        inc hl
        ld (ob_c),hl                ; cases
        ld a,(sp_rec)
        ld (sp_id),a
        ld hl,(sp_rec + 1)
        ld (sp_id + 1),hl
        xor a
        ld (sp_qi),a
.q:     ld a,(sp_qm)
        ld b,a
        ld a,(sp_qi)
        inc a
        ld c,a
.sh:    rr b
        dec c
        jr nz,.sh
        jr nc,.nq
        ld a,(sp_qi)
        ld (sp_id + 3),a
        call sp_slotq               ; E = case ; retenue : nouvelle
        jr nc,.hv
        ld a,e
        ld (sp_k2),a
        push de
        ld a,(sp_rec)
        call gx_map
        ld hl,(sp_data)
        call sp_copy
        pop de
.hv:    ld hl,(sp_data)             ; tuiles du quart suivant
        ld bc,128
        add hl,bc
        ld (sp_data),hl
        ld hl,(ob_c)                ; case et sa version
        ld a,(sp_qi)
        add a,l
        ld l,a
        jr nc,.c1
        inc h
.c1:    ld (hl),e
        inc hl
        inc hl
        inc hl
        inc hl
        ld d,high ckp
        ld a,(de)
        ld (hl),a
.nq:    ld hl,sp_qi
        inc (hl)
        ld a,(hl)
        cp 4
        jr nz,.q
        ld a,(ob_i)
        call of_at
        ld de,18
        add hl,de                   ; HL = cases
ob_emit:                            ; HL = cases des quarts, sp_qm ; cadre gp_umin, gp_xmin ; rang gp_rk
        ld a,(sp_qm)
        ld c,a
        xor a
        ld (sp_qi),a
.q:     rr c
        jr nc,.n
        push bc
        push hl
        ld a,(hl)                   ; case
        call sp_use
        ld c,a                      ; tuile
        ld a,(gp_umin)
        sub 33
        ld b,a                      ; Y
        ld a,(gp_xmin)
        ld e,a                      ; X
        ld a,(sp_qi)
        bit 1,a
        jr z,.r0
        ld a,b
        add a,16
        ld b,a
.r0:    ld a,(sp_qi)
        rrca
        jr nc,.c0
        ld a,e
        add a,16
        jr c,.skip                  ; X >= 256
        ld e,a
.c0:    call sp_item
.skip:  pop hl
        pop bc
.n:     inc hl
        ld a,(sp_qi)
        inc a
        ld (sp_qi),a
        cp 4
        jr nz,.q
        ret

of_at:                              ; A = objet -> HL = of_tab + 26 A
        ld l,a
        ld h,0
        add hl,hl
        ld e,l
        ld d,h                      ; 2 A
        add hl,hl
        add hl,hl
        add hl,hl                   ; 16 A
        add hl,de
        add hl,de
        add hl,de
        add hl,de
        add hl,de                   ; 26 A
        ld de,of_tab
        add hl,de
        ret

sp_order:                           ; une ligne de l'écran aurait plus de 8 sprites SMS (plus de 4
        ld a,(sp_nq)                ; quarts) : sp_list dans l'ordre des rangs (celui du jeu)
        cp 5
        ret c
        ld b,a                      ; v = max(u, 32) de chaque quart (u = Y + 33 ; ligne 0 : 32)
        ld de,sp_list               ;   -> SP_BAND, trié (insertion)
        ld hl,spg + SP_BAND
.u:     ld a,(de)
        add a,33
        cp 32
        jr nc,.u1
        ld a,32
.u1:    ld c,a
        push hl
.in:    ld a,l                      ; décaler les plus grands
        cp SP_BAND
        jr z,.st
        dec l
        ld a,(hl)
        cp c
        jr z,.st1
        jr c,.st1
        inc l
        ld (hl),a
        dec l
        jr .in
.st1:   inc l
.st:    ld (hl),c
        pop hl
        inc l
        inc de
        inc de
        inc de
        inc de
        djnz .u
        ld a,(sp_nq)                ; quarts i et i + 4 : v(i + 4) - v(i) <= 15 -> débordement
        sub 4
        ld b,a
        ld l,SP_BAND
.w:     ld a,l
        add a,4
        ld e,a
        ld d,h
        ld a,(de)
        sub (hl)
        cp 16
        jr c,.sort
        inc l
        djnz .w
        ret
.sort:  xor a                       ; (ordre d'envoi utilisé : la passe suivante est refaite)
        ld (sp_prev_ok),a
        ld hl,spg + SP_CNT           ; tri par rang (comptage, stable ; rangs 0-31) : nombre
        xor a                       ; d'éléments de chaque rang
        ld b,32
.z:     ld (hl),a
        inc l
        djnz .z
        ld a,(sp_nq)
        ld b,a
        ld de,sp_list + 3
.ca:    ld a,(de)
        add a,SP_CNT
        ld l,a
        inc (hl)
        inc de
        inc de
        inc de
        inc de
        djnz .ca
        ld l,SP_CNT                 ; -> place du premier de chaque rang
        ld b,32
        xor a
.pf:    ld c,(hl)
        ld (hl),a
        add a,c
        inc l
        djnz .pf
        ld a,(sp_nq)
        ld b,a
        ld de,sp_list
.pl:    push bc
        inc de
        inc de
        inc de
        ld a,(de)                   ; rang
        dec de
        dec de
        dec de
        add a,SP_CNT
        ld l,a
        ld h,high spg
        ld a,(hl)                   ; place
        inc (hl)
        add a,a
        add a,a
        add a,SP_TMP
        ld l,a
        ex de,hl                    ; élément -> SP_TMP + 4 x place
        ldi
        ldi
        ldi
        ldi
        ex de,hl                    ; DE = élément suivant
        pop bc
        djnz .pl
        ld a,(sp_nq)
        add a,a
        add a,a
        ld c,a
        ld b,0
        ld hl,spg + SP_TMP
        ld de,sp_list
        ldir
        ret

sp_slotq:                           ; sp_id (page, adresse, quart) -> E = case (D = 0) ; retenue si
        ld a,(sp_id)                ; nouvelle (à remplir ; sa version change) ; marquée tout de
        add a,a                     ; suite. Identité : CK_LO, CK_HI, CK_PQ (page x 4 + quart ; ou,
        add a,a                     ; page 0 : couleur | $80)
        ld b,a
        ld a,(sp_id + 3)
        bit 7,a
        jr nz,.pq
        or b
.pq:    ld (sp_pq),a
        ld hl,ckp + CK_LO
        ld bc,SP_SLOTS
.s:     ld a,(sp_id + 1)
        cpir
        jr nz,.new
        push hl
        dec l                       ; L = CK_LO + case
        ld a,l
        sub CK_LO
        ld e,a
        add a,CK_HI
        ld l,a
        ld a,(sp_id + 2)
        cp (hl)
        jr nz,.no
        ld a,e
        add a,CK_PQ
        ld l,a
        ld a,(sp_pq)
        cp (hl)
        jr nz,.no
        pop hl
        ld d,0
        call .mark
        or a
        ret
.no:    pop hl
        ld a,b
        or c
        jr nz,.s
.new:   ld a,SP_SLOTS               ; case prise à tour de rôle, hors celles de cette passe et
        ld (sp_try),a               ; des tables montrée ou en attente ; si toutes le sont (non vu),
.v1:    ld a,(ck_next)              ; hors celles de cette passe seulement
        ld e,a
        inc a
        cp SP_SLOTS
        jr c,.w
        xor a
.w:     ld (ck_next),a
        ld a,e
        add a,CK_STAMP
        ld l,a
        ld h,high ckp
        ld a,(sp_stamp)
        cp (hl)
        jr z,.v1
        ld a,(sp_try)
        or a
        jr z,.v2
        dec a
        ld (sp_try),a
        ld a,(sp_shown)
        ld c,a
        ld a,(hl)
        sub c
        ld b,a
        ld a,(sp_stamp)
        sub c
        cp b
        jr nc,.v1
.v2:    ld h,high ckp
        ld l,e                      ; (CK_VER = 0) : nouvelle version
        inc (hl)
        ld a,e
        add a,CK_LO
        ld l,a
        ld a,(sp_id + 1)
        ld (hl),a
        ld a,e
        add a,CK_HI
        ld l,a
        ld a,(sp_id + 2)
        ld (hl),a
        ld a,e
        add a,CK_PQ
        ld l,a
        ld a,(sp_pq)
        ld (hl),a
        ld d,0
        call .mark
        scf
        ret
.mark:  ld a,e                      ; marquée tout de suite (un autre quart de la même passe ne la
        add a,CK_STAMP              ; reprend pas)
        ld l,a
        ld h,high ckp
        ld a,(sp_stamp)
        ld (hl),a
        ret

sp_gen1:                            ; une couche (sp_kfull : 1, contenu, couleur) : chaque octet du
        ld a,(sp_kfull + 3)         ; motif -> 4 plans (masques de la couleur)
        cp 5                        ; couleurs 5 et 9 -> 4 et 8 (mêmes teintes : cases 5 et 9 de la
        jr z,.c4                    ; palette laissées aux couches du décor)
        cp 9
        jr nz,.c
.c4:    dec a
.c:
        ld hl,sp_mask
        ld d,4
.m:     rra
        ld e,0
        jr nc,.m0
        dec e
.m0:    ld (hl),e
        inc hl
        dec d
        jr nz,.m
        ld a,SPR_PAGE               ; source : $8000 + 32 x contenu
        call gx_map
        ld hl,(sp_kfull + 1)
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        set 7,h
        push hl
        ld a,(sp_k2)                ; destination : $2000 + 128 x case
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,VRAM_SPR | $4000
        add hl,de
        ld a,(irq_busy)
        or a
        jr nz,.w
        di
.w:     ld a,l
        out (VDP_CTRL),a
        ld a,h
        out (VDP_CTRL),a
        pop hl
        ld b,32
.b:     ld c,(hl)                   ; un octet du motif -> 4 plans
        inc hl
        ld a,(sp_mask)
        and c
        out (VDP_DATA),a
        ld a,(sp_mask + 1)
        and c
        out (VDP_DATA),a
        ld a,(sp_mask + 2)
        and c
        out (VDP_DATA),a
        ld a,(sp_mask + 3)
        and c
        out (VDP_DATA),a
        djnz .b
        ld a,(irq_busy)
        or a
        ret nz
        ei
        ret
