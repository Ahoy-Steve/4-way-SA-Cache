`include "defs.vh"
`timescale 1ns/1ps

module memory
  #(parameter ADDRESS_WIDTH = 18,
    parameter BLOCK_SIZE = 256,
    parameter FILE = ""
    )
   (
    input wire clock,
    input wire [BLOCK_SIZE - 1:0] din,
    input wire [ADDRESS_WIDTH - 1:0] address,
    input wire rden,
    input wire wren,
    output reg [BLOCK_SIZE -1:0] dout
    );

   localparam DEPTH = 2 ** 18;
   
   reg [BLOCK_SIZE-1:0] mem [0:DEPTH-1];

   integer              i;

   initial
     begin
        //read file content
        if (FILE != "")
          $readmemh(FILE, mem);
        else
          for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = {BLOCK_SIZE{1'b0}};
     end

   always @(posedge clock)
     begin
        if (wren)
          mem[address] <= din;
     end

   always @(posedge clock)
     begin
        if (rden)
          dout <= mem[address];
     end

endmodule // memory