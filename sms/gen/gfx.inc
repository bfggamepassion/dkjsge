; gfx.inc - produit par sms/tools/gfx_build.py (ne pas modifier)
GFX_PAGE0       equ 6         ; première page des données du décor
GFX_PAGES       equ 25
GFX_TILES       equ 905        ; tuiles SMS converties (numéro = contenu)
GFX_NONE        equ $FFFF       ; contenu jamais affiché dans les parties relevées
GFX_NSTATES     equ 59
GFX_ANY_PAGE    equ 10
GFX_ANY_ADDR    equ $B3A0
SPR_PAGE        equ 11         ; motifs 16x16 des sprites : numéro n -> $8000 + 32n
SPR_PATTERNS    equ 154
SPR_ANY_PAGE    equ 11
SPR_ANY_ADDR    equ $9C84
TITLE_PAGE      equ 31         ; écran de titre (démarrage) : 768 noms (2 octets), puis les tuiles
TITLE_ADDR      equ $8000
TITLE_TILES     equ 155
GO_PAGE         equ 31         ; écran de fin de partie (même format, puis tuiles des chiffres
GO_ADDR         equ $9960       ; 0-9 : 10 octets)
GO_TILES        equ 152
GO_BLANK        equ 0         ; tuile du fond
GO_LINE1        equ 555       ; cellule du début de « 1UP 000000 », puis « 2UP » : GO_LINE2
GO_LINE2        equ 619
LAY_N           equ 5         ; couches du décor (couches.py) : en-tête
LAY_PAGE        equ 30
LAY_ADDR        equ $AF7B
LAY_CLES        equ 2         ; couche de l'écran des clés (sprite.asm sp_screen ; 0 : aucune)
gfx_palette:    db $00, $00, $0C, $1D, $30, $35, $03, $3C, $17, $17, $0B, $0F, $08, $33, $2A, $3F
