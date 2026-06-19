library verilog;
use verilog.vl_types.all;
entity memory is
    generic(
        ADDRESS_WIDTH   : integer := 18;
        BLOCK_SIZE      : integer := 256;
        \FILE\          : string  := ""
    );
    port(
        clock           : in     vl_logic;
        din             : in     vl_logic_vector;
        address         : in     vl_logic_vector;
        rden            : in     vl_logic;
        wren            : in     vl_logic;
        dout            : out    vl_logic_vector
    );
end memory;
