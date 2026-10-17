; engine0.asm - moteur, partie logée dans un trou libre de l'OS7 ($08DF-$0F36).
; Elle existe à l'identique dans la page 0 normale et dans la page 0 « données » (fenêtre) :
; tout ce qui peut s'exécuter pendant une fenêtre (interruption, manettes, cassette) est ici.

; --- NMI du TMS9918 reproduite -------------------------------------------------------------------
; TMS : NMI au FRONT MONTANT de (indicateur de trame ET autorisation reg.1 bit 5) ; l'indicateur
; est posé à chaque retour de trame, effacé seulement par la lecture de l'état. Ici :
; - l'interruption de trame SMS est autorisée comme la NMI (reg.1 bit 5 recopié) ;
; - tms_flag ($80) = indicateur déjà vu par le jeu-NMI et pas encore lu : pas de nouveau front.
; Le moteur d'affichage peut avoir mis une page de données dans l'emplacement 2 ($8000) : le
; gestionnaire du jeu ($8078, page 2) la trouve remise, puis elle est rétablie (cur_slot2).
eng_irq:
        push af
        ld a,$FF                    ; l'adresse du VDP va changer (gx_cell)
        ld (gx_vnext + 1),a
        in a,(VDP_CTRL)             ; acquitte ; bit 7 : interruption de trame (sinon : de ligne)
        push bc
        ld b,a
        bit 7,b                     ; retour de trame : table des sprites cachée prête -> montrée
        jr z,.nf
        ld a,(sat_pend)
        or a
        jr z,.nf
        push hl
        ld hl,sat_flip_vb
        call gx_call
        pop hl
.nf:
        ld a,(pal_on)
        or a
        call nz,eng_pal             ; PAL : NZ si cette interruption n'est pas une NMI du jeu
        pop bc
        jr z,.ev
        ld a,(pal_owed)             ; PAL : NMI due (trame lue par le jeu, eng_read_register)
        or a
        jr z,.no
        xor a
        ld (pal_owed),a
.ev:    ld a,(tms_flag)
        or a
        jr nz,.drop                 ; indicateur non lu depuis la dernière NMI : pas de front
        push hl
        ld hl,nmi_defer             ; NMI différée ? (engine.asm)
        call gx_call
        pop hl
        jr nz,.no
        ld a,$80
        ld (tms_flag),a
        ld a,1
        ld (irq_busy),a
        ld a,(cur_slot2)
        ld (irq_slot2),a
        ld a,2
        ld (cur_slot2),a
        ld (MAP_SLOT2),a
        ld a,(test_mode)            ; manettes de la SMS -> octets Coleco (input.asm), avant que le
        or a                        ; gestionnaire du jeu les lise (POLLER)
        jr nz,.t
        push bc
        push de
        push hl
        ld hl,in_frame
        call gx_call
        pop hl
        pop de
        pop bc
.t:     push hl                     ; table des sprites sautée (scène chargée) : sp_late_nmi
        ld hl,sp_late_nmi
        call gx_call
        pop hl
        pop af
        call $8078                  ; nmi_handler du jeu (finit par RETN)
        push af
        ld a,(irq_slot2)
        ld (cur_slot2),a
        ld (MAP_SLOT2),a
        xor a
        ld (irq_busy),a
        ld a,(pal_owed)             ; une NMI due (PAL : trame lue par le jeu pendant cette NMI ;
        or a                        ; NMI différée qui passe avec celle-ci) : maintenant, sauf si
        jr z,.no                    ; le jeu n'a pas encore relu l'indicateur (gestionnaire
        ld a,(tms_flag)             ; différé par son verrou $70D4) : à la prochaine occasion
        or a
        jr nz,.no
        ld (pal_owed),a
        jr .ev
.drop:  push hl                     ; (rendue plus tard si le moteur en est la cause : nmi_drop)
        ld hl,nmi_drop
        call gx_call
        pop hl
.no:    pop af
        ei
        ret

; --- PAL : même vitesse qu'en NTSC -----------------------------------------------------------
; 50 images par seconde : 6 NMI du jeu pour 5 images (60 par seconde, comme l'original). Une
; interruption de ligne ne peut venir que des lignes 0 à 192 : l'image A reçoit deux NMI
; (ligne 0 et interruption de trame, ligne 192), les quatre suivantes une chacune (lignes 154,
; 116, 77, 39). Écarts : 192 lignes une fois, 275 lignes cinq fois (NTSC : 262).
; B = état du VDP ; sortie Z : NMI du jeu ; garde HL.
eng_pal:
        bit 7,b
        jr nz,.fr
        ld a,VDP_R0                 ; interruption de ligne : coupée jusqu'à la prochaine trame
        out (VDP_CTRL),a
        ld a,$80
        out (VDP_CTRL),a
        ld a,($73C4+RAM_SHIFT)      ; NMI autorisée par le jeu (registre 1 du TMS, bit 5)
        cpl
        and $20
        ret
.fr:
pal_frame:                          ; début d'image : programme son interruption de ligne ; Z : NMI
        push hl
        ld hl,pal_phase             ; phase de l'image qui commence (0 = image A)
        ld a,(hl)
        inc a
        cp 5
        jr c,.p
        xor a
.p:     ld (hl),a
        add a,low pal_lines
        ld l,a
        adc a,high pal_lines
        sub l
        ld h,a
        ld a,(hl)
        out (VDP_CTRL),a            ; registre 10 : ligne de l'interruption de cette image
        ld a,$8A
        out (VDP_CTRL),a
        ld a,VDP_R0 | $10           ; registre 0 : interruption de ligne autorisée
        out (VDP_CTRL),a
        ld a,$80
        out (VDP_CTRL),a
        pop hl
        ld a,(pal_phase)            ; fin de l'image A : NMI
        cp 1
        ret
pal_lines:  db 0, 154, 116, 77, 39
pal_rd:                             ; indicateur de trame lu par le jeu : pal_rd1 (engine.asm)
        push af
        push hl
        ld hl,pal_rd1
        call gx_call
        pop hl
        pop af
        ret

nmi_now:                            ; NMI différée délivrée par le fil principal (eng_test_signal)
        di
        push af
        jp eng_irq.ev

; --- bouton Pause ---------------------------------------------------------------------------
eng_nmi:
        push af
        ld a,1
        ld (pause_req),a
        pop af
        retn

; --- registres du TMS9918 -------------------------------------------------------------------
; = OS7 $1CCA. Le registre 1 du TMS est recopié dans celui de la SMS pour le bit 5
; (interruption de trame) : écrire le bit 5 alors que l'image est finie (indicateur non lu)
; déclenche l'interruption aussitôt, comme la NMI du TMS.
eng_write_register:                 ; = OS7 $1CCA (B = registre, C = valeur), mêmes accès
        ld a,b
        cp 1
        jp z,.r1
        cp 7
        call z,eng_backdrop         ; registre 7 : couleur du fond -> couleur 0 des palettes
        ld a,b
        cp 5
        jr z,.r5
        cp 3
        jr z,.rm
        cp 4
        jr z,.rm
        or a
        jr nz,.n0
        call .rm
        ld a,c
        ld ($73C3+RAM_SHIFT),a
        ret
.n0:
        ld a,b                      ; (registres 0, 2-6 : tables du TMS, sans objet en mode 4)
        cp $00
        ret nz
        ld a,c
        ld ($73C3+RAM_SHIFT),a
        ret
.rm:    ld a,b                      ; registres 0, 3, 4 (mode, masques des tables) : retenus, et automate
        cp 3
        ld a,c
        jr nz,.r4
        ld (tms_r3),a
        jr .rr
.r4:    bit 2,b
        jr z,.r0
        ld (tms_r4),a
        jr .rr
.r0:    ld (tms_r0),a
.rr:    push bc                     ; du décor,
        push de                     ; clé (4, registre, valeur, 0)
        push hl
        ld a,4
        ld (gx_kind),a
        ld (gx_dest),bc             ; octet bas = registre (B -> octet haut : remis ci-dessous)
        ld a,b
        ld (gx_dest),a
        xor a
        ld (gx_dest + 1),a
        ld a,c
        ld (gx_cnt),a
        xor a
        ld (gx_cnt + 1),a
        ld (gx_sum),a
        ld (gx_sum + 1),a
        ld hl,gx_pc
        call gx_call
        pop hl
        pop de
        pop bc
        ld a,b
        ret
.r5:    ld a,c                      ; registre 5 : table des sprites visible
        ld (sat_reg5),a
        push bc
        push de
        push hl
        push ix
        ld hl,sp_reg5
        call gx_call
        pop ix
        pop hl
        pop de
        pop bc
        ld a,b
        ret
.r1:    ld a,(tms_flag)             ; indicateur déjà replié AVANT l'écriture ?
        ld (wr_flag),a
        ld a,(irq_busy)
        or a
        jr nz,.r1w
        di                          ; deux octets de commande : pas d'interruption entre eux
.r1w:   ld a,c                      ; registre 1 : bit 6 (écran allumé) et bit 5 (NMI ->
        and $60                     ; interruption de trame SMS)
        or R1_SMS
        out (VDP_CTRL),a            ; (si l'image est finie, l'interruption part au EI, comme la NMI)
        ld a,$81
        out (VDP_CTRL),a
        ld a,(irq_busy)
        or a
        jr nz,eng_wr_after_out
        ei
eng_wr_after_out:                   ; (= $1CD2 de l'OS7 : point où la NMI du TMS part)
        ld a,(wr_flag)              ; indicateur replié et autorisation qui monte : NMI ici
        or a
        jr z,.cp
        ld a,($73C4+RAM_SHIFT)
        and $20
        jr nz,.cp
        bit 5,c
        call nz,$8078
.cp:    ld a,($73C4+RAM_SHIFT)      ; écran rallumé (bit 6 de 0 à 1) : sprites en attente
        cpl
        and c
        and $40
        ld a,c
        ld ($73C4+RAM_SHIFT),a
        ret z
        push bc
        push de
        push hl
        ld hl,sp_display_on
        call gx_call
        pop hl
        pop de
        pop bc
        ld a,c
        ret

eng_backdrop:                       ; C = registre 7 du TMS : couleur 0 des deux palettes SMS
        push hl
        push de
        ld a,c
        and 15
        ld e,a
        ld d,0
        ld hl,gfx_palette
        add hl,de
        ld e,(hl)
        ld a,(irq_busy)
        or a
        jr nz,.w
        di
.w:     xor a
        out (VDP_CTRL),a
        ld a,$C0
        out (VDP_CTRL),a
        ld a,e
        out (VDP_DATA),a
        ld a,16
        out (VDP_CTRL),a
        ld a,$C0
        out (VDP_CTRL),a
        ld a,e
        out (VDP_DATA),a
        ld a,(irq_busy)
        or a
        jr nz,.x
        ei
.x:     pop de
        pop hl
        ret

eng_read_register:                  ; = OS7 $1D57 : état (bit 7 = image finie), efface l'indicateur
        in a,(VDP_CTRL)             ; indicateur matériel (images sans interruption)
        and $80
        call nz,pal_rd
        push hl
        ld hl,tms_flag
        or (hl)
        ld (hl),0
        pop hl
        ret

; --- ports des manettes Coleco : « rst $30 » + une instruction sans effet qui code l'action ----------
; ld b,b ($40) lire $FC (manette 1) ; ld c,c ($49) lire $FF (manette 2) ;
; ld d,d ($52) mode pavé ($80) ; ld e,e ($5B) mode joystick ($C0). Au retour, cette instruction
; s'exécute (sans effet). Garde tous les registres et F ; A change seulement pour une lecture.
eng_colport:
        ex (sp),hl                  ; HL = adresse de l'action ; pile : HL d'origine
        push af
        ld a,(hl)
        cp $49
        jr c,.p1                    ; $40
        jr z,.p2                    ; $49
        and 1                       ; $52 -> 0 : pavé ; $5B -> 1 : joystick
        xor 1                       ; col_mode : 1 pavé, 0 joystick
        ld (col_mode),a
        pop af
        ex (sp),hl
        ret
.p2:    ld a,2
        jr .rd
.p1:    xor a
.rd:    push hl
        ld hl,col_mode
        add a,(hl)
        ld l,a
        ld h,0
        push de
        ld de,col_raw
        add hl,de
        pop de
        ld a,(hl)
        pop hl
        ld (col_val),a
        pop af                      ; F d'origine
        ld a,(col_val)
        ex (sp),hl
        ret

; --- cassette simulée -----------------------------------------------------------------------
; Les fichiers sont déjà en ROM : rien n'est copié. On garde le rythme de l'EOS simulé de
; l'original : une commande posée dans le DCB est finie quand le jeu le consulte ensuite.
dcb_done:                           ; commande en attente -> finie ($80)
        ld a,(fake_dcb)
        or a
        ret z
        bit 7,a
        ret nz
        ld a,$80
        ld (fake_dcb),a
        ret

eos_FC54:                           ; FIND_DCB : IY = DCB, Z
        push af
        call dcb_done
        pop af
        ld iy,fake_dcb
        cp a
        ret

eos_FCA2:                           ; START_RD_1_BLOCK : refusé (NZ) si le DCB est occupé
        ld a,4
        jr eos_start
eos_FCAB:                           ; START_WR_1_BLOCK
        ld a,3
eos_start:
        push af
        ld a,(fake_dcb)
        or a
        jr z,.ok
        bit 7,a
        jr nz,.ok
        pop af
        ld a,2
        or a                        ; NZ : occupé
        ret
.ok:    pop af
        ld (fake_dcb),a
        xor a                       ; Z
        ret

eos_FC45:                           ; END_RD_1_BLOCK : NC en cours ; C+Z fini ; C+NZ erreur
        call dcb_done
        ld a,(fake_dcb)
        or a
        jr nz,.busy
        ld a,3
        or a
        scf
        ret
.busy:  bit 7,a
        ret z
        cp $80
        scf
        ret

eos_FC63:                           ; impression (imprimante absente) : rien
eos_FC66:
        ret

; --- affichage : remplaçants de WRITE_VRAM ($1D01) et FILL_VRAM ($18D4) de l'OS7 ---------------
; Ici (présent dans les deux cartes mémoire) : la source peut être dans une fenêtre de données.
; Les octets utiles sont lus ici (somme, morceaux de noms recopiés dans gx_buf), le travail est
; fait en page 1 (display.asm) par gx_call. Registres de sortie identiques à ceux de l'OS7.
eng_vram_write:                     ; HL source, DE adresse VRAM, BC nombre (OS7 $1D01)
        ld (gx_src),hl
        ld (gx_dest),de
        ld (gx_cnt),bc
        ld h,0                      ; nombre réel, comme l'OS7 : E (0 = 256) octets, puis 256 par
        ld l,c                      ; unité de D au-delà de 1 (D de 2 à 128)
        ld a,c
        or a
        jr nz,.e
        inc h
.e:     ld a,b
        cp 2
        jr c,.n
        cp 129
        jr nc,.n
        dec a
        add a,h
        ld h,a
.n:     ld (gx_n),hl
        ld a,(gx_stream)            ; dans un flot RLE vers motifs/couleurs : traité à sa fin
        cp 3
        jr z,.x
        ld a,1
        ld (gx_kind),a
        call gx_dispatch
.x:
        ld hl,(gx_src)              ; HL = source + nombre ; B = 0, C = $BE ; D = $FF si D était 0,
        ld de,(gx_n)                ; sinon 0 ; E inchangé ; A = octet haut de (adresse + $4000)
        add hl,de
        ld de,(gx_cnt)
        ld a,d
        or a
        ld d,$FF
        jr z,.d
        ld d,0
.d:     ld a,(gx_dest + 1)
        add a,$40
        ld bc,$00BE
        ret

eng_vram_fill:                      ; HL adresse VRAM, DE nombre (0 = 65536), A valeur (OS7 $18D4)
        ld (gx_val),a
        ld a,(gx_stream)            ; dans un flot RLE vers motifs/couleurs : traité à sa fin
        cp 3
        jr nz,.n
        ld de,0
        ld a,(gx_val)
        ld c,a
        jp eng_read_register
.n:     ld a,(gx_val)
        ld (gx_dest),hl
        ld (gx_cnt),de
        ld (gx_n),de
        ld (gx_val),a
        ld (gx_bsave),bc
        ld b,a                      ; somme de la clé : valeur * $0101, xor registres 3 (haut) et 4
        ld c,a
        ld a,(tms_r3)
        xor b
        ld b,a
        ld a,(tms_r0)
        add a,a
        add a,a
        add a,a
        add a,a
        xor c
        ld c,a
        ld a,(tms_r4)
        xor c
        ld c,a
        ld (gx_sum),bc
        ld a,2
        ld (gx_kind),a
        call gx_dispatch
        ld hl,(gx_dest)             ; HL inchangé, DE = 0, B inchangé, C = valeur
        ld de,0
        ld bc,(gx_bsave)
        ld a,(gx_val)
        ld c,a
        jp eng_read_register        ; comme l'OS7 : lecture de l'état en fin de remplissage

; --- flots RLE ($83A0) vers les tables de motifs / couleurs : une transition par flot ----------
eng_rle_in:                         ; remplace « ld ($7137),bc » en $83A0 ; HL = adresse VRAM,
        ld ($7137+RAM_SHIFT),bc     ; BC = octets de contrôle, IY = valeurs ; garde tout
        push af
        ld a,h
        cp $18
        jr c,.pc                    ; motifs
        sub $20
        cp $18
        jr c,.pc                    ; couleurs
        ld a,h                      ; noms ($1800-$1AFF) : écran mis d'accord en fin de flot
        sub $18
        cp 3
        jr nc,.x
        ld a,4
        ld (gx_stream),a
        push hl
        ld hl,$FFFF
        ld (gx_dmin),hl
        inc hl
        ld (gx_dmax),hl
        pop hl
        jr .x
.pc:    ld a,3
        ld (gx_stream),a
        ld (gx_skey),hl
        ld (gx_skey + 2),bc
        ld (gx_skey + 4),iy
.x:     pop af
        ret

eng_rle_out:                        ; remplace « jp z,$8422 » en $83B4 : fin du flot, puis le « ret »
        push af                     ; de $8422 ; garde tout
        ld a,(gx_stream)
        or a
        jr z,.x
        push bc
        push de
        push hl
        cp 4
        jr z,.names
        xor a
        ld (gx_stream),a
        ld a,3                      ; clé : type 3, adresse, contrôle, valeurs
        ld (gx_kind),a
        ld hl,(gx_skey)
        ld (gx_dest),hl
        ld hl,(gx_skey + 2)
        ld (gx_cnt),hl
        ld hl,(gx_skey + 4)
        ld (gx_sum),hl
        ld hl,gx_pc
        call gx_call
.y:     pop hl
        pop de
        pop bc
.x:     pop af
        ret
.names: xor a                       ; flot vers les noms : plage [gx_dmin, gx_dmax) mise d'accord
        ld (gx_stream),a
        ld hl,(gx_dmax)
        ld de,(gx_dmin)
        or a
        sbc hl,de
        jr c,.y
        jr z,.y
        ld (gx_nlen),hl
        ld (gx_ncell),de
        ld hl,gx_reconcile_e
        call gx_call
        jr .y

eng_spr_table:                      ; = OS7 $1C82 WR_SPR_NM_TBL (A = nombre d'entrées) : sprite.asm
        ld (sp_count),a
        ld hl,sp_table
        call gx_call
        ld ix,(sp_out_ix)           ; registres de sortie de l'OS7
        ld hl,(sp_out_hl)
        ld de,($73F2+RAM_SHIFT)
        ld iy,$73F2+RAM_SHIFT
        ld bc,$00BE
        xor a
        ret

gx_dispatch:                        ; opération : gx_kind, gx_dest, gx_n, gx_src ou gx_val
        ld a,(gx_stream)            ; dans un flot de motifs/couleurs : traité à sa fin
        cp 3
        ret z
        ld hl,(gx_dest)
        ld de,(gx_n)
        add hl,de                   ; HL = fin (exclue)
        jr c,.gen
        ld a,(gx_dest + 1)          ; cas courant : entièrement dans la table des noms
        cp $18
        jr c,.gen
        cp $1B
        jr nc,.gen
        ld a,h
        cp $1B
        jr c,.pure
        jr nz,.gen
        ld a,l
        or a
        jr nz,.gen
.pure:  ld hl,(gx_dest)
        ld (gx_nlen),de
        ld de,-$1800
        add hl,de
        ld (gx_ncell),hl
        ld hl,(gx_src)
        ld (gx_nsrc),hl
        jp gx_names_part
.gen:   ld hl,(gx_dest)             ; noms : début = max(adresse, $1800), fin = min(fin, $1B00)
        ld de,(gx_n)
        add hl,de
        jr c,.cap
        ld de,$1B00
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,.e
.cap:   ld hl,$1B00
.e:     ld (gx_nend),hl
        ld hl,(gx_dest)
        ld de,$1800
        push hl
        or a
        sbc hl,de
        pop hl
        jr nc,.b
        ld hl,$1800
.b:     ld (gx_nbeg),hl
        ex de,hl
        ld hl,(gx_nend)
        or a
        sbc hl,de
        jr c,.pc
        jr z,.pc
        ld (gx_nlen),hl
        ld hl,-$1800
        add hl,de
        ld (gx_ncell),hl
        ld hl,(gx_nbeg)             ; source des noms = source + (début - adresse)
        ld de,(gx_dest)
        or a
        sbc hl,de
        ld de,(gx_src)
        add hl,de
        ld (gx_nsrc),hl
        call gx_names_part
.pc:    call gx_parts               ; A : bit 0 motifs/couleurs, bit 1 motifs des sprites, bit 2 table des sprites
        ld (gx_parts_v),a
        and 3
        jr z,.sat
        ld a,(gx_kind)              ; clé : somme des 8 premiers octets écrits (s'ils touchent les
        cp 1                        ; motifs des sprites : de tous, tournée) ; lus ici : la source peut être dans
        jr nz,.k                    ; une fenêtre
        ld hl,(gx_n)
        ld a,(gx_parts_v)
        and 2
        jr nz,.q8
        ld a,h
        or a
        jr nz,.s8
        ld a,l
        cp 8
        jr c,.all
.s8:    ld hl,8
.all:   ld b,h                      ; somme des 8 premiers octets
        ld c,l
        ld hl,(gx_src)
        ld de,0
.s:     ld a,(hl)
        add a,e
        ld e,a
        jr nc,.s1
        inc d
.s1:    inc hl
        dec bc
        ld a,b
        or c
        jr nz,.s
        jr .sd
.q8:    ld b,h                      ; motifs des sprites : tous les octets, E tourné d'un bit avant
        ld c,l                      ; chaque octet ajouté, retenues dans D (gfx_build.py key_of)
        ld hl,(gx_src)
        ld de,0
.t:     ld a,e
        rlca
        add a,(hl)
        ld e,a
        jr nc,.t1
        inc d
.t1:    inc hl
        dec bc
        ld a,b
        or c
        jr nz,.t
.sd:    ld (gx_sum),de
.k:     ld a,(gx_parts_v)
        rra
        jr nc,.q
        ld hl,gx_pc
        call gx_call
.q:     ld a,(gx_parts_v)
        and 2
        jr z,.sat
        ld hl,sp_q
        call gx_call
.sat:   ld a,(gx_parts_v)
        and 4
        ret z
        ld hl,sp_sat_op
        jp gx_call

gx_parts:                           ; parties touchées par [gx_dest, gx_dest + gx_n) -> A (bits 0-2)
        ld hl,(gx_dest)
        ld de,(gx_n)
        add hl,de
        jr nc,.e
        ld hl,$FFFF
.e:     ld (gx_endx),hl
        ld c,0
        ld hl,$0000                 ; motifs
        ld de,$1800
        call gx_over
        jr nc,.c
        set 0,c
.c:     ld hl,$2000                 ; couleurs
        ld de,$3800
        call gx_over
        jr nc,.q
        set 0,c
.q:     ld hl,$3800                 ; motifs des sprites
        ld de,$4000
        call gx_over
        jr nc,.s
        set 1,c
.s:     ld hl,$1B00                 ; tables des sprites
        ld de,$1B80
        call gx_over
        jr nc,.s2
        set 2,c
.s2:    ld hl,$1F00
        ld de,$1F80
        call gx_over
        jr nc,.x
        set 2,c
.x:     ld a,c
        ret

gx_over:                            ; C si [gx_dest, gx_endx) recoupe [HL, DE) (garde C)
        push hl                     ; gx_dest < DE ?
        ld hl,(gx_dest)
        or a
        sbc hl,de
        pop hl
        ret nc                      ; NC : non
        ex de,hl                    ; HL < gx_endx ?
        ld hl,(gx_endx)
        scf
        sbc hl,de                   ; gx_endx - 1 - lo : >= 0 si recouvrement
        ccf
        ret

gx_names_part:                      ; gx_nlen cellules dès gx_ncell ; source gx_nsrc ou valeur gx_val
        ld hl,(gx_ncell)            ; recopiées ici dans name_shadow (la source peut être dans une
        ld de,name_shadow           ; fenêtre), puis l'écran SMS est mis d'accord (gx_reconcile)
        add hl,de
        ex de,hl
        ld bc,(gx_nlen)
        ld a,(gx_kind)
        cp 2
        jr z,.fill
        ld hl,(gx_nsrc)
        ldir
        jr .done
.fill:  ld a,(gx_val)
        ld (de),a
        dec bc
        ld a,b
        or c
        jr z,.done
        ld h,d
        ld l,e
        inc de
        ldir
.done:  ld a,(gx_stream)
        cp 4
        jr z,.defer
        ld hl,gx_reconcile_e
        jr gx_call
.defer: ld hl,(gx_ncell)            ; dans un flot vers les noms : plage à mettre d'accord en fin de flot
        ld de,(gx_dmin)
        push hl
        or a
        sbc hl,de
        pop hl
        jr nc,.m1
        ld (gx_dmin),hl
.m1:    ld de,(gx_nlen)
        add hl,de                   ; fin (exclue)
        ld de,(gx_dmax)
        push hl
        or a
        sbc hl,de
        pop hl
        ret c
        ld (gx_dmax),hl
        ret

gx_call:                            ; HL = routine en page 1 ; si les pages de données sont en place
        ld a,(map01)                ; (fenêtre), pages normales le temps de l'appel. Appelable aussi
        or a                        ; depuis l'interruption (sprites) : map01 dit la carte réelle
        jr z,.go
        call map_normal
        call .go
        push af
        call map_data
        pop af
        ret
.go:    jp (hl)

map_normal:                         ; pages 0 et 1 normales (garde HL ; pas d'interruption au milieu)
        ld a,(irq_busy)
        or a
        jr nz,.n
        di
.n:     xor a
        ld (map01),a
        ld (MAP_SLOT0),a
        inc a
        ld (MAP_SLOT1),a
        jr map_ei
map_data:                           ; pages de données (fenêtre)
        ld a,(irq_busy)
        or a
        jr nz,.n
        di
.n:     ld a,PAGE_DATA0
        ld (MAP_SLOT0),a
        ld a,(data_page1)
        ld (MAP_SLOT1),a
        ld a,1
        ld (map01),a
map_ei: ld a,(irq_busy)
        or a
        ret nz
        ei
        ret

        INCLUDE "../gen/gfx.inc"     ; palette (ici : lue aussi pendant une fenêtre)

; --- fenêtres : données graphiques d'origine ($2000-$6EFF) le temps d'une routine du jeu ------
; Les routines d'affichage du jeu lisent leurs données aux adresses d'origine, où le portage a
; mis son code relocalisé. On met en place, le temps de l'appel, les pages « données » (OS7 et
; ce moteur à l'identique en $0000-$1FFF, données en $2000-$7FFF) : mêmes lectures, même durée.
win_8376:
        call win_on
        call $8376
        jr win_off
win_83A0:
        call win_on
        call $83A0
        jr win_off
win_8CED:
        call win_on
        call $8CED
        jr win_off
win_8D10:
        call win_on
        call $8D10
win_off:                            ; garde AF
        push af
        ld a,(win_depth)
        dec a
        ld (win_depth),a
        call z,map_normal
        pop af
        ret
win_on:                             ; garde AF
        push af
        ld a,(win_depth)
        inc a
        ld (win_depth),a
        call map_data
        pop af
        ret

