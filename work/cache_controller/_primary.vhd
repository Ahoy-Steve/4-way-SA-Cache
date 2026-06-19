library verilog;
use verilog.vl_types.all;
entity cache_controller is
    generic(
        BLOCK_SIZE      : integer := 256;
        ADDRESS_WIDTH   : integer := 21;
        INDEX_WIDTH     : integer := 8;
        TAG_WIDTH       : integer := 10;
        OFFSET_WIDTH    : integer := 3;
        WORD_SIZE       : integer := 32;
        NSETS           : integer := 256;
        WAYS            : integer := 4
    );
    port(
        clock           : in     vl_logic;
        rst_n           : in     vl_logic;
        caddress        : in     vl_logic_vector;
        cdin            : in     vl_logic_vector;
        mdin            : in     vl_logic_vector;
        rden            : in     vl_logic;
        wren            : in     vl_logic;
        hit             : out    vl_logic;
        cdout           : out    vl_logic_vector;
        mdout           : out    vl_logic_vector;
        maddress        : out    vl_logic_vector;
        mrden           : out    vl_logic;
        mwren           : out    vl_logic
    );
end cache_controller;
