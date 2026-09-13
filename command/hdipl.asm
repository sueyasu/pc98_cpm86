; HDIPL.ASM
; PC-9801 SCSI HDD partition IPL for CP/M-86.
; NASM syntax, 8086/V30 compatible, exactly 512 bytes.
;
; Boot requirements:
;   - relocate the IPL to 0000:8000 before absolute-label access
;   - load the resident system at 0400:0000
;   - do not initialize or access serial I/O
;   - preserve the PC-98 BIOS work area while INT 1Bh disk services are used
;
; Partition layout:
;   relative cyl 0, H0/S0 : this IPL
;   following 31 sectors  : resident CP/M-86 image (3E00h bytes)
;   rest of cylinder      : reserved
;   relative cyl 1 onward : CP/M filesystem (DPB OFF=1)
;
; Partition IPL metadata written by HDFORMAT:
;   01E0h..01E7h : signature "CPM86FS1"
;   01E8h..01EFh : 64-bit filesystem ID
;   01F0h..01F1h : absolute partition start cylinder
;   01FEh..01FFh : 55AAh signature

cpu 8086
bits 16
org 0x8000

OS_SEG          equ 0x0400
BIOS_OFS        equ 0x2500
SYS_SECTORS     equ 31
BOOT_HINT_OFS   equ 0x3de0
BOOT_DAUA       equ 0x0584
SECTOR_BYTES    equ 512

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

    mov al, [BOOT_DAUA]
    mov [boot_drive], al

    ; Obtain geometry from the SCSI unit actually selected by the PC-98
    ; fixed-disk boot path.  DA/UA is therefore current even after ID changes.
    mov al, [boot_drive]
    mov ah, 0x84                  ; NEW SENSE
    mov bx, 0xa55a
    mov cx, 0x5aa5
    mov dx, 0xc33c
    push ds
    int 0x1b
    pop ds
    jc read_error
    cmp bx, SECTOR_BYTES
    jne read_error
    or dh, dh
    jz read_error
    or dl, dl
    jz read_error
    mov [heads], dh
    mov [spt], dl

    ; System image begins at the physical sector immediately after the IPL.
    mov ax, [ipl_start_cyl]
    mov [cylinder], ax
    mov byte [head], 0
    mov byte [sector], 1
    mov word [dest_seg], OS_SEG
    mov cx, SYS_SECTORS

.load_loop:
    push cx
    mov di, 5

.retry:
    mov ax, [dest_seg]
    mov es, ax
    xor bp, bp
    mov bx, SECTOR_BYTES
    mov cx, [cylinder]
    mov dh, [head]
    mov dl, [sector]
    mov al, [boot_drive]
    mov ah, 0x06                  ; SCSI READ

    push di
    push ds
    int 0x1b
    pop ds
    pop di
    jnc .read_ok

    dec di
    jnz .retry
    pop cx
    jmp read_error

.read_ok:
    add word [dest_seg], 0x20
    call advance_chs
    pop cx
    loop .load_loop

    ; Install the HDD boot-source hint at system offset 3DE0h.
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
    mov byte [es:BOOT_HINT_OFS + 8], 1       ; HDD
    mov al, [boot_drive]
    mov [es:BOOT_HINT_OFS + 9], al

    mov si, ipl_fsid
    mov di, BOOT_HINT_OFS + 10
    mov cx, 4
    rep movsw

    jmp OS_SEG:BIOS_OFS

advance_chs:
    inc byte [sector]
    mov al, [sector]
    cmp al, [spt]
    jb .done
    mov byte [sector], 0
    inc byte [head]
    mov al, [head]
    cmp al, [heads]
    jb .done
    mov byte [head], 0
    inc word [cylinder]
.done:
    ret

read_error:
    cli
.hang:
    hlt
    jmp .hang

boot_drive      db 0
heads           db 0
spt             db 0
cylinder        dw 0
head            db 0
sector          db 1
dest_seg        dw OS_SEG

; Fixed partition IPL metadata area. Offsets are relative to this 512-byte IPL.
times 0x1e0-($-$$) db 0
ipl_signature   db 'CPM86FS1'
ipl_fsid        times 8 db 0       ; 01E8h
ipl_start_cyl   dw 0               ; 01F0h
times 510-($-$$) db 0
dw 0xaa55
