; FDIPL.ASM
; PC-9801 2DD/2HD common boot IPL for CP/M-86 v1.1.
;

cpu 8086
bits 16

org 0x8000

OS_SEG          equ 0x0400
BIOS_OFS        equ 0x2500
SYS_SECTORS     equ 31
BOOT_HINT_OFS   equ 0x3de0
BOOT_DAUA       equ 0x0584

start:
    cli
    push cs
    pop ds
    xor si, si
    xor ax, ax
    mov es, ax
    mov di, 0x8000
    mov cx, 256
    cld
    rep movsw
    jmp 0x0000:relocated

relocated:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x9000
    sti
    cld

    ; ROM BIOS records the physical boot-device DA/UA here.  Its upper
    ; nibble identifies the media geometry and command family used to load
    ; this boot sector:
    ;   10h / 70h = 2DD, 8 x 512-byte sectors per side
    ;   90h / F0h = 2HD, 15 x 512-byte sectors per side
    mov al, [BOOT_DAUA]
    mov [boot_drive], al
    and al, 0xf0
    cmp al, 0x10
    je .boot_2dd
    cmp al, 0x70
    je .boot_2dd
    cmp al, 0x90
    je .boot_2hd
    cmp al, 0xf0
    jne read_error

.boot_2hd:
    mov word [sectors_per_side], 15
    jmp .geometry_ready

.boot_2dd:
    mov word [sectors_per_side], 8

.geometry_ready:
    mov word [lba], 1
    mov word [dest_seg], OS_SEG
    mov cx, SYS_SECTORS

.load_loop:
    push cx
    mov di, 5

.retry:
    ; Rebuild all INT 1Bh request registers for each retry.  Do not depend on
    ; the ROM BIOS preserving request registers after a failed transfer.
    mov ax, [dest_seg]
    mov es, ax
    xor bp, bp

    call make_chs
    mov bx, 512
    mov al, [boot_drive]
    mov ah, 0x56                  ; READ + SEEK + MFM

    push di
    push ds
    int 0x1b
    pop ds
    pop di
    jnc .read_ok

    push di
    push ds
    mov al, [boot_drive]
    mov ah, 0x07                  ; recalibrate FDD
    int 0x1b
    pop ds
    pop di

    dec di
    jnz .retry
    jmp read_error

.read_ok:
    add word [dest_seg], 0x20     ; next 512-byte destination sector
    inc word [lba]
    pop cx
    loop .load_loop

    ; All ROM BIOS disk calls are complete.  Initialize the boot-source hint
    ; in the freshly loaded resident image.  The BIOS uses this to identify
    ; the physical system drive independently of CP/M's current drive.
    mov ax, OS_SEG
    mov es, ax
    mov di, BOOT_HINT_OFS
    xor ax, ax
    mov cx, 16
    rep stosw

    mov word [es:BOOT_HINT_OFS + 0], 0x5043
    mov word [es:BOOT_HINT_OFS + 2], 0x3638
    mov word [es:BOOT_HINT_OFS + 4], 0x4f42
    mov word [es:BOOT_HINT_OFS + 6], 0x544f
    mov byte [es:BOOT_HINT_OFS + 8], 0       ; source type: FDD
    mov al, [boot_drive]
    mov [es:BOOT_HINT_OFS + 9], al

    jmp OS_SEG:BIOS_OFS

; Convert the linear 512-byte sector number to the CHS request selected by
; the ROM-BIOS boot DA/UA.  Both formats use 80 cylinders and two heads:
;   2DD:  8 sectors/side, 16 sectors/cylinder
;   2HD: 15 sectors/side, 30 sectors/cylinder
make_chs:
    mov ax, [lba]
    xor dx, dx
    mov si, [sectors_per_side]
    shl si, 1
    div si
    mov cl, al

    mov ax, dx
    xor dx, dx
    mov si, [sectors_per_side]
    div si
    mov dh, al
    inc dl
    mov ch, 2                     ; 512-byte sector size code
    ret

; No console device is initialized by the IPL.  If the resident image cannot
; be loaded after the retry limit, stop with interrupts disabled.
read_error:
halt:
    cli
.hang:
    hlt
    jmp .hang

boot_drive       db 0
sectors_per_side dw 8
lba              dw 1
dest_seg         dw OS_SEG

times 510-($-$$) db 0
dw 0xaa55
