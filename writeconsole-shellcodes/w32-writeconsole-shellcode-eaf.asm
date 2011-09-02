; Copyright (c) 2006-2010, Berend-Jan "SkyLined" Wever <berendjanwever@gmail.com>
; Project homepage: http://code.google.com/p/testival/
; All rights reserved. See COPYRIGHT.txt for details.
BITS 32
SECTION .text
; Windows x86 null-free shellcode that writes "Hello, world!" to stdout.
; Works in any console application for Windows 5.0-7.0 all service packs.
; (See http://skypher.com/wiki/index.php/Hacking/Shellcode).
; This version uses 16-bit hashes.

%define message `Hello, world!\r\n`
%strlen sizeof_message message

%include "w32-writeconsole-shellcode-hash-list.asm"

%define B2W(b1,b2)                      (((b2) << 8) + (b1))
%define W2DW(w1,w2)                     (((w2) << 16) + (w1))
%define B2DW(b1,b2,b3,b4)               (((b4) << 24) + ((b3) << 16) + ((b2) << 8) + (b1))

global shellcode
shellcode:
global _shellcode
_shellcode:
%ifdef STACK_ALIGN
    AND     SP, 0xFFFC
%endif
    PUSH    W2DW(hash_kernel32_FlushFileBuffers, hash_kernel32_ExitProcess)
    PUSH    W2DW(hash_kernel32_GetStdHandle, hash_kernel32_WriteFile) ;
    MOV     EDI, ESP                    ;
    PUSH    BYTE -11                    ; GetStdHandle(nStdHandle) = STD_OUTPUT_HANDLE
    POP     ESI

next_hash:
    PUSH    ESI ; PUSH STD_OUTPUT_HANDLE or GetStdHandle(STD_OUTPUT_HANDLE) as follows:
    ; GetStdHandle():     __in  DWORD nStdHandle = STD_OUTPUT_HANDLE
    ; WriteConsole():     __in  HANDLE hFile = GetStdHandle(STD_OUTPUT_HANDLE)
    ; FlushFileBuffers(): __in  HANDLE hFile = GetStdHandle(STD_OUTPUT_HANDLE)
    ; RtlExitUserProcess(): __in  UINT uExitCode = GetStdHandle(STD_OUTPUT_HANDLE)
    XOR     EAX, EAX                    ; EAX = 0
; Find base address of kernel32.dll. This code should work on Windows 5.0-7.0
    MOV     ESI, [FS:EAX + 0x30]        ; ESI = &(PEB) ([FS:0x30])
    MOV     ESI, [ESI + 0x0C]           ; ESI = PEB->Ldr
    MOV     ESI, [ESI + 0x1C]           ; ESI = PEB->Ldr.InInitOrder (first module)

; The first loaded module is ntdll on x86 systems and ntdll32 on x64 systems. Both modules have this code:
; 76fba03c ntdll32!RtlGetCurrentPeb (<no parameter info>)
;     76fba03c 64a118000000    mov     eax,dword ptr fs:[00000018h]
;     76fba042 8b4030          mov     eax,dword ptr [eax+30h]
;     76fba045 c3              ret
%define MEMORY_READER_OFFSET 0x30
    MOV     EDX, [ESI + 0x08]           ; EDX = InInitOrder[X].base_address == module
    MOVZX   EBP, WORD [EDX + 0x3C]      ; EBX = module->pe_header_offset
    ADD     EDX, [EDX + EBP + 0x2C]     ; EDX = module + module.pe_header->code_offset == module code
scan_for_memory_reader:
    INC     EDX
    CMP     DWORD [EDX], 0xC330408B     ; EDX => MOV EAX, [EAX+30], RET ?
    JNE     scan_for_memory_reader
    PUSH    EDX                         ; Save &(MOV EAX, [EAX+30], RET)
next_module:
    MOV     EBP, [ESI + 0x08]           ; EBP = InInitOrder[X].base_address
    MOV     ESI, [ESI]                  ; ESI = InInitOrder[X].flink == InInitOrder[X+1]
get_proc_address_loop:
; Find the PE header and export and names tables of the module:
    MOV     EBX, [EBP + 0x3C]           ; EBX = &(PE header)
    MOV     EBX, [EBP + EBX + 0x78]     ; EBX = offset(export table)
    ADD     EBX, EBP                    ; EBX = &(export table)
; Hash each function name and check it against the requested hash:
    MOV     ECX, [EBX + 0x18]           ; ECX = number of name pointers
next_function_loop:
; Get the next function name:
    PUSH    EDI
    MOV     EDI, [EBX + 0x20]           ; EDI = offset(names table)
    ADD     EDI, EBP                    ; EDI = &(names table)
    MOV     EDI, [EDI + ECX * 4 - 4]    ; EDI = offset(function name)
    ADD     EDI, EBP                    ; EDI = &(function name)
    CDQ                                 ; EDX = 0
hash_loop:
    XOR     DL, [EDI]
    ROR     DX, hash_ror_value
    SCASB
    JNE     hash_loop
    POP     EDI
    CMP     DX, [EDI]
    LOOPNE  next_function_loop
    JNE     next_module
; Find the address of the requested function:
    MOV     EDX, [EBX + 0x24]           ; EDI = offset ordinals table
    ADD     EDX, EBP                    ; EDI = &oridinals table
    MOVZX   EDX, WORD [EDX + 2 * ECX]   ; ECX = ordinal number of function
    XCHG    EAX, ECX                    ; ECX = 0
    LEA     EAX, [EBX + 0x1C - MEMORY_READER_OFFSET]     ; EAX = &offset address table - MEMORY_READER_OFFSET
    POP     ESI                         ; ESI = &(MOV EAX, [EAX+30], RET) 
    CALL    ESI                         ; EAX = [EAX + 0x30] == [&offset address table] == offset address table
    XCHG    EAX, ECX                    ; ECX = offset address table, EAX = 0
    ADD     ECX, EBP                    ; ECX = &address table
    MOV     EDX, [ECX + 4 * EDX]        ; EAX = offset function in DLL
    ADD     EDX, EBP                    ; EAX = &(function)
    POP     ESI
    PUSH    ESI
    CALL    EDX
    CMP     EDI, ESP
    JNE     not_GetStdHandle
    MOV     ESI, EAX                    ; Save result of GetStdHandle(STD_OUTPUT_HANDLE) in ESI
not_GetStdHandle:
    XOR     EDX, EDX                    ; EDX = 0
    PUSH    ESP                         ; [ESP] = ESP+4
    XCHG    EDX, [ESP]                  ; EDX = ESP+4, __inout_opt  LPOVERLAPPED lpOverlapped = NULL
    PUSH    EDX                         ; __out_opt    LPDWORD lpNumberOfBytesWritten = ESP+4 (whatever)
    PUSH    BYTE sizeof_message         ; __in         DWORD nNumberOfBytesToWrite = strlen(message)
    SCASW                               ; Next hash
    CALL    next_hash                   ; __in         LPCVOID lpBuffer = message
    db      message
