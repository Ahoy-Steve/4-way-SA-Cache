`timescale 1ns/1ps
`include "defs.vh"

module tb_cache();

   // System Signals (Driven by testbench, must be reg)
   reg clock;
   reg rst_n;

   // CPU <-> Cache Signals
   reg [20:0]  caddress;
   reg [31:0]  cdin;
   reg         rden;
   reg         wren;
   wire        hit;          // Driven by module output, must be wire
   wire [31:0] cdout;

   // Cache <-> Memory Signals
   wire [255:0] mdin;
   wire [255:0] mdout;
   wire [17:0]  maddress;
   wire         mrden;
   wire         mwren;

   // ---------------------------------------------------------
   // 1. Instantiate the Cache Controller
   // ---------------------------------------------------------
   cache_controller #(
      .BLOCK_SIZE(256),
      .ADDRESS_WIDTH(21),
      .INDEX_WIDTH(8),     // 256 sets
      .TAG_WIDTH(10),      // 10 bits
      .OFFSET_WIDTH(3),    // 8 words/block
      .WORD_SIZE(32),
      .NSETS(256),
      .WAYS(4)
   ) UUT_CACHE (
      .clock(clock),
      .rst_n(rst_n),
      .caddress(caddress),
      .cdin(cdin),
      .mdin(mdin),
      .rden(rden),
      .wren(wren),
      .hit(hit),
      .cdout(cdout),
      .mdout(mdout),
      .maddress(maddress),
      .mrden(mrden),
      .mwren(mwren)
   );

   // ---------------------------------------------------------
   // 2. Instantiate Main Memory
   // Note: Ensure your memory file is also standard Verilog
   //       (using reg/wire instead of logic)
   // ---------------------------------------------------------
   memory #(
      .ADDRESS_WIDTH(18),
      .BLOCK_SIZE(256),
      .FILE("") // Leave empty to initialize with 0s
   ) MAIN_MEM (
      .clock(clock),
      .din(mdout),
      .address(maddress),
      .rden(mrden),
      .wren(mwren),
      .dout(mdin)
   );

   // ---------------------------------------------------------
   // 3. Clock Generation (100 MHz)
   // ---------------------------------------------------------
   initial begin
      clock = 0;
      forever #5 clock = ~clock;
   end

   // ---------------------------------------------------------
   // 4. Test Stimulus
   // ---------------------------------------------------------
   initial begin
      // Initialize signals
      rst_n    = 0;
      caddress = 0;
      cdin     = 0;
      rden     = 0;
      wren     = 0;

      // Apply Reset
      $display("[%0t] Applying Reset...", $time);
      #20;
      rst_n = 1;
      #10;

      // Test 1: Write Miss (Write-Allocate)
      // Writing 0xDEADBEEF to Word Address 0x000004
      $display("[%0t] Test 1: Write Miss to 0x000004", $time);
      @(posedge clock);
      caddress = 21'h000004;
      cdin     = 32'hDEADBEEF;
      wren     = 1;
      @(posedge clock);
      wren     = 0;
      
      // Wait for cache state machine to finish
      repeat(10) @(posedge clock);

      // Test 2: Read Hit (Same Block)
      // Reading from Word Address 0x000004
      $display("[%0t] Test 2: Read Hit from 0x000004", $time);
      @(posedge clock);
      caddress = 21'h000004;
      rden     = 1;
      @(posedge clock);
      rden     = 0;
      
      // Wait for read to process
      repeat(5) @(posedge clock);
      if (hit && cdout == 32'hDEADBEEF)
         $display("[%0t] SUCCESS: Read Hit! Data = %h", $time, cdout);
      else
         $display("[%0t] ERROR: Expected hit with DEADBEEF, got %h", $time, cdout);

      // Test 3: Read Miss (Different Block, fetches 0s from memory)
      // Reading from Word Address 0x00000A
      $display("[%0t] Test 3: Read Miss from 0x00000A", $time);
      @(posedge clock);
      caddress = 21'h00000A;
      rden     = 1;
      @(posedge clock);
      rden     = 0;

      repeat(10) @(posedge clock);

      $display("[%0t] Simulation Complete.", $time);
      $stop; // Pause simulation
   end

endmodule