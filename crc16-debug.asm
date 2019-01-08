%include "/usr/local/share/csc314/asm_io.inc"


segment .data
        ;data
        test1 db "This is a test string",10,0
        divisor dd 0xAC9A0000 ; common divisor value for CRC-16, claims to have HD of 8. padded with 0
        test_filename db "asdf",0
        ;error
        error_no_args db "usage: %s <file_name>",10,0

        ;info
        mask db         "Mask:   ",0
        xors db         "XOR:    ",0
        shifts db       "Shift:  ",0
        result db       "Result: ",0

        opened_file db "Opened file",10,0
        print_fd db "File descriptor is %x",10,0
        open_filename db "Opening '%s'",10,0
        data_init db "Completed data init",10,0
        check_bit db "Checking most significant bit...",0
        print_mask db 9,"Mask value is ",0
        check_bit_1 db "bit is 1",10,0
        check_bit_0 db "bit is 0",10,0
        exec_fill db "Filling mask from right",10,0
        byte_read db 9,"Read byte from source",10,0
        counter_val db 9,"Bit counter is %d",10,0
        reached_eof db "Reached EOF",10,0
        crc16_fmt db "CRC-16 value is: %x",10,0
        finalizing db "Finalizing",10,0

segment .bss

segment .text
        global  asm_main
        extern printf

asm_main:
        push    ebp
        mov             ebp, esp
        ; ********** CODE STARTS HERE **********

        mov ecx, DWORD [ebp+8]
        cmp ecx, 2
        jne error_quit
                mov eax, DWORD [ebp+12]
                add eax, 4
                mov eax, [eax]
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
                mov eax, 1
                int 0x1

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
        push DWORD [ebp+8]
        push open_filename
        call printf
        add esp, 8

        mov eax, 0x5
        mov ebx, DWORD [ebp+8]
        mov ecx, 0
        mov edx, 0
        int 0x80

        ;store the fd
        mov DWORD [ebp-8], eax
        mov eax, opened_file  ;Opened file
        call print_string

        push DWORD [ebp-8]
        push print_fd
        call printf
        sub esp, 4

        ;read 4 bytes to initialize the data mask
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

                mov eax, mask
                push DWORD [ebp-4]
                call print_string
                call print_binary
                add esp, 4

                mov eax, xors
                call print_string
                push DWORD [divisor]
                call print_binary
                add esp, 4

                mov eax, [divisor]
                xor DWORD [ebp-4], eax

                mov eax, result
                call print_string
                push DWORD [ebp-4]
                call print_binary
                add esp, 4
                call print_nl

        ;if the msb is 0, shift left once and increment the bit counter
        ;we fall through to fill in case we have gone through a whole byte
        shift:
                mov eax, mask
                push DWORD [ebp-4]
                call print_string
                call print_binary
                add esp, 4

                shl DWORD [ebp-4], 1
                inc DWORD [ebp-12]

                mov eax, shifts
                call print_string
                push DWORD [ebp-4]
                call print_binary
                add esp, 4
                call print_nl

        ;if the loop has gone through 8 bits, refill another byte
        ;this emulates a stream of data
        fill:
                cmp DWORD [ebp-12], 8
                jl start_check_loop
                        mov DWORD [ebp-12], 0
                        mov eax, exec_fill
                        call print_string
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

                mov eax, reached_eof
                call print_string


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

                        mov eax, mask
                        push DWORD [ebp-4]
                        call print_string
                        call print_binary
                        add esp, 4

                        mov eax, xors
                        push DWORD [divisor]
                        call print_string
                        call print_binary
                        add esp, 4

                        mov eax, [divisor]
                        xor DWORD [ebp-4], eax

                        mov eax, result
                        call print_string
                        push DWORD [ebp-4]
                        call print_binary
                        add esp, 4
                        call print_nl

                        shift2:
                                mov eax, mask
                                push DWORD [ebp-4]
                                call print_string
                                call print_binary
                                add esp, 4

                                shl DWORD [ebp-4], 1
                                inc DWORD [ebp-12]

                                mov eax, shifts
                                call print_string
                                push DWORD [ebp-4]
                                call print_binary
                                add esp, 4
                                call print_nl
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

                push eax
                mov eax, mask
                push  eax
                call print_string
                call print_binary
                add esp, 4

                mov eax, xors
                call print_string
                push edx
                call print_binary
                add esp, 4
                pop eax
                                        xor eax, edx
                                        shr ax, 16
                push eax
                mov eax, result
                call print_string
                push eax
                call print_binary
                add esp, 4
                call print_nl
                pop eax



                                final_shift:
                                push eax
                                mov eax, mask
                                push DWORD edx
                                call print_string
                                call print_binary
                                add esp, 4
                                        shr edx, 1
                                mov eax, shifts
                                call print_string
                                push DWORD edx
                                call print_binary
                                add esp, 4
                                call print_nl
                                pop eax

                                shr esi, 1
                                mov ecx, esi
                                jmp start_actual_final_loop

                        end_actual_final_loop:
                        mov ax, dx

        mov esp, ebp
        pop ebp
        ret

;a debug funtion for printing a number as binary
;andrew you should make this a part of the functions in asm_io.inc
print_binary:
        push ebp
        mov ebp, esp

        push edi
        push esi
        push edx
        push ecx
        push ebx
        push eax

        mov eax, DWORD [ebp+8]
        mov ecx, 0
        mov ebx, 2

        start_bin_loop:
        cmp eax, 0
        je end_bin_loop
        ;cmp ecx, 32
        ;je end_bin_loop
                mov edx, 0
                div ebx
                push edx
                inc ecx
                jmp start_bin_loop
        end_bin_loop:

        mov esi, 32
        sub esi, ecx

        mov edi, 0
        start_bin_pad_loop:
                cmp edi, esi
                je end_bin_pad_loop
                mov eax, 0
                call print_int
                inc edi

                cmp edi, 8
                        je print_pad_space
                cmp edi, 16
                        je print_pad_space
                cmp edi, 24
                        je print_pad_space

                jmp start_bin_pad_loop

                print_pad_space:
                        mov eax, ' '
                        call print_char
                jmp start_bin_pad_loop
        end_bin_pad_loop:

        start_bin_print_loop:
                dec ecx
                pop eax
                call print_int
                cmp ecx, 0
                        je end_bin_print_loop

                cmp ecx, 8
                        je print_space
                cmp ecx, 16
                        je print_space
                cmp ecx, 24
                        je print_space

                jmp start_bin_print_loop
                print_space:
                        mov eax, ' '
                        call print_char
                jmp start_bin_print_loop
        end_bin_print_loop:
        call print_nl

        pop eax
        pop ebx
        pop ecx
        pop edx
        pop esi
        pop edi

        mov esp, ebp
        pop ebp
        ret
