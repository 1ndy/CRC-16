%include "/usr/local/share/csc314/asm_io.inc"


segment .data
        ;data
        divisor dd 0xb7b10000 ; common divisor value for CRC-16, claims to have HD of 8. padded with 0

        ;error
        error_no_args db "usage: %s <file_name>",10,0
        err_file_open db "Error opening file",10,0

        ;info
        crc16_fmt db "CRC-16 value is: %x",10,0

segment .bss

segment .text
        global  asm_main
        extern printf

asm_main:
        push    ebp
        mov             ebp, esp
        ; ********** CODE STARTS HERE **********

        mov ecx, DWORD [ebp+8]
        cmp ecx, 1
        je from_stdin
                mov eax, DWORD [ebp+12]
                add eax, 4
                mov eax, [eax]
                push eax
                call crc16_file
                add esp, 4
                jmp end


        from_stdin:
                mov eax, 1
                push eax
                call crc16_file
                add esp, 4
                jmp end


        error_quit:
                mov eax, DWORD [ebp+12]
                mov eax, [eax]
                push eax
                push error_no_args
                call printf
                add esp, 8
                mov eax, 0x1
                mov ebx, 1
                int 0x80

        end:
                push eax
                push crc16_fmt
                call printf
        ; *********** CODE ENDS HERE ***********
        mov             eax, 0
        mov             esp, ebp
        pop             ebp
        ret

crc16_file:
        push ebp
        mov ebp, esp

        ;-4 destination for bytes read from file
        ;-8 fd
        ;-12 counter for refill determination
        ;-16 space for reading more bytes from file
        sub esp, 16
        mov DWORD [ebp-4], 0
        mov DWORD [ebp-8], 0
        mov DWORD [ebp-12], 0

        ;open the file
        cmp DWORD [ebp+8], 1
        je read
        mov eax, 0x5
        mov ebx, DWORD [ebp+8]
        mov ecx, 0
        mov edx, 0
        int 0x80

        ;test if file opened completely
        cmp eax, -1
        jne continue
                push err_file_open
                call printf
                add esp, 4
                mov eax, 0x1
                mov ebx, 1
                int 0x80

        ;store the fd
        continue:
        mov DWORD [ebp-8], eax

        ;read 4 bytes to initialize the data mask
        read:
        mov eax, 0x3
        mov ebx, DWORD [ebp-8]
        lea ecx, [ebp-4]
        mov edx, 4
        int 0x80

        ;loop to calculate crc
        ;1. div must be aligned with most significant 1. shift if needed
        ;2. if there is a space of 8 on the right side of the mask, read another byte into it
        ;3. xor masked data with divisor
        ;4. loop until end of file
        ;5. keep xor'ing until mask is 0
        ;6. determine how much of divisor went past end of file, that is crc
        ;msb == most significant bit
        start_check_loop:

        mov eax, 1
        shl eax, 31
        and eax, DWORD [ebp-4]
        cmp eax, 0
        je shift
        ;if the msb is 1, xor the 16 msb with the divisor
        ;we can fall through to shift because we know the msb will now be 0
                mov eax, [divisor]
                xor DWORD [ebp-4], eax

        ;if the msb is 0, shift left once and increment the bit counter
        ;we fall through to fill in case we have gone through a whole byte
        shift:
                shl DWORD [ebp-4], 1
                inc DWORD [ebp-12]

        ;if the loop has gone through 8 bits, refill another byte
        ;this emulates a stream of data
        fill:
                cmp DWORD [ebp-12], 8
                jl start_check_loop
                        mov DWORD [ebp-12], 0
                        mov eax, 0x3
                        mov ebx, DWORD [ebp-8]
                        lea ecx, [ebp-16]
                        mov edx, 1
                        int 0x80
                        cmp eax, 0
                        je near_eof
                        mov eax, DWORD [ebp-4]
                        mov ebx, DWORD [ebp-16]
                        mov al, bl
                        mov DWORD [ebp-4], eax
                jmp start_check_loop

        ;continue xoring until [ebp-4 is 0]
        ;this means that entire input has benn zeroed
        ;increment the counter in each calculation
        ;counter tells us how many bits from the divisor make up the crc
        near_eof:
                ;close the file, because we are good server cizitens
                mov eax, 0x6
                mov ebx, DWORD [ebp-8]
                int 0x80

                mov DWORD [ebp-12], 0

                start_final_loop:

                ;mov eax, print_mask
                ;call print_string
                ;push DWORD [ebp-4]
                ;call print_binary
                ;add esp, 4

                mov eax, DWORD [ebp-4]
                cmp ax, 0
                je final
                ;cmp DWORD [ebp-12], 32
                ;je final

                        mov eax, 1
                        shl eax, 31
                        and eax, DWORD [ebp-4]
                        cmp eax, 0
                        je shift2

                        mov eax, [divisor]
                        xor DWORD [ebp-4], eax

                        shift2:
                                shl DWORD [ebp-4], 1
                                inc DWORD [ebp-12]
                                jmp start_final_loop

                ;now that we know we have <= the number of
                ; bit in the CRC, we can start shifting the XOR divisor
                ; instead of the mask of bits in the data
                ;This will also generate the final value
                final:
                        mov eax, DWORD [ebp-4]
                        mov esi, 1
                        shl esi, 31
                        mov ecx, esi
                        mov edx, [divisor]
                        start_actual_final_loop:
                                cmp eax, 0
                                je end_actual_final_loop
                                and ecx, eax
                                cmp ecx, 0
                                je final_shift
                                        xor eax, edx
                                        shr ax, 16

                                final_shift:
                                        shr edx, 1

                                shr esi, 1
                                mov ecx, esi
                                jmp start_actual_final_loop

                        end_actual_final_loop:
                        mov ax, dx

        mov esp, ebp
        pop ebp
        ret
