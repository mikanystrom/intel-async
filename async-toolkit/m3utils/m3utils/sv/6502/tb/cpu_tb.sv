// cpu_tb.sv -- Testbench for cpu_6502
//
// Loads a hex image into a 64KB memory, resets the CPU, and runs
// until PC reaches the success address or a stuck-loop is detected.
//
// Parameters are passed via plusargs:
//   +hexfile=<file>     hex image ($readmemh format)
//   +reset=<hex>        override reset vector (default: use image's vector)
//   +success=<hex>      success PC (simulation stops with PASS)
//   +max_cycles=<dec>   cycle limit (default 100000000)

`timescale 1ns/1ps

module cpu_tb;

  // Clock and reset
  logic clk = 0;
  logic reset_n;

  // CPU interface
  logic [15:0] AB;
  logic [7:0]  DI, DO;
  logic        WE;

  // Memory
  reg [7:0] mem [0:65535];

  // CPU instance
  cpu_6502 cpu (
    .clk     (clk),
    .reset_n (reset_n),
    .AB      (AB),
    .DI      (DI),
    .DO      (DO),
    .WE      (WE),
    .IRQ     (1'b0),
    .NMI     (1'b0),
    .RDY     (1'b1)
  );

  // Clock generation: 100 MHz (10ns period)
  always #5 clk = ~clk;

  // Asynchronous memory read, synchronous write
  assign DI = mem[AB];

  always @(posedge clk) begin
    if (WE)
      mem[AB] <= DO;
  end

  // Parameters
  integer reset_addr;
  integer success_addr;
  integer max_cycles;
  string  hex_file;
  integer has_reset;

  // Monitoring
  integer cycle_count;
  reg [15:0] prev_PC;
  reg [15:0] prev_prev_PC;
  reg [15:0] prev3_PC;
  integer stuck_count;

  initial begin
    // Parse plusargs
    if (!$value$plusargs("hexfile=%s", hex_file)) begin
      $display("ERROR: +hexfile=<file> required");
      $finish;
    end
    has_reset = $value$plusargs("reset=%h", reset_addr);
    if (!$value$plusargs("success=%h", success_addr))
      success_addr = 16'h3469;
    if (!$value$plusargs("max_cycles=%d", max_cycles))
      max_cycles = 100_000_000;

    $display("=== 6502 CPU Simulation ===");
    $display("  Hex file: %s", hex_file);
    $display("  Success:  0x%04h", success_addr[15:0]);
    $display("  Max cycles: %0d", max_cycles);
    $display("");

    // Load hex image (full 64KB, includes reset vector at FFFC/FFFD)
    $readmemh(hex_file, mem);

    // Override reset vector if specified
    if (has_reset) begin
      mem[16'hFFFC] = reset_addr[7:0];
      mem[16'hFFFD] = reset_addr[15:8];
    end

    $display("  Reset vector: 0x%02h%02h", mem[16'hFFFD], mem[16'hFFFC]);
    $display("");

    // Reset sequence
    reset_n = 0;
    cycle_count = 0;
    prev_PC = 16'hFFFF;
    prev_prev_PC = 16'hFFFE;
    prev3_PC = 16'hFFFD;
    stuck_count = 0;

    #100;
    reset_n = 1;

    $display("Reset released, starting execution...");
    $display("");
  end

  // Monitor PC and detect success/stuck
  always @(posedge clk) begin
    if (reset_n) begin
      cycle_count <= cycle_count + 1;

      //

      // Progress report every 1M cycles
      if (cycle_count % 1_000_000 == 0 && cycle_count > 0)
        $display("  [%0d M cycles] PC=0x%04h A=0x%02h X=0x%02h Y=0x%02h SP=0x%02h P=0x%02h",
                 cycle_count / 1_000_000,
                 cpu.PC, cpu.A, cpu.X, cpu.Y, cpu.SP, cpu.P);

      // Stuck-loop detection: PC cycling among up to 3 values
      // (catches BNE *, JMP * patterns — JMP is 3 cycles)
      if (cpu.PC == prev_PC || cpu.PC == prev_prev_PC || cpu.PC == prev3_PC)
        stuck_count <= stuck_count + 1;
      else
        stuck_count <= 0;

      prev3_PC <= prev_prev_PC;
      prev_prev_PC <= prev_PC;
      prev_PC <= cpu.PC;

      if (stuck_count > 100) begin
        $display("");
        if (cpu.PC == success_addr[15:0] ||
            prev_PC == success_addr[15:0] ||
            prev_prev_PC == success_addr[15:0] ||
            prev3_PC == success_addr[15:0]) begin
          $display("SUCCESS: PC=0x%04h at cycle %0d", cpu.PC, cycle_count);
          $display("  A=0x%02h X=0x%02h Y=0x%02h SP=0x%02h P=0x%02h",
                   cpu.A, cpu.X, cpu.Y, cpu.SP, cpu.P);
          $display("PASS");
        end else begin
          $display("STUCK: PC=0x%04h for >1000 cycles at cycle %0d",
                   cpu.PC, cycle_count);
          $display("  A=0x%02h X=0x%02h Y=0x%02h SP=0x%02h P=0x%02h",
                   cpu.A, cpu.X, cpu.Y, cpu.SP, cpu.P);
          $display("FAIL");
        end
        $finish;
      end

      // Cycle limit
      if (cycle_count >= max_cycles) begin
        $display("");
        $display("TIMEOUT at cycle %0d, PC=0x%04h", cycle_count, cpu.PC);
        $display("FAIL");
        $finish;
      end
    end
  end

endmodule
