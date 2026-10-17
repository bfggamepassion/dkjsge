; Généré par tools/disasm.py depuis names.txt -- ne pas éditer
OS7_PLAY_SONGS           EQU $1F61   ; écrit le port son $FF (appelé 1x/trame par la NMI)
OS7_FILL_VRAM            EQU $1F82   ; écrit le VDP ($BE/$BF)
OS7_INIT_TABLE           EQU $1FB8   ; HYP: vecteur cité en $8051 (enveloppe RST)
OS7_WR_SPR_NM_TBL        EQU $1FC4   ; copie la table de sprites RAM vers la VRAM (A = nombre)
OS7_REQUEST_SIGNAL       EQU $1FCD   ; crée une minuterie (HL = trames) -> A = numéro
OS7_TEST_SIGNAL          EQU $1FD0   ; A = minuterie ; NZ si échue (boucle principale)
OS7_TIME_MGR             EQU $1FD3   ; fait avancer les minuteries (NMI, 1x/trame)
OS7_WRITE_REGISTER       EQU $1FD9   ; HYP: écrit un registre VDP (B = registre, C = valeur)
OS7_READ_REGISTER        EQU $1FDC   ; lit l'état VDP (in $BF) -> A
OS7_WRITE_VRAM           EQU $1FDF   ; écrit le VDP ($BE/$BF)
OS7_POLLER               EQU $1FEB   ; lit les manettes (in $FC/$FF, out $80/$C0) -> tampon $7000
OS7_SOUND_MAN            EQU $1FF4   ; gestion des canaux son (NMI, 1x/trame)
OS7_RAND_GEN             EQU $1FFD   ; générateur pseudo-aléatoire de l'OS7
FILE_QUEUE               EQU $6F6A   ; file circulaire des demandes de fichiers cassette ($80 vide, $FF fin)
LOAD_WAIT                EQU $6F7E   ; 1 : la séquence attend la fin du chargement ($8289)
LOAD_BUSY                EQU $6F7F   ; 1 : chargement en cours (attendu en $8144, $8179)
KEYS                     EQU $6FB3   ; écran 1 : 6 clés x (X, Y), Y = $98 en bas ; copiées de $EA25 par $EA15 (lu)
CTRL_BUFFER              EQU $7000   ; tampon des manettes de l'OS7 (en-tête $8008) ; pavé J1 en $7006
SPR_ORDER                EQU $702B   ; ordre d'affichage des 32 sprites (tourne à chaque NMI : clignotement)
SPR_TABLE                EQU $704B   ; table des sprites en RAM (Y, X, motif, couleur) x 32 -> VRAM par la NMI
FRAME_FLAG               EQU $70D3   ; mis à 1 par le jeu, remis à 0 par la NMI ($80B2) : attente de trame ($8BE4)
NMI_LOCK                 EQU $70D4   ; bit 0 : VDP occupé (enveloppes RST) ; bit 7 : NMI différée
LEVEL_BCD                EQU $70F7   ; compteur d'étapes jouées +1, en BCD (affiché « BONUS nn » ; 09 à l'étape 8, vu)
STAGE_CYCLE12            EQU $70F8   ; 1 (posé en $915A) : cycle de 12 étapes, sinon 8 ($CA16)
NB_PLAYERS               EQU $70FA   ; nombre de joueurs (1 ou 2, vu en simulation)
CUR_PLAYER               EQU $70FB   ; joueur courant 1/2 (vu : alterne aux morts ; choisit la manette, $C8CF)
SCREEN                   EQU $70FD   ; type d'écran 0-4 de l'étape (posé en $8262) ; 0,1,0,2,1,0,1,3,4,2,3,4 (vu)
STAGE                    EQU $70FE   ; étape 0-11 ; mise à 0 en $CACF, +1 en $CA2A ; choisit la séquence ($7829)
STAGE_RESULT             EQU $7103   ; résultat rendu par la boucle d'étape (1 = gagnée), $C945
P1_LIVES                 EQU $7106   ; vies du joueur 1 (5 au départ, -1 à chaque mort, vu en simulation)
P1_SCORE                 EQU $710F   ; score du joueur 1, 6 chiffres ASCII (vu : « 049000 » affiché)
P2_LIVES                 EQU $7115   ; vies du joueur 2 (vu : 5 -> 4 à la mort du joueur 2)
P2_SCORE                 EQU $711E   ; score du joueur 2, 6 chiffres ASCII
TICK_TIMER               EQU $7126   ; minuterie OS7 de game_tick, testée en $C834
KEYS_LOCKED              EQU $7130   ; écran 1 : clés posées ; 6 -> étape gagnée ($E811, lu)
LOAD_FILE                EQU $713D   ; fichier cassette en cours de chargement ($FF : aucun)
LOAD_STATE               EQU $713E   ; étape du chargeur (0 repos, 2 lecture, 3 état, 4 contrôle)
LOAD_CMD                 EQU $713F   ; $81 lecture, $82 écriture, 0 : rien ; erreur sinon
LOAD_ADDR                EQU $7140   ; adresse du bloc en cours (mot)
LOAD_BLOCK               EQU $7142   ; numéro du bloc en cours (mot)
LOAD_COUNT               EQU $7144   ; blocs restant à lire
ANIM_SIGNAL              EQU $7145   ; minuterie OS7 du moteur d'animation (créée en $8873, testée en $8879)
SCRIPT_ARGS              EQU $7146   ; arguments de l'opcode de cinématique en cours, copiés par $8917 (2 à 9 octets ; restes des précédents au-delà)
JR_OBJ                   EQU $720E   ; Junior : +0 pose, +1 X, +3 Y (lu par $DBD3 pour ses 3 sprites)
JR_X                     EQU $720F   ; X de Junior (pixels)
JR_Y                     EQU $7211   ; Y de Junior (pixels, 0 = haut)
OBJECTS                  EQU $7213   ; 13 objets x 10 octets, objet k -> sprite k+3 ($7057+4k) (boucle $DF38)
MAIN_SP                  EQU $7297   ; SP sauvé à l'entrée de la boucle principale ($C80F)
JR_STATE                 EQU $72EA   ; état de Junior : 0 au sol, 1 accroché (liane/chaîne), 2 chute, 3 saut (vu en simulation)
ZONE_NEXT                EQU $72FB   ; suite de la liste de zones après une entrée $FE ($D25B, relu en $D26C)
VDP_STATUS_COPY          EQU $73C5   ; copie de l'état VDP (NMI, OS7_READ_REGISTER)
FILE_TABLE_PTR           EQU $7DD4   ; pointeur vers la table des fichiers cassette ($7DD6)
FILE_TABLE               EQU $7DD6   ; 10 x (adresse, bloc, nombre de blocs)
EOS_GAME_MAP             EQU $FC1A   ; octet de carte mémoire « jeu » (3 = OS7 + RAM), lu par l'amorce
EOS_END_RD_1_BLOCK       EQU $FC45   ; A = unité ; NC : en cours ; C+Z : fini ; C+NZ : erreur
EOS_FIND_DCB             EQU $FC54   ; A = unité -> IY = DCB
EOS_WRITE_STRING         EQU $FC63   ; écrit une chaîne vers l'unité 2 (imprimante) ; messages d'erreur
EOS_WRITE_CHAR           EQU $FC66   ; écrit A vers l'unité 2 (imprimante)
EOS_START_RD_1_BLOCK     EQU $FCA2   ; A = unité, HL = tampon, BCDE = bloc (DCB commande 4)
EOS_START_WR_1_BLOCK     EQU $FCAB   ; même chose en écriture (DCB commande 3)
EOS_SET_MEMORY_MAP       EQU $FD14   ; out ($7F),A et mémorise en $FD6E
EOS_BOOT_DEVICE          EQU $FD6F   ; unité de démarrage (8 = cassette 1), lue par le chargeur du jeu
NET_RESET                EQU $3F   ; port
MEMMAP                   EQU $7F   ; port
KEYPAD_MODE              EQU $80   ; port
VDP_DATA                 EQU $BE   ; port
VDP_CTRL                 EQU $BF   ; port
JOY_MODE                 EQU $C0   ; port
JOY1                     EQU $FC   ; port
SOUND_JOY2               EQU $FF   ; port
