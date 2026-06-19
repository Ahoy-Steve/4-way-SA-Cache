`timescale 1ns/1ps
`include "defs.vh"

module tb_cache();

   // ---- System ----
   reg clock;
   reg rst_n;

   // ---- CPU <-> Cache ----
   reg  [20:0] caddress;
   reg  [31:0] cdin;
   reg  rden;
   reg  wren;
   wire hit;
   wire [31:0] cdout;

   // ---- Cache <-> Memory ----
   wire [255:0] mdin;
   wire [255:0] mdout;
   wire [17:0]  maddress;
   wire mrden;
   wire mwren;

   // ---- Scoreboard / capture ----
   integer errors;
   reg [31:0] captured_data;
   reg access_was_hit;

   // ---- Controller FSM encodings (must match cache_controller.v) ----
   localparam ST_IDLE = 3'd0;
   localparam ST_READ_HIT = 3'd1;

   // Five blocks that all map to the SAME set (index 5, offset 0) but carry
   // different tags, so they contend for the 4 ways of set 5.
   localparam [20:0] ADDR_A = 21'h000028; // tag 0
   localparam [20:0] ADDR_B = 21'h000828; // tag 1
   localparam [20:0] ADDR_C = 21'h001028; // tag 2
   localparam [20:0] ADDR_D = 21'h001828; // tag 3
   localparam [20:0] ADDR_E = 21'h002028; // tag 4

   //----------------------------------------------------------------------
   // DUT
   //----------------------------------------------------------------------
   cache_controller #(
      .BLOCK_SIZE(256), .ADDRESS_WIDTH(21), .INDEX_WIDTH(8),
      .TAG_WIDTH(10),  .OFFSET_WIDTH(3),  .WORD_SIZE(32),
      .NSETS(256),     .WAYS(4)
   ) UUT_CACHE (
      .clock(clock), .rst_n(rst_n),
      .caddress(caddress), .cdin(cdin), .mdin(mdin),
      .rden(rden), .wren(wren),
      .hit(hit), .cdout(cdout), .mdout(mdout),
      .maddress(maddress), .mrden(mrden), .mwren(mwren)
   );

   memory #(.ADDRESS_WIDTH(18), .BLOCK_SIZE(256), .FILE("")) MAIN_MEM (
      .clock(clock), .din(mdout), .address(maddress),
      .rden(mrden), .wren(mwren), .dout(mdin)
   );

   wire [31:0] stat_refs, stat_hits, stat_misses;
   cache_stats #(.COUNTER_WIDTH(32)) STATS (
      .clock(clock), .rst_n(rst_n),
      .rden(rden), .wren(wren), .hit(hit),
      .num_references(stat_refs),
      .num_hits(stat_hits),
      .num_misses(stat_misses)
   );

   //----------------------------------------------------------------------
   // Clock (100 MHz) + watchdog
   //----------------------------------------------------------------------
   initial begin
      clock = 0;
      forever #5 clock = ~clock;
   end

   initial begin
      #50000;
      $display("[%0t] TIMEOUT - watchdog fired (possible FSM hang)", $time);
      $stop;
   end

   //----------------------------------------------------------------------
   // Checkers
   //----------------------------------------------------------------------
   task check_hit(input is_write, input [20:0] addr, input got, input exp);
      begin
         if (got === exp)
            $display("[%0t]   OK  %0s 0x%06h : %0s",
                     $time, is_write ? "WRITE" : "READ ", addr,
                     got ? "HIT" : "MISS");
         else begin
            $display("[%0t]  ERR %0s 0x%06h : got %0s, expected %0s",
                     $time, is_write ? "WRITE" : "READ ", addr,
                     got ? "HIT" : "MISS", exp ? "HIT" : "MISS");
            errors = errors + 1;
         end
      end
   endtask

   task check_data(input [20:0] addr, input [31:0] got, input [31:0] exp);
      begin
         if (got === exp)
            $display("[%0t]   OK  DATA 0x%06h = 0x%08h", $time, addr, got);
         else begin
            $display("[%0t]  ERR DATA 0x%06h : got 0x%08h, expected 0x%08h",
                     $time, addr, got, exp);
            errors = errors + 1;
         end
      end
   endtask

   //----------------------------------------------------------------------
   // Access tasks
   // Both drive a clean one-cycle request, classify hit/miss at the moment
   // of acceptance (controller still IDLE), then wait for completion using
   // negedge sampling to avoid posedge non-blocking-update races.
   //----------------------------------------------------------------------
   task do_write(input [20:0] addr, input [31:0] data, input exp_hit);
      reg sampled_hit;
      begin
         @(posedge clock);
         caddress = addr;
         cdin = data;
         wren = 1'b1;
         @(negedge clock);                                 // still IDLE here
         sampled_hit = hit;
         @(posedge clock);                                 // request accepted
         wren = 1'b0;
         @(negedge clock);
         while (UUT_CACHE.current_state !== ST_IDLE) @(negedge clock);
         check_hit(1'b1, addr, sampled_hit, exp_hit);
      end
   endtask

   task do_read(input [20:0] addr, input exp_hit,
                input check_d, input [31:0] exp_data);
      begin
         @(posedge clock);
         caddress = addr;
         rden     = 1'b1;
         @(negedge clock);                                 // still IDLE here
         access_was_hit = hit;
         @(posedge clock);                                 // request accepted
         rden = 1'b0;
         // wait for the data-valid cycle, then sample cdout inside it
         @(negedge clock);
         while (UUT_CACHE.current_state !== ST_READ_HIT) @(negedge clock);
         captured_data = cdout;
         // let the controller settle back to IDLE
         @(negedge clock);
         while (UUT_CACHE.current_state !== ST_IDLE) @(negedge clock);
         check_hit(1'b0, addr, access_was_hit, exp_hit);
         if (check_d) check_data(addr, captured_data, exp_data);
      end
   endtask

   //----------------------------------------------------------------------
   // Stimulus
   //----------------------------------------------------------------------
   initial begin
      errors = 0;
      rst_n = 0;
      caddress = 0;
      cdin = 0;
      rden = 0;
      wren = 0;

      $display("\n[%0t] === Reset ===", $time);
      #20; rst_n = 1; #10;

      // Test 1 -- write miss => write-allocate
      $display("\n[%0t] === Test 1: write miss (write-allocate) ===", $time);
      do_write(21'h000004, 32'hDEADBEEF, 1'b0);

      // Test 2 -- read hit (cdout sampled at the right cycle)
      $display("\n[%0t] === Test 2: read hit ===", $time);
      do_read(21'h000004, 1'b1, 1'b1, 32'hDEADBEEF);

      // Test 3 -- read miss to a fresh block => returns zeros
      $display("\n[%0t] === Test 3: read miss (fresh block) ===", $time);
      do_read(21'h00000A, 1'b0, 1'b1, 32'h00000000);

      // Test 4 -- fill all four ways of set 5 (all become dirty)
      $display("\n[%0t] === Test 4a: fill the 4 ways of set 5 ===", $time);
      do_write(ADDR_A, 32'hAAAA0000, 1'b0);
      do_write(ADDR_B, 32'hBBBB1111, 1'b0);
      do_write(ADDR_C, 32'hCCCC2222, 1'b0);
      do_write(ADDR_D, 32'hDDDD3333, 1'b0); // set full; LRU = A

      // Re-touch A: now A is MRU and B is the LRU victim. If the policy were
      // FIFO, A (oldest by fill order) would be evicted next instead of B.
      $display("\n[%0t] === Test 4b: re-touch A (LRU victim becomes B) ===", $time);
      do_read(ADDR_A, 1'b1, 1'b1, 32'hAAAA0000);

      // Bring in E: must evict the LRU way (B). B is dirty => written back.
      $display("\n[%0t] === Test 4c: write E -> evicts B, writes B back ===", $time);
      do_write(ADDR_E, 32'hEEEE4444, 1'b0);

      // Read B: now a miss (it was evicted). The data must still be correct
      // because B was written back to memory and is re-fetched from there.
      $display("\n[%0t] === Test 4d: read B -> miss, data proves write-back ===", $time);
      do_read(ADDR_B, 1'b0, 1'b1, 32'hBBBB1111);

      // Survivors must still hit (A proves LRU kept the re-touched block).
      $display("\n[%0t] === Test 4e: survivors still hit ===", $time);
      do_read(ADDR_A, 1'b1, 1'b1, 32'hAAAA0000);
      do_read(ADDR_D, 1'b1, 1'b1, 32'hDDDD3333);
      do_read(ADDR_E, 1'b1, 1'b1, 32'hEEEE4444);
      do_read(ADDR_B, 1'b1, 1'b1, 32'hBBBB1111); // B resident again

      // C was evicted (and written back) during the read-B miss; its data
      // must come back correctly from memory on this miss.
      $display("\n[%0t] === Test 4f: read C -> miss, data proves write-back ===", $time);
      do_read(ADDR_C, 1'b0, 1'b1, 32'hCCCC2222);

      // Test 5 -- write hit: D is resident, so no memory traffic occurs.
      $display("\n[%0t] === Test 5: write hit (no memory access) ===", $time);
      do_write(ADDR_D, 32'hD00D0000, 1'b1);
      do_read (ADDR_D, 1'b1, 1'b1, 32'hD00D0000);

      // ---- Statistics ----
      $display("");
      STATS.report;
      if (stat_refs !== 17) begin errors=errors+1;
         $display("  ERR references=%0d (expected 17)", stat_refs); end
      else $display("   OK  references=%0d", stat_refs);
      if (stat_hits !== 8)  begin errors=errors+1;
         $display("  ERR hits=%0d (expected 8)", stat_hits); end
      else $display("   OK  hits=%0d", stat_hits);
      if (stat_misses !== 9)  begin errors=errors+1;
         $display("  ERR misses=%0d (expected 9)", stat_misses); end
      else $display("   OK  misses=%0d", stat_misses);

      // ---- Summary ----
      $display("\n========================================");
      if (errors == 0) $display(" RESULT: ALL CHECKS PASSED");
      else             $display(" RESULT: %0d CHECK(S) FAILED", errors);
      $display("========================================\n");

      $stop;
   end

endmodule