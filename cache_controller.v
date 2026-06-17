`include "defs.vh"
`timescale 1ns/1ps

module cache_controller
  #(
    parameter BLOCK_SIZE = 256,
    parameter ADDRESS_WIDTH = 21,
    parameter INDEX_WIDTH = 8,     // 256 sets
    parameter TAG_WIDTH = 10,      // 21 - 8 - 3 = 10 bits
    parameter OFFSET_WIDTH = 3,
    parameter WORD_SIZE = 32,
    parameter NSETS = 256,
    parameter WAYS = 4
)
   (
    input wire                                  clock,
    input wire                                  rst_n,
    input wire [ADDRESS_WIDTH - 1:0]            caddress,
    input wire [WORD_SIZE - 1:0]                cdin,
    input wire [BLOCK_SIZE - 1:0]               mdin,
    input wire                                  rden,
    input wire                                  wren,
    output wire                                 hit,
    output reg [WORD_SIZE - 1:0]                cdout,
    output reg [BLOCK_SIZE - 1:0]               mdout,
    output reg [TAG_WIDTH + INDEX_WIDTH - 1:0]  maddress,
    output reg                                  mrden,
    output reg                                  mwren
    );

   // FSM States using localparam
   localparam STATE_IDLE       = 3'd0,
              STATE_READ_HIT   = 3'd1,
              STATE_READ_MISS  = 3'd2,
              STATE_WRITE_HIT  = 3'd3,
              STATE_WRITE_MISS = 3'd4,
              STATE_REPLACE    = 3'd5,
              STATE_FETCH      = 3'd6,
              STATE_FILL       = 3'd7;

   reg [2:0] current_state, next_state;

   localparam TAG_MSB           = 20;
   localparam TAG_LSB           = 11;
   localparam INDEX_MSB         = 10;
   localparam INDEX_LSB         = 3;
   localparam BLOCK_OFFSET_MSB  = 2;
   localparam BLOCK_OFFSET_LSB  = 0;

   // 2D Arrays for 4-way Set Associativity
   reg                         cache_valid [0:NSETS - 1][0:WAYS - 1];
   reg                         cache_dirty [0:NSETS - 1][0:WAYS - 1];
   reg [TAG_WIDTH - 1:0]       cache_tag   [0:NSETS - 1][0:WAYS - 1];
   reg [BLOCK_SIZE - 1:0]      cache_mem   [0:NSETS - 1][0:WAYS - 1];
   reg [1:0]                   cache_lru   [0:NSETS - 1][0:WAYS - 1];

   reg [ADDRESS_WIDTH - 1:0]   req_addr;
   reg                         req_read;
   reg                         req_write;
   reg [WORD_SIZE - 1:0]       req_wdata;

   wire [ADDRESS_WIDTH - 1:0]  active_addr;
   wire [INDEX_WIDTH - 1:0]    active_index;
   wire [TAG_WIDTH - 1:0]      active_tag;
   wire [OFFSET_WIDTH - 1:0]   active_offset;

   wire                        lookup_hit;
   wire [WORD_SIZE - 1:0]      read_data;
   
   // Way selection logic signals
   reg [WAYS-1:0]              way_hit;
   reg [1:0]                   hit_way_idx;
   reg [1:0]                   victim_way_idx;
   reg [1:0]                   target_way;

   // Loop iteration variables
   integer i, j, k, w;
   reg [1:0] old_lru; // Temp holding register for LRU updates

   // Helper Functions
   function [WORD_SIZE - 1:0] block_get_word;
      input [BLOCK_SIZE - 1:0] block;
      input [OFFSET_WIDTH - 1:0] word_offset;
      begin
         block_get_word = block[32 * word_offset +: WORD_SIZE];
      end
   endfunction

   function [BLOCK_SIZE - 1:0] block_set_word;
      input [BLOCK_SIZE - 1:0] block;
      input [OFFSET_WIDTH - 1:0] word_offset;
      input [WORD_SIZE - 1:0] word;
      reg [BLOCK_SIZE - 1:0] result;
      begin
         result = block;
         result[32 * word_offset +: WORD_SIZE] = word;
         block_set_word = result;
      end
   endfunction

   // Address Decoding
   assign active_addr   = (current_state == STATE_IDLE) ? caddress : req_addr;
   assign active_index  = active_addr[INDEX_MSB:INDEX_LSB];
   assign active_tag    = active_addr[TAG_MSB:TAG_LSB];
   assign active_offset = active_addr[BLOCK_OFFSET_MSB:BLOCK_OFFSET_LSB];

   // Hit Logic (Parallel check across all 4 ways)
   always @* begin
      way_hit = 0;
      for (i = 0; i < WAYS; i = i + 1) begin
         if (cache_valid[active_index][i] && (cache_tag[active_index][i] == active_tag))
            way_hit[i] = 1'b1;
      end
   end

   assign lookup_hit = |way_hit;
   assign hit = lookup_hit;

   // Determine which way was hit
   always @* begin
      hit_way_idx = 2'b00;
      if (way_hit[1]) hit_way_idx = 2'b01;
      if (way_hit[2]) hit_way_idx = 2'b10;
      if (way_hit[3]) hit_way_idx = 2'b11;
   end

   // LRU Victim Selection (Find invalid first, then find LRU == 3)
   always @* begin
      victim_way_idx = 2'b00;
      if      (!cache_valid[active_index][0]) victim_way_idx = 2'b00;
      else if (!cache_valid[active_index][1]) victim_way_idx = 2'b01;
      else if (!cache_valid[active_index][2]) victim_way_idx = 2'b10;
      else if (!cache_valid[active_index][3]) victim_way_idx = 2'b11;
      else begin
         if      (cache_lru[active_index][0] == 2'b11) victim_way_idx = 2'b00;
         else if (cache_lru[active_index][1] == 2'b11) victim_way_idx = 2'b01;
         else if (cache_lru[active_index][2] == 2'b11) victim_way_idx = 2'b10;
         else                                          victim_way_idx = 2'b11;
      end
   end

   // Multiplex the target block data for reads
   assign read_data = block_get_word(cache_mem[active_index][target_way], active_offset);

   // Combinational FSM Output Logic
   always @* begin
      next_state = current_state;
      cdout    = 0;
      mdout    = 0;
      maddress = 0;
      mrden    = 1'b0;
      mwren    = 1'b0;

      case (current_state)
         STATE_IDLE: begin
            if (rden && lookup_hit)
               next_state = STATE_READ_HIT;
            else if (rden)
               next_state = STATE_READ_MISS;
            else if (wren && lookup_hit)
               next_state = STATE_WRITE_HIT;
            else if (wren)
               next_state = STATE_WRITE_MISS;
         end

         STATE_READ_HIT: begin
            cdout = read_data;
            next_state = STATE_IDLE;
         end

         STATE_READ_MISS: begin
            if (cache_dirty[active_index][target_way])
               next_state = STATE_REPLACE;
            else
               next_state = STATE_FETCH;
         end

         STATE_WRITE_MISS: begin
            if (cache_dirty[active_index][target_way])
               next_state = STATE_REPLACE;
            else
               next_state = STATE_FETCH;
         end

         STATE_REPLACE: begin
            mwren    = 1'b1;
            maddress = {cache_tag[active_index][target_way], active_index};
            mdout    = cache_mem[active_index][target_way];
            next_state = STATE_FETCH;
         end

         STATE_FETCH: begin
            mrden    = 1'b1;
            maddress = {active_tag, active_index};
            next_state = STATE_FILL;
         end

         STATE_FILL: begin
            if (req_read)
               next_state = STATE_READ_HIT;
            else if (req_write)
               next_state = STATE_WRITE_HIT;
            else
               next_state = STATE_IDLE;
         end

         STATE_WRITE_HIT: begin
            next_state = STATE_IDLE;
         end

         default: begin
            next_state = STATE_IDLE;
         end
      endcase
   end

   // Initialization
   initial begin
      for (k = 0; k < NSETS; k = k + 1) begin
         for (w = 0; w < WAYS; w = w + 1) begin
            cache_valid[k][w] = 1'b0;
            cache_dirty[k][w] = 1'b0;
            cache_tag[k][w]   = 0;
            cache_mem[k][w]   = 0;
            cache_lru[k][w]   = w[1:0]; // Init 0,1,2,3 permutation
         end
      end
   end

   // Sequential FSM & Datapath Logic
   always @(posedge clock) begin
      if (!rst_n) begin
         current_state <= STATE_IDLE;
         req_read      <= 1'b0;
         req_write     <= 1'b0;
         target_way    <= 2'b00;
         req_addr      <= 0;
         req_wdata     <= 0;
         for (k = 0; k < NSETS; k = k + 1) begin
            for (w = 0; w < WAYS; w = w + 1) begin
               cache_valid[k][w] <= 1'b0;
               cache_dirty[k][w] <= 1'b0;
               cache_tag[k][w]   <= 0;
               cache_mem[k][w]   <= 0;
               cache_lru[k][w]   <= w[1:0];
            end
         end
      end else begin
         current_state <= next_state;

         // Latch Request Data on IDLE Transition
         if (current_state == STATE_IDLE && (rden || wren)) begin
            req_addr   <= caddress;
            req_read   <= rden;
            req_write  <= wren;
            req_wdata  <= cdin;
            // Latch the exact way we are hitting, or the victim we plan to replace
            target_way <= lookup_hit ? hit_way_idx : victim_way_idx;
         end

         // Handle Main Memory Block Fill
         if (current_state == STATE_FILL) begin
            cache_mem[active_index][target_way]   <= mdin;
            cache_tag[active_index][target_way]   <= active_tag;
            cache_valid[active_index][target_way] <= 1'b1;
            cache_dirty[active_index][target_way] <= 1'b0;
         end

         // Handle Write Data Merge into Cache Block
         if (current_state == STATE_WRITE_HIT) begin
            cache_mem[active_index][target_way] <= block_set_word(
               cache_mem[active_index][target_way], active_offset, req_wdata
            );
            cache_dirty[active_index][target_way] <= 1'b1;
         end

         // Update LRU Counter exclusively during Hit States
         if (current_state == STATE_READ_HIT || current_state == STATE_WRITE_HIT) begin
            old_lru = cache_lru[active_index][target_way];
            cache_lru[active_index][target_way] <= 2'b00; // Accessed way becomes MRU

            for (j = 0; j < WAYS; j = j + 1) begin
               // Increment ways that were strictly newer than the old age
               if (j != target_way && cache_lru[active_index][j] < old_lru) begin
                  cache_lru[active_index][j] <= cache_lru[active_index][j] + 1;
               end
            end
         end
      end
   end

endmodule