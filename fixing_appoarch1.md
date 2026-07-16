# **Software Requirements Specification (SRS): LunaOS `ip` Command — Bug Fix & Correct Implementation**

**Document Version:** 2.0 (Revised based on actual runtime behavior)
**Date:** 2026-07-16
**Project:** LunaOS (https://github.com/slowy07/LunaOs)
**Feature:** Fix `ip` command to display IP address instead of debug/task dump

---

## **0. Critical Finding: Current State Analysis**

### **0.1 Observed Behavior (from screenshot)**

When user types `ip` and presses **Enter**, the system displays:

```
Task queue properties (Size CBytes/Task Count/Free): 4088 4 9
Pages (Total/Used/Free): 224 102 122

Memory
Address            Content
00000000010700     00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00000000010710     FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
...
```

This is **task queue properties + page statistics + memory hex dump** — NOT IP address information.

### **0.2 Root Cause Hypothesis**

Based on the project documentation structure 【turn0fetch0】:

| Likely Source | Doc Reference | Why |
|---|---|---|
| **Debug mode handler** | `kernel/docs/debug.txt` — "Debug mode handler (register dump, process name, PID)" | Shows memory dump, task info |
| **Task scheduler debug** | `kernel/docs/task.txt` — "Task scheduler" | Shows task queue properties |
| **Prompt dispatch misrouting** | `kernel/service/docs/prompt.txt` — "Command dispatch (clear, ip, etc.)" | `ip` string is matched to wrong handler |

**Most probable cause:** In `kernel/service/shell.asm` (or the prompt dispatch section), the string comparison for `"ip"` is either:
1. **Incorrectly branching** to the debug/task-dump routine instead of a network IP routine.
2. **The `ip` handler was never implemented**, and the dispatch falls through to a default debug display.
3. **String matching collision** — the 2-byte string `"ip"` partially matches another token or the comparison logic is flawed (e.g., only comparing first 2 bytes of a longer command).

### **0.3 Impact**

| Severity | Description |
|---|---|
| **HIGH** | The `ip` command is documented in `prompt.txt` as a valid command 【turn0fetch0】【turn1search0】 but produces completely incorrect output. Users cannot retrieve network IP information. |

---

## **1. Introduction & Background**

### **1.1 Purpose**
This document defines the requirements for **fixing** the `ip` command in LunaOS's interactive shell so that it correctly displays the network IP address, replacing the current incorrect debug/task-dump output.

### **1.2 Project Context**
LunaOS is a multitasking OS written in x86-64 assembly with:
- **Shell service** (`kernel/service/docs/shell.txt`, `prompt.txt`) — command dispatch loop 【turn0fetch0】
- **Network service** (`kernel/service/docs/network.txt`) — ARP, ICMP, TCP, config wrapper 【turn0fetch0】
- **Intel 82540EM driver** (`kernel/driver/network/i82540em.txt`) 【turn0fetch0】
- **Debug handler** (`kernel/docs/debug.txt`) — register dump, process name, PID, memory dump 【turn0fetch0】
- **Task scheduler** (`kernel/docs/task.txt`) — task queue management 【turn0fetch0】
- **IPC system** (`kernel/docs/ipc.txt`) — inter-process communication 【turn0fetch0】

### **1.3 Scope**
- **In-Scope:** Fix the `ip` command dispatch, implement correct IP address retrieval and display.
- **Out-of-Scope:** Changing the debug/task-dump functionality (it should remain accessible via its own correct command, if any). Network configuration changes.

---

## **2. Requirements**

### **2.1 Functional Requirements**

| ID | Requirement | Description | Priority |
|---|---|---|---|
| **FR-01** | **Remove incorrect routing** | The `ip` command must NO LONGER display task queue properties, page statistics, or memory hex dump. | **MUST** |
| **FR-02** | **Command recognition** | Shell dispatcher (`prompt.txt` logic) shall recognize exact string `"ip"` (case-sensitive, null-terminated, length=2) as a distinct command. | **MUST** |
| **FR-03** | **Display IP address** | Upon `ip` command, display: `IP Address: <x.x.x.x>` where `<x.x.x.x>` is the primary IPv4 address of the first network interface. | **MUST** |
| **FR-04** | **Query network service** | Shell shall send IPC message to network service requesting the IP address. | **MUST** |
| **FR-05** | **Network service responds** | Network service shall read IP from NIC state and return it as null-terminated dotted-decimal string via IPC. | **MUST** |
| **FR-06** | **Error: no IP** | If NIC has no IP assigned, display: `Error: No IP address assigned.` | **MUST** |
| **FR-07** | **Error: service down** | If network service IPC times out, display: `Error: Unable to contact network service.` | **SHOULD** |
| **FR-08** | **Preserve debug output** | The task queue + memory dump currently shown by `ip` must still be accessible through its **correct** command (if one exists), or documented as moved. | **SHOULD** |

### **2.2 Non-Functional Requirements**

| ID | Requirement | Target |
|---|---|---|
| **NFR-01** | Response time | < 2 seconds |
| **NFR-02** | No kernel panic | Must not crash even if network service is down |
| **NFR-03** | Minimal code size | Consistent with assembly-level optimization |
| **NFR-04** | Documentation updated | `shell.txt`, `prompt.txt`, `network.txt` updated |

---

## **3. Investigation Tasks (MUST complete before coding)**

The agent **MUST** read the following source files to understand the bug:

| # | File to Read | Purpose |
|---|---|---|
| **1** | `kernel/service/docs/prompt.txt` | Understand how commands are dispatched, find the `ip` entry point |
| **2** | `kernel/service/docs/shell.txt` | Understand the shell loop structure |
| **3** | `kernel/service/docs/network.txt` | Understand existing IPC interface, data structures for IP storage |
| **4** | `kernel/service/docs/network/data.txt` | Find where IP address is stored in memory |
| **5** | `kernel/docs/debug.txt` | Confirm that the task queue + memory dump output comes from here |
| **6** | `kernel/docs/task.txt` | Confirm task queue properties output source |
| **7** | `kernel/service/shell.asm` | **Actual source code** — find the `ip` string comparison and branch target |
| **8** | `kernel/service/network.asm` | **Actual source code** — find where IP address is stored/accessible |

### **3.1 What to Look For in `shell.asm`**

Search for the command dispatch section. It will likely look similar to:

```assembly
; Pseudocode of EXPECTED structure in shell.asm
command_dispatch:
    ; Compare user input with known commands
    cmp dword [input_buffer], 'cler'  ; "clear"
    je .cmd_clear
    
    cmp dword [input_buffer], 'ip  '  ; "ip" + padding
    je .cmd_ip                         ; <--- FIND THIS BRANCH
    
    cmp dword [input_buffer], 'free'  ; "free"
    je .cmd_free
    
    ; ... more commands ...
    jmp .cmd_unknown
```

**The bug is likely one of:**

```assembly
; BUG SCENARIO A: Branch points to wrong label
    cmp dword [input_buffer], 'ip  '
    je .cmd_debug_dump        ; <--- WRONG! Points to debug handler

; BUG SCENARIO B: No handler exists, falls through
    cmp dword [input_buffer], 'ip  '
    je .cmd_ip
    ; .cmd_ip doesn't exist or is empty, falls through to next label
.cmd_debug_dump:              ; <--- Accidentally executes this
    ; prints task queue, pages, memory dump...

; BUG SCENARIO C: String comparison is wrong
    cmp word [input_buffer], 'ip'     ; Only 2 bytes, no null/pad check
    je .cmd_something_else    ; Matches "ip" but also "ipconfig" prefix etc.

; BUG SCENARIO D: The label .cmd_ip exists but calls debug function
.cmd_ip:
    call debug_task_queue     ; <--- Copied from debug, never replaced
    ret
```

### **3.2 What to Look For in `network.asm` / `network/data.txt`**

Find where the IP address is stored after DHCP/static configuration:

```assembly
; Expected in network/data.txt or network.asm data section
section .data
    nic_ip_address: db "192.168.1.100", 0   ; <--- FIND THIS
    nic_ip_octets:    db 192, 168, 1, 100   ; <--- OR THIS (needs conversion)
    nic_status:       db 1                   ; 1=up, 0=down
```

---

## **4. Implementation Requirements**

### **4.1 Changes to `kernel/service/shell.asm`**

#### **Step 1: Locate and fix the dispatch**

Find the `ip` comparison block. Ensure it:
1. Compares exactly 2 bytes + null/pad (not partial match)
2. Branches to a NEW `.cmd_ip` label (not the debug dump label)

```assembly
; CORRECT implementation
    cmp dword [input_buffer], 'ip  '   ; "ip" + 2 space pads (or nulls)
    je .cmd_ip
```

#### **Step 2: Implement `.cmd_ip` handler**

```assembly
.cmd_ip:
    ; --- Send IPC request to Network Service ---
    mov rax, IPC_SEND_MSG            ; Syscall number for IPC send
    mov rcx, NETWORK_SERVICE_ID      ; Network service port/ID
    mov rdx, MSG_TYPE_GET_IP         ; Request type constant (e.g., 0x01)
    mov r8, input_buffer             ; Buffer for response
    mov r9, 32                       ; Max response size
    syscall

    ; --- Check if IPC succeeded ---
    test rax, rax
    jz .ip_error_service             ; rax == 0 means timeout/failure

    ; --- Check response status byte ---
    cmp byte [input_buffer], 0x00    ; 0x00 = STATUS_OK
    jne .ip_error_no_ip

    ; --- Print "IP Address: " ---
    mov rsi, str_ip_prefix
    call shell_print_string

    ; --- Print IP address (starts at offset 1 in response buffer) ---
    lea rsi, [input_buffer + 1]
    call shell_print_string

    ; --- Print newline ---
    mov rsi, str_newline
    call shell_print_string

    jmp .command_done

.ip_error_no_ip:
    mov rsi, str_err_no_ip
    call shell_print_string
    jmp .command_done

.ip_error_service:
    mov rsi, str_err_service
    call shell_print_string
    jmp .command_done
```

#### **Step 3: Add string constants to data section**

```assembly
section .data
    str_ip_prefix:     db "IP Address: ", 0
    str_err_no_ip:     db "Error: No IP address assigned.", 10, 0
    str_err_service:   db "Error: Unable to contact network service.", 10, 0
    str_newline:       db 10, 0
```

### **4.2 Changes to `kernel/service/network.asm`**

#### **Step 1: Add IPC message handler for GET_IP**

In the network service's IPC receive loop, add a case for the new message type:

```assembly
; Inside network service IPC dispatch loop
.network_ipc_dispatch:
    cmp byte [ipc_msg_type], MSG_TYPE_GET_IP    ; e.g., 0x01
    je .net_handle_get_ip

    ; ... other existing handlers (HTTP, TX, etc.) ...
    jmp .net_ipc_unknown

.net_handle_get_ip:
    ; Check if NIC is up and has IP
    cmp byte [nic_status], 1
    jne .net_get_ip_fail

    ; Check if IP address string is non-empty
    cmp byte [nic_ip_address], 0
    je .net_get_ip_fail

    ; Build response: [STATUS_OK] [IP string]
    mov byte [ipc_response_buf], 0x00           ; STATUS_OK
    lea rsi, [nic_ip_address]
    lea rdi, [ipc_response_buf + 1]
    call string_copy                             ; Copy IP string to response

    ; Send response via IPC
    mov rax, IPC_SEND_REPLY
    mov rcx, ipc_response_buf
    mov rdx, rsi                                 ; Length
    syscall
    jmp .net_ipc_done

.net_get_ip_fail:
    mov byte [ipc_response_buf], 0x01           ; STATUS_NO_IP
    mov byte [ipc_response_buf + 1], 0          ; Empty string
    mov rax, IPC_SEND_REPLY
    mov rcx, ipc_response_buf
    mov rdx, 2
    syscall
    jmp .net_ipc_done
```

### **4.3 Documentation Updates**

#### **`kernel/service/docs/prompt.txt`** — Update command table:

```text
COMMAND DISPATCH TABLE
======================
Command    Handler           Description
--------   --------          -----------
clear      .cmd_clear        Clear screen
ip         .cmd_ip           Show primary IP address of NIC
free       .cmd_free         Show memory usage
...
```

#### **`kernel/service/docs/shell.txt`** — Add section:

```text
IP COMMAND
----------
Handler: .cmd_ip
Input: User types "ip" at shell prompt
Output: "IP Address: x.x.x.x" or error message
Mechanism: IPC query to network service (MSG_TYPE_GET_IP = 0x01)
Response format: [1 byte status] [N bytes IP string null-terminated]
Error codes: 0x00=OK, 0x01=NO_IP, 0x02=ERROR
```

#### **`kernel/service/docs/network.txt`** — Add IPC interface:

```text
IPC INTERFACE - GET_IP
----------------------
Message Type: 0x01 (MSG_TYPE_GET_IP)
Request: Empty (type byte only)
Response: [status:u8] [ip_string:null-terminated]
  status = 0x00 : OK, ip_string contains "x.x.x.x"
  status = 0x01 : NO_IP, ip_string is empty
  status = 0x02 : ERROR, ip_string is empty
```

---

## **5. Test Cases**

| ID | Scenario | Steps | Expected Result | Priority |
|---|---|---|---|---|
| **TC-01** | **Fix verified: no more debug dump** | Type `ip` + Enter | Must NOT show task queue, pages, or memory dump | **MUST** |
| **TC-02** | **IP displayed correctly** | Boot with network up, type `ip` | `IP Address: x.x.x.x` with valid IPv4 | **MUST** |
| **TC-03** | **No IP configured** | Boot with network down, type `ip` | `Error: No IP address assigned.` | **MUST** |
| **TC-04** | **Case sensitivity** | Type `IP` or `Ip` | Unknown command or no match | **MUST** |
| **TC-05** | **Service timeout** | Kill network service, type `ip` | `Error: Unable to contact network service.` | **SHOULD** |
| **TC-06** | **Regression: other commands** | Type `clear`, `free`, etc. | All other commands still work correctly | **MUST** |
| **TC-07** | **Debug dump still accessible** | Type whatever command shows task queue (if any) | Debug output still works via its correct command | **SHOULD** |

---

## **6. Acceptance Criteria**

- [ ] **AC-01:** Typing `ip` + Enter **never** shows task queue properties, page stats, or memory hex dump
- [ ] **AC-02:** Typing `ip` + Enter shows `IP Address: <valid_ipv4>` when network is configured
- [ ] **AC-03:** Typing `ip` + Enter shows `Error: No IP address assigned.` when network is down
- [ ] **AC-04:** All other shell commands (`clear`, `free`, etc.) remain functional (no regression)
- [ ] **AC-05:** No kernel panic in any scenario
- [ ] **AC-06:** Documentation files (`prompt.txt`, `shell.txt`, `network.txt`) are updated

---

## **7. Risk Summary**

| Risk | Mitigation |
|---|---|
| **Fixing `ip` breaks debug dump access permanently** | Identify which command *should* show the debug dump; if none exists, consider adding a `debug` command |
| **IPC protocol mismatch between shell and network** | Define message format constants in a shared header or document clearly in `network.txt` |
| **IP address stored as raw bytes, not string** | Add byte-to-ASCII conversion in network service before sending IPC response |
| **String comparison in dispatch still buggy after fix** | Use exact 4-byte (`dword`) comparison with padding, matching the pattern of other commands like `clear` |

---

## **8. References**

- LunaOS Repository: [https://github.com/slowy07/LunaOs](https://github.com/slowy07/LunaOs) 【turn0fetch0】
- `kernel/service/docs/prompt.txt` — Command dispatch (lists `ip` as command) 【turn0fetch0】【turn1search0】
- `kernel/service/docs/network.txt` — Network service (7 sub-files) 【turn0fetch0】
- `kernel/docs/debug.txt` — Debug mode handler (register dump, process name, PID) 【turn0fetch0】
- `kernel/docs/task.txt` — Task scheduler 【turn0fetch0】
- `kernel/driver/network/i82540em.txt` — Intel NIC driver 【turn0fetch0】

---

**Document Prepared For:** Agentic Code Generation — Bug Fix
**Critical Instruction:** The agent MUST read the actual `.asm` source files listed in Section 3 before writing any code. The root cause is in the dispatch logic of `kernel/service/shell.asm` where `ip` is incorrectly routed to the debug/task-dump handler.

## Other reference
https://github.com/DietrichGebert/ponytail/tree/main/.opencode/comman kalo dijad
network stack - `https://wiki.osdev.org/Network_Stack`

## positive (do it)

You are a lazy senior developer. Lazy means efficient, not careless. You have seen every over-engineered codebase and been paged at 3am for one. The best code is the code never written.

Forces the laziest solution that actually works, simplest, shortest, most
  minimal. Channels a senior dev who has seen everything: question whether the
  task needs to exist at all (YAGNI), reach for the standard library before
  custom code, native platform features before dependencies, one line before
  fifty. Supports intensity levels: lite, full (default), ultra. Use on ANY
  coding task: writing, adding, refactoring, fixing, reviewing, or designing
  code, and choosing libraries or dependencies. Also use whenever the user
  says "ponytail", "be lazy", "lazy mode", "simplest solution", "minimal
  solution", "yagni", "do less", or "shortest path", or complains about
  over-engineering, bloat, boilerplate, or unnecessary dependencies. Do NOT
  use for non-coding requests (general knowledge, prose, translation,
  summaries, recipes).

### The Ladder

Stop at the first rung that holds:

1. **Does this need to exist at all?** Speculative need = skip it, say so in one line. (YAGNI)
2. **Already in this codebase?** A helper, util, type, or pattern that already lives here → reuse it. Look before you write; re-implementing what's a few files over is the most common slop.
3. **Stdlib does it?** Use it.
5. **Already-installed dependency solves it?** Use it. Never add a new one for what a few lines can do.
6. **Can it be one line?** One line.
7. **Only then:** the minimum code that works.

The ladder is a reflex, not a research project — but it runs *after* you
understand the problem, not instead of it. Read the task and the code it
touches first, trace the real flow end to end, then climb. Two rungs work →
take the higher one and move on. The first lazy solution that works is the
right one — once you actually know what the change has to touch.

**Bug fix = root cause, not symptom.** A report names a symptom. Before you
edit, grep every caller of the function you're about to touch. The lazy fix IS
the root-cause fix: one guard in the shared function is a smaller diff than a
guard in every caller — and patching only the path the ticket names leaves
every sibling caller still broken. Fix it once, where all callers route through.

