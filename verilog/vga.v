module top (
    input clk,

    output [1:0] r,
    output [1:0] g,
    output [1:0] b,
    output h_sync,
    output v_sync //
);
    // Important information when loading images
    //
    // Image should not contain greater than 128x128 pixels due to block ram size limitations
    // 128x128 is the max, however 100x100 is recommended as some more complex 128x128 images will not load
    // Non square aspect ratios are also supported, and can be scaled
    //
    // Each colour channel only has 2 bits so that an entire pixel can fit in a byte

    parameter IMAGE_HEX_FILE = "demo.hex";

    // Image physical dimensions
    parameter IMAGE_SOURCE_X = 100;
    parameter IMAGE_SOURCE_Y = 100;

    // Image scale can be used to increase the size of the image on the screen by repeating pixels
    // The image as it appears on screen is scaled by 2^(IMAGE_SCALE - 1)
    parameter IMAGE_SCALE = 3;
    parameter IMAGE_PIXELS_X = IMAGE_SOURCE_X * (1 << (IMAGE_SCALE - 1));
    parameter IMAGE_PIXELS_Y = IMAGE_SOURCE_Y * (1 << (IMAGE_SCALE - 1));;
    

    // 800 x 600 @ 56Hz
    // Originally 36MHz pixel clock, multiplied horizontal timings by 0.75 to reach 27 MHz pixel clock
    // The result is a stretched resolution (600x600 across 800x600)
    // http://tinyvga.com/vga-timing/800x600@56Hz

    `define COUNTER_BUS_WIDTH 10 // Counter bus must be able to hold maximum value stored in either the horizontal or vertical counter, in this case 768
    `define MEMORY_ADDRESS_BITS 14 // Number of bits addressable to the fpga block ram

    // Horizontal timing, total 768 pixels, 28.44 us @ 27MHz
    parameter [`COUNTER_BUS_WIDTH - 1:0] H_DISPLAY_PIXELS = 600;
    parameter [`COUNTER_BUS_WIDTH - 1:0] H_FRONT_PORCH_PIXELS = 18;
    parameter [`COUNTER_BUS_WIDTH - 1:0] H_SYNC_PIXELS = 54;
    parameter [`COUNTER_BUS_WIDTH - 1:0] H_BACK_PORCH_PIXELS = 96;

    // Vertical timing, total 625 lines, 17.78 ms @ 27MHz
    parameter [`COUNTER_BUS_WIDTH - 1:0] V_DISPLAY_LINES = 600;
    parameter [`COUNTER_BUS_WIDTH - 1:0] V_FRONT_PORCH_LINES = 1;
    parameter [`COUNTER_BUS_WIDTH - 1:0] V_SYNC_LINES = 2;
    parameter [`COUNTER_BUS_WIDTH - 1:0] V_BACK_PORCH_LINES = 22;



    wire [1:0] h_signals;
    wire [1:0] v_signals;

    wire [`COUNTER_BUS_WIDTH - 1:0] h_counter;
    wire [`COUNTER_BUS_WIDTH - 1:0] v_counter;

    wire v_clk;
    wire nc;

    // Generate horizontal timing
    line_timing h(
        // Inputs
        clk,
        H_DISPLAY_PIXELS,
        H_FRONT_PORCH_PIXELS,
        H_SYNC_PIXELS,
        H_BACK_PORCH_PIXELS,

        // Outputs
        h_signals,
        h_counter,
        v_clk
    );

    // Generate vertical timing
    line_timing v(
        // Inputs
        v_clk,
        V_DISPLAY_LINES,
        V_FRONT_PORCH_LINES,
        V_SYNC_LINES,
        V_BACK_PORCH_LINES,
        
        // Outputs
        v_signals,
        v_counter,
        nc
    );



    // Read hex file to screen buffer
    reg [5:0] screen_buffer [(IMAGE_SOURCE_X * IMAGE_SOURCE_Y):0];
    initial screen_buffer[(IMAGE_SOURCE_X * IMAGE_SOURCE_Y)] <= 0; // Inferer BRAM
    initial $readmemh(IMAGE_HEX_FILE, screen_buffer, 0, (IMAGE_SOURCE_X * IMAGE_SOURCE_Y) - 1);

    reg [`MEMORY_ADDRESS_BITS - 1:0] screen_address = 0;
    reg [5:0] pixel = 0;

    // These counters only count the pixels and lines, not the blanking areas
    reg [`COUNTER_BUS_WIDTH - 1:0] h_pixel_counter;
    reg [`COUNTER_BUS_WIDTH - 1:0] v_line_counter;

    reg display_reg = 0;
    reg h_sync_reg = 0;
    reg v_sync_reg = 0;



    // Convert horizontal and vertical counters, into pixel and line counters which only count the screenspace
    // These counters are needed to address memory, so that memory addresses do not need to be wasted on off pixels during blanking intervals
    always @(*) begin
        if (h_counter < IMAGE_PIXELS_X) begin
            h_pixel_counter = h_counter >> IMAGE_SCALE - 1;
        end else begin
            h_pixel_counter = 0;
        end

        if (v_counter < IMAGE_PIXELS_Y) begin
            v_line_counter = v_counter >> IMAGE_SCALE - 1;
        end else begin
            v_line_counter = 0;
        end

        pixel = screen_buffer[screen_address]; // Get pixel
    end



    // Updates screen address, and misc registers
    always @(posedge clk) begin
        screen_address <= {{14 - `COUNTER_BUS_WIDTH{1'b0}}, h_pixel_counter} + (v_line_counter * IMAGE_SOURCE_X); // Convert x and y coordinates to screen buffer indices
        
        // Pixels appear one clock cycle late due to screen_address being calculated as part of a non-blocking statement
        // So a non-blocking statement must also be used to assign the horizontal and vertical sync signals to ensure that timing is maintained
        h_sync_reg <= h_signals[0];
        v_sync_reg <= v_signals[0];

        if (h_counter > IMAGE_PIXELS_X - 1 | v_counter > IMAGE_PIXELS_Y - 1) begin // This if statement ensures pixels outside of the image resolution are turned off
            display_reg <= 0;
        end else begin
            display_reg <= h_signals[1] & v_signals[1]; // Only display when both horizontal and vertical counters are in their visible areas
        end
    end



    reg [1:0] r_reg;
    reg [1:0] g_reg;
    reg [1:0] b_reg;

    // Seperate pixel into r, g, b values
    always @(*) begin
        if (display_reg) begin
            r_reg = {pixel[5], pixel[4]};
            g_reg = {pixel[3], pixel[2]};
            b_reg = {pixel[1], pixel[0]};
        end else begin
            r_reg = 0;
            g_reg = 0;
            b_reg = 0;
        end
    end

    assign h_sync = h_sync_reg;
    assign v_sync = v_sync_reg;

    assign r = r_reg;
    assign g = g_reg;
    assign b = b_reg;

endmodule

// Generate either horizontal or vertical timing for vga display
module line_timing(
    input clk,
    input [`COUNTER_BUS_WIDTH - 1:0] visible, 
    input [`COUNTER_BUS_WIDTH - 1:0] front,
    input [`COUNTER_BUS_WIDTH - 1:0] sync,
    input [`COUNTER_BUS_WIDTH - 1:0] back,

    output [1:0] signals, // signals[0] = ~snyc pulse, signals[1] = visible area
    output [`COUNTER_BUS_WIDTH - 1:0] counter,
    output reset // Goes high for one clock pulse once the counter resets
);
    reg [`COUNTER_BUS_WIDTH - 1:0] counter_reg = 0;
    reg [1:0] signals_reg = 0;
    reg reset_reg = 0;

    // Count pixels / lines every clock
    always @(posedge clk) begin
        counter_reg <= counter_reg + 1;
        if (counter_reg == (visible + front + sync + back) - 1) begin
            counter_reg <= 0;
            reset_reg <= 1;
        end else begin
            reset_reg <= 0;
        end
    end

    // Convert pixels / lines into usable signals which indicate wether the display is in the visible area, or sync area
    always @(*) begin
        if (counter_reg < visible) begin
            signals_reg = 2'b11; // Visible area
        end else if (counter_reg < visible + front) begin
            signals_reg = 2'b01; // Front porch
        end else if (counter_reg < visible + front + sync) begin
            signals_reg = 2'b00; // Sync pulse (active low)
        end else begin
            signals_reg = 2'b01; // Back porch
        end
    end

    assign signals = signals_reg;
    assign reset = reset_reg;
    assign counter = counter_reg;
    
endmodule
