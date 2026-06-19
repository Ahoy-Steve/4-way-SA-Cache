library verilog;
use verilog.vl_types.all;
entity cache_stats is
    generic(
        COUNTER_WIDTH   : integer := 32
    );
    port(
        clock           : in     vl_logic;
        rst_n           : in     vl_logic;
        rden            : in     vl_logic;
        wren            : in     vl_logic;
        hit             : in     vl_logic;
        num_references  : out    vl_logic_vector;
        num_hits        : out    vl_logic_vector;
        num_misses      : out    vl_logic_vector
    );
end cache_stats;
