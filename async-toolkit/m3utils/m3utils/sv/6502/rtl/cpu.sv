// MOS 6502 CPU -- synthesizable SystemVerilog
//
// Written from scratch based on the 6502 instruction set architecture
// as documented in fake6502.c (public domain, Mike Chambers).
//
// Interface:
//   clk      -- clock
//   reset_n  -- asynchronous reset (active low, async assert / sync deassert)
//   AB[15:0] -- address bus output
//   DI[7:0]  -- data in (memory read)
//   DO[7:0]  -- data out (memory write)
//   WE       -- write enable
//   IRQ      -- interrupt request (active high)
//   NMI      -- non-maskable interrupt (edge-sensitive, active high)
//   RDY      -- ready (pauses CPU when low)
//
// Architecture:
//   Multi-cycle FSM. Each instruction takes 2-7 cycles.
//   State machine fetches opcode, computes effective address,
//   executes operation, and writes back results.
//
module cpu_6502 (
  input  logic        clk,
  input  logic        reset_n,
  output logic [15:0] AB,
  input  logic [7:0]  DI,
  output logic [7:0]  DO,
  output logic        WE,
  input  logic        IRQ,
  input  logic        NMI,
  input  logic        RDY
);

  // Reset synchronizer: async assert, sync deassert
  logic reset_meta, rst_sync_n;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      reset_meta <= 1'b0;
      rst_sync_n <= 1'b0;
    end
    else begin
      reset_meta <= 1'b1;
      rst_sync_n <= reset_meta;
    end
  end

  // Registers
  logic [15:0] PC;
  logic [7:0]  A, X, Y, SP;
  logic [7:0]  P;  // status: NV-BDIZC

  // Status flag positions
  localparam F_C = 0;  // carry
  localparam F_Z = 1;  // zero
  localparam F_I = 2;  // interrupt disable
  localparam F_D = 3;  // decimal
  localparam F_B = 4;  // break
  localparam F_U = 5;  // unused (always 1)
  localparam F_V = 6;  // overflow
  localparam F_N = 7;  // negative/sign

  // Internal registers
  logic [7:0]  opcode;
  logic [7:0]  data_latch;   // latched data byte
  logic [15:0] addr_lo;      // effective address accumulator
  logic [7:0]  bal;          // base address low (for page-cross check)
  logic        nmi_prev;     // previous NMI state for edge detection
  logic        nmi_pending;
  logic        brk_b_flag;   // 1 = software BRK (set B in pushed P)
  logic        brk_nmi;      // 1 = NMI vector (FFFA), 0 = IRQ/BRK vector (FFFE)

  // ALU wires (directly computed, no submodule to keep it all in one file)
  logic [8:0]  alu_sum;
  logic [7:0]  alu_result;
  logic        alu_carry;
  logic [4:0]  bcd_al, bcd_ah;   // BCD low/high nibble accumulators
  logic        bcd_lo_borrow;    // BCD low nibble borrow for SBC

  // FSM states
  typedef enum logic [5:0] {
    S_RESET0,     // reset: read vector low
    S_RESET1,     // reset: read vector high
    S_FETCH,      // fetch opcode
    S_DECODE,     // decode + fetch first operand byte
    S_IMM,        // immediate: operand ready
    S_ZP,         // zero-page: addr ready
    S_ZP_RD,      // zero-page: read memory
    S_ZPX,        // zero-page,X: compute addr
    S_ZPX_RD,     // zero-page,X: read memory
    S_ABS0,       // absolute: fetch addr high
    S_ABS1,       // absolute: addr ready, access memory
    S_ABSX0,      // absolute,X: fetch addr high
    S_ABSX1,      // absolute,X: access memory (or page-cross fix)
    S_ABSY0,      // absolute,Y: fetch addr high
    S_ABSY1,      // absolute,Y: access
    S_INDX0,      // (indirect,X): fetch ptr base
    S_INDX1,      // (indirect,X): fetch ptr+1
    S_INDX2,      // (indirect,X): fetch addr high
    S_INDY0,      // (indirect),Y: fetch ptr low
    S_INDY1,      // (indirect),Y: fetch addr high
    S_INDY2,      // (indirect),Y: access
    S_EXEC,       // execute instruction (write-back to registers/memory)
    S_RMW_WR,     // read-modify-write: write back to memory
    S_PUSH,       // push byte
    S_PULL0,      // pull: dummy read from stack
    S_PULL1,      // pull: read data from stack
    S_JSR0,       // JSR: push PCH
    S_JSR1,       // JSR: push PCL, set PC
    S_RTS0,       // RTS: pull PCL
    S_RTS1,       // RTS: pull PCH, increment
    S_BRK0,       // BRK/IRQ/NMI: push PCL
    S_BRK1,       // BRK/IRQ/NMI: push P
    S_BRK2        // BRK/IRQ/NMI: set up vector read
  } state_t;

  state_t state;

  // Address mode classification from opcode
  logic       is_rmw;        // read-modify-write instruction
  logic       is_store;      // STA, STX, STY
  logic       is_branch;     // conditional branch
  logic       is_implied;    // implied/accumulator addressing
  logic [7:0] exec_operand;  // operand for execution

  // Instruction decode helpers (from opcode)
  // The 6502 opcode layout: aaabbbcc
  // cc=01: group 1 (ORA, AND, EOR, ADC, STA, LDA, CMP, SBC)
  // cc=10: group 2 (ASL, ROL, LSR, ROR, STX, LDX, DEC, INC)
  // cc=00: group 3 (BIT, JMP, STY, LDY, CPY, CPX, branches, flags)
  logic [2:0] aaa;
  logic [2:0] bbb;
  logic [1:0] cc;

  assign aaa = opcode[7:5];
  assign bbb = opcode[4:2];
  assign cc  = opcode[1:0];

  // Forward declarations for execution
  logic [7:0]  next_A, next_X, next_Y, next_SP, next_P;
  logic [15:0] next_PC;
  logic        do_write_mem;
  logic [7:0]  write_data;

  // Branch condition evaluation
  logic branch_taken;
  always_comb begin
    case (aaa)
      3'b000: branch_taken = ~P[F_N]; // BPL
      3'b001: branch_taken =  P[F_N]; // BMI
      3'b010: branch_taken = ~P[F_V]; // BVC
      3'b011: branch_taken =  P[F_V]; // BVS
      3'b100: branch_taken = ~P[F_C]; // BCC
      3'b101: branch_taken =  P[F_C]; // BCS
      3'b110: branch_taken = ~P[F_Z]; // BNE
      3'b111: branch_taken =  P[F_Z]; // BEQ
      default: branch_taken = 1'b0;
    endcase
  end

  // Sign-extend relative address
  logic [15:0] branch_offset;
  assign branch_offset = {{8{data_latch[7]}}, data_latch};

  // Flag update helpers
  function logic [7:0] set_nz(input logic [7:0] val, input logic [7:0] flags);
    set_nz = flags;
    set_nz[F_N] = val[7];
    set_nz[F_Z] = (val == 8'd0);
  endfunction

  // Execution logic: computes new register values based on opcode and operand
  always_comb begin
    next_A  = A;
    next_X  = X;
    next_Y  = Y;
    next_SP = SP;
    next_P  = P;
    next_P[F_U] = 1'b1;  // always set
    next_PC = PC;
    do_write_mem = 1'b0;
    write_data   = 8'd0;
    alu_result   = 8'd0;
    alu_carry    = 1'b0;
    bcd_al       = 5'd0;
    bcd_ah       = 5'd0;
    bcd_lo_borrow = 1'b0;

    case (opcode)
      // --- Group 1: cc=01 ---
      // ORA
      8'h01, 8'h05, 8'h09, 8'h0D, 8'h11, 8'h15, 8'h19, 8'h1D: begin
        alu_result = A | exec_operand;
        next_A = alu_result;
        next_P = set_nz(alu_result, next_P);
      end
      // AND
      8'h21, 8'h25, 8'h29, 8'h2D, 8'h31, 8'h35, 8'h39, 8'h3D: begin
        alu_result = A & exec_operand;
        next_A = alu_result;
        next_P = set_nz(alu_result, next_P);
      end
      // EOR
      8'h41, 8'h45, 8'h49, 8'h4D, 8'h51, 8'h55, 8'h59, 8'h5D: begin
        alu_result = A ^ exec_operand;
        next_A = alu_result;
        next_P = set_nz(alu_result, next_P);
      end
      // ADC
      8'h61, 8'h65, 8'h69, 8'h6D, 8'h71, 8'h75, 8'h79, 8'h7D: begin
        // Binary result (used for N, Z, V flags on NMOS 6502)
        alu_sum = {1'b0, A} + {1'b0, exec_operand} + {8'd0, P[F_C]};
        alu_result = alu_sum[7:0];
        next_P = set_nz(alu_result, next_P);
        next_P[F_V] = (A[7] == exec_operand[7]) && (alu_result[7] != A[7]);
        if (P[F_D]) begin
          // BCD mode: adjust result and carry
          bcd_al = {1'b0, A[3:0]} + {1'b0, exec_operand[3:0]} + {4'd0, P[F_C]};
          if (bcd_al > 5'd9) bcd_al = bcd_al + 5'd6;
          bcd_ah = {1'b0, A[7:4]} + {1'b0, exec_operand[7:4]} + {4'd0, bcd_al[4]};
          if (bcd_ah > 5'd9) bcd_ah = bcd_ah + 5'd6;
          next_A = {bcd_ah[3:0], bcd_al[3:0]};
          next_P[F_C] = bcd_ah[4];
        end else begin
          next_A = alu_result;
          next_P[F_C] = alu_sum[8];
        end
      end
      // STA
      8'h81, 8'h85, 8'h8D, 8'h91, 8'h95, 8'h99, 8'h9D: begin
        do_write_mem = 1'b1;
        write_data   = A;
      end
      // LDA
      8'hA1, 8'hA5, 8'hA9, 8'hAD, 8'hB1, 8'hB5, 8'hB9, 8'hBD: begin
        next_A = exec_operand;
        next_P = set_nz(exec_operand, next_P);
      end
      // CMP
      8'hC1, 8'hC5, 8'hC9, 8'hCD, 8'hD1, 8'hD5, 8'hD9, 8'hDD: begin
        alu_sum = {1'b0, A} + {1'b0, ~exec_operand} + 9'd1;
        alu_result = alu_sum[7:0];
        next_P = set_nz(alu_result, next_P);
        next_P[F_C] = alu_sum[8];
      end
      // SBC
      8'hE1, 8'hE5, 8'hE9, 8'hED, 8'hF1, 8'hF5, 8'hF9, 8'hFD: begin
        // Binary result (used for ALL flags on NMOS 6502)
        alu_sum = {1'b0, A} + {1'b0, ~exec_operand} + {8'd0, P[F_C]};
        alu_result = alu_sum[7:0];
        next_P = set_nz(alu_result, next_P);
        next_P[F_C] = alu_sum[8];
        next_P[F_V] = (A[7] != exec_operand[7]) && (alu_result[7] != A[7]);
        if (P[F_D]) begin
          // BCD mode: adjust result only (flags from binary, NMOS behavior)
          bcd_al = {1'b0, A[3:0]} - {1'b0, exec_operand[3:0]} - {4'd0, ~P[F_C]};
          bcd_lo_borrow = bcd_al[4];
          if (bcd_al[4]) bcd_al = bcd_al - 5'd6;
          bcd_ah = {1'b0, A[7:4]} - {1'b0, exec_operand[7:4]} - {4'd0, bcd_lo_borrow};
          if (bcd_ah[4]) bcd_ah = bcd_ah - 5'd6;
          next_A = {bcd_ah[3:0], bcd_al[3:0]};
        end else begin
          next_A = alu_result;
        end
      end

      // --- Group 2: cc=10 (RMW / LDX / STX) ---
      // ASL (accumulator mode uses A directly, not exec_operand)
      8'h06, 8'h0A, 8'h0E, 8'h16, 8'h1E: begin
        if (opcode == 8'h0A) begin
          {alu_carry, alu_result} = {A, 1'b0};
          next_A = alu_result;
        end else begin
          {alu_carry, alu_result} = {exec_operand, 1'b0};
          do_write_mem = 1'b1; write_data = alu_result;
        end
        next_P = set_nz(alu_result, next_P);
        next_P[F_C] = alu_carry;
      end
      // ROL
      8'h26, 8'h2A, 8'h2E, 8'h36, 8'h3E: begin
        if (opcode == 8'h2A) begin
          {alu_carry, alu_result} = {A, P[F_C]};
          next_A = alu_result;
        end else begin
          {alu_carry, alu_result} = {exec_operand, P[F_C]};
          do_write_mem = 1'b1; write_data = alu_result;
        end
        next_P = set_nz(alu_result, next_P);
        next_P[F_C] = alu_carry;
      end
      // LSR
      8'h46, 8'h4A, 8'h4E, 8'h56, 8'h5E: begin
        if (opcode == 8'h4A) begin
          alu_carry = A[0];
          alu_result = {1'b0, A[7:1]};
          next_A = alu_result;
        end else begin
          alu_carry = exec_operand[0];
          alu_result = {1'b0, exec_operand[7:1]};
          do_write_mem = 1'b1; write_data = alu_result;
        end
        next_P = set_nz(alu_result, next_P);
        next_P[F_C] = alu_carry;
      end
      // ROR
      8'h66, 8'h6A, 8'h6E, 8'h76, 8'h7E: begin
        if (opcode == 8'h6A) begin
          alu_carry = A[0];
          alu_result = {P[F_C], A[7:1]};
          next_A = alu_result;
        end else begin
          alu_carry = exec_operand[0];
          alu_result = {P[F_C], exec_operand[7:1]};
          do_write_mem = 1'b1; write_data = alu_result;
        end
        next_P = set_nz(alu_result, next_P);
        next_P[F_C] = alu_carry;
      end
      // STX
      8'h86, 8'h8E, 8'h96: begin
        do_write_mem = 1'b1;
        write_data   = X;
      end
      // LDX
      8'hA2, 8'hA6, 8'hAE, 8'hB6, 8'hBE: begin
        next_X = exec_operand;
        next_P = set_nz(exec_operand, next_P);
      end
      // DEC
      8'hC6, 8'hCE, 8'hD6, 8'hDE: begin
        alu_result = exec_operand - 8'd1;
        next_P = set_nz(alu_result, next_P);
        do_write_mem = 1'b1;
        write_data = alu_result;
      end
      // INC
      8'hE6, 8'hEE, 8'hF6, 8'hFE: begin
        alu_result = exec_operand + 8'd1;
        next_P = set_nz(alu_result, next_P);
        do_write_mem = 1'b1;
        write_data = alu_result;
      end

      // --- Group 3: cc=00 ---
      // BIT (zp, abs)
      8'h24, 8'h2C: begin
        alu_result = A & exec_operand;
        next_P[F_Z] = (alu_result == 8'd0);
        next_P[F_N] = exec_operand[7];
        next_P[F_V] = exec_operand[6];
      end
      // STY
      8'h84, 8'h8C, 8'h94: begin
        do_write_mem = 1'b1;
        write_data   = Y;
      end
      // LDY
      8'hA0, 8'hA4, 8'hAC, 8'hB4, 8'hBC: begin
        next_Y = exec_operand;
        next_P = set_nz(exec_operand, next_P);
      end
      // CPY
      8'hC0, 8'hC4, 8'hCC: begin
        alu_sum = {1'b0, Y} + {1'b0, ~exec_operand} + 9'd1;
        alu_result = alu_sum[7:0];
        next_P = set_nz(alu_result, next_P);
        next_P[F_C] = alu_sum[8];
      end
      // CPX
      8'hE0, 8'hE4, 8'hEC: begin
        alu_sum = {1'b0, X} + {1'b0, ~exec_operand} + 9'd1;
        alu_result = alu_sum[7:0];
        next_P = set_nz(alu_result, next_P);
        next_P[F_C] = alu_sum[8];
      end

      // --- Implied / single-byte ---
      // PHP
      8'h08: begin end  // handled in push state
      // PLP
      8'h28: begin
        next_P = exec_operand | 8'h20;  // bit 5 always set
      end
      // PHA
      8'h48: begin end  // handled in push state
      // PLA
      8'h68: begin
        next_A = exec_operand;
        next_P = set_nz(exec_operand, next_P);
      end

      // CLC, SEC, CLI, SEI, CLV, CLD, SED
      8'h18: next_P[F_C] = 1'b0;
      8'h38: next_P[F_C] = 1'b1;
      8'h58: next_P[F_I] = 1'b0;
      8'h78: next_P[F_I] = 1'b1;
      8'hB8: next_P[F_V] = 1'b0;
      8'hD8: next_P[F_D] = 1'b0;
      8'hF8: next_P[F_D] = 1'b1;

      // TAX, TXA, TAY, TYA, TSX, TXS
      8'hAA: begin next_X = A;  next_P = set_nz(A, next_P); end
      8'h8A: begin next_A = X;  next_P = set_nz(X, next_P); end
      8'hA8: begin next_Y = A;  next_P = set_nz(A, next_P); end
      8'h98: begin next_A = Y;  next_P = set_nz(Y, next_P); end
      8'hBA: begin next_X = SP; next_P = set_nz(SP, next_P); end
      8'h9A: begin next_SP = X; end

      // INX, DEX, INY, DEY
      8'hE8: begin next_X = X + 8'd1; next_P = set_nz(X + 8'd1, next_P); end
      8'hCA: begin next_X = X - 8'd1; next_P = set_nz(X - 8'd1, next_P); end
      8'hC8: begin next_Y = Y + 8'd1; next_P = set_nz(Y + 8'd1, next_P); end
      8'h88: begin next_Y = Y - 8'd1; next_P = set_nz(Y - 8'd1, next_P); end

      // NOP
      8'hEA: begin end

      default: begin end  // unknown opcodes: NOP
    endcase
  end

  // Is this a read-modify-write instruction? (memory-addressed shifts/inc/dec)
  always_comb begin
    is_rmw = 1'b0;
    case (opcode)
      8'h06, 8'h0E, 8'h16, 8'h1E,  // ASL mem
      8'h26, 8'h2E, 8'h36, 8'h3E,  // ROL mem
      8'h46, 8'h4E, 8'h56, 8'h5E,  // LSR mem
      8'h66, 8'h6E, 8'h76, 8'h7E,  // ROR mem
      8'hC6, 8'hCE, 8'hD6, 8'hDE,  // DEC mem
      8'hE6, 8'hEE, 8'hF6, 8'hFE:  // INC mem
        is_rmw = 1'b1;
      default: is_rmw = 1'b0;
    endcase
  end

  // Is this a store instruction?
  always_comb begin
    is_store = 1'b0;
    case (opcode)
      8'h81, 8'h85, 8'h8D, 8'h91, 8'h95, 8'h99, 8'h9D,  // STA
      8'h86, 8'h8E, 8'h96,                                  // STX
      8'h84, 8'h8C, 8'h94:                                  // STY
        is_store = 1'b1;
      default: is_store = 1'b0;
    endcase
  end

  // Main FSM
  always_ff @(posedge clk or negedge rst_sync_n) begin
    if (!rst_sync_n) begin
      state       <= S_RESET0;
      PC          <= 16'd0;
      A           <= 8'd0;
      X           <= 8'd0;
      Y           <= 8'd0;
      SP          <= 8'hFD;
      P           <= 8'h24;  // IRQ disabled, unused bit set
      AB          <= 16'hFFFC;
      DO          <= 8'd0;
      WE          <= 1'b0;
      nmi_prev    <= 1'b0;
      nmi_pending <= 1'b0;
      opcode      <= 8'hEA;  // NOP
      data_latch  <= 8'd0;
      addr_lo     <= 16'd0;
      bal         <= 8'd0;
      exec_operand <= 8'd0;
      brk_b_flag  <= 1'b0;
      brk_nmi     <= 1'b0;
    end
    else if (RDY) begin
      // NMI edge detection
      if (NMI && !nmi_prev)
        nmi_pending <= 1'b1;
      nmi_prev <= NMI;

      WE <= 1'b0;

      case (state)
        // --- RESET ---
        S_RESET0: begin
          data_latch <= DI;
          AB <= AB + 16'd1;
          state <= S_RESET1;
        end
        S_RESET1: begin
          PC <= {DI, data_latch};
          AB <= {DI, data_latch};
          state <= S_FETCH;
        end

        // --- FETCH ---
        S_FETCH: begin
          // Check for interrupts
          if (nmi_pending) begin
            nmi_pending <= 1'b0;
            opcode <= 8'h00;
            brk_b_flag <= 1'b0;  // NMI: B clear in pushed P
            brk_nmi <= 1'b1;     // use NMI vector (FFFA)
            AB <= {8'h01, SP};
            DO <= PC[15:8];
            WE <= 1'b1;
            SP <= SP - 8'd1;
            state <= S_BRK0;
          end
          else if (IRQ && !P[F_I]) begin
            opcode <= 8'h00;
            brk_b_flag <= 1'b0;  // IRQ: B clear in pushed P
            brk_nmi <= 1'b0;     // use IRQ vector (FFFE)
            AB <= {8'h01, SP};
            DO <= PC[15:8];
            WE <= 1'b1;
            SP <= SP - 8'd1;
            state <= S_BRK0;
          end
          else begin
            opcode <= DI;
            PC <= PC + 16'd1;
            AB <= PC + 16'd1;
            state <= S_DECODE;
          end
        end

        // --- DECODE: opcode is latched, DI has first operand byte ---
        S_DECODE: begin
          data_latch <= DI;

          case (opcode)
            // Implied / accumulator (single byte)
            8'h0A, 8'h2A, 8'h4A, 8'h6A,  // ASL/ROL/LSR/ROR A
            8'h18, 8'h38, 8'h58, 8'h78,   // CLC/SEC/CLI/SEI
            8'hB8, 8'hD8, 8'hF8,          // CLV/CLD/SED
            8'hAA, 8'h8A, 8'hA8, 8'h98,   // TAX/TXA/TAY/TYA
            8'hBA, 8'h9A,                  // TSX/TXS
            8'hE8, 8'hCA, 8'hC8, 8'h88,   // INX/DEX/INY/DEY
            8'hEA: begin                   // NOP
              // Execute immediately (operand is A or implicit)
              exec_operand <= A;
              A  <= next_A;
              X  <= next_X;
              Y  <= next_Y;
              SP <= next_SP;
              P  <= next_P;
              AB <= PC;  // re-fetch from same PC (we didn't consume the byte)
              state <= S_FETCH;
            end

            // Branches (relative)
            8'h10, 8'h30, 8'h50, 8'h70,
            8'h90, 8'hB0, 8'hD0, 8'hF0: begin
              // Branch offset comes from DI (current operand byte),
              // not data_latch (which won't update until next cycle)
              PC <= PC + 16'd1;
              if (branch_taken) begin
                PC <= PC + 16'd1 + {{8{DI[7]}}, DI};
                AB <= PC + 16'd1 + {{8{DI[7]}}, DI};
              end
              else begin
                AB <= PC + 16'd1;
              end
              state <= S_FETCH;
            end

            // Immediate
            8'h09, 8'h29, 8'h49, 8'h69,  // ORA/AND/EOR/ADC #imm
            8'hA9, 8'hC9, 8'hE9,          // LDA/CMP/SBC #imm
            8'hA2, 8'hA0,                  // LDX/LDY #imm
            8'hC0, 8'hE0: begin            // CPY/CPX #imm
              exec_operand <= DI;
              PC <= PC + 16'd1;
              state <= S_EXEC;
            end

            // Zero page
            8'h05, 8'h25, 8'h45, 8'h65,  // ORA/AND/EOR/ADC zp
            8'h85, 8'hA5, 8'hC5, 8'hE5,  // STA/LDA/CMP/SBC zp
            8'h06, 8'h26, 8'h46, 8'h66,  // ASL/ROL/LSR/ROR zp
            8'h24,                         // BIT zp
            8'h84, 8'h86,                 // STY/STX zp
            8'hA4, 8'hA6,                 // LDY/LDX zp
            8'hC4, 8'hE4,                 // CPY/CPX zp
            8'hC6, 8'hE6: begin           // DEC/INC zp
              addr_lo <= {8'd0, DI};
              AB <= {8'd0, DI};
              PC <= PC + 16'd1;
              state <= S_ZP_RD;
            end

            // Zero page,X / Zero page,Y
            8'h15, 8'h35, 8'h55, 8'h75,  // ORA/AND/EOR/ADC zp,X
            8'h95, 8'hB5, 8'hD5, 8'hF5,  // STA/LDA/CMP/SBC zp,X
            8'h16, 8'h36, 8'h56, 8'h76,  // ASL/ROL/LSR/ROR zp,X
            8'h94, 8'hB4,                 // STY/LDY zp,X
            8'hD6, 8'hF6: begin           // DEC/INC zp,X
              addr_lo <= {8'd0, DI + X};
              AB <= {8'd0, DI + X};  // zero-page wraparound (8-bit add)
              PC <= PC + 16'd1;
              state <= S_ZP_RD;
            end
            8'h96, 8'hB6: begin           // STX/LDX zp,Y
              addr_lo <= {8'd0, DI + Y};
              AB <= {8'd0, DI + Y};
              PC <= PC + 16'd1;
              state <= S_ZP_RD;
            end

            // Absolute
            8'h0D, 8'h2D, 8'h4D, 8'h6D,  // ORA/AND/EOR/ADC abs
            8'h8D, 8'hAD, 8'hCD, 8'hED,  // STA/LDA/CMP/SBC abs
            8'h0E, 8'h2E, 8'h4E, 8'h6E,  // ASL/ROL/LSR/ROR abs
            8'h2C,                         // BIT abs
            8'h8C, 8'h8E,                 // STY/STX abs
            8'hAC, 8'hAE,                 // LDY/LDX abs
            8'hCC, 8'hEC,                 // CPY/CPX abs
            8'hCE, 8'hEE: begin           // DEC/INC abs
              bal <= DI;
              AB <= PC + 16'd1;
              PC <= PC + 16'd1;
              state <= S_ABS0;
            end

            // Absolute,X
            8'h1D, 8'h3D, 8'h5D, 8'h7D,  // ORA/AND/EOR/ADC abs,X
            8'h9D, 8'hBD, 8'hDD, 8'hFD,  // STA/LDA/CMP/SBC abs,X
            8'h1E, 8'h3E, 8'h5E, 8'h7E,  // ASL/ROL/LSR/ROR abs,X
            8'hBC,                         // LDY abs,X
            8'hDE, 8'hFE: begin           // DEC/INC abs,X
              bal <= DI;
              AB <= PC + 16'd1;
              PC <= PC + 16'd1;
              state <= S_ABSX0;
            end

            // Absolute,Y
            8'h19, 8'h39, 8'h59, 8'h79,  // ORA/AND/EOR/ADC abs,Y
            8'h99, 8'hB9, 8'hD9, 8'hF9,  // STA/LDA/CMP/SBC abs,Y
            8'hBE: begin                   // LDX abs,Y
              bal <= DI;
              AB <= PC + 16'd1;
              PC <= PC + 16'd1;
              state <= S_ABSY0;
            end

            // (Indirect,X)
            8'h01, 8'h21, 8'h41, 8'h61,  // ORA/AND/EOR/ADC (zp,X)
            8'h81, 8'hA1, 8'hC1, 8'hE1: begin  // STA/LDA/CMP/SBC (zp,X)
              bal <= DI + X;  // pointer base (wraps in zero page)
              AB <= {8'd0, DI + X};
              PC <= PC + 16'd1;
              state <= S_INDX0;
            end

            // (Indirect),Y
            8'h11, 8'h31, 8'h51, 8'h71,  // ORA/AND/EOR/ADC (zp),Y
            8'h91, 8'hB1, 8'hD1, 8'hF1: begin  // STA/LDA/CMP/SBC (zp),Y
              AB <= {8'd0, DI};
              bal <= DI;
              PC <= PC + 16'd1;
              state <= S_INDY0;
            end

            // JMP absolute
            8'h4C: begin
              bal <= DI;
              AB <= PC + 16'd1;
              PC <= PC + 16'd1;
              state <= S_ABS0;  // reuse abs fetch, then jump
            end

            // JMP (indirect)
            8'h6C: begin
              bal <= DI;
              AB <= PC + 16'd1;
              PC <= PC + 16'd1;
              state <= S_ABS0;  // fetch high byte first, then indirect
            end

            // JSR
            8'h20: begin
              bal <= DI;
              AB <= PC + 16'd1;
              PC <= PC + 16'd1;
              state <= S_ABS0;
            end

            // BRK
            8'h00: begin
              PC <= PC + 16'd1;  // BRK skips padding byte
              brk_b_flag <= 1'b1;  // software BRK: B set in pushed P
              brk_nmi <= 1'b0;     // use IRQ vector (FFFE)
              AB <= {8'h01, SP};
              DO <= (PC + 16'd1) >> 8;  // push PCH of return address
              WE <= 1'b1;
              SP <= SP - 8'd1;
              state <= S_BRK0;
            end

            // RTS
            8'h60: begin
              AB <= {8'h01, SP + 8'd1};
              SP <= SP + 8'd1;
              state <= S_RTS0;
            end

            // RTI
            8'h40: begin
              AB <= {8'h01, SP + 8'd1};
              SP <= SP + 8'd1;
              state <= S_PULL0;  // pull P, then pull PC
            end

            // PHA
            8'h48: begin
              AB <= {8'h01, SP};
              DO <= A;
              WE <= 1'b1;
              SP <= SP - 8'd1;
              state <= S_PUSH;
            end

            // PHP
            8'h08: begin
              AB <= {8'h01, SP};
              DO <= P | 8'h30;  // B and U flags set in pushed value
              WE <= 1'b1;
              SP <= SP - 8'd1;
              state <= S_PUSH;
            end

            // PLA
            8'h68: begin
              AB <= {8'h01, SP + 8'd1};
              SP <= SP + 8'd1;
              state <= S_PULL1;
            end

            // PLP
            8'h28: begin
              AB <= {8'h01, SP + 8'd1};
              SP <= SP + 8'd1;
              state <= S_PULL1;
            end

            default: begin
              // Unknown opcode: treat as 1-byte NOP
              AB <= PC;
              state <= S_FETCH;
            end
          endcase
        end

        // --- ZERO PAGE READ ---
        S_ZP_RD: begin
          if (is_store) begin
            // Write store data
            exec_operand <= A;  // will be overridden by execution logic
            AB <= addr_lo;
            state <= S_EXEC;
          end
          else begin
            exec_operand <= DI;
            if (is_rmw) begin
              data_latch <= DI;
              state <= S_EXEC;
            end
            else begin
              state <= S_EXEC;
            end
          end
        end

        // --- ABSOLUTE: fetch high byte ---
        S_ABS0: begin
          addr_lo <= {DI, bal};
          AB <= {DI, bal};
          PC <= PC + 16'd1;

          // Special case: JMP absolute
          if (opcode == 8'h4C) begin
            PC <= {DI, bal};
            AB <= {DI, bal};
            state <= S_FETCH;
          end
          // JMP indirect
          else if (opcode == 8'h6C) begin
            addr_lo <= {DI, bal};
            AB <= {DI, bal};
            PC <= PC + 16'd1;
            state <= S_INDX0;  // reuse for indirect read
          end
          // JSR
          else if (opcode == 8'h20) begin
            // 6502 pushes PC pointing to last byte of JSR (= addr of high operand)
            // At this point, PC still holds that address (non-blocking PC+1
            // from line above won't apply until clock edge).
            // Push PCH first, then PCL in S_JSR0.
            // Latch the return address in data_latch for PCL push.
            addr_lo <= {DI, bal};
            data_latch <= PC[7:0];  // save PCL for push in S_JSR0
            AB <= {8'h01, SP};
            DO <= PC[15:8];  // push PCH
            WE <= 1'b1;
            SP <= SP - 8'd1;
            state <= S_JSR0;
          end
          else begin
            state <= S_ABS1;
          end
        end

        // --- ABSOLUTE: access memory ---
        S_ABS1: begin
          if (is_store) begin
            exec_operand <= A;
            state <= S_EXEC;
          end
          else begin
            exec_operand <= DI;
            state <= S_EXEC;
          end
        end

        // --- ABSOLUTE,X: fetch high byte ---
        S_ABSX0: begin
          addr_lo <= {DI, bal} + {8'd0, X};
          AB <= {DI, bal} + {8'd0, X};
          PC <= PC + 16'd1;
          state <= S_ABSX1;
        end

        S_ABSX1: begin
          if (is_store) begin
            exec_operand <= A;
            state <= S_EXEC;
          end
          else begin
            exec_operand <= DI;
            state <= S_EXEC;
          end
        end

        // --- ABSOLUTE,Y ---
        S_ABSY0: begin
          addr_lo <= {DI, bal} + {8'd0, Y};
          AB <= {DI, bal} + {8'd0, Y};
          PC <= PC + 16'd1;
          state <= S_ABSY1;
        end

        S_ABSY1: begin
          if (is_store) begin
            exec_operand <= A;
            state <= S_EXEC;
          end
          else begin
            exec_operand <= DI;
            state <= S_EXEC;
          end
        end

        // --- (INDIRECT,X) ---
        S_INDX0: begin
          data_latch <= DI;  // low byte of target address
          if (opcode == 8'h6C)
            // JMP indirect: read high byte from pointer+1
            // (with 6502 page-crossing bug: wraps within page)
            AB <= {addr_lo[15:8], addr_lo[7:0] + 8'd1};
          else
            // (indirect,X): pointer is in zero page, wraps within ZP
            AB <= {8'd0, bal + 8'd1};
          state <= S_INDX1;
        end

        S_INDX1: begin
          // For JMP indirect, this is the indirect vector read
          if (opcode == 8'h6C) begin
            PC <= {DI, data_latch};
            AB <= {DI, data_latch};
            state <= S_FETCH;
          end
          else begin
            addr_lo <= {DI, data_latch};
            AB <= {DI, data_latch};
            state <= S_INDX2;
          end
        end

        S_INDX2: begin
          if (is_store) begin
            exec_operand <= A;
            state <= S_EXEC;
          end
          else begin
            exec_operand <= DI;
            state <= S_EXEC;
          end
        end

        // --- (INDIRECT),Y ---
        S_INDY0: begin
          data_latch <= DI;  // low byte of base address
          AB <= {8'd0, bal + 8'd1};  // zero-page wrap for high byte
          state <= S_INDY1;
        end

        S_INDY1: begin
          addr_lo <= {DI, data_latch} + {8'd0, Y};
          AB <= {DI, data_latch} + {8'd0, Y};
          state <= S_INDY2;
        end

        S_INDY2: begin
          if (is_store) begin
            exec_operand <= A;
            state <= S_EXEC;
          end
          else begin
            exec_operand <= DI;
            state <= S_EXEC;
          end
        end

        // --- EXECUTE ---
        S_EXEC: begin
          A  <= next_A;
          X  <= next_X;
          Y  <= next_Y;
          SP <= next_SP;
          P  <= next_P;

          if (do_write_mem) begin
            AB <= addr_lo;
            DO <= write_data;
            WE <= 1'b1;
            // All writes need an extra cycle: AB must hold the write
            // address while WE is high. S_RMW_WR advances to fetch.
            state <= S_RMW_WR;
          end
          else begin
            AB <= PC;
            state <= S_FETCH;
          end
        end

        // --- RMW WRITE BACK ---
        S_RMW_WR: begin
          AB <= PC;
          state <= S_FETCH;
        end

        // --- PUSH ---
        S_PUSH: begin
          AB <= PC;
          state <= S_FETCH;
        end

        // --- PULL (for RTI: pull P first) ---
        S_PULL0: begin
          // RTI: read P from stack
          P <= DI | 8'h20;  // bit 5 always set
          AB <= {8'h01, SP + 8'd1};
          SP <= SP + 8'd1;
          state <= S_RTS0;  // then read PC like RTS
        end

        // --- PULL (PLA/PLP) ---
        S_PULL1: begin
          exec_operand <= DI;
          // Apply execution logic for PLA/PLP
          case (opcode)
            8'h68: begin  // PLA
              A <= DI;
              P <= set_nz(DI, P);
            end
            8'h28: begin  // PLP
              P <= DI | 8'h20;
            end
            default: begin end
          endcase
          AB <= PC;
          state <= S_FETCH;
        end

        // --- JSR: push PCL ---
        S_JSR0: begin
          AB <= {8'h01, SP};
          DO <= data_latch;  // push PCL (saved in S_ABS0)
          WE <= 1'b1;
          SP <= SP - 8'd1;
          state <= S_JSR1;
        end

        S_JSR1: begin
          // Jump to target
          PC <= addr_lo;
          AB <= addr_lo;
          state <= S_FETCH;
        end

        // --- RTS: pull PCL ---
        S_RTS0: begin
          data_latch <= DI;  // PCL
          AB <= {8'h01, SP + 8'd1};
          SP <= SP + 8'd1;
          state <= S_RTS1;
        end

        // --- RTS: pull PCH and increment ---
        S_RTS1: begin
          if (opcode == 8'h40) begin
            // RTI: don't add 1
            PC <= {DI, data_latch};
            AB <= {DI, data_latch};
          end
          else begin
            // RTS: add 1
            PC <= {DI, data_latch} + 16'd1;
            AB <= {DI, data_latch} + 16'd1;
          end
          state <= S_FETCH;
        end

        // --- BRK/IRQ/NMI: push PCL, push P, load vector ---
        S_BRK0: begin
          AB <= {8'h01, SP};
          DO <= PC[7:0];
          WE <= 1'b1;
          SP <= SP - 8'd1;
          state <= S_BRK1;
        end

        S_BRK1: begin
          // Push P to stack
          AB <= {8'h01, SP};
          if (brk_b_flag)
            DO <= P | 8'h30;  // B flag set for software BRK
          else
            DO <= (P | 8'h20) & 8'hEF;  // B clear for IRQ/NMI
          WE <= 1'b1;
          SP <= SP - 8'd1;
          P[F_I] <= 1'b1;
          state <= S_BRK2;
        end

        S_BRK2: begin
          // Set up vector read (WE cleared by default at top)
          if (brk_nmi)
            AB <= 16'hFFFA;  // NMI vector
          else
            AB <= 16'hFFFE;  // IRQ/BRK vector
          state <= S_RESET0;  // reuse reset vector read states
        end

        default: begin
          state <= S_FETCH;
        end
      endcase
    end
  end

endmodule
