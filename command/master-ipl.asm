; CPM86-MASTER-IPL.ASM
; Minimal PC-9801 SCSI HDD master IPL for CP/M-86.
;
; NASM syntax, 8086/V30 compatible, exactly 512 bytes.
;
; Behaviour:
;   1. Relocate itself to 0000:8000.
;   2. Obtain boot HDD DA/UA from PC-98 BDA 0000:0584.
;   3. Read the PC-98 partition table from C0/H0/S1.
;   4. Scan 16 x 32-byte entries in table order.
;   5. Select the first entry satisfying:
;        +00h == 95h              ; bootable marker used by FDISK
;        (+01h & 7Fh) == 70h      ; CP/M-86 partition type
;   6. Read that partition's first sector (HDIPL) to 07C0:0000.
;   7. Verify "CPM86FS1" at +1E0h and 55AAh at +1FEh.
;   8. Jump to 07C0:0000.
;
; Boot policy:
;   - no partition-selection menu
;   - only CP/M-86 partitions are booted
;   - the first bootable CP/M-86 partition in table order is selected
;
; Disk I/O:
;   PC-98 ROM BIOS INT 1Bh
;   SCSI READ: AH=06h, AL=DA/UA, BX=512, CX=cylinder,
;              DH=head, DL=zero-based sector, ES:BP=buffer
;
; Build:
;   nasm -f bin -o CPM86-MASTER-IPL.BIN CPM86-MASTER-IPL.ASM
;
; Convert for ASM86 INCLUDE:
;   python3 bin2a86.py CPM86-MASTER-IPL.BIN MASTERIPL.INC \
;       --label masteripl_template --expect-size 512

cpu 8086
bits 16
org 0x8000

BOOT_DAUA       equ 0x0584
SELF_ADDR       equ 0x8000
PT_ADDR         equ 0x8200
HDIPL_SEG       equ 0x07c0
HDIPL_ADDR      equ 0x7c00

SECTOR_BYTES    equ 512
PART_COUNT      equ 16
PART_SIZE       equ 32
BOOT_MARK       equ 0x95
CPM_SYS         equ 0x70
MAX_RETRY       equ 5

start:
        ; PC-98 may enter a disk IPL at a machine-dependent CS.
        ; Source is always CS:0000; relocate to a known linear address.
        cli
        push    cs
        pop     ds
        xor     si,si
        xor     ax,ax
        mov     es,ax
        mov     di,SELF_ADDR
        mov     cx,SECTOR_BYTES/2
        cld
        rep     movsw
        jmp     0x0000:relocated

relocated:
        xor     ax,ax
        mov     ds,ax
        mov     es,ax
        mov     ss,ax
        mov     sp,0x9000
        sti
        cld

        mov     al,[BOOT_DAUA]
        mov     [boot_drive],al

        call    read_partition_table
        jc      boot_error

        mov     si,PT_ADDR
        mov     cx,PART_COUNT

.scan:
        cmp     byte [si+0x00],BOOT_MARK
        jne     .next
        mov     al,[si+0x01]
        and     al,0x7f
        cmp     al,CPM_SYS
        jne     .next

        ; Save the selected partition start CHS before ROM BIOS calls.
        mov     al,[si+0x08]
        mov     [part_sector],al
        mov     al,[si+0x09]
        mov     [part_head],al
        mov     ax,[si+0x0a]
        mov     [part_cylinder],ax

        call    read_partition_ipl
        jc      boot_error

        ; Require the HDFORMAT/HDIPL metadata signature.
        cmp     word [HDIPL_ADDR+0x1e0],0x5043 ; "CP"
        jne     boot_error
        cmp     word [HDIPL_ADDR+0x1e2],0x384d ; "M8"
        jne     boot_error
        cmp     word [HDIPL_ADDR+0x1e4],0x4636 ; "6F"
        jne     boot_error
        cmp     word [HDIPL_ADDR+0x1e6],0x3153 ; "S1"
        jne     boot_error
        cmp     word [HDIPL_ADDR+0x1fe],0xaa55
        jne     boot_error

        ; HDIPL expects to start at offset 0000 in its load segment.
        jmp     HDIPL_SEG:0x0000

.next:
        add     si,PART_SIZE
        loop    .scan

boot_error:
        cli
.hang:
        hlt
        jmp     .hang

; ----------------------------------------------------------------------
; Read master partition table: absolute C0/H0/S1 -> 0000:8200.
; ----------------------------------------------------------------------
read_partition_table:
        mov     di,MAX_RETRY
.retry:
        xor     ax,ax
        mov     es,ax
        mov     bp,PT_ADDR
        mov     bx,SECTOR_BYTES
        xor     cx,cx
        xor     dx,dx
        mov     dl,1
        mov     al,[boot_drive]
        mov     ah,0x06
        push    di
        push    ds
        int     0x1b
        pop     ds
        pop     di
        jnc     .ok
        dec     di
        jnz     .retry
        stc
        ret
.ok:
        clc
        ret

; ----------------------------------------------------------------------
; Read selected partition IPL -> 07C0:0000.
; Inputs are rebuilt for every retry.
; ----------------------------------------------------------------------
read_partition_ipl:
        mov     di,MAX_RETRY
.retry:
        mov     ax,HDIPL_SEG
        mov     es,ax
        xor     bp,bp
        mov     bx,SECTOR_BYTES
        mov     cx,[part_cylinder]
        mov     dh,[part_head]
        mov     dl,[part_sector]
        mov     al,[boot_drive]
        mov     ah,0x06
        push    di
        push    ds
        int     0x1b
        pop     ds
        pop     di
        jnc     .ok
        dec     di
        jnz     .retry
        stc
        ret
.ok:
        clc
        ret

boot_drive      db 0
part_sector     db 0
part_head       db 0
part_cylinder   dw 0

; PC-98 fixed-disk master IPL signature at offset 00FEh.
times 0x0fe-($-$$) db 0
dw 0xaa55

; Conventional full-sector 55AAh signature at offset 01FEh.
times 0x1fe-($-$$) db 0
dw 0xaa55
