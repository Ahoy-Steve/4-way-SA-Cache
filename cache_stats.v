`timescale 1ns/1ps
`include "defs.vh"

module cache_stats
  #(parameter integer COUNTER_WIDTH = 32)
   (
    input  wire                     clock,
    input  wire                     rst_n,
    input  wire                     rden,
    input  wire                     wren,
    input  wire                     hit,
    output reg [COUNTER_WIDTH-1:0]  num_references,
    output reg [COUNTER_WIDTH-1:0]  num_hits,
    output reg [COUNTER_WIDTH-1:0]  num_misses
    );

   wire request = rden | wren;
   reg  request_d;                         // request delayed by one cycle
   wire new_access = request & ~request_d; // rising edge => a fresh access

   real hit_rate;                          // used only inside report()

   always @(posedge clock) begin
      if (!rst_n) begin
         request_d <= 1'b0;
         num_references <= {COUNTER_WIDTH{1'b0}};
         num_hits <= {COUNTER_WIDTH{1'b0}};
         num_misses <= {COUNTER_WIDTH{1'b0}};
      end else begin
         request_d <= request;
         if (new_access) begin
            num_references <= num_references + 1'b1;
            if (hit) num_hits   <= num_hits   + 1'b1;
            else     num_misses <= num_misses + 1'b1;
         end
      end
   end

   // Pretty-print the counters. Call from the testbench as: STATS.report;
   task report;
      begin
         if (num_references != 0)
            hit_rate = (100.0 * num_hits) / num_references;
         else
            hit_rate = 0.0;
         $display("----------------------------------------");
         $display(" CACHE STATISTICS");
         $display("----------------------------------------");
         $display("   References : %0d", num_references);
         $display("   Hits       : %0d", num_hits);
         $display("   Misses     : %0d", num_misses);
         $display("   Hit rate   : %0.2f %%", hit_rate);
         $display("----------------------------------------");
      end
   endtask

endmodule // cache_stats
