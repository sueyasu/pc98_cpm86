; CP/M-86 v1.1 BIOS for PC-9801
;


cpu 8086
bits 16

org 0x2500

BDOS_INT        equ 0x00e0
BDOS_OFS        equ 0x0b06
BOOT_DAUA       equ 0x0584
SER_DATA        equ 0x30
SER_CTRL        equ 0x32
PIT_CH2         equ 0x75
PIT_CTRL        equ 0x77
SYS_FLAG        equ 0x0501
HIRES_BIT       equ 0x08
MEMSW_SEG       equ 0xA000
MEMSW3_OFS      equ 0x3FEA
TPA_BASE_SEG    equ 0x0800
BIOS_BIN_SIZE   equ 0x1900

HDD_FIRST_DRIVE equ 4
HDD_MAX_DRIVES  equ 4
HDD_CPM_SYS     equ 0x70

BIOS_WORK_BASE  equ 0x3E00
dirbuf          equ BIOS_WORK_BASE + 0x000   ; 128 bytes
physbuf         equ BIOS_WORK_BASE + 0x080   ; 512 bytes
stack_space     equ BIOS_WORK_BASE + 0x280   ; 256 bytes
stack_top       equ BIOS_WORK_BASE + 0x380

; physbuf on GVRAM
rw_write        equ physbuf + 0x00
win_slot        equ physbuf + 0x01
win_seg         equ physbuf + 0x02
win_cx          equ physbuf + 0x04
win_head        equ physbuf + 0x06
win_first       equ physbuf + 0x07
win_count       equ physbuf + 0x08
win_index       equ physbuf + 0x09
flush_slot      equ physbuf + 0x0A
flush_start     equ physbuf + 0x0B
flush_count     equ physbuf + 0x0C
io_write        equ physbuf + 0x0D
io_slot         equ physbuf + 0x0E
io_start        equ physbuf + 0x0F
io_count        equ physbuf + 0x10
io_daua         equ physbuf + 0x11
io_cmd          equ physbuf + 0x12
io_retry        equ physbuf + 0x13
io_cx           equ physbuf + 0x14
io_head         equ physbuf + 0x16
io_sector       equ physbuf + 0x17

; HDD discovery scratch is INIT-only and reuses dirbuf before CCP/BDOS starts.
hdd_heap_next   equ dirbuf + 0x00
hdd_heap_after  equ dirbuf + 0x02
hdd_scan_id     equ dirbuf + 0x04
hdd_scan_part   equ dirbuf + 0x05
hdd_scan_daua   equ dirbuf + 0x06
hdd_scan_heads  equ dirbuf + 0x07
hdd_scan_spt    equ dirbuf + 0x08
hdd_scan_cylast equ dirbuf + 0x0A
hdd_tmp_start   equ dirbuf + 0x0C
hdd_tmp_blocks  equ dirbuf + 0x0E
hdd_tmp_alv     equ dirbuf + 0x10

HDD_HEAP_BASE   equ BIOS_WORK_BASE + 0x380
HDD_HEAP_LIMIT  equ 0x9000
HDD_DPH_SIZE    equ 16
HDD_DPB_OFS     equ 16
HDD_CSV_OFS     equ 32
HDD_ALV_OFS     equ 160
BOOT_HINT_OFS   equ 0x3DE0
BOOT_HINT_SIZE  equ 32
BOOT_TYPE_FDD   equ 0
BOOT_TYPE_HDD   equ 1

; GVRAM fixed-window write-back cache.
; Physical A8000h..B83FFh is reserved while CP/M-86 is running.
;
; Eight independent data windows occupy exactly 64 KiB, arranged so no window
; crosses the physical 64-KiB DMA boundary at B0000h:
;   A: A8000-A9DFF  15 sectors (7.5 KiB)   FDD
;   B: A9E00-ABBFF  15 sectors (7.5 KiB)   FDD
;   E: ABC00-ADDFF  17 sectors (8.5 KiB)   HDD
;   F: ADE00-AFFFF  17 sectors (8.5 KiB)   HDD
;   C: B0000-B1DFF  15 sectors (7.5 KiB)   FDD
;   D: B1E00-B3BFF  15 sectors (7.5 KiB)   FDD
;   G: B3C00-B5DFF  17 sectors (8.5 KiB)   HDD
;   H: B5E00-B7FFF  17 sectors (8.5 KiB)   HDD
; Metadata uses B8000h..B83FFh.  Dirty sectors are flushed as maximal
; contiguous runs with one ROM-BIOS multi-sector WRITE per run.
CACHE_META_SEG   equ 0xB800
CACHE_META_SIZE  equ 16
CACHE_VALID      equ 0xA5
; Slot number already identifies FDD/HDD and DA/UA is kept in the per-drive
; maps, so metadata only needs the window key and dirty bitmap.
CM_VALID         equ 0
CM_HEAD          equ 1
CM_CX            equ 2
CM_FIRST         equ 4
CM_DIRTY         equ 6
CM_DIRTY_HI      equ 8
CACHE_SLOTS      equ 8
CACHE_HDD_WINDOW equ 17
HDD_REMOUNT_OFS  equ 0x3DD0
FDD_DAUA_OFS    equ 0x3DD4
CACHE_SYNC_OFS  equ 0x3DD8
CACHE_RESET_OFS equ 0x3DDC

; ----------------------------------------------------------------------
; CP/M-86 BIOS jump vector.
; ----------------------------------------------------------------------
    jmp near INIT
    jmp near WBOOT
    jmp near CONST
    jmp near CONIN
    jmp near CONOUT
    jmp near LISTOUT
    jmp near PUNCH
    jmp near READER
    jmp near HOME
    jmp near SELDSK
    jmp near SETTRK
    jmp near SETSEC
    jmp near SETDMA
    jmp near READ
    jmp near WRITE
    jmp near LISTST
    jmp near SECTRAN
    jmp near SETDMAB
    jmp near GETSEGT
    jmp near GETIOBF
    jmp near SETIOBF

    times 15 db 0

    dw compat_pfktable
    dw cur_disk
    dw compat_ser1
    db 0x10, 0x33
    dw compat_fiddsmem
    dw compat_crtmod

; ----------------------------------------------------------------------
; Initialization / warm boot
; ----------------------------------------------------------------------
INIT:
    cli
    mov ax, cs
    mov ss, ax
    mov sp, stack_top
    mov ds, ax
    mov es, ax
    cld

    ; Install CP/M-86 BDOS interrupt E0h -> system-segment:0B06h.
    push ds
    xor ax, ax
    mov ds, ax
    mov word [BDOS_INT * 4], BDOS_OFS
    mov ax, cs
    mov word [BDOS_INT * 4 + 2], ax

    ; Select the FDD ROM-BIOS command family from the boot DA/UA.
    ; Dual-mode FDDs use paired DA/UA families:
    ;   1MB-interface mode   : 2DD=10h..13h, 2HD=90h..93h
    ;   640KB-interface mode : 2DD=70h..73h, 2HD=F0h..F3h
    ; HDD boot cannot identify the active FDD command family from BOOT_DAUA,
    ; so leave it unknown and let the first FDD SELDSK probe both families.
    ; The 70h/F0h pair remains the first candidate for compatibility.
    ;
    ; For an FDD boot, BOOT_DAUA identifies the physical unit, media type,
    ; and command family already selected by ROM BIOS.  Cache that state so
    ; the first SELDSK of the boot drive does not re-detect the medium.
    mov byte [cs:fdd_2dd_base], 0x70
    mov byte [cs:fdd_2hd_base], 0xF0
    mov byte [cs:fdd_if_known], 0

    mov al, [BOOT_DAUA]
    mov ah, al
    and ah, 0xF0
    cmp ah, 0x10
    je .boot_if_1mb_2dd
    cmp ah, 0x90
    je .boot_if_1mb_2hd
    cmp ah, 0x70
    je .boot_if_640k_2dd
    cmp ah, 0xF0
    je .boot_if_640k_2hd
    jmp .fdd_boot_seed_done       ; SCSI HDD or unknown FDD family

.boot_if_1mb_2dd:
    mov byte [cs:fdd_2dd_base], 0x10
    mov byte [cs:fdd_2hd_base], 0x90
    mov dl, 1
    jmp .seed_boot_fdd

.boot_if_1mb_2hd:
    mov byte [cs:fdd_2dd_base], 0x10
    mov byte [cs:fdd_2hd_base], 0x90
    mov dl, 2
    jmp .seed_boot_fdd

.boot_if_640k_2dd:
    mov dl, 1
    jmp .seed_boot_fdd

.boot_if_640k_2hd:
    mov dl, 2

.seed_boot_fdd:
    mov byte [cs:fdd_if_known], 1
    mov bl, al
    and bl, 3
    xor bh, bh
    mov [cs:fdd_media_map + bx], dl
    mov [cs:fdd_daua_map + bx], al
    mov byte [cs:fdd_boot_seed_map + bx], 1
    mov [cs:disk_daua], al

.fdd_boot_seed_done:

    pop ds

    sti

    call serial_init

    ; This BIOS intentionally supports PC-9801 normal mode only.
    call check_normal_mode
    jc .hires_unsupported

    ; Build the initial HDD drive map through the same path used by a
    ; requested WBOOT remount.  This keeps cold-start and runtime rebuilds
    ; identical without making every WBOOT rescan the SCSI bus.
    call hdd_rebuild
    jc init_bad_memory_switch

    ; Initialize the local PC-98 console.  Keyboard handling and CRT/GDC
    ; setup are delegated to ROM BIOS; character cells are written directly
    ; to text VRAM by screen_putc.
    call keyboard_init
    call screen_init
    call cache_clear

    mov word [cur_track], 0
    mov word [cur_sector], 0
    mov word [dma_off], 0x0080
    mov ax, cs
    mov [dma_seg], ax

    mov si, init_msg
    call console_puts
    call print_memory_info

    ; Enter CCP cold start at offset 0000h.  DS/ES/SS/CS all still refer
    ; to the common CP/M system segment.
    xor cx, cx
    mov cl, [cur_disk]
    mov [0x24b7], cl    ; BDOS CURDRV
    jmp 0x0000

.hires_unsupported:
    mov si, hires_msg
    call serial_puts
    jmp fatal_halt

init_bad_memory_switch:
    mov si, memsw_msg
    call serial_puts
    jmp fatal_halt

WBOOT:
    call CACHE_SYNC

    cmp byte [cs:hdd_remount_pending], 0
    je .normal

    ; The transient program may have installed its own stack in the old TPA.
    ; A remount can raise the HDD heap/TPA boundary, so switch back to the
    ; BIOS-private stack and system data segment before rebuilding E:..H:.
    cli
    mov ax, cs
    mov ss, ax
    mov sp, stack_top
    mov ds, ax
    mov es, ax
    cld
    sti

    ; The old drive-to-window mapping is no longer valid after FDISK/HDFORMAT
    ; changes disk metadata.  CACHE_SYNC above has committed all dirty data, so
    ; invalidate the tags before rebuilding E:..H:.
    call cache_clear
    call hdd_rebuild
    jc .bad_memory_switch

    mov byte [cs:esc_state], 0
    mov byte [cs:current_attr], DEFAULT_ATTR
    xor cx, cx
    mov cl, [cur_disk]
    mov [0x24b7], cl              ; BDOS CURDRV
    jmp 0x0000                    ; rebuild BDOS/CCP disk state

.normal:
    mov byte [cs:esc_state], 0
    mov byte [cs:current_attr], DEFAULT_ATTR
    xor cx, cx
    mov cl, [cur_disk]
    jmp 0x0006

.bad_memory_switch:
    mov si, memsw_msg
    call serial_puts
    jmp fatal_halt

; Rebuild the HDD drive map and the MRT/TPA boundary.  INIT and an explicitly
; requested WBOOT remount share this path.
hdd_rebuild:
    call hdd_init
    call resolve_boot_drive
    call init_mrt
    jc .done
    mov byte [cs:hdd_remount_pending], 0
.done:
    ret

; Private ABI implementation.  The caller only requests a remount; the actual
; rebuild runs after the current transient program has terminated and WBOOT is
; executing outside the old TPA.
HDD_REMOUNT_REQUEST:
    mov byte [cs:hdd_remount_pending], 1
    ret


; ----------------------------------------------------------------------
; Machine / memory configuration.
; ----------------------------------------------------------------------
; BIOS common area 0000:0501h bit3:
;   0 = normal PC-9801 mode
;   1 = high-resolution mode
; Return CF=1 for unsupported high-resolution mode.
check_normal_mode:
    push ds
    xor ax, ax
    mov ds, ax
    test byte [SYS_FLAG], HIRES_BIT
    pop ds
    jnz .high
    clc
    ret
.high:
    stc
    ret

; Normal-mode nonvolatile memory switch SW3 is physical A3FEAh.
; Bits 2..0 specify the conventional RAM size in 128 KiB steps:
;   0 -> 128 KiB  top segment 2000h
;   1 -> 256 KiB  top segment 4000h
;   2 -> 384 KiB  top segment 6000h
;   3 -> 512 KiB  top segment 8000h
;   4 -> 640 KiB  top segment A000h
; Values 5..7 are invalid for this BIOS and cause a fatal stop.
;
init_mrt:
    push bx
    push dx
    push es

    mov ax, MEMSW_SEG
    mov es, ax
    mov al, [es:MEMSW3_OFS]
    and al, 0x07
    mov [cs:mem_size_code], al
    cmp al, 4
    ja .invalid

    ; Top of conventional RAM in paragraphs.
    xor ah, ah
    inc ax                       ; 1..5
    mov cl, 13                   ; * 2000h paragraphs (=128 KiB)
    shl ax, cl
    mov dx, ax                   ; DX = top segment

    ; Convert the system-segment-relative HDD heap end to an absolute segment.
    ; hdd_heap_next is paragraph-aligned after every allocated HDD object.
    mov bx, [cs:hdd_heap_next]
    add bx, 15
    mov cl, 4
    shr bx, cl
    mov ax, cs
    add bx, ax
    cmp bx, TPA_BASE_SEG
    jae .base_ready
    mov bx, TPA_BASE_SEG
.base_ready:
    cmp bx, dx
    jae .invalid

    mov [cs:mrt_base], bx
    mov ax, dx
    sub ax, bx
    mov [cs:mrt_length], ax

    pop es
    pop dx
    pop bx
    clc
    ret
.invalid:
    pop es
    pop dx
    pop bx
    stc
    ret


; Print detected conventional RAM and the actual TPA size in KiB.
; RAM KiB = (mem_size_code + 1) * 128
; TPA KiB = mrt_length paragraphs * 16 / 1024 = mrt_length / 64
print_memory_info:
    push ax
    push bx
    push dx
    push si

    mov si, ram_msg
    call console_puts

    xor ax, ax
    mov al, [mem_size_code]
    inc ax
    mov cl, 7                   ; * 128 KiB
    shl ax, cl
    call console_put_u16_dec

    mov si, tpa_msg
    call console_puts

    mov ax, [mrt_length]
    mov cl, 6                   ; paragraphs -> KiB
    shr ax, cl
    call console_put_u16_dec

    mov si, kib_crlf_msg
    call console_puts

    pop si
    pop dx
    pop bx
    pop ax
    ret

; AX = unsigned 16-bit value, print in decimal with no leading zeroes
; through the current CON device.
console_put_u16_dec:
    push ax
    push bx
    push cx
    push dx

    xor cx, cx
    mov bx, 10
.convert:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .convert

.emit:
    pop dx
    mov al, dl
    add al, '0'
    call console_putc
    loop .emit

    pop dx
    pop cx
    pop bx
    pop ax
    ret

fatal_halt:
    cli
.halt:
    hlt
    jmp .halt

; ----------------------------------------------------------------------
; Console I/O -- ROM BIOS keyboard + text VRAM screen.
;
; Keyboard:
;   INT 18h AH=00h  blocking key read, AL=character code
;   INT 18h AH=01h  key-buffer sense, BH=0/1 (does not consume key)
;   INT 18h AH=03h  keyboard-interface initialization
;
; Screen (normal PC-98 mode only):
;   INT 18h AH=0Ah  CRT mode setup (AL=00h -> 80 columns, 25 lines)
;   INT 18h AH=16h  clear text VRAM (DX=E120h: space/default attr)
;   INT 18h AH=0Ch  enable text display
;   INT 18h AH=11h  show cursor
;   INT 18h AH=13h  set cursor, DX=byte offset from text VRAM base
;
; Character cells are written directly to A000:0000.  The attribute
; plane is A200:0000.  Both use 2 bytes per cell.
; ----------------------------------------------------------------------
TEXT_SEG        equ 0xA000
ATTR_SEG        equ 0xA200
SCREEN_COLS     equ 80
SCREEN_ROWS     equ 25
ROW_BYTES       equ 160
DEFAULT_ATTR    equ 0xE1

keyboard_init:
    mov ah, 0x03
    int 0x18
    ret

screen_init:
    push ax
    push dx

    ; Configure the PC-98 CRT for 80 columns and 25 text rows.
    mov ax, 0x0A00              ; 80 columns, 25 lines
    int 0x18

    mov ah, 0x0D                ; stop text display while reconfiguring
    int 0x18

    mov dx, 0xE120              ; E1h attribute + ASCII space
    mov ah, 0x16                ; clear text/attribute VRAM
    int 0x18

    xor dx, dx                  ; display starts at A000:0000
    mov ah, 0x0E
    int 0x18

    mov ah, 0x0C                ; enable text display
    int 0x18

    mov byte [cs:screen_col], 0
    mov byte [cs:screen_row], 0
    mov byte [cs:esc_state], 0
    mov byte [cs:current_attr], DEFAULT_ATTR
    mov byte [cs:csi_arg1], 0
    mov byte [cs:csi_arg2], 0
    mov byte [cs:saved_screen_col], 0
    mov byte [cs:saved_screen_row], 0
    call screen_update_cursor

    mov ah, 0x11                ; show cursor
    int 0x18

    pop dx
    pop ax
    ret

; ----------------------------------------------------------------------
; CP/M IOBYTE logical-device routing.
;
;   bits 1..0  CON:  00 TTY, 01 CRT, 10 BAT, 11 UC1
;   bits 3..2  RDR:  00 TTY, 01 PTR, 10 UR1, 11 UR2
;   bits 5..4  PUN:  00 TTY, 01 PTP, 10 UP1, 11 UP2
;   bits 7..6  LST:  00 TTY, 01 CRT, 10 LPT, 11 UL1
;
; Physical devices currently available in this BIOS:
;   local keyboard/screen and PC-98 standard RS-232C.
;
; RDR PTR/UR1/UR2 and PUN PTP/UP1/UP2 are aliases of RS-232C until
; additional physical devices are implemented.  LST LPT/UL1 likewise
; alias RS-232C; only LST:=CRT: selects the local screen.
;
; BAT follows the CP/M convention: console input comes from the current
; RDR device and console output goes to the current LST device.
; UC1 accepts input from either the local keyboard or RS-232C, with the
; local keyboard taking priority if both are ready, and mirrors output to
; both the local screen and RS-232C.
; ----------------------------------------------------------------------
CONST:
    mov al, [iobyte]
    and al, 0x03
    cmp al, 0x00
    je .tty
    cmp al, 0x01
    je .crt
    cmp al, 0x02
    je .bat

    ; UC1: ready when either local keyboard or RS-232C has input.
    call uc1_const
    ret

.tty:
    call serial_const
    ret

.crt:
    call local_const
    ret

.bat:
    call reader_const
    ret

CONIN:
    mov al, [iobyte]
    and al, 0x03
    cmp al, 0x00
    je .tty
    cmp al, 0x01
    je .crt
    cmp al, 0x02
    je .bat

    ; UC1: accept either local or serial input, local taking priority.
    call uc1_getc
    ret

.tty:
    call serial_getc
    ret

.crt:
    call local_getc
    ret

.bat:
    call reader_getc
    ret

CONOUT:
    mov al, cl
    call console_putc           ; dispatch according to CON field in IOBYTE
    ret

LISTOUT:
    mov al, cl
    call list_putc
    ret

PUNCH:
    mov al, cl
    call punch_putc
    ret

READER:
    call reader_getc
    ret

LISTST:
    ; LST:=CRT: is always ready.  TTY/LPT/UL1 currently map to RS-232C.
    mov al, [iobyte]
    and al, 0xc0
    cmp al, 0x40
    je .ready
    call serial_outst
    ret
.ready:
    mov al, 0xff
    ret

; Local keyboard status/read helpers used by CRT and UC1.
local_const:
    push bx
    mov ah, 0x01
    int 0x18
    test bh, bh
    jz .none
    mov al, 0xff                ; CP/M convention: input ready
    pop bx
    ret
.none:
    xor al, al
    pop bx
    ret

local_getc:
    mov ah, 0x00
    int 0x18                    ; AL=ANK character, AH=key code
    ret

; UC1 console input combines the local keyboard and RS-232C.
; Local input has priority when both devices are ready.
uc1_const:
    call local_const
    test al, al
    jnz .ready
    call serial_const
    ret
.ready:
    mov al, 0xff
    ret

uc1_getc:
.wait:
    call local_const
    test al, al
    jnz .local
    call serial_const
    test al, al
    jz .wait
    call serial_getc
    ret
.local:
    call local_getc
    ret

; RDR field decoder.  This version has one physical character-input
; device on the auxiliary side, so TTY/PTR/UR1/UR2 all use RS-232C.
reader_const:
    ; Keep the IOBYTE read here so this routine remains the single RDR
    ; dispatch point when PTR/UR devices are added later.
    mov al, [iobyte]
    and al, 0x0c
    call serial_const
    ret

reader_getc:
    mov al, [iobyte]
    and al, 0x0c
    call serial_getc
    ret

; PUN field decoder.  TTY/PTP/UP1/UP2 currently all use RS-232C.
punch_putc:
    push ax
    mov al, [iobyte]
    and al, 0x30
    pop ax
    call serial_putc
    ret

; LST field decoder.
;   00 TTY -> RS-232C
;   01 CRT -> local screen
;   10 LPT -> RS-232C alias until printer support is added
;   11 UL1 -> RS-232C alias
list_putc:
    push ax
    mov al, [iobyte]
    and al, 0xc0
    cmp al, 0x40
    pop ax
    je .crt
    call serial_putc
    ret
.crt:
    call screen_putc
    ret

; AL = character.  Dispatch according to the CON field in IOBYTE.
;   00 TTY -> RS-232C
;   01 CRT -> local screen
;   10 BAT -> current LIST device
;   11 UC1 -> local screen + RS-232C mirror
; This routine is used both by CP/M CONOUT and by normal BIOS startup
; messages, so the initial CON:=CRT setting does not touch RS-232C.
console_putc:
    push ax
    mov al, [iobyte]
    and al, 0x03
    cmp al, 0x00
    je .tty
    cmp al, 0x02
    je .bat
    cmp al, 0x03
    je .uc1

    ; CRT
    pop ax
    call screen_putc
    ret

.tty:
    pop ax
    call serial_putc
    ret

.bat:
    pop ax
    call list_putc
    ret

.uc1:
    pop ax
    push ax
    call screen_putc
    pop ax
    call serial_putc
    ret

; DS:SI -> zero-terminated string.  Output through the current CON device.
console_puts:
    cld
.next:
    lodsb
    test al, al
    jz .done
    call console_putc
    jmp .next
.done:
    ret

; AL = ANK/control character or one byte of the supported ANSI/VT100 subset.
; Normal controls: BEL, BS, TAB, LF, FF and CR.
; Supported ANSI/VT100 escape sequences:
;   ESC 7 / ESC 8              save / restore cursor
;   CSI n A/B/C/D              cursor up/down/right/left
;   CSI n E/F                  next/previous line, column 1
;   CSI n G                    absolute column
;   CSI n d                    absolute row
;   CSI row;col H / f          absolute cursor position
;   CSI 0/1/2 J                erase display
;   CSI 0/1/2 K                erase line
;   CSI s / u                  save / restore cursor
; Supported SGR color subset:
;   CSI 0 m                     reset attributes
;   CSI 30..37 m                ANSI foreground colors
;   CSI 39 m                    default foreground (white)
; Up to two SGR parameters are accepted.  Unsupported SGR
; parameters are silently ignored.  Decoration/background colors are not yet
; implemented.  Other unsupported/invalid escape sequences are consumed.
screen_putc:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    cmp byte [cs:esc_state], 0
    jne .ansi_feed

    cmp al, 0x1B
    jne .normal
    mov byte [cs:esc_state], 1
    jmp .done

.ansi_feed:
    call ansi_feed
    jmp .done

.normal:
    cmp al, 0x07
    je .bel
    cmp al, 0x0D
    je .cr
    cmp al, 0x0A
    je .lf
    cmp al, 0x0C
    je .ff
    cmp al, 0x08
    je .bs
    cmp al, 0x09
    je .tab
    cmp al, 0x20
    jb .done

    ; Store one ANK character with the current SGR-derived attribute.
    mov bl, al
    call screen_calc_offset      ; DI = byte address of current cell

    mov ax, TEXT_SEG
    mov es, ax
    xor ax, ax
    mov al, bl
    stosw                        ; A000:DI, then DI += 2

    sub di, 2                    ; same cell in the attribute plane
    mov ax, ATTR_SEG
    mov es, ax
    xor ax, ax
    mov al, [cs:current_attr]
    stosw                        ; A200:DI

    inc byte [cs:screen_col]
    cmp byte [cs:screen_col], SCREEN_COLS
    jb .cursor
    mov byte [cs:screen_col], 0
    inc byte [cs:screen_row]
    jmp .check_scroll

.bel:
    mov ah, 0x17
    int 0x18
    xor cx, cx
.bel_delay1:
    loop .bel_delay1
    xor cx, cx
.bel_delay2:
    loop .bel_delay2
    mov ah, 0x18
    int 0x18
    jmp .done

.ff:
    mov dx, 0xE120              ; E1h attribute + ASCII space
    mov ah, 0x16
    int 0x18
    mov byte [cs:screen_col], 0
    mov byte [cs:screen_row], 0
    jmp .cursor

.cr:
    mov byte [cs:screen_col], 0
    jmp .cursor

.lf:
    inc byte [cs:screen_row]
.check_scroll:
    cmp byte [cs:screen_row], SCREEN_ROWS
    jb .cursor
    call screen_scroll
    mov byte [cs:screen_row], SCREEN_ROWS - 1
    jmp .cursor

.bs:
    cmp byte [cs:screen_col], 0
    je .cursor
    dec byte [cs:screen_col]
    jmp .cursor

.tab:
.tab_loop:
    mov al, ' '
    call screen_putc
    mov al, [cs:screen_col]
    test al, 7
    jnz .tab_loop
    jmp .done

.cursor:
    call screen_update_cursor
.done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Feed AL to the ANSI parser.  esc_state values:
;   1 = after ESC
;   2 = CSI first argument
;   3 = CSI second argument
; Cursor/erase commands need at most two numeric arguments.  SGR also
; accepts one or two parameters for SGR.
ansi_feed:
    mov bl, al
    mov al, [cs:esc_state]
    cmp al, 1
    jne .csi

    cmp bl, '7'
    je ansi_save
    cmp bl, '8'
    je ansi_restore
    cmp bl, '['
    jne ansi_abort
    mov byte [cs:esc_state], 2
    mov byte [cs:csi_arg1], 0
    mov byte [cs:csi_arg2], 0
    ret

.csi:
    mov al, bl
    sub al, '0'
    cmp al, 10
    jb ansi_digit

    cmp bl, ';'
    je ansi_semicolon
    cmp bl, 'm'
    jne .not_sgr
    jmp ansi_sgr
.not_sgr:
    cmp bl, 'A'
    je ansi_up
    cmp bl, 'B'
    je ansi_down
    cmp bl, 'C'
    je ansi_right
    cmp bl, 'D'
    je ansi_left
    cmp bl, 'E'
    je ansi_nextline
    cmp bl, 'F'
    je ansi_prevline
    cmp bl, 'G'
    je ansi_col
    cmp bl, 'J'
    je ansi_erase_display
    cmp bl, 'K'
    je ansi_erase_line
    cmp bl, 'H'
    je ansi_position
    cmp bl, 'f'
    je ansi_position
    cmp bl, 'd'
    je ansi_row
    cmp bl, 's'
    je ansi_save
    cmp bl, 'u'
    je ansi_restore
    jmp ansi_abort

ansi_digit:
    ; BL still contains the original character.  Convert it to 0..9 in DL.
    mov dl, bl
    sub dl, '0'
    mov al, [cs:esc_state]
    cmp al, 2
    je .arg1
    cmp al, 3
    jne ansi_abort
    mov si, csi_arg2
    jmp .accumulate
.arg1:
    mov si, csi_arg1
.accumulate:
    mov al, [cs:si]
    cmp al, 25                  ; saturate rather than overflow above 255
    ja .saturate
    jne .calc
    cmp dl, 5
    ja .saturate
.calc:
    xor ah, ah
    mov cl, al
    shl al, 1                   ; old * 2
    mov ah, al
    shl al, 1                   ; old * 4
    shl al, 1                   ; old * 8
    add al, ah                  ; old * 10
    add al, dl
    mov [cs:si], al
    ret
.saturate:
    mov byte [cs:si], 0xFF
    ret

ansi_semicolon:
    cmp byte [cs:esc_state], 2
    jne ansi_abort
    mov byte [cs:esc_state], 3
    ret

; AL <- first argument, with ANSI default 1 for zero/omitted.
ansi_count:
    mov al, [cs:csi_arg1]
    test al, al
    jnz .done
    mov al, 1
.done:
    ret

ansi_up:
    call ansi_count
    mov bl, al
    mov al, [cs:screen_row]
    sub al, bl
    jnc .store
    xor al, al
.store:
    mov [cs:screen_row], al
    jmp ansi_move_finish

ansi_down:
    call ansi_count
    mov bl, al
    mov al, [cs:screen_row]
    add al, bl
    jc .max
    cmp al, SCREEN_ROWS
    jb .store
.max:
    mov al, SCREEN_ROWS - 1
.store:
    mov [cs:screen_row], al
    jmp ansi_move_finish

ansi_right:
    call ansi_count
    mov bl, al
    mov al, [cs:screen_col]
    add al, bl
    jc .max
    cmp al, SCREEN_COLS
    jb .store
.max:
    mov al, SCREEN_COLS - 1
.store:
    mov [cs:screen_col], al
    jmp ansi_move_finish

ansi_left:
    call ansi_count
    mov bl, al
    mov al, [cs:screen_col]
    sub al, bl
    jnc .store
    xor al, al
.store:
    mov [cs:screen_col], al
    jmp ansi_move_finish

ansi_nextline:
    call ansi_count
    mov bl, al
    mov al, [cs:screen_row]
    add al, bl
    jc .max
    cmp al, SCREEN_ROWS
    jb .row_ok
.max:
    mov al, SCREEN_ROWS - 1
.row_ok:
    mov [cs:screen_row], al
    mov byte [cs:screen_col], 0
    jmp ansi_move_finish

ansi_prevline:
    call ansi_count
    mov bl, al
    mov al, [cs:screen_row]
    sub al, bl
    jnc .row_ok
    xor al, al
.row_ok:
    mov [cs:screen_row], al
    mov byte [cs:screen_col], 0
    jmp ansi_move_finish

ansi_col:
    mov al, [cs:csi_arg1]
    test al, al
    jnz .nonzero
    mov al, 1
.nonzero:
    cmp al, SCREEN_COLS + 1
    jb .range_ok
    mov al, SCREEN_COLS
.range_ok:
    dec al
    mov [cs:screen_col], al
    jmp ansi_move_finish

ansi_row:
    mov al, [cs:csi_arg1]
    test al, al
    jnz .nonzero
    mov al, 1
.nonzero:
    cmp al, SCREEN_ROWS + 1
    jb .range_ok
    mov al, SCREEN_ROWS
.range_ok:
    dec al
    mov [cs:screen_row], al
    jmp ansi_move_finish

ansi_position:
    mov al, [cs:csi_arg1]
    test al, al
    jnz .row_nonzero
    mov al, 1
.row_nonzero:
    cmp al, SCREEN_ROWS + 1
    jb .row_ok
    mov al, SCREEN_ROWS
.row_ok:
    dec al
    mov [cs:screen_row], al

    mov al, [cs:csi_arg2]
    test al, al
    jnz .col_nonzero
    mov al, 1
.col_nonzero:
    cmp al, SCREEN_COLS + 1
    jb .col_ok
    mov al, SCREEN_COLS
.col_ok:
    dec al
    mov [cs:screen_col], al
    jmp ansi_move_finish

ansi_save:
    mov al, [cs:screen_col]
    mov [cs:saved_screen_col], al
    mov al, [cs:screen_row]
    mov [cs:saved_screen_row], al
    jmp ansi_finish

ansi_restore:
    mov al, [cs:saved_screen_col]
    cmp al, SCREEN_COLS
    jb .col_ok
    mov al, SCREEN_COLS - 1
.col_ok:
    mov [cs:screen_col], al
    mov al, [cs:saved_screen_row]
    cmp al, SCREEN_ROWS
    jb .row_ok
    mov al, SCREEN_ROWS - 1
.row_ok:
    mov [cs:screen_row], al
    jmp ansi_move_finish

ansi_erase_display:
    mov al, [cs:csi_arg1]
    cmp al, 0
    je .mode0
    cmp al, 1
    je .mode1
    cmp al, 2
    je .mode2
    jmp ansi_abort

.mode0:
    ; Current cell through bottom-right.
    call screen_calc_offset
    mov bx, di
    mov ax, SCREEN_ROWS * SCREEN_COLS
    mov dx, di
    shr dx, 1
    sub ax, dx
    mov cx, ax
    mov di, bx
    call screen_blank_cells
    jmp ansi_move_finish

.mode1:
    ; Top-left through current cell.
    call screen_calc_offset
    shr di, 1
    inc di
    mov cx, di
    xor di, di
    call screen_blank_cells
    jmp ansi_move_finish

.mode2:
    xor di, di
    mov cx, SCREEN_ROWS * SCREEN_COLS
    call screen_blank_cells
    jmp ansi_move_finish

ansi_erase_line:
    mov al, [cs:csi_arg1]
    cmp al, 0
    je .mode0
    cmp al, 1
    je .mode1
    cmp al, 2
    je .mode2
    jmp ansi_abort

.mode0:
    call screen_calc_offset
    mov bx, di
    xor ax, ax
    mov al, [cs:screen_col]
    mov cx, SCREEN_COLS
    sub cx, ax
    mov di, bx
    call screen_blank_cells
    jmp ansi_move_finish

.mode1:
    call screen_calc_offset
    xor ax, ax
    mov al, [cs:screen_col]
    inc ax
    mov cx, ax
    xor ax, ax
    mov al, [cs:screen_row]
    mov bx, ROW_BYTES
    mul bx
    mov di, ax
    call screen_blank_cells
    jmp ansi_move_finish

.mode2:
    xor ax, ax
    mov al, [cs:screen_row]
    mov bx, ROW_BYTES
    mul bx
    mov di, ax
    mov cx, SCREEN_COLS
    call screen_blank_cells
    jmp ansi_move_finish

ansi_sgr:
    ; Apply parameter 1.  Omitted parameter is zero, i.e. SGR reset.
    mov al, [cs:csi_arg1]
    call ansi_sgr_apply

    ; esc_state==3 means a semicolon introduced parameter 2.  An omitted
    ; second parameter is also zero, matching ANSI's empty-parameter rule.
    cmp byte [cs:esc_state], 3
    jne ansi_finish
    mov al, [cs:csi_arg2]
    call ansi_sgr_apply
    jmp ansi_finish

; Apply one SGR parameter in AL.
; Supported:
;   0        reset all attributes
;   4 / 24   underline on/off
;   5 / 25   blink on/off
;   7 / 27   reverse on/off
;   30..37   ANSI foreground colors
;   39       default foreground color
; Other SGR parameters (for example bold/intensity) are silently ignored.
;
; PC-98 text attribute low bits used here:
;   bit 3 = underline, bit 2 = reverse, bit 1 = blink, bit 0 = display enable.
; DEFAULT_ATTR keeps bit 0 set, and decoration changes preserve it.
ansi_sgr_apply:
    test al, al
    jz .reset

    cmp al, 4
    je .underline_on
    cmp al, 5
    je .blink_on
    cmp al, 7
    je .reverse_on

    cmp al, 24
    je .underline_off
    cmp al, 25
    je .blink_off
    cmp al, 27
    je .reverse_off

    cmp al, 30
    jb .done
    cmp al, 37
    jbe .color
    cmp al, 39
    je .default_color
    jmp .done

.reset:
    mov byte [cs:current_attr], DEFAULT_ATTR
    ret

.underline_on:
    or byte [cs:current_attr], 0x08
    ret
.underline_off:
    and byte [cs:current_attr], 0xF7
    ret

.blink_on:
    or byte [cs:current_attr], 0x02
    ret
.blink_off:
    and byte [cs:current_attr], 0xFD
    ret

.reverse_on:
    or byte [cs:current_attr], 0x04
    ret
.reverse_off:
    and byte [cs:current_attr], 0xFB
    ret

.default_color:
    mov al, [cs:current_attr]
    and al, 0x1F                  ; preserve decoration/control bits
    or al, (DEFAULT_ATTR & 0xE0)  ; default foreground = white
    mov [cs:current_attr], al
    ret

.color:
    sub al, 30
    xor bh, bh
    mov bl, al
    mov al, [cs:ansi_color_bits + bx]
    mov ah, [cs:current_attr]
    and ah, 0x1F                  ; preserve decoration/control bits
    or al, ah
    mov [cs:current_attr], al
.done:
    ret

ansi_move_finish:
    call screen_update_cursor
ansi_finish:
    mov byte [cs:esc_state], 0
    ret

ansi_abort:
    mov byte [cs:esc_state], 0
    ret

; Blank CX cells beginning at byte offset DI in both text and attribute VRAM.
; The cursor position is not changed.
screen_blank_cells:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    mov bx, di
    mov dx, cx
    mov ax, TEXT_SEG
    mov es, ax
    mov ax, 0x0020
    cld
    rep stosw

    mov di, bx
    mov cx, dx
    mov ax, ATTR_SEG
    mov es, ax
    mov ax, DEFAULT_ATTR
    rep stosw

    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Return DI = row*160 + col*2.
screen_calc_offset:
    ; Preserve BX.  screen_putc keeps the character in BL while calling
    ; this routine; clobbering BX here would replace it with A0h
    ; (ROW_BYTES = 160).
    push bx
    xor ax, ax
    mov al, [cs:screen_row]
    mov bx, ROW_BYTES
    mul bx
    mov di, ax
    xor ax, ax
    mov al, [cs:screen_col]
    shl ax, 1
    add di, ax
    pop bx
    ret

screen_update_cursor:
    push ax
    push bx
    push dx
    push di
    call screen_calc_offset
    mov dx, di
    mov ah, 0x13
    int 0x18
    pop di
    pop dx
    pop bx
    pop ax
    ret

; Scroll one text row upward, including attributes, and clear the bottom.
screen_scroll:
    push ax
    push cx
    push si
    push di
    push ds
    push es

    cld

    ; Character plane: rows 1..24 -> rows 0..23.
    mov ax, TEXT_SEG
    mov ds, ax
    mov es, ax
    mov si, ROW_BYTES
    xor di, di
    mov cx, (SCREEN_ROWS - 1) * SCREEN_COLS
    rep movsw

    mov ax, 0x0020              ; blank final row with spaces
    mov cx, SCREEN_COLS
    rep stosw

    ; Attribute plane: move rows and restore default attribute on last row.
    mov ax, ATTR_SEG
    mov ds, ax
    mov es, ax
    mov si, ROW_BYTES
    xor di, di
    mov cx, (SCREEN_ROWS - 1) * SCREEN_COLS
    rep movsw

    mov ax, DEFAULT_ATTR
    mov cx, SCREEN_COLS
    rep stosw

    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    ret

; BDA 0000:0501 bit7 selects the system-clock family.
; x16 clock for 9600 bps: divisor 13 at 1.9968MHz, 16 at 2.4576MHz.
serial_init:
    push ds
    xor ax, ax
    mov ds, ax

    mov al, 0xb6                  ; PIT ch2, mode 3, lobyte/hibyte
    out PIT_CTRL, al
    mov ax, 16
    test byte [SYS_FLAG], 0x80
    jz .pit_set
    mov ax, 13
.pit_set:
    out PIT_CH2, al
    mov al, ah
    out PIT_CH2, al

    pop ds

    xor al, al
    out SER_CTRL, al
    out SER_CTRL, al
    out SER_CTRL, al
    mov al, 0x40                  ; internal reset
    out SER_CTRL, al
    mov al, 0x4e                  ; async x16, 8N1
    out SER_CTRL, al
    mov al, 0x37                  ; Tx/Rx enable, DTR/RTS, reset errors
    out SER_CTRL, al
    ret

serial_const:
    in al, SER_CTRL
    test al, 0x02                 ; RxRDY
    jz .none
    mov al, 0xff
    ret
.none:
    xor al, al
    ret

serial_outst:
    in al, SER_CTRL
    test al, 0x01                 ; TxRDY
    jz .none
    mov al, 0xff
    ret
.none:
    xor al, al
    ret

serial_getc:
.wait:
    in al, SER_CTRL
    test al, 0x02                 ; RxRDY
    jz .wait
    in al, SER_DATA
    ret

serial_putc:
    push ax
.wait:
    in al, SER_CTRL
    test al, 0x01                 ; TxRDY
    jz .wait
    pop ax
    out SER_DATA, al
    ret

serial_puts:
    cld
.next:
    lodsb
    test al, al
    jz .done
    call serial_putc
    jmp .next
.done:
    ret

; ----------------------------------------------------------------------
; CP/M disk setup calls
; ----------------------------------------------------------------------
HOME:
    mov word [cur_track], 0
    ret

SELDSK:
    ; Each A:..H: drive owns an independent cache window.  Normal drive changes
    ; therefore do not force write-back.  A newly logged-in drive is flushed
    ; and invalidated before media/partition selection, preserving the private
    ; cache-coherency contract while leaving all other drive windows resident.
    xor bx, bx
    cmp cl, 16                    ; CP/M supports A:..P:
    jb .range_ok
    ret
.range_ok:
    cmp cl, CACHE_SLOTS
    jae .cache_login_done
    test dl, 1
    jnz .cache_login_done
    call cache_reset_drive
    jc .cache_error
.cache_login_done:
    jmp .cache_done
.cache_error:
    xor bx, bx
    ret
.cache_done:

    cmp cl, 4
    jae .hdd

    ; A:..D: floppy.  The command family is selected at INIT.  A newly
    ; logged-in disk is re-detected, except for the first selection of the
    ; FDD boot drive whose media type and DA/UA were cached at cold start.
    mov byte [rec_mask], 3

    xor ch, ch
    mov si, cx                    ; SI = physical FDD unit 0..3
    mov bx, si
    shl bx, 1
    mov bx, [dph_table + bx]

    cmp byte [fdd_boot_seed_map + si], 0
    je .fdd_not_seeded
    mov byte [fdd_boot_seed_map + si], 0
    jmp .fdd_apply

.fdd_not_seeded:
    test dl, 1                    ; DL bit 0 = 0: newly logged-in disk
    jz .fdd_detect
    cmp byte [fdd_media_map + si], 0
    jne .fdd_apply

.fdd_detect:
    push bx
    call fdd_detect_media
    pop bx
    jc .fdd_absent
    mov [fdd_media_map + si], al

.fdd_apply:
    mov al, [fdd_daua_map + si]
    test al, al
    jz .fdd_absent
    mov [disk_daua], al

    cmp byte [fdd_media_map + si], 2
    je .fdd_2hd
    cmp byte [fdd_media_map + si], 1
    jne .fdd_absent
    mov word [bx + 0x0A], dpb_2dd
    jmp short .fdd_selected

.fdd_2hd:
    mov word [bx + 0x0A], dpb_2hd
.fdd_selected:
    mov byte [disk_kind], 0
    mov [cur_disk], cl
    ret

.fdd_absent:
    mov byte [fdd_media_map + si], 0
    mov byte [fdd_daua_map + si], 0
    xor bx, bx
    ret

.hdd:
    ; E:..H: map to detected HDD partitions in discovery order.
    mov al, cl
    sub al, HDD_FIRST_DRIVE
    cmp al, [hdd_count]
    jb .hdd_present
    xor bx, bx
    ret

.hdd_present:
    mov byte [disk_kind], 1
    xor ah, ah
    mov si, ax

    mov al, [hdd_daua_map + si]
    mov [hdd_daua_cur], al
    mov al, [hdd_heads_map + si]
    mov [hdd_heads_cur], al
    mov al, [hdd_spt_map + si]
    mov [hdd_spt_cur], al

    mov di, si
    shl di, 1
    mov ax, [hdd_start_cyl_map + di]
    mov [hdd_start_cyl_cur], ax
    mov ax, [hdd_dph_ptrs + di]
    mov bx, ax

    ; A 512-byte HDD sector contains four 128-byte CP/M records.
    mov byte [rec_mask], 3
    mov [cur_disk], cl
    ret

SETTRK:
    mov [cur_track], cx
    ret

SETSEC:
    mov [cur_sector], cx          ; 128-byte CP/M record within current track
    ret

SETDMA:
    mov [dma_off], cx
    ret

SETDMAB:
    mov [dma_seg], cx
    ret

SECTRAN:
    mov bx, cx                    ; no skew table
    ret

GETSEGT:
    mov bx, mrt
    ret

GETIOBF:
    mov al, [iobyte]
    ret

SETIOBF:
    mov [iobyte], cl
    ret

; ----------------------------------------------------------------------
; CP/M 128-byte logical sector READ/WRITE directly against the GVRAM window.
; ----------------------------------------------------------------------
READ:
    xor al, al                    ; 0=READ
    jmp short rw_common
WRITE:
    mov al, 1                    ; 1=WRITE
rw_common:
    push ds
    push es
    mov [cs:rw_write], al
    call window_prepare_current
    jc .error

    ; AX = segment of the selected 512-byte cached sector.
    xor ax, ax
    mov al, [cs:win_index]
    mov cl, 5
    shl ax, cl
    add ax, [cs:win_seg]

    ; BX = byte offset of the selected 128-byte quarter.
    xor bx, bx
    mov bl, [cs:cur_sector]
    and bl, [cs:rec_mask]
    mov cl, 7
    shl bx, cl

    cmp byte [cs:rw_write], 0
    jne .write

    mov ds, ax
    mov si, bx
    mov ax, [cs:dma_seg]
    mov es, ax
    mov di, [cs:dma_off]
    mov cx, 64
    cld
    rep movsw
    pop es
    pop ds
    xor al, al
    ret

.write:
    mov es, ax
    mov di, bx
    mov ax, [cs:dma_seg]
    mov ds, ax
    mov si, [cs:dma_off]
    mov cx, 64
    cld
    rep movsw
    call window_mark_dirty
    pop es
    pop ds
    xor al, al
    ret
.error:
    pop es
    pop ds
    mov al, 1
    ret

; ----------------------------------------------------------------------
; Fixed-window GVRAM cache.
; One independent slot is retained for each A:..H:.  FDD slots hold one full
; side-track (8/15 sectors); HDD slots hold up to 17 sectors within one head.
; ----------------------------------------------------------------------
window_prepare_current:

    xor bx, bx
    mov bl, [cs:cur_disk]
    cmp bl, CACHE_SLOTS
    jae .error
    mov [cs:win_slot], bl
    shl bx, 1
    mov ax, [cs:cache_slot_segs + bx]
    mov [cs:win_seg], ax

    cmp byte [cs:disk_kind], 0
    jne .hdd

    call make_chs
    mov [cs:win_cx], cx
    mov [cs:win_head], dh
    mov byte [cs:win_first], 1
    mov al, dl
    dec al
    mov [cs:win_index], al
    xor bx, bx
    mov bl, [cs:cur_disk]
    mov al, [cs:fdd_media_map + bx]
    mov byte [cs:win_count], 8
    cmp al, 1
    je .key_ready
    cmp al, 2
    jne .error
    mov byte [cs:win_count], 15
    jmp .key_ready

.hdd:
    call make_hdd_chs
    mov [cs:win_cx], cx
    mov [cs:win_head], dh
    xor ax, ax
    mov al, dl
    xor dx, dx
    mov bx, CACHE_HDD_WINDOW
    div bx                        ; DX=index, AX=window number
    mov [cs:win_index], dl
    mov bx, CACHE_HDD_WINDOW
    mul bx
    mov [cs:win_first], al
    mov dl, [cs:hdd_spt_cur]
    sub dl, al
    cmp dl, CACHE_HDD_WINDOW
    jbe .hdd_count_ok
    mov dl, CACHE_HDD_WINDOW
.hdd_count_ok:
    test dl, dl
    jz .error
    mov [cs:win_count], dl

.key_ready:
    ; DI = metadata slot offset.
    mov ax, CACHE_META_SEG
    mov es, ax
    xor ax, ax
    mov al, [cs:win_slot]
    mov cl, 4
    shl ax, cl
    mov di, ax

    cmp byte [es:di + CM_VALID], CACHE_VALID
    jne .miss
    mov al, [cs:win_head]
    cmp [es:di + CM_HEAD], al
    jne .miss
    mov ax, [cs:win_cx]
    cmp [es:di + CM_CX], ax
    jne .miss
    mov al, [cs:win_first]
    cmp [es:di + CM_FIRST], al
    jne .miss
    clc
    jmp .done

.miss:
    mov bl, [cs:win_slot]
    call cache_flush_slot
    jc .error

    ; Publish the new key as invalid so the common I/O helper can use it.
    mov ax, CACHE_META_SEG
    mov es, ax
    xor ax, ax
    mov al, [cs:win_slot]
    mov cl, 4
    shl ax, cl
    mov di, ax
    mov byte [es:di + CM_VALID], 0
    mov al, [cs:win_head]
    mov [es:di + CM_HEAD], al
    mov ax, [cs:win_cx]
    mov [es:di + CM_CX], ax
    mov al, [cs:win_first]
    mov [es:di + CM_FIRST], al
    mov word [es:di + CM_DIRTY], 0
    mov byte [es:di + CM_DIRTY_HI], 0

    xor si, si                    ; start index
    xor di, di
    mov dl, [cs:win_count]
    xor dh, dh
    mov di, dx                    ; count
    xor al, al                    ; READ
    mov bl, [cs:win_slot]
    call cache_io_run
    jc .error

    mov ax, CACHE_META_SEG
    mov es, ax
    xor bx, bx
    mov bl, [cs:win_slot]
    mov cl, 4
    shl bx, cl
    mov byte [es:bx + CM_VALID], CACHE_VALID
    clc
    jmp .done

.error:
    stc
.done:
    ret

; Mark the current 512-byte sector dirty in its drive slot.
window_mark_dirty:
    mov ax, CACHE_META_SEG
    mov es, ax
    xor bx, bx
    mov bl, [cs:win_slot]
    mov cl, 4
    shl bx, cl
    xor ax, ax
    mov al, [cs:win_index]
    cmp al, 16
    jae .hi
    mov cl, al
    mov ax, 1
    shl ax, cl
    or [es:bx + CM_DIRTY], ax
    jmp .done
.hi:
    or byte [es:bx + CM_DIRTY_HI], 1
.done:
    ret

; Test dirty bit SI in metadata ES:DI.  CF=1 dirty.
cache_dirty_test:
    cmp si, 16
    jae .hi
    mov ax, 1
    mov cx, si
    shl ax, cl
    test [es:di + CM_DIRTY], ax
    jz .clean
    stc
    jmp .done
.hi:
    test byte [es:di + CM_DIRTY_HI], 1
    jz .clean
    stc
    jmp .done
.clean:
    clc
.done:
    ret

; Clear dirty bits [flush_start, flush_start+flush_count) after successful I/O.
cache_clear_run:
    xor ax, ax
    mov al, [cs:flush_start]
    mov si, ax
    xor ax, ax
    mov al, [cs:flush_count]
    add ax, si
.loop:
    cmp si, ax
    jae .done
    cmp si, 16
    jae .hi
    push ax
    mov ax, 1
    mov cx, si
    shl ax, cl
    not ax
    and [es:di + CM_DIRTY], ax
    pop ax
    jmp .next
.hi:
    and byte [es:di + CM_DIRTY_HI], 0xFE
.next:
    inc si
    jmp .loop
.done:
    ret

; Flush one drive slot BL.  Each maximal contiguous dirty run is one WRITE.
cache_flush_slot:
    push bx
    push es

    cmp bl, CACHE_SLOTS
    jae .clean
    mov [cs:flush_slot], bl
    mov ax, CACHE_META_SEG
    mov es, ax
    xor bh, bh
    mov di, bx
    mov cl, 4
    shl di, cl
    cmp byte [es:di + CM_VALID], CACHE_VALID
    jne .clean
    mov ax, [es:di + CM_DIRTY]
    or al, [es:di + CM_DIRTY_HI]
    test ax, ax
    jz .clean

    xor si, si
.scan:
    cmp si, CACHE_HDD_WINDOW
    jae .clean
    call cache_dirty_test
    jc .run_start
    inc si
    jmp .scan
.run_start:
    mov ax, si
    mov [cs:flush_start], al
.find_end:
    inc si
    cmp si, CACHE_HDD_WINDOW
    jae .run_ready
    call cache_dirty_test
    jc .find_end
.run_ready:
    mov ax, si
    sub al, [cs:flush_start]
    mov [cs:flush_count], al

    ; cache_io_run: BL=slot, SI=start, DI=count, AL=1 WRITE.
    xor si, si
    mov al, [cs:flush_start]
    xor ah, ah
    mov si, ax
    xor di, di
    mov al, [cs:flush_count]
    xor ah, ah
    mov di, ax
    mov al, 1
    mov bl, [cs:flush_slot]
    call cache_io_run
    jc .error

    ; Restore metadata pointer and clear only the successfully written run.
    mov ax, CACHE_META_SEG
    mov es, ax
    xor di, di
    mov al, [cs:flush_slot]
    xor ah, ah
    mov cl, 4
    shl ax, cl
    mov di, ax
    call cache_clear_run
    xor si, si
    jmp .scan

.clean:
    clc
    jmp .done
.error:
    stc
.done:
    pop es
    pop bx
    ret

; Common multi-sector ROM-BIOS I/O.
; BL=slot, SI=start index in window, DI=count, AL=0 READ / AL=1 WRITE.
; The window key (CX/head/first) is read from the slot metadata.
cache_io_run:

    mov [cs:io_write], al
    mov [cs:io_slot], bl
    mov ax, si
    mov [cs:io_start], al
    mov ax, di
    mov [cs:io_count], al

    ; Snapshot key and derive DA/UA before ES becomes the data buffer.
    mov ax, CACHE_META_SEG
    mov es, ax
    xor bh, bh
    mov di, bx
    mov cl, 4
    shl di, cl
    mov ax, [es:di + CM_CX]
    mov [cs:io_cx], ax
    mov al, [es:di + CM_HEAD]
    mov [cs:io_head], al
    mov al, [es:di + CM_FIRST]
    add al, [cs:io_start]
    mov [cs:io_sector], al

    cmp byte [cs:io_slot], 4
    jae .hdd_setup
    xor bx, bx
    mov bl, [cs:io_slot]
    mov al, [cs:fdd_daua_map + bx]
    mov [cs:io_daua], al
    mov byte [cs:io_retry], 10
    mov ah, 0x56
    sub ah, [cs:io_write]         ; READ=56h, WRITE=55h
    mov [cs:io_cmd], ah
    jmp .retry
.hdd_setup:
    xor bx, bx
    mov bl, [cs:io_slot]
    sub bl, 4
    mov al, [cs:hdd_daua_map + bx]
    mov [cs:io_daua], al
    mov byte [cs:io_retry], 3
    mov ah, 0x06
    sub ah, [cs:io_write]         ; READ=06h, WRITE=05h
    mov [cs:io_cmd], ah

.retry:
    xor bx, bx
    mov bl, [cs:io_slot]
    shl bx, 1
    mov ax, [cs:cache_slot_segs + bx]
    xor bx, bx
    mov bl, [cs:io_start]
    mov cl, 5
    shl bx, cl
    add ax, bx
    mov es, ax
    xor bp, bp
    xor bx, bx
    mov bl, [cs:io_count]
    mov cl, 9
    shl bx, cl
    mov al, [cs:io_daua]
    mov ah, [cs:io_cmd]
    mov cx, [cs:io_cx]
    mov dh, [cs:io_head]
    mov dl, [cs:io_sector]
    push ds
    int 0x1B
    pop ds
    jnc .ok

    cmp byte [cs:io_slot], 4
    jae .retry_dec
    mov al, [cs:io_daua]
    mov ah, 0x07
    push ds
    int 0x1B
    pop ds
.retry_dec:
    dec byte [cs:io_retry]
    jnz .retry
    stc
    jmp .done
.ok:
    clc
.done:
    ret

; Flush all eight independent drive windows.
CACHE_SYNC:
    push bx
    xor bx, bx
.loop:
    call cache_flush_slot
    jc .done
    inc bl
    cmp bl, CACHE_SLOTS
    jb .loop
.done:
    pop bx
    ret

CACHE_RESET:
    call CACHE_SYNC
    jc .done
    call cache_clear                 ; cache_clear leaves CF clear
.done:
    ret

; Flush/invalidate only CL on a newly logged-in SELDSK.
cache_reset_drive:
    push cx
    push es
    xor bx, bx
    mov bl, cl
    call cache_flush_slot
    jc .done
    mov ax, CACHE_META_SEG
    mov es, ax
    xor ax, ax
    mov al, bl
    mov cl, 4
    shl ax, cl
    mov di, ax
    and byte [es:di + CM_VALID], 0 ; invalidate and leave CF clear
    mov word [es:di + CM_DIRTY], 0
    mov byte [es:di + CM_DIRTY_HI], 0
.done:
    pop es
    pop cx
    ret

cache_clear:
    push ax
    push cx
    push di
    push es
    mov ax, CACHE_META_SEG
    mov es, ax
    xor ax, ax
    xor di, di
    mov cx, (CACHE_SLOTS * CACHE_META_SIZE) / 2
    cld
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    ret

; Convert CP/M HDD track/record to absolute PC-98 SCSI CHS.
; One CP/M track is one SCSI BIOS cylinder because DPB SPT is generated as
; heads * sectors/cylinder * 4 logical 128-byte records.
make_hdd_chs:
    ; Absolute cylinder.
    mov cx, [cs:cur_track]
    add cx, [cs:hdd_start_cyl_cur]

    ; Physical sector index inside the cylinder = logical record / 4.
    mov ax, [cs:cur_sector]
    shr ax, 1
    shr ax, 1

    ; head = index / sectors-per-cylinder, sector = remainder.
    xor bx, bx
    mov bl, [cs:hdd_spt_cur]
    xor dx, dx
    div bx                        ; AX=head, DX=sector
    mov bh, dl                    ; save sector
    mov dh, al                    ; head
    mov dl, bh                    ; sector
    ret

; Detect the inserted medium in physical FDD unit SI (0..3).
;
; FDD boot fixes the active ROM-BIOS command family at INIT from BOOT_DAUA.
; HDD boot leaves the family unknown because BOOT_DAUA identifies the SCSI
; device instead.  In that case the first FDD detection tries 70h/F0h first,
; then 10h/90h.  The family that verifies successfully becomes the global
; active family for subsequent FDD selections.
;
; For each density, RECALIBRATE is followed by VERIFY of C=0/H=0/S=1.
; The DA/UA that verifies successfully is cached and used unchanged by
; subsequent READ, WRITE, and retry RECALIBRATE operations for that drive.
;
; Return: AL=1 for 2DD, AL=2 for 2HD/2HC; CF set if neither mode verifies.
fdd_detect_media:
    push bx
    push cx
    push dx
    push si

    call fdd_detect_active_family
    jnc .found

    cmp byte [cs:fdd_if_known], 0
    jne .absent

    ; HDD boot starts with the compatibility 70h/F0h candidate.  If neither
    ; density verifies, try the alternate 10h/90h interface family once.
    cmp byte [cs:fdd_2dd_base], 0x70
    jne .try_640k_family

    mov byte [cs:fdd_2dd_base], 0x10
    mov byte [cs:fdd_2hd_base], 0x90
    jmp .try_alternate

.try_640k_family:
    mov byte [cs:fdd_2dd_base], 0x70
    mov byte [cs:fdd_2hd_base], 0xF0

.try_alternate:
    call fdd_detect_active_family
    jnc .found

    ; Keep the historical pair as the next first candidate while the family
    ; is still unknown.
    mov byte [cs:fdd_2dd_base], 0x70
    mov byte [cs:fdd_2hd_base], 0xF0

.absent:
    xor al, al
    stc
    jmp .done

.found:
    mov byte [cs:fdd_if_known], 1
    clc

.done:
    pop si
    pop dx
    pop cx
    pop bx
    ret

; Probe one already-selected DA/UA family for physical FDD unit SI.
; Return values are the same as fdd_detect_media.
fdd_detect_active_family:
    ; Try 2HD/2HC first.
    mov ax, si
    add al, [cs:fdd_2hd_base]
    mov ah, 0x07                  ; RECALIBRATE
    push ds
    push si
    int 0x1B
    pop si
    pop ds
    jc .try_2dd

    mov ax, si
    add al, [cs:fdd_2hd_base]
    mov ah, 0x51                  ; VERIFY
    mov bx, 512
    xor cx, cx
    mov ch, 2                     ; 512-byte sector size code
    xor dx, dx
    mov dl, 1
    push ds
    push si
    int 0x1B
    pop si
    pop ds
    jnc .is_2hd

.try_2dd:
    mov ax, si
    add al, [cs:fdd_2dd_base]
    mov ah, 0x07                  ; RECALIBRATE
    push ds
    push si
    int 0x1B
    pop si
    pop ds
    jc .absent

    mov ax, si
    add al, [cs:fdd_2dd_base]
    mov ah, 0x51                  ; VERIFY
    mov bx, 512
    xor cx, cx
    mov ch, 2                     ; 512-byte sector size code
    xor dx, dx
    mov dl, 1
    push ds
    push si
    int 0x1B
    pop si
    pop ds
    jnc .is_2dd

.absent:
    xor al, al
    stc
    ret

.is_2dd:
    mov ax, si
    add al, [cs:fdd_2dd_base]
    mov [cs:fdd_daua_map + si], al
    mov al, 1
    clc
    ret

.is_2hd:
    mov ax, si
    add al, [cs:fdd_2hd_base]
    mov [cs:fdd_daua_map + si], al
    mov al, 2
    clc
    ret

; Return the exact ROM-BIOS DA/UA selected for one CP/M floppy drive.
; This is used by utilities that call INT 1Bh directly after SELDSK has
; detected the medium.  Input AL=0..3 for A:..D:.
; Return AL=DA/UA and CF=0 when known; AL=0 and CF=1 otherwise.
; BX is preserved.
GET_FDD_DAUA:
    push bx
    xor bh, bh
    mov bl, al
    cmp bl, 4
    jae .fail
    mov al, [cs:fdd_daua_map + bx]
    test al, al
    jz .fail
    pop bx
    clc
    ret
.fail:
    pop bx
    xor al, al
    stc
    ret

; Convert CP/M logical track/sector to PC-98 2DD/2HD CHS.
;
; CP/M logical track is one floppy SIDE:
;   cylinder = track / 2
;   head     = track & 1
;
; Four 128-byte records form one physical 512-byte sector:
;   sector = (cur_sector / 4) + 1, range 1..8 (2DD) or 1..15 (2HD)
;
; Returns PC-98 register fields CH/CL/DH/DL.
make_chs:
    mov ax, [cs:cur_track]
    mov dx, ax
    and dl, 1
    mov dh, dl                      ; head
    shr ax, 1
    mov cl, al                      ; cylinder 0..79

    mov ax, [cs:cur_sector]
    shr ax, 1
    shr ax, 1
    inc al
    mov dl, al                      ; sector 1..8 or 1..15
    mov ch, 2                       ; 512-byte sector size code
    ret

; ----------------------------------------------------------------------
; Resolve cold-start drive from the fixed boot-hint block at system offset
; 3DE0h.  A current IPL writes this block after copying the resident image.
;
; HDD matching rule:
;   current boot DA/UA (read by IPL at boot time) + persistent 64-bit FS-ID.
; Because DA/UA is captured at boot, changing the HDD SCSI ID is supported.
; ----------------------------------------------------------------------
resolve_boot_drive:
    mov byte [cur_disk], 0

    ; Ignore the hint unless it has the expected IPL signature/version.
    push cs
    pop es
    mov si, boot_hint
    mov di, boot_hint_magic
    mov cx, 8
    cld
    repe cmpsb
    jne .done

    cmp byte [boot_hint + 8], BOOT_TYPE_HDD
    je .hdd

    ; FDD IPL: the low two DA/UA bits are the physical unit A:..D:.
    cmp byte [boot_hint + 8], BOOT_TYPE_FDD
    jne .done
    mov al, [boot_hint + 9]
    and al, 3
    mov [cur_disk], al
    ret

.hdd:
    ; HDD IPL records the DA/UA actually used for this boot, not the DA/UA
    ; present when HDFORMAT was run.  Therefore a later SCSI-ID change is
    ; naturally reflected here.  Search only that current SCSI unit, then
    ; use the persistent FS-ID to distinguish its CP/M partitions.
    xor si, si
.scan:
    xor ax, ax
    mov al, [hdd_count]
    cmp si, ax
    jae .done

    mov al, [hdd_daua_map + si]
    cmp al, [boot_hint + 9]
    jne .next

    mov di, si
    shl di, 1
    mov cx, [hdd_start_cyl_map + di]
    xor dx, dx
    mov bp, physbuf
    mov bx, 512
    mov ah, 0x06
    push ds
    push si
    int 0x1b
    pop si
    pop ds
    jc .next
    push cs
    pop es

    push si
    mov si, physbuf + 0x1E8
    mov di, boot_hint + 10
    mov cx, 8
    repe cmpsb
    pop si
    jne .next

    mov ax, si
    add al, HDD_FIRST_DRIVE
    mov [cur_disk], al
    ret

.next:
    inc si
    jmp .scan

.done:
    ret


; ----------------------------------------------------------------------
; SCSI HDD discovery and dynamic DPH/DPB construction.
;
; Scan order is stable:
;   SCSI ID 0..6, then PC-98 partition entry 1..16.
; Only formatted CP/M partitions ((syss & 7Fh)=70h and sysm='CP/M-86         ')
; are packed into E:..H: in SCSI-ID order, then partition-number order.
;
; Only 512-byte SCSI sectors are accepted.  The partition
; layout must be cylinder-aligned as produced by the matching FDISK:
; start H/S = 0/0 and end H/S = 0/0; end cylinder is inclusive.
;
; Dynamic objects are placed from HDD_HEAP_BASE upward:
;   +000 DPH (16)
;   +010 DPB (15, one byte pad)
;   +020 checksum vector (128)
;   +0A0 allocation vector (ceil(blocks/8))
;
; At most four HDD partitions are mounted (E:..H:).  init_mrt converts the
; final system-segment-relative heap end to a physical segment and places the
; TPA immediately above it when the heap extends beyond physical 08000h.
; ----------------------------------------------------------------------
hdd_init:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es

    mov byte [hdd_count], 0
    mov word [hdd_heap_next], HDD_HEAP_BASE
    mov byte [hdd_scan_id], 0

.id_loop:
    cmp byte [hdd_scan_id], 7
    jb .sense
    jmp .done

.sense:
    mov al, [hdd_scan_id]
    add al, 0xA0
    mov [hdd_scan_daua], al

    mov bx, 0xA55A
    mov cx, 0x5AA5
    mov dx, 0xC33C
    mov ah, 0x84
    push ds
    int 0x1b
    pop ds
    jnc .sense_cf_ok
    jmp .next_id
.sense_cf_ok:

    ; Only the 512-byte SCSI path is supported.
    cmp bx, 512
    je .sense_size_ok
    jmp .next_id
.sense_size_ok:
    test cx, cx
    jnz .sense_cyl_ok
    jmp .next_id
.sense_cyl_ok:
    test dh, dh
    jnz .sense_heads_ok
    jmp .next_id
.sense_heads_ok:
    test dl, dl
    jnz .sense_spt_ok
    jmp .next_id
.sense_spt_ok:

    mov [hdd_scan_cylast], cx
    mov [hdd_scan_heads], dh
    mov [hdd_scan_spt], dl

    ; Read PC-98 partition table C0/H0/S1.
    mov ax, cs
    mov es, ax
    mov bp, physbuf
    mov bx, 512
    xor cx, cx
    xor dx, dx
    mov dl, 1
    mov al, [hdd_scan_daua]
    mov ah, 0x06
    push ds
    int 0x1b
    pop ds
    jnc .pt_read_ok
    jmp .next_id
.pt_read_ok:

    mov si, physbuf
    mov byte [hdd_scan_part], 0

.part_loop:
    cmp byte [hdd_scan_part], 16
    jb .part_check
    jmp .next_id

.part_check:
    mov al, [si + 1]
    and al, 0x7F
    cmp al, HDD_CPM_SYS
    je .part_type_ok
    jmp .part_next
.part_type_ok:
    ; sysm is kept printable because the PC-98 fixed-disk boot menu uses it
    ; as the partition name.  Exact label also serves as formatted marker.
    push si
    push di
    push cx
    push ds
    pop es
    add si, 16
    mov di, hdd_fs_label
    mov cx, 16
    cld
    repe cmpsb
    pop cx
    pop di
    pop si
    je .part_signature_ok
    jmp .part_next

.part_signature_ok:
    cmp byte [si + 8], 0          ; start sector
    je .part_ss_ok
    jmp .part_next
.part_ss_ok:
    cmp byte [si + 9], 0          ; start head
    je .part_sh_ok
    jmp .part_next
.part_sh_ok:
    cmp byte [si + 12], 0         ; end sector
    je .part_es_ok
    jmp .part_next
.part_es_ok:
    cmp byte [si + 13], 0         ; end head
    je .part_eh_ok
    jmp .part_next
.part_eh_ok:

    mov ax, [si + 10]             ; start cylinder
    mov dx, [si + 14]             ; inclusive end cylinder
    cmp dx, ax
    jae .part_order_ok
    jmp .part_next
.part_order_ok:
    cmp dx, [hdd_scan_cylast]
    jbe .part_end_ok
    jmp .part_next
.part_end_ok:

    ; Partition-size policy remains 1..512 MiB for the whole partition.
    ; The first cylinder is then excluded from DSM because DPB OFF=1
    ; reserves it for the partition IPL and resident system image.
    sub dx, ax
    inc dx                        ; DX = total cylinders
    cmp dx, 2
    jae .part_has_data
    jmp .part_next
.part_has_data:
    mov [hdd_tmp_start], ax
    mov bp, dx                    ; BP = total cylinders

    ; First validate total partition size in 16-KiB units.
    mov ax, bp
    xor bx, bx
    mov bl, [hdd_scan_heads]
    mul bx
    xor bx, bx
    mov bl, [hdd_scan_spt]
    call hdd_mul32_16

    ; FDISK's 1-MiB request is cylinder-rounded DOWN, so the resulting
    ; partition may be less than 1 MiB by at most one cylinder.  Accept only
    ; that lower-bound rounding tolerance.  The 512-MiB upper bound remains
    ; strict because rounding down can never exceed it.
    test dx, dx
    jnz .total_min_ok
    push ax
    xor ax, ax
    mov al, [hdd_scan_heads]
    xor bx, bx
    mov bl, [hdd_scan_spt]
    mul bx                        ; AX = sectors/cylinder
    mov bx, 2049                  ; 1 MiB = 2048 x 512-byte sectors
    sub bx, ax
    pop ax
    cmp ax, bx
    jae .total_min_ok
    jmp .part_next
.total_min_ok:
    mov cl, 5
.total_shift5:
    shr dx, 1
    rcr ax, 1
    dec cl
    jnz .total_shift5
    test dx, dx
    jz .total_blocks_16
    jmp .part_next
.total_blocks_16:
    cmp ax, 32768                 ; whole partition <= 512 MiB
    jbe .total_max_ok
    jmp .part_next
.total_max_ok:

    ; Now calculate filesystem allocation blocks after removing one cylinder.
    mov ax, bp
    dec ax
    xor bx, bx
    mov bl, [hdd_scan_heads]
    mul bx
    xor bx, bx
    mov bl, [hdd_scan_spt]
    call hdd_mul32_16
    mov cl, 5
.data_shift5:
    shr dx, 1
    rcr ax, 1
    dec cl
    jnz .data_shift5
    test dx, dx
    jz .data_blocks_16
    jmp .part_next
.data_blocks_16:
    test ax, ax
    jnz .data_nonzero
    jmp .part_next
.data_nonzero:
    mov [hdd_tmp_blocks], ax

    cmp byte [hdd_count], HDD_MAX_DRIVES
    jb .count_ok
    jmp .done
.count_ok:

    call hdd_build_drive
    jnc .build_ok
    jmp .done                     ; workspace exhausted: keep prior drives
.build_ok:

.part_next:
    add si, 32
    inc byte [hdd_scan_part]
    jmp .part_loop

.next_id:
    inc byte [hdd_scan_id]
    jmp .id_loop

.done:
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; Build one DPH/DPB/CSV/ALV object at hdd_heap_next.
; Input comes from current hdd_scan_* and hdd_tmp_* values.
hdd_build_drive:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    ; ALV bytes = ceil(blocks / 8).
    mov ax, [hdd_tmp_blocks]
    add ax, 7
    mov cl, 3
    shr ax, cl
    mov dx, ax                    ; DX = ALV bytes
    mov [hdd_tmp_alv], ax

    mov bx, [hdd_heap_next]
    mov ax, bx
    add ax, HDD_ALV_OFS
    add ax, dx
    jnc .heap_add_ok
    jmp .no_room
.heap_add_ok:
    add ax, 15
    and ax, 0xFFF0                ; next object paragraph-aligned
    cmp ax, HDD_HEAP_LIMIT
    jbe .heap_limit_ok
    jmp .no_room
.heap_limit_ok:
    mov [hdd_heap_after], ax

    ; Slot index and map entries.
    xor ax, ax
    mov al, [hdd_count]
    mov di, ax
    mov al, [hdd_scan_daua]
    mov [hdd_daua_map + di], al
    mov al, [hdd_scan_heads]
    mov [hdd_heads_map + di], al
    mov al, [hdd_scan_spt]
    mov [hdd_spt_map + di], al

    mov ax, di
    shl ax, 1
    mov bp, ax
    mov ax, [hdd_tmp_start]
    mov [hdd_start_cyl_map + bp], ax
    mov [hdd_dph_ptrs + bp], bx

    ; Zero DPH + DPB pad + CSV.
    push ds
    pop es
    mov di, bx
    mov cx, HDD_ALV_OFS
    xor ax, ax
    rep stosb

    ; DPH fields.
    mov di, bx
    mov word [di + 0], 0
    mov word [di + 2], 0
    mov word [di + 4], 0
    mov word [di + 6], 0
    mov word [di + 8], dirbuf
    mov ax, bx
    add ax, HDD_DPB_OFS
    mov [di + 10], ax
    mov ax, bx
    add ax, HDD_CSV_OFS
    mov [di + 12], ax
    mov ax, bx
    add ax, HDD_ALV_OFS
    mov [di + 14], ax

    ; DPB.
    mov di, bx
    add di, HDD_DPB_OFS

    xor ax, ax
    mov al, [hdd_scan_heads]
    xor cx, cx
    mov cl, [hdd_scan_spt]
    mul cx
    shl ax, 1
    shl ax, 1                    ; *4 records per 512-byte physical sector
    mov [di + 0], ax             ; SPT
    mov byte [di + 2], 7         ; BSH
    mov byte [di + 3], 127       ; BLM

    mov ax, [hdd_tmp_blocks]
    dec ax
    mov [di + 5], ax             ; DSM
    cmp ax, 255
    jbe .small_exm
    mov byte [di + 4], 7
    jmp .exm_done
.small_exm:
    mov byte [di + 4], 15
.exm_done:
    mov word [di + 7], 511       ; DRM
    mov byte [di + 9], 0x80      ; AL0: directory block 0
    mov byte [di + 10], 0x00     ; AL1
    mov word [di + 11], 128      ; CKS
    mov word [di + 13], 1        ; OFF: IPL/system cylinder

    ; Zero the allocation vector.  CSV was already zeroed above.
    mov di, bx
    add di, HDD_ALV_OFS
    mov cx, [hdd_tmp_alv]
    xor ax, ax
    rep stosb

    mov ax, [hdd_heap_after]
    mov [hdd_heap_next], ax
    inc byte [hdd_count]

    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret

.no_room:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret


; DX:AX *= BX, low 32-bit result in DX:AX.
hdd_mul32_16:
    push cx
    push si

    mov si, dx
    mul bx
    mov cx, dx
    mov dx, si
    push ax
    mov ax, dx
    mul bx
    add ax, cx
    mov dx, ax
    pop ax

    pop si
    pop cx
    ret

; ----------------------------------------------------------------------
; DPH / DPB for auto-detected PC-98 2DD / 2HD floppy media.
;
; 2DD: 80 cylinders x 2 heads x 8 x 512 bytes, SPT=32, OFF=4, 2 KiB blocks.
; 2HD: 80 cylinders x 2 heads x 15 x 512 bytes, SPT=60, OFF=3, 4 KiB blocks.
; SELDSK updates DPH+0Ah to the DPB selected for the inserted medium.
; ----------------------------------------------------------------------
dph_table:
    dw dph0, dph1, dph2, dph3

dph0:
    dw 0
    dw 0, 0, 0
    dw dirbuf
    dw dpb_2dd
    dw csv0
    dw alv0

dph1:
    dw 0
    dw 0, 0, 0
    dw dirbuf
    dw dpb_2dd
    dw csv1
    dw alv1

dph2:
    dw 0
    dw 0, 0, 0
    dw dirbuf
    dw dpb_2dd
    dw csv2
    dw alv2

dph3:
    dw 0
    dw 0, 0, 0
    dw dirbuf
    dw dpb_2dd
    dw csv3
    dw alv3

dpb_2dd:
    dw 32                   ; SPT: 8 x 512-byte sectors / side
    db 4                    ; BSH: 2048-byte block
    db 15                   ; BLM
    db 0                    ; EXM: DSM >= 256
    dw 311                  ; DSM: blocks 0..311
    dw 127                  ; DRM: 128 directory entries
    db 0xC0                 ; AL0: first two blocks reserved for directory
    db 0x00                 ; AL1
    dw 32                   ; CKS: (DRM+1)/4
    dw 4                    ; OFF: four logical side-tracks

dpb_2hd:
    dw 60                   ; SPT: 15 x 512-byte sectors / side
    db 5                    ; BSH: 4096-byte block
    db 31                   ; BLM
    db 1                    ; EXM
    dw 293                  ; DSM: blocks 0..293
    dw 127                  ; DRM: 128 directory entries
    db 0x80                 ; AL0: first block reserved for directory
    db 0x00                 ; AL1
    dw 32                   ; CKS: (DRM+1)/4
    dw 3                    ; OFF: three logical side-tracks

; One contiguous transient area. Base/length are filled by INIT from SW3
; after the final HDD workspace extent is known.
mrt:
    db 1
mrt_base:
    dw TPA_BASE_SEG          ; normally physical 08000h
mrt_length:
    dw 0                     ; initialized before CCP starts

init_msg db 13,10,'CP/M-86 v1.1 for PC-9801 series',13,10,0
ram_msg db 13,10,'       [RAM ',0
tpa_msg db 'KiB / TPA ',0
kib_crlf_msg db 'KiB]',13,10,13,10,0
hires_msg db 13,10,'Hi-res unsupported.',13,10,0
memsw_msg db 13,10,'Bad memory switch.',13,10,0

; Compatibility objects referenced from the fixed configuration area.
compat_pfktable times 400 db 0
compat_ser1     db 0
compat_fiddsmem dw 0
compat_crtmod   db 3

iobyte       db 0x01              ; default CON:=CRT:
cur_disk     db 0
cur_track    dw 0
cur_sector   dw 0
dma_off      dw 0x0080
dma_seg      dw 0

disk_daua       db 0x70
fdd_2dd_base    db 0x70          ; active/candidate interface family: 10h or 70h
fdd_2hd_base    db 0xF0          ; paired 2HD family: 90h or F0h
fdd_if_known    db 0             ; 0=probe both families, 1=family fixed
fdd_media_map   times 4 db 0     ; 0=unknown, 1=2DD, 2=2HD/2HC
fdd_daua_map    times 4 db 0     ; DA/UA used by normal I/O after detection
fdd_boot_seed_map times 4 db 0   ; skip first detection for FDD boot drive
mem_size_code db 0
screen_col    db 0
screen_row    db 0
current_attr  db DEFAULT_ATTR
esc_state     db 0
csi_arg1      db 0
csi_arg2      db 0
saved_screen_col db 0
saved_screen_row db 0

; PC-98 text color bits (attr bits 7..5).  PC-98 palette index order is
; black, blue, red, magenta, green, cyan, yellow, white, while ANSI 30..37
; orders colors black, red, green, yellow, blue, magenta, cyan, white.
ansi_color_bits db 0x00,0x40,0x80,0xC0,0x20,0x60,0xA0,0xE0

disk_kind       db 0              ; 0=FDD, 1=SCSI HDD
rec_mask        db 3              ; logical-record index mask inside phys sector

; Drive-to-GVRAM data slot segments.  Ordering is logical A:..H:; physical
; placement interleaves FDD/HDD slots so B0000h is always a slot boundary.
cache_slot_segs:
    dw 0xA800, 0xA9E0, 0xB000, 0xB1E0
    dw 0xABC0, 0xADE0, 0xB3C0, 0xB5E0

hdd_count       db 0
hdd_remount_pending db 0
; Printable sysm label doubles as the formatted-partition marker.
hdd_fs_label     db 'CP/M-86         '

hdd_dph_ptrs       times HDD_MAX_DRIVES dw 0
hdd_daua_map        times HDD_MAX_DRIVES db 0
hdd_heads_map       times HDD_MAX_DRIVES db 0
hdd_spt_map         times HDD_MAX_DRIVES db 0
hdd_start_cyl_map   times HDD_MAX_DRIVES dw 0

hdd_daua_cur      db 0
hdd_heads_cur     db 0
hdd_spt_cur       db 0
hdd_start_cyl_cur dw 0
boot_hint_magic   db 'CP86BOOT'

; FDD CSV/ALV remain resident because BDOS accesses them through the DPH.
; dirbuf/physbuf also host INIT-only and cache scratch state in the unloaded
; 3E00h..417Fh workspace; they therefore consume no resident BIOS bytes.
csv0         times 32 db 0
csv1         times 32 db 0
csv2         times 32 db 0
csv3         times 32 db 0
alv0         times 39 db 0
alv1         times 39 db 0
alv2         times 39 db 0
alv3         times 39 db 0

; Private ABI for utilities that perform direct ROM-BIOS disk I/O.
; The fixed-offset FAR-call stubs are outside the standard CP/M-86 jump table
; and are called through the resident system segment (normally 0400h).
; Preserve these offsets for binary compatibility with such utilities.
;   0400:HDD_REMOUNT_OFS  - request one HDD remount on the next WBOOT
;   0400:FDD_DAUA_OFS    - AL=FDD unit 0..3 -> AL=active DA/UA, CF=status
;   0400:CACHE_SYNC_OFS  - flush dirty runs from all eight drive windows
;   0400:CACHE_RESET_OFS - flush, then invalidate all GVRAM window metadata
times (HDD_REMOUNT_OFS - 0x2500) - ($ - $$) db 0
    call HDD_REMOUNT_REQUEST
    retf
    call GET_FDD_DAUA
    retf
    call CACHE_SYNC
    retf
    call CACHE_RESET
    retf

; Fixed IPL -> BIOS boot-hint block.  It is part of the 3E00h resident
; image and therefore has a fixed offset within the resident system image.
boot_hint:
times BOOT_HINT_SIZE db 0

; Full resident system remains exactly 3E00h bytes = 31 physical sectors.
times BIOS_BIN_SIZE - ($ - $$) db 0
