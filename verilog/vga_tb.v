module test();
    reg clk = 0;

    wire [1:0] r;
    wire [1:0] g;
    wire [1:0] b;
    wire h_sync;
    wire v_sync;

    always
    #1 clk = ~clk;

    top hello(clk, r, g, b, h_sync, v_sync);

    initial begin
        $dumpfile("vga.vcd");
        $dumpvars(0, test);

        #10000 $finish;
    end
endmodule
