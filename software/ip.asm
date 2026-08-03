 %include "config.asm"
 %include "kernel/config.asm"

[BITS 64]

[DEFAULT REL]

[ORG SOFTWARE_base_address]

ip:

 ; Get the IP address from the kernel's network system service
 mov ax, KERNEL_SERVICE_SYSTEM_network
 int KERNEL_SERVICE

 ; Store the returned packed IP address (in r8) to r12
 mov r12, r8

 ; Check if IP is 0.0.0.0 (no IP assigned)
 test r12, r12
 jz .no_ip

 ; Print "IP Address: " prefix
 mov ax, KERNEL_SERVICE_VIDEO_string
 mov ecx, ip_prefix_end - ip_prefix
 mov rsi, ip_prefix
 int KERNEL_SERVICE

 ; Print First Octet (A)
 movzx r8, r12b
 mov ax, KERNEL_SERVICE_VIDEO_number
 mov bl, STATIC_NUMBER_SYSTEM_decimal
 xor ecx, ecx
 int KERNEL_SERVICE

 ; Print dot
 mov ax, KERNEL_SERVICE_VIDEO_char
 mov ecx, 1
 mov dx, '.'
 int KERNEL_SERVICE

 ; Print Second Octet (B)
 mov r8, r12
 shr r8, 8
 movzx r8, r8b
 mov ax, KERNEL_SERVICE_VIDEO_number
 mov bl, STATIC_NUMBER_SYSTEM_decimal
 xor ecx, ecx
 int KERNEL_SERVICE

 ; Print dot
 mov ax, KERNEL_SERVICE_VIDEO_char
 mov ecx, 1
 mov dx, '.'
 int KERNEL_SERVICE

 ; Print Third Octet (C)
 mov r8, r12
 shr r8, 16
 movzx r8, r8b
 mov ax, KERNEL_SERVICE_VIDEO_number
 mov bl, STATIC_NUMBER_SYSTEM_decimal
 xor ecx, ecx
 int KERNEL_SERVICE

 ; Print dot
 mov ax, KERNEL_SERVICE_VIDEO_char
 mov ecx, 1
 mov dx, '.'
 int KERNEL_SERVICE

 ; Print Fourth Octet (D)
 mov r8, r12
 shr r8, 24
 movzx r8, r8b
 mov ax, KERNEL_SERVICE_VIDEO_number
 mov bl, STATIC_NUMBER_SYSTEM_decimal
 xor ecx, ecx
 int KERNEL_SERVICE

 ; Print newline at the end
 mov ax, KERNEL_SERVICE_VIDEO_char
 mov ecx, 1
 mov dx, STATIC_ASCII_NEW_LINE
 int KERNEL_SERVICE

 jmp .exit

.no_ip:
 ; Print "Error: No IP address assigned."
 mov ax, KERNEL_SERVICE_VIDEO_string
 mov ecx, ip_err_no_ip_end - ip_err_no_ip
 mov rsi, ip_err_no_ip
 int KERNEL_SERVICE

.exit:
 ; Exit process
 xor ax, ax
 int KERNEL_SERVICE

section .data
ip_prefix db "IP Address: "
ip_prefix_end:

ip_err_no_ip db "Error: No IP address assigned.", STATIC_ASCII_NEW_LINE
ip_err_no_ip_end:
