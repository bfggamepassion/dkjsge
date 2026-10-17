; vars.asm - variables du moteur (RAM $C500-)
        ORG ENG_RAM
        ASSERT ENG_RAM % 256 == 0
; tables alignées sur 256 octets (indexées par (banque, motif), cellule, case, sprite)
name_shadow: ds 768             ; table des noms du TMS (écrite par le jeu) : cellule -> motif
name_applied: ds 768            ; ce que montre la table des noms SMS : cellule -> motif
bi_slot:    ds 768              ; tuile TMS (banque*256+motif) -> case SMS ($FF : aucune)
cc_lo:      ds 768              ; tuile TMS -> contenu actuel (numéro de tuile convertie), octet bas
cc_hi:      ds 768              ;   octet haut
ref_lo:     ds 256              ; case -> nombre de cellules qui l'affichent, octet bas
ref_hi:     ds 256              ;   octet haut
free_slots: ds 256              ; pile des cases libres
spg:        ds 256              ; sprites : rangs, groupes, quarts (sprite.asm, SP_RANK...)
spg2:       ds 256              ; sprites : entrées rapides des sprites seuls (SF)
ckp:        ds 256              ; cases du cache des tuiles : versions, passes (CK_VER, CK_STAMP)
frames:     ds 2                ; compteur d'images SMS
pause_req:  ds 1                ; bouton Pause appuyé (NMI)
tms_flag:   ds 1                ; indicateur de trame du TMS9918 (posé au retour de trame, effacé par READ_REGISTER)
wr_flag:    ds 1                ; tms_flag au début d'une écriture du registre 1
col_mode:   ds 1                ; 0 joystick, 1 pavé (dernière sélection des manettes Coleco)
col_val:    ds 1                ; valeur lue (passage)
col_raw:    ds 4                ; octets Coleco bruts : j1 joystick, j1 pavé, j2 joystick, j2 pavé
pal_on:     ds 1                ; 1 : console PAL (50 images/s) : 6 NMI du jeu pour 5 images
pal_phase:  ds 1                ; image en cours dans le cycle de 5 (0 = image A, deux NMI)
pal_owed:   ds 1                ; 1 : NMI due, délivrée à la prochaine interruption (PAL : trame lue par le jeu)
nmi_owed:   ds 1                ; 1 : NMI différée (nmi_defer), délivrée par eng_test_signal ou avec la suivante
tick_age:   ds 1                ; NMI délivrées depuis le dernier test de la minuterie du tour
ts_timer:   ds 1                ; minuterie testée, résultat (eng_test_signal)
ts_res:     ds 1
nmi_fixed:  ds 1                ; 1 : NMI imposées par un outil de test (lockstep) : jamais différées
test_mode:  ds 1                ; 1 : col_raw écrit par l'outil de test, pas par la manette
fake_dcb:   ds 21               ; DCB de la cassette simulé (commandes terminées à l'image suivante)
V_8563:     ds 2                ; ex-$8563 : pointeur d'état du chargeur (était dans le code)
V_FD6F:     ds 1                ; ex-$FD6F : unité de démarrage EOS (8 = cassette 1)
win_depth:  ds 1                ; profondeur des fenêtres de données ouvertes
data_page1: ds 1                ; page « données » pour $4000-$7FFF (selon les fichiers chargés)
irq_busy:   ds 1                ; 1 pendant le gestionnaire d'interruption (pas de DI/EI du moteur)
cur_slot2:  ds 1                ; page en $8000-$BFFF (2 = code du jeu ; données du décor sinon)
irq_slot2:  ds 1                ; page de l'emplacement 2 au moment de l'interruption
; décor (display.asm) : opération en cours, clé de l'automate (7 octets contigus)
gx_kind:    ds 1                ; 1 écriture, 2 remplissage
gx_dest:    ds 2                ; adresse VRAM du TMS
gx_cnt:     ds 2                ; nombre passé (BC ou DE)
gx_sum:     ds 2                ; somme 16 bits des octets (remplissage : valeur * $0101)
gx_n:       ds 2                ; octets réellement écrits
gx_src:     ds 2
gx_val:     ds 1
gx_bsave:   ds 2
gx_nbeg:    ds 2
gx_nend:    ds 2
gx_nlen:    ds 2
gx_ncell:   ds 2
gx_nsrc:    ds 2
gx_buf:     ds 64
gx_dpage:   ds 1
gx_stream:  ds 1                ; 3 : flot RLE vers les motifs/couleurs en cours (eng_rle_in)
gx_skey:    ds 6                ; sa clé : adresse VRAM, octets de contrôle, valeurs
gx_vnext:   ds 2                ; cellule où en est l'adresse du VDP (gx_cell ; $FFxx : inconnue)
gx_dmin:    ds 2                ; flot vers les noms (4) : plage de cellules à mettre d'accord
gx_dmax:    ds 2
tms_r0:     ds 1                ; registre 0 du TMS (bit 1 : mode graphique 2)
tms_r3:     ds 1                ; registres 3 et 4 du TMS (masques des tables de couleurs, motifs)
tms_r4:     ds 1
gx_list:    ds 3
gx_endx:    ds 2                ; fin (exclue) de l'opération en cours
gx_parts_v: ds 1                ; parties touchées (bit 0 motifs/couleurs, 1 motifs des sprites, 2 tables des sprites)
gx_err_sat: ds 2                ; copies dans une table de sprites (jamais vu)
map01:      ds 1                ; 1 : pages de données en $0000-$7FFF (fenêtre), 0 : pages normales
; sprites (sprite.asm)
sq_list:    ds 3                ; automate des motifs des sprites : liste de l'état courant
sat_reg5:   ds 1                ; registre 5 du TMS
sat_act:    ds 1                ; table visible : 1 = $1B00, 2 = $1F00, 0 = aucune
sp_count:   ds 1
sp_tab:     ds 1
sp_out_ix:  ds 2                ; registres de sortie de WR_SPR_NM_TBL
sp_out_hl:  ds 2
sp_touch:   ds 1
sp_y:       ds 1
sp_s:       ds 1
own_1b:     ds 32               ; table $1B00 « vive » : sprite du jeu de chaque entrée (ordre à l'envoi)
own_1f:     ds 32               ; idem $1F00
tab_mode:   ds 2                ; $1B00, $1F00 : 0 vive, 1 remplie
tab_fill:   ds 2                ;   valeur de remplissage
sp_cc:      ds 128              ; motif 16x16 (0-63) -> contenu (numéro de motif converti)
sp_list:    ds 128              ; quarts affichés : Y, X, première tuile, rang (sp_rebuild)
sp_n:       ds 1                ; entrées avant la fin de table
sp_fk:      ds 17               ; clé rapide du groupe en cours
sp_rk:      ds 21               ; clé de la ROM : n, (contenu bas, haut, couleur, du, dx) x n
sp_rec:     ds 3                ; enregistrement de la pose trouvée (page, adresse)
sp_data:    ds 2                ; tuiles du quart suivant
sp_qm:      ds 1                ; quarts présents
sp_id:      ds 4
sp_nq:      ds 1
sp_pq:      ds 1
sp_qi:      ds 1
of_tab:     ds 8 * 26           ; entrées rapides des objets : clé (17), quarts, cases (4), versions (4)
ob_i:       ds 1
ob_p:       ds 2
ob_c:       ds 2
gp_rk:      ds 1
gq_t:       ds 4
sp_kfull:   ds 4                ; sprite seul inconnu : 1, contenu, couleur (sp_gen1)
ob_n:       ds 8
ob_m:       ds 32
ob_tmp:     ds 4
ob_cnt:     ds 1
ob_max:     ds 1
gp_s:       ds 1
gp_umin:    ds 1
gp_xmin:    ds 1
gp_tx:      ds 1
gq_y:       ds 1
gq_x:       ds 1

sp_mask:    ds 4                ; masques des 4 plans d'une couleur (sp_gen1)
ck_next:    ds 1
sp_stamp:   ds 1
sp_k2:      ds 1
sp_pending: ds 1
sp_prev_ok: ds 1                ; SP_PREV (spg2) valable pour sp_same
sp_prev_x:  ds 2                ; table active, écran de la passe précédente
sp_heavy:   ds 1                ; dernière table des sprites lourde : demande suivante sautée
sp_late:    ds 1                ; demande sautée : NMI depuis (0 : aucune)
sat_back:   ds 1                ; octet haut de la table des sprites SMS cachée ($37 ou $3F)
sat_pend:   ds 1                ; 1 : table cachée prête, montrée à la prochaine interruption de trame
sp_bstamp:  ds 1                ; passe (sp_stamp) écrite dans la table cachée
sp_shown:   ds 1                ; passe de la table montrée : ses cases ne sont pas reprises
sp_try:     ds 1
; couches des sprites fusionnées (sp_rebuild) : groupes de sprites du jeu à la même place
sp_klen:    ds 1
; manettes et menus (input.asm)
in_n1:      ds 1                ; manette 1, 2 (0 = appuyé : haut, bas, gauche, droite, b1, b2)
in_n2:      ds 1
in_prev1:   ds 1
in_prev2:   ds 1
in_pause:   ds 1                ; images restantes de « * »
menu_on:    ds 1                ; images restantes : le jeu attend une touche du pavé (eng_menu)
menu_was:   ds 1
menu_lo:    ds 1                ; touches acceptées : menu_lo à menu_hi - 1
menu_hi:    ds 1
menu_pads:  ds 1                ; bit 0 pavé 1, bit 1 pavé 2
menu_sel:   ds 1                ; chiffre choisi
menu_hold:  ds 1                ; images restantes de la touche validée
menu_cell:  ds 2                ; cellule du chiffre choisi à l'écran ($FFFF : pas trouvée)
menu_bc:    ds 2                ; bornes et pavés du menu en cours ($7162) : autre menu -> premier choix
gx_err_full: ds 2               ; tuiles sans case libre (jamais vu)
gx_err_none: ds 2               ; tuiles affichées sans contenu relevé (jamais vu)
free_top:   ds 1
title_skip: ds 1                ; écran de titre passé sans bouton (outils de test : smssim, scripts Mesen)
go_sat:     ds 2                ; écran de fin de partie : premiers octets des deux tables des sprites
go_dig:     ds 2                ;   tuiles des chiffres 0-9 (adresse dans la page GO_PAGE)
adam_hide:  ds 1                ; écran ADAM du chargement caché (palette noire) : 1 ; 2 : chargement fini (section $0F),
                                ; palette rendue quand il rallume l'écran (sp_display_on -> adam_show) ; 0 : fini
; couches du décor (display.asm, lay_*)
lay_seen:   ds 1                ; couche désignée par les repères (même couches coupées : lockstep)
lay_cur:    ds 1                ; couche montrée : 0 aucune, 1-n, $FF écran à redessiner
lay_pa:     ds 1                ; enregistrement A de la couche (page, adresse)
lay_aa:     ds 2
lay_pb:     ds 1                ; page B (listes des cellules), adresse de ses 768 pointeurs
lay_ab:     ds 2
lay_hi:     ds 1                ; octet haut de l'entrée de la table des noms (retournements, palette)
lay_nb:     ds 1                ; lay_scan : cellules trouvées (octets bas, banque connue)
lay_buf:    ds 16
lay_sc:     ds 2 * 19           ; cache de lay_scan : 2 x (banque ($FF : vide), motif, nombre, 16 cellules)
lay_sc_next: ds 1               ;   liste remplacée au prochain parcours
lay_cv:     ds 2                ; redessin : contenu, cellule
lay_cl:     ds 2
        ALIGN 256
bi_slot4:   ds 256              ; couches : bases 768-1023 -> case (suite de bi_slot)
ENG_RAM_END:
