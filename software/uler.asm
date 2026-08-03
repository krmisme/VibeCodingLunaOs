%include "config.asm"
%include "kernel/config.asm"

[BITS 64]
[DEFAULT REL]
[ORG SOFTWARE_base_address]

; --- KONSTANTA WARNA DAN GEOMETRI KEPALA ---
COLOR_LCD_BG    equ 0x00849700 
COLOR_BORDER    equ 0x00104004 
COLOR_SNAKE     equ 0x004A6901 
COLOR_FOOD      equ 0x00FF0000 
COLOR_SNAKE_EAR equ 0x001A3300 
COLOR_TONGUE    equ 0x00FF6666 

; --- KONSTANTA WARNA JEJAK EKOR (Pre-calculated Hex Gradient) ---
COLOR_FADE_1    equ 0x00597500 ; Tahap 1: Mulai pudar (75% Snake, 25% BG)
COLOR_FADE_2    equ 0x00678000 ; Tahap 2: Setengah pudar (50% Snake, 50% BG)
COLOR_FADE_3    equ 0x00768C00 ; Tahap 3: Sangat pudar (25% Snake, 75% BG)
COLOR_FADE_4    equ 0x007E9200 ; Tahap 4: Jejak akhir (10% Snake, 90% BG)

HEAD_SIZE       equ 20         
CORE_WIDTH      equ 12         
CORE_OFFSET     equ 4          
EAR_THICK       equ 4          
EAR_LENGTH      equ 10         
EAR_OFFSET      equ 5          

TONGUE_W        equ 4          
TONGUE_L        equ 8          
TONGUE_OFFSET   equ 8          

snake:
  call draw_title_menu

.menu_wait:
  mov ax, KERNEL_SERVICE_KEYBOARD_key
  int KERNEL_SERVICE
  jz .menu_wait
  cmp al, STATIC_ASCII_ENTER
  jne .menu_wait

start_game:
  call init_game

game_loop:
  cmp byte [game_over], 0
  jne game_over_screen

  call delay
  call move_snake
  call check_collisions
  
  cmp byte [game_over], 0
  jne game_over_screen

  call check_food

  ; 0. [DIPERBAIKI] Hapus lidah lama SEBELUM menggambar elemen lain
  ; Mencegah visual lidah melubangi makanan saat tumpang tindih
  call erase_tongue_if_any

  ; 1. Gambar leher menimpa posisi visual wajah lama
  mov al, byte [snake_x + 1]
  mov ah, byte [snake_y + 1]
  mov r9d, COLOR_SNAKE
  call draw_block

  ; 2. Panggil fungsi animasi ekor memudar (O(1) update dengan Z-Order scanning)
  call draw_tail_fade

  ; 3. Gambar ulang makanan setiap frame agar berada di atas jejak ekor
  mov al, byte [food_x]
  mov ah, byte [food_y]
  mov r9d, COLOR_FOOD
  call draw_block

  ; 4. Gambar wajah, telinga, dan deteksi lidah baru di layar teratas
  mov al, byte [snake_x]
  mov ah, byte [snake_y]
  call draw_head

  jmp game_loop

game_over_screen:
  call draw_gameover_screen

.gameover_wait:
  mov ax, KERNEL_SERVICE_KEYBOARD_key
  int KERNEL_SERVICE
  jz .gameover_wait
  
  cmp al, STATIC_ASCII_ENTER
  je start_game
  
  cmp ax, STATIC_ASCII_ESCAPE
  je exit_game
  
  jmp .gameover_wait

exit_game:
  mov ax, KERNEL_SERVICE_VIDEO_clean
  int KERNEL_SERVICE
  xor ax, ax
  int KERNEL_SERVICE

erase_tongue_if_any:
  push rax
  push rbx
  push rcx
  push rdx
  push r8
  push r9

  mov rdx, qword [t_w]
  cmp rdx, 0
  je .skip
  mov r8, qword [t_h]
  mov rbx, qword [t_x]
  mov rcx, qword [t_y]
  mov r9d, COLOR_LCD_BG
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE
  mov qword [t_w], 0 ; Reset ukuran setelah dihapus
.skip:
  pop r9
  pop r8
  pop rdx
  pop rcx
  pop rbx
  pop rax
  ret

draw_tail_fade:
  push rax
  push rbx
  push rcx
  push rdx
  push r8
  push r9
  push r12
  push r13
  push rdi
  push rsi

  movzx rcx, word [snake_len]
  lea rdi, [snake_x]
  lea rsi, [snake_y]

  ; r13 menentukan batas index solid body (Head sampai batas awal ekor memudar)
  mov r13, rcx
  sub r13, 4
  cmp r13, 0
  jg .bounds_ok
  mov r13, 0
.bounds_ok:

  ; Tahap 0: Kembalikan warna blok ke-5 dari belakang menjadi solid
  mov rbx, rcx
  sub rbx, 5
  cmp rbx, 2 
  jl .skip_solid
  mov al, byte [rdi + rbx]
  mov ah, byte [rsi + rbx]
  mov r9d, COLOR_SNAKE
  call draw_block
.skip_solid:

  ; Tahap 1: Fade 1 (Blok ke-4 dari belakang)
  mov rbx, rcx
  sub rbx, 4
  cmp rbx, 2
  jl .skip_f1
  mov al, byte [rdi + rbx]
  mov ah, byte [rsi + rbx]
  call .check_overlap
  cmp r12, 1
  je .skip_f1
  mov r9d, COLOR_FADE_1
  call draw_block
.skip_f1:

  ; Tahap 2: Fade 2 (Blok ke-3 dari belakang)
  mov rbx, rcx
  sub rbx, 3
  cmp rbx, 2
  jl .skip_f2
  mov al, byte [rdi + rbx]
  mov ah, byte [rsi + rbx]
  call .check_overlap
  cmp r12, 1
  je .skip_f2
  mov r9d, COLOR_FADE_2
  call draw_block
.skip_f2:

  ; Tahap 3: Fade 3 (Blok ke-2 dari belakang)
  mov rbx, rcx
  sub rbx, 2
  cmp rbx, 2
  jl .skip_f3
  mov al, byte [rdi + rbx]
  mov ah, byte [rsi + rbx]
  call .check_overlap
  cmp r12, 1
  je .skip_f3
  mov r9d, COLOR_FADE_3
  call draw_block
.skip_f3:

  ; Tahap 4: Fade Terakhir (Blok paling ujung ekor)
  mov rbx, rcx
  sub rbx, 1
  cmp rbx, 2
  jl .skip_f4
  mov al, byte [rdi + rbx]
  mov ah, byte [rsi + rbx]
  call .check_overlap
  cmp r12, 1
  je .skip_f4
  mov r9d, COLOR_FADE_4
  call draw_block
.skip_f4:

  jmp .end_fade

.check_overlap:
  ; Memindai apakah koordinat Fade (al, ah) sedang ditutupi oleh indeks badan solid
  mov r12, 0
  cmp r13, 0
  jle .overlap_done
  push rbx
  xor rbx, rbx
.overlap_loop:
  cmp al, byte [rdi + rbx]
  jne .overlap_next
  cmp ah, byte [rsi + rbx]
  jne .overlap_next
  mov r12, 1
  jmp .overlap_found
.overlap_next:
  inc rbx
  cmp rbx, r13
  jl .overlap_loop
.overlap_found:
  pop rbx
.overlap_done:
  ret

.end_fade:
  pop rsi
  pop rdi
  pop r13
  pop r12
  pop r9
  pop r8
  pop rdx
  pop rcx
  pop rbx
  pop rax
  ret

draw_head:
  push rax
  push rbx
  push rcx
  push rdx
  push r8
  push r9
  push r10
  push r11

  ; [DIPERBAIKI] Baca al dan ah dengan instruksi aman agar bebas dari upper-bits garbage
  movzx r10, al
  imul r10, r10, HEAD_SIZE
  
  movzx r11, ax    ; Salin 16-bit (AL dan AH) lalu nol-kan sisa bit atasnya
  shr r11, 8       ; Geser 8 bit ke kanan untuk mendapatkan nilai murni AH
  imul r11, r11, HEAD_SIZE

  ; Render Bentuk Wajah
  mov al, byte [last_moved_dir]
  cmp al, 2
  jge .horizontal

.vertical:
  mov rbx, r10
  add rbx, CORE_OFFSET
  mov rcx, r11
  mov rdx, CORE_WIDTH
  mov r8, HEAD_SIZE
  mov r9d, COLOR_SNAKE
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE
  mov rbx, r10
  mov rcx, r11
  add rcx, EAR_OFFSET
  mov rdx, EAR_THICK
  mov r8, EAR_LENGTH
  mov r9d, COLOR_SNAKE_EAR
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE
  mov rbx, r10
  add rbx, 16 
  mov rcx, r11
  add rcx, EAR_OFFSET
  mov rdx, EAR_THICK
  mov r8, EAR_LENGTH
  mov r9d, COLOR_SNAKE_EAR
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE
  jmp .check_tongue

.horizontal:
  mov rbx, r10
  mov rcx, r11
  add rcx, CORE_OFFSET
  mov rdx, HEAD_SIZE
  mov r8, CORE_WIDTH
  mov r9d, COLOR_SNAKE
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE
  mov rbx, r10
  add rbx, EAR_OFFSET
  mov rcx, r11
  mov rdx, EAR_LENGTH
  mov r8, EAR_THICK
  mov r9d, COLOR_SNAKE_EAR
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE
  mov rbx, r10
  add rbx, EAR_OFFSET
  mov rcx, r11
  add rcx, 16 
  mov rdx, EAR_LENGTH
  mov r8, EAR_THICK
  mov r9d, COLOR_SNAKE_EAR
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE

.check_tongue:
  mov cl, byte [snake_x]
  mov ch, byte [snake_y]
  mov dl, byte [food_x]
  mov dh, byte [food_y]
  
  mov al, byte [last_moved_dir]
  cmp al, 0
  je .tongue_up
  cmp al, 1
  je .tongue_down
  cmp al, 2
  je .tongue_left
  jmp .tongue_right

.tongue_up:
  cmp cl, dl          
  jne .done
  cmp ch, dh          
  jle .done
  mov al, ch          
  sub al, dh
  cmp al, 3           
  jg .done
  mov rbx, r10
  add rbx, TONGUE_OFFSET
  mov rcx, r11
  sub rcx, TONGUE_L
  mov rdx, TONGUE_W
  mov r8, TONGUE_L
  jmp .draw_tongue

.tongue_down:
  cmp cl, dl
  jne .done
  cmp dh, ch          
  jle .done
  mov al, dh
  sub al, ch
  cmp al, 3
  jg .done
  mov rbx, r10
  add rbx, TONGUE_OFFSET
  mov rcx, r11
  add rcx, HEAD_SIZE
  mov rdx, TONGUE_W
  mov r8, TONGUE_L
  jmp .draw_tongue

.tongue_left:
  cmp ch, dh          
  jne .done
  cmp cl, dl          
  jle .done
  mov al, cl
  sub al, dl
  cmp al, 3
  jg .done
  mov rbx, r10
  sub rbx, TONGUE_L
  mov rcx, r11
  add rcx, TONGUE_OFFSET
  mov rdx, TONGUE_L
  mov r8, TONGUE_W
  jmp .draw_tongue

.tongue_right:
  cmp ch, dh
  jne .done
  cmp dl, cl
  jle .done
  mov al, dl
  sub al, cl
  cmp al, 3
  jg .done
  mov rbx, r10
  add rbx, HEAD_SIZE
  mov rcx, r11
  add rcx, TONGUE_OFFSET
  mov rdx, TONGUE_L
  mov r8, TONGUE_W

.draw_tongue:
  mov qword [t_x], rbx
  mov qword [t_y], rcx
  mov qword [t_w], rdx
  mov qword [t_h], r8
  mov r9d, COLOR_TONGUE
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE

.done:
  pop r11
  pop r10
  pop r9
  pop r8
  pop rdx
  pop rcx
  pop rbx
  pop rax
  ret

draw_block:
  push rbx
  push rcx
  push rdx
  push r8
  push rax

; [DIPERBAIKI] Cara x86_64 aman mengambil AH tanpa REX prefix error
  movzx rbx, al
  imul rbx, rbx, 20
  
  movzx rcx, ax    ; Salin 16-bit (AL dan AH)
  shr rcx, 8       ; Geser 8 bit ke kanan untuk mendapatkan nilai murni AH
  imul rcx, rcx, 20

  mov rdx, 20
  mov r8, 20

  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE

  pop rax
  pop r8
  pop rdx
  pop rcx
  pop rbx
  ret

spawn_food:
.retry:
  mov rax, 0
  mov rbx, 31
  call rand_range
  mov byte [food_x], al

  mov rax, 2
  mov rbx, 23
  call rand_range
  mov byte [food_y], al

  xor rcx, rcx
  movzx rdx, word [snake_len]
  lea rdi, [snake_x]
  lea rsi, [snake_y]
.check_loop:
  mov al, byte [rdi + rcx]
  mov ah, byte [rsi + rcx]
  cmp al, byte [food_x]
  jne .no_collision
  cmp ah, byte [food_y]
  je .retry
.no_collision:
  inc rcx
  cmp rcx, rdx
  jl .check_loop
  ret

move_snake:
  movzx rcx, word [snake_len]
  lea rdi, [snake_x]
  lea rsi, [snake_y]
  mov al, byte [rdi + rcx - 1]
  mov ah, byte [rsi + rcx - 1]
  mov byte [prev_tail_x], al
  mov byte [prev_tail_y], ah

  dec rcx
.shift_loop:
  mov al, byte [rdi + rcx - 1]
  mov ah, byte [rsi + rcx - 1]
  mov byte [rdi + rcx], al
  mov byte [rsi + rcx], ah
  dec rcx
  jnz .shift_loop

  mov al, byte [key_head]
  cmp al, byte [key_tail]
  je .no_dequeue
  
  mov al, byte [key_tail]
  lea rbx, [key_queue]
  and al, 3
  movzx rax, al
  mov al, byte [rbx + rax]
  mov byte [snake_dir], al
  inc byte [key_tail]
.no_dequeue:

  mov al, byte [snake_dir]
  mov byte [last_moved_dir], al
  mov al, byte [snake_x]
  mov ah, byte [snake_y]

  cmp byte [snake_dir], 0
  je .go_up
  cmp byte [snake_dir], 1
  je .go_down
  cmp byte [snake_dir], 2
  je .go_left
  cmp byte [snake_dir], 3
  je .go_right
  jmp .done

.go_up:
  dec ah
  cmp ah, 2
  jge .done
  mov ah, 23
  jmp .done
.go_down:
  inc ah
  cmp ah, 24
  jne .done
  mov ah, 2
  jmp .done
.go_left:
  dec al
  cmp al, 0xFF
  jne .done
  mov al, 31
  jmp .done
.go_right:
  inc al
  cmp al, 32
  jne .done
  mov al, 0
  jmp .done

.done:
  mov byte [snake_x], al
  mov byte [snake_y], ah
  ret

check_collisions:
  mov al, byte [snake_x]
  mov ah, byte [snake_y]

  movzx rcx, word [snake_len]
  
  ; Mengurangi radius deteksi tabrakan sebanyak 4 blok memudar dari belakang
  sub rcx, 4
  
  ; Memastikan masih ada sisa blok solid untuk dideteksi
  cmp rcx, 1
  jle .no_collide

  mov rsi, 1
  lea rdi, [snake_x]
  lea rdx, [snake_y]
.self_loop:
  cmp al, byte [rdi + rsi]
  jne .no_match
  cmp ah, byte [rdx + rsi]
  je .collide
.no_match:
  inc rsi
  cmp rsi, rcx
  jl .self_loop

.no_collide:
  ret
.collide:
  mov byte [game_over], 1
  ret

check_food:
  mov al, byte [snake_x]
  mov ah, byte [snake_y]
  cmp al, byte [food_x]
  jne .no_eat
  cmp ah, byte [food_y]
  jne .no_eat

  add word [score], 10
  call draw_header

  movzx rcx, word [snake_len]
  lea rdi, [snake_x]
  lea rsi, [snake_y]
  mov al, byte [prev_tail_x]
  mov byte [rdi + rcx], al
  mov al, byte [prev_tail_y]
  mov byte [rsi + rcx], al

  inc rcx
  mov word [snake_len], cx

  call spawn_food
  jmp .exit

.no_eat:
  mov al, byte [prev_tail_x]
  mov ah, byte [prev_tail_y]

  movzx rcx, word [snake_len]
  lea rdi, [snake_x]
  lea rsi, [snake_y]
  xor rbx, rbx
.overlap_check:
  cmp al, byte [rdi + rbx]
  jne .next_seg
  cmp ah, byte [rsi + rbx]
  je .exit
.next_seg:
  inc rbx
  cmp rbx, rcx
  jl .overlap_check

  mov r9d, COLOR_LCD_BG
  call draw_block

.exit:
  ret

delay:
  push rcx
  push rax
  push rdx
  movzx rax, word [snake_len]
  imul rax, rax, 50000
  mov rcx, 6000000
  sub rcx, rax

  cmp rcx, 500000
  jge .delay_ok
  mov rcx, 500000
.delay_ok:

.chunk_loop:
  mov rdx, 200000
  cmp rcx, rdx
  jge .run_chunk
  mov rdx, rcx
.run_chunk:
  sub rcx, rdx

.inner_loop:
  dec rdx
  jnz .inner_loop

  mov ax, KERNEL_SERVICE_KEYBOARD_key
  int KERNEL_SERVICE
  jz .no_key
  call process_key
.no_key:

  inc qword [rand_seed]
  cmp rcx, 0
  jg .chunk_loop

  pop rdx
  pop rax
  pop rcx
  ret

process_key:
  cmp ax, STATIC_ASCII_ESCAPE
  je .exit_game
  cmp ax, 'w'
  je .up
  cmp ax, 'W'
  je .up
  cmp ax, 0xE048
  je .up
  cmp ax, 's'
  je .down
  cmp ax, 'S'
  je .down
  cmp ax, 0xE050
  je .down
  cmp ax, 'a'
  je .left
  cmp ax, 'A'
  je .left
  cmp ax, 0xE04B
  je .left
  cmp ax, 'd'
  je .right
  cmp ax, 'D'
  je .right
  cmp ax, 0xE04D
  je .right
  ret

.up:
  mov cl, 0
  jmp .enqueue
.down:
  mov cl, 1
  jmp .enqueue
.left:
  mov cl, 2
  jmp .enqueue
.right:
  mov cl, 3
  jmp .enqueue
.exit_game:
  mov byte [game_over], 1
  ret

.enqueue:
  mov al, cl
  xor al, 1
  cmp al, byte [last_added_dir]
  je .ret
  cmp cl, byte [last_added_dir]
  je .ret

  mov al, byte [key_head]
  mov ah, al
  sub ah, byte [key_tail]
  cmp ah, 4
  jge .ret

  mov byte [last_added_dir], cl
  
  lea rbx, [key_queue]
  and al, 3
  movzx rax, al
  mov byte [rbx + rax], cl
  inc byte [key_head]
.ret:
  ret

rand:
  mov rax, qword [rand_seed]
  imul rax, rax, 1103515245
  add rax, 12345
  and rax, 0x7FFFFFFF
  mov qword [rand_seed], rax
  ret

rand_range:
  push rbx
  push rcx
  push rdx

  mov rcx, rbx
  sub rcx, rax
  inc rcx
  push rax

  call rand
  xor rdx, rdx
  div rcx

  pop rax
  add rax, rdx

  pop rdx
  pop rcx
  pop rbx
  ret

init_game:
  xor rbx, rbx
  xor rcx, rcx
  mov rdx, 640
  mov r8, 480
  mov r9d, COLOR_LCD_BG
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE

  xor rbx, rbx
  xor rcx, rcx
  mov rdx, 640
  mov r8, 40
  mov r9d, COLOR_LCD_BG
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE

  xor rbx, rbx
  mov rcx, 38
  mov rdx, 640
  mov r8, 2
  mov r9d, COLOR_BORDER
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE

  mov word [score], 0
  call draw_header

  mov word [snake_len], 4
  mov byte [snake_dir], 0
  mov byte [last_moved_dir], 0 
  mov byte [key_head], 0
  mov byte [key_tail], 0
  mov byte [last_added_dir], 0
  mov qword [t_w], 0 
  
  mov byte [snake_x], 16
  mov byte [snake_y], 10
  mov byte [snake_x + 1], 16
  mov byte [snake_y + 1], 11
  mov byte [snake_x + 2], 16
  mov byte [snake_y + 2], 12
  mov byte [snake_x + 3], 16
  mov byte [snake_y + 3], 13

  call spawn_food

  ; 1. Gambar Kepala
  mov al, byte [snake_x]
  mov ah, byte [snake_y]
  call draw_head 

  ; 2. Gambar Leher
  mov r9d, COLOR_SNAKE
  mov al, byte [snake_x + 1]
  mov ah, byte [snake_y + 1]
  call draw_block

  ; 3. Gambar Sisa Badan Memudar Secara Otomatis
  call draw_tail_fade

  ; 4. Gambar Makanan Inisialisasi
  mov al, byte [food_x]
  mov ah, byte [food_y]
  mov r9d, COLOR_FOOD
  call draw_block

  mov byte [game_over], 0
  ret

draw_header:
  push rax
  push rbx
  push rcx
  push rdx
  push rsi
  push r8
  push r9

  xor rbx, rbx
  xor rcx, rcx
  mov rdx, 640
  mov r8, 38
  mov r9d, COLOR_LCD_BG
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE

  mov r9d, COLOR_BORDER

  mov al, 10
  mov rbx, 16
  mov rcx, 8
  call draw_large_char_rect
  mov al, 11
  mov rbx, 32
  mov rcx, 8
  call draw_large_char_rect
  mov al, 10
  mov rbx, 48
  mov rcx, 8
  call draw_large_char_rect
  mov al, 12
  mov rbx, 64
  mov rcx, 8
  call draw_large_char_rect

  movzx rax, word [score]
  xor rdx, rdx
  mov rbx, 100
  div rbx
  inc rax

  mov rbx, 84
  mov rcx, 8
  call draw_large_number_left

  mov ax, word [score]
  mov rbx, 624
  mov rcx, 8
  call draw_large_number_right

  pop r9
  pop r8
  pop rsi
  pop rdx
  pop rcx
  pop rbx
  pop rax
  ret

draw_title_menu:
  push rax
  push rbx
  push rcx
  push rdx
  push rsi
  push r8

  xor rbx, rbx
  xor rcx, rcx
  mov rdx, 640
  mov r8, 480
  mov r9d, COLOR_LCD_BG
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE

  mov r9d, COLOR_SNAKE

  mov eax, 0x0608
  call draw_block
  mov eax, 0x0708
  call draw_block
  mov eax, 0x0808
  call draw_block
  mov eax, 0x0908
  call draw_block
  mov eax, 0x0A08
  call draw_block
  mov eax, 0x0A09
  call draw_block
  mov eax, 0x060A
  call draw_block
  mov eax, 0x070A
  call draw_block
  mov eax, 0x080A
  call draw_block
  mov eax, 0x090A
  call draw_block
  mov eax, 0x0A0A
  call draw_block

  mov eax, 0x060C
  call draw_block
  mov eax, 0x070C
  call draw_block
  mov eax, 0x080C
  call draw_block
  mov eax, 0x090C
  call draw_block
  mov eax, 0x0A0C
  call draw_block
  mov eax, 0x0A0D
  call draw_block
  mov eax, 0x0A0E
  call draw_block

  mov eax, 0x0610
  call draw_block
  mov eax, 0x0710
  call draw_block
  mov eax, 0x0810
  call draw_block
  mov eax, 0x0910
  call draw_block
  mov eax, 0x0A10
  call draw_block
  mov eax, 0x0611
  call draw_block
  mov eax, 0x0612
  call draw_block
  mov eax, 0x0811
  call draw_block
  mov eax, 0x0812
  call draw_block
  mov eax, 0x0A11
  call draw_block
  mov eax, 0x0A12
  call draw_block

  mov eax, 0x0614
  call draw_block
  mov eax, 0x0714
  call draw_block
  mov eax, 0x0814
  call draw_block
  mov eax, 0x0914
  call draw_block
  mov eax, 0x0A14
  call draw_block
  mov eax, 0x0615
  call draw_block
  mov eax, 0x0616
  call draw_block
  mov eax, 0x0716
  call draw_block
  mov eax, 0x0816
  call draw_block
  mov eax, 0x0815
  call draw_block
  mov eax, 0x0915
  call draw_block
  mov eax, 0x0A16
  call draw_block

  mov rbx, 22
  shl rbx, 32
  or rbx, 40
  mov ax, KERNEL_SERVICE_VIDEO_cursor_set
  int KERNEL_SERVICE

  lea rsi, [menu_prompt_text]
  mov rcx, 25
  mov ax, KERNEL_SERVICE_VIDEO_string
  int KERNEL_SERVICE

  pop r8
  pop rsi
  pop rdx
  pop rcx
  pop rbx
  pop rax
  ret

draw_gameover_screen:
  push rax
  push rbx
  push rcx
  push rdx
  push rsi
  push r8

  mov r9d, COLOR_FOOD

  mov eax, 0x0604
  call draw_block
  mov eax, 0x0704
  call draw_block
  mov eax, 0x0804
  call draw_block
  mov eax, 0x0904
  call draw_block
  mov eax, 0x0A04
  call draw_block
  mov eax, 0x0805
  call draw_block
  mov eax, 0x0905
  call draw_block
  mov eax, 0x0A05
  call draw_block
  mov eax, 0x0606
  call draw_block
  mov eax, 0x0706
  call draw_block
  mov eax, 0x0806
  call draw_block
  mov eax, 0x0906
  call draw_block
  mov eax, 0x0A06
  call draw_block

  mov eax, 0x0608
  call draw_block
  mov eax, 0x0708
  call draw_block
  mov eax, 0x0808
  call draw_block
  mov eax, 0x0908
  call draw_block
  mov eax, 0x0A08
  call draw_block
  mov eax, 0x0609
  call draw_block
  mov eax, 0x0809
  call draw_block
  mov eax, 0x060A
  call draw_block
  mov eax, 0x070A
  call draw_block
  mov eax, 0x080A
  call draw_block
  mov eax, 0x090A
  call draw_block
  mov eax, 0x0A0A
  call draw_block

  mov eax, 0x060C
  call draw_block
  mov eax, 0x070C
  call draw_block
  mov eax, 0x080C
  call draw_block
  mov eax, 0x0A0C
  call draw_block
  mov eax, 0x060D
  call draw_block
  mov eax, 0x080D
  call draw_block
  mov eax, 0x0A0D
  call draw_block
  mov eax, 0x060E
  call draw_block
  mov eax, 0x080E
  call draw_block
  mov eax, 0x090E
  call draw_block
  mov eax, 0x0A0E
  call draw_block

  mov eax, 0x0610
  call draw_block
  mov eax, 0x0611
  call draw_block
  mov eax, 0x0711
  call draw_block
  mov eax, 0x0811
  call draw_block
  mov eax, 0x0911
  call draw_block
  mov eax, 0x0A11
  call draw_block
  mov eax, 0x0612
  call draw_block

  mov eax, 0x0614
  call draw_block
  mov eax, 0x0714
  call draw_block
  mov eax, 0x0814
  call draw_block
  mov eax, 0x0914
  call draw_block
  mov eax, 0x0A14
  call draw_block
  mov eax, 0x0615
  call draw_block
  mov eax, 0x0616
  call draw_block
  mov eax, 0x0815
  call draw_block
  mov eax, 0x0816
  call draw_block
  mov eax, 0x0A15
  call draw_block
  mov eax, 0x0A16
  call draw_block

  mov eax, 0x0618
  call draw_block
  mov eax, 0x0718
  call draw_block
  mov eax, 0x0818
  call draw_block
  mov eax, 0x0918
  call draw_block
  mov eax, 0x0A18
  call draw_block
  mov eax, 0x0619
  call draw_block
  mov eax, 0x0A19
  call draw_block
  mov eax, 0x071A
  call draw_block
  mov eax, 0x081A
  call draw_block
  mov eax, 0x091A
  call draw_block

  mov rbx, 21
  shl rbx, 32
  or rbx, 36
  mov ax, KERNEL_SERVICE_VIDEO_cursor_set
  int KERNEL_SERVICE

  lea rsi, [gameover_prompt_text]
  mov rcx, 31
  mov ax, KERNEL_SERVICE_VIDEO_string
  int KERNEL_SERVICE

  pop r8
  pop rsi
  pop rdx
  pop rcx
  pop rbx
  pop rax
  ret

draw_large_char_rect:
  push rax
  push rbx
  push rcx
  push rdx
  push rsi
  push rdi
  push r8
  push r9
  push r10
  push r11

  mov r10, rbx
  mov r11, rcx

  movzx rax, al
  imul rax, rax, 12
  lea rsi, [large_font_matrix]
  add rsi, rax

  mov bl, 0
.row_loop:
  mov cl, 5
.bit_loop:
  movzx rax, cl
  bt word [rsi], ax
  jnc .bit_done

  movzx rdx, cl
  mov r8, 5
  sub r8, rdx
  shl r8, 1
  add r8, r10

  movzx rdx, bl
  shl rdx, 1
  add rdx, r11

  push rbx
  push rcx
  push rdx
  push r8
  push r9

  mov rbx, r8
  mov rcx, rdx
  mov rdx, 2
  mov r8, 2
  mov ax, KERNEL_SERVICE_VIDEO_rect
  int KERNEL_SERVICE

  pop r9
  pop r8
  pop rdx
  pop rcx
  pop rbx

.bit_done:
  dec cl
  jns .bit_loop

  inc rsi
  inc bl
  cmp bl, 12
  jl .row_loop

  pop r11
  pop r10
  pop r9
  pop r8
  pop rdi
  pop rsi
  pop rdx
  pop rcx
  pop rbx
  pop rax
  ret

draw_large_number_left:
  push rax
  push rbx
  push rcx
  push rdx
  push rsi
  push r8
  push r9

  movzx rax, ax
  xor rsi, rsi
.push_loop:
  xor rdx, rdx
  mov rdi, 10
  div rdi
  push rdx
  inc rsi
  test rax, rax
  jnz .push_loop

.pop_loop:
  pop rdx
  push rbx
  push rcx
  push rdx
  push rsi
  mov al, dl
  call draw_large_char_rect
  pop rsi
  pop rdx
  pop rcx
  pop rbx

  add rbx, 16
  dec rsi
  jnz .pop_loop

  pop r9
  pop r8
  pop rsi
  pop rdx
  pop rcx
  pop rbx
  pop rax
  ret

draw_large_number_right:
  push rax
  push rbx
  push rcx
  push rdx
  push rsi
  push r8
  push r9

  movzx rax, ax
.digit_loop:
  xor rdx, rdx
  mov rdi, 10
  div rdi
  push rax
  push rbx
  push rcx
  push rdx
  mov al, dl
  call draw_large_char_rect
  pop rdx
  pop rcx
  pop rbx
  pop rax

  sub rbx, 16

  test rax, rax
  jnz .digit_loop

  pop r9
  pop r8
  pop rsi
  pop rdx
  pop rcx
  pop rbx
  pop rax
  ret

section .data

score           dw 0
snake_len       dw 0
snake_dir       db 0
last_moved_dir  db 0 
game_over       db 0

key_queue       times 4 db 0
key_head        db 0
key_tail        db 0
last_added_dir  db 0

food_x          db 0
food_y          db 0

prev_tail_x     db 0
prev_tail_y     db 0

lvl_text             db "LVL.    "
score_spaces         db "      "
menu_prompt_text     db "Tekan Enter Untuk Memulai"
wasted_text          db "WASTED"
score_label_text     db "SKOR ANDA: "
gameover_prompt_text db "Enter : Main Lagi, Esc : Keluar"

rand_seed dq 0x12345678

t_x dq 0
t_y dq 0
t_w dq 0
t_h dq 0

snake_x times 1024 db 0
snake_y times 1024 db 0

large_font_matrix:
  db 0x00, 0x00, 0x00, 0x1c, 0x22, 0x22, 0x2a, 0x22, 0x22, 0x1c, 0x00, 0x00
  db 0x00, 0x00, 0x00, 0x08, 0x18, 0x08, 0x08, 0x08, 0x08, 0x1c, 0x00, 0x00
  db 0x00, 0x00, 0x00, 0x1c, 0x22, 0x02, 0x04, 0x08, 0x10, 0x3e, 0x00, 0x00
  db 0x00, 0x00, 0x00, 0x1c, 0x22, 0x02, 0x0c, 0x02, 0x22, 0x1c, 0x00, 0x00
  db 0x00, 0x00, 0x00, 0x04, 0x0c, 0x14, 0x24, 0x3e, 0x04, 0x04, 0x00, 0x00
  db 0x00, 0x00, 0x00, 0x3e, 0x20, 0x20, 0x3c, 0x02, 0x22, 0x1c, 0x00, 0x00
  db 0x00, 0x00, 0x00, 0x0c, 0x10, 0x20, 0x3c, 0x22, 0x22, 0x1c, 0x00, 0x00
  db 0x00, 0x00, 0x00, 0x3e, 0x02, 0x04, 0x08, 0x08, 0x10, 0x10, 0x00, 0x00
  db 0x00, 0x00, 0x00, 0x1c, 0x22, 0x22, 0x1c, 0x22, 0x22, 0x1c, 0x00, 0x00
  db 0x00, 0x00, 0x00, 0x1c, 0x22, 0x22, 0x1e, 0x02, 0x04, 0x18, 0x00, 0x00
  db 0x00, 0x00, 0x00, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x3e, 0x00, 0x00
  db 0x00, 0x00, 0x00, 0x22, 0x22, 0x22, 0x22, 0x14, 0x14, 0x08, 0x00, 0x00
  db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x00, 0x00, 0x00