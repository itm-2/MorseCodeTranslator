module EncoderPiezoPlayer #(
    parameter CLK_FREQ = 50_000_000,
    parameter TONE_FREQ = 440  // ? 파라미터로 변경!
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [255:0] bitstream,
    input  wire [8:0]  bit_length,
    
    input  wire [31:0] DitTime,
    input  wire [31:0] DahTime,
    input  wire [31:0] DitGap,
    
    output reg         busy,
    output reg         done,
    output reg         piezo_out
);

    // ? 톤 생성 주기 계산
    localparam HALF_PERIOD = CLK_FREQ / (2 * TONE_FREQ);
    
    localparam IDLE    = 2'd0;
    localparam DECODE  = 2'd1;
    localparam PLAY    = 2'd2;
    localparam DONE_ST = 2'd3;
    
    reg [1:0] state;
    reg [8:0] bit_index;
    reg [255:0] bitstream_reg;
    reg [31:0] play_timer;
    reg [31:0] tone_counter;
    
    reg [1:0] current_symbol;
    reg [31:0] current_duration;
    reg        current_tone_enable;
    reg [2:0]  current_bits_consumed;
    
    // 디코딩 로직
    reg [1:0] next_symbol;
    reg [31:0] next_duration;
    reg next_tone_enable;
    reg [2:0] next_bits_consumed;
    
    always @(*) begin
        next_symbol = 2'd0;
        next_bits_consumed = 3'd1;
        next_duration = DitTime + DitGap;
        next_tone_enable = 1'b1;
        
        if (bit_index < bit_length) begin
            if (bit_index + 3 < bit_length &&
                bitstream_reg[bit_index] == 1'b1 &&
                bitstream_reg[bit_index+1] == 1'b1 &&
                bitstream_reg[bit_index+2] == 1'b1 &&
                bitstream_reg[bit_index+3] == 1'b1) begin
                next_symbol = 2'd3;
                next_bits_consumed = 3'd4;
                next_duration = DitGap * 7;
                next_tone_enable = 1'b0;
            end
            else if (bit_index + 1 < bit_length &&
                     bitstream_reg[bit_index] == 1'b1 &&
                     bitstream_reg[bit_index+1] == 1'b1) begin
                next_symbol = 2'd2;
                next_bits_consumed = 3'd2;
                next_duration = DitGap * 3;
                next_tone_enable = 1'b0;
            end
            else if (bit_index + 1 < bit_length &&
                     bitstream_reg[bit_index] == 1'b1 &&
                     bitstream_reg[bit_index+1] == 1'b0) begin
                next_symbol = 2'd1;
                next_bits_consumed = 3'd2;
                next_duration = DahTime + DitGap;
                next_tone_enable = 1'b1;
            end
            else if (bitstream_reg[bit_index] == 1'b0) begin
                next_symbol = 2'd0;
                next_bits_consumed = 3'd1;
                next_duration = DitTime + DitGap;
                next_tone_enable = 1'b1;
            end
            else begin
                next_symbol = 2'd0;
                next_bits_consumed = 3'd1;
                next_duration = DitGap;
                next_tone_enable = 1'b0;
            end
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            piezo_out <= 1'b0;
            bit_index <= 9'd0;
            bitstream_reg <= 256'd0;
            play_timer <= 32'd0;
            tone_counter <= 32'd0;
            current_symbol <= 2'd0;
            current_duration <= 32'd0;
            current_tone_enable <= 1'b0;
            current_bits_consumed <= 3'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    piezo_out <= 1'b0;
                    if (start && bit_length > 0) begin
                        bitstream_reg <= bitstream;
                        bit_index <= 9'd0;
                        busy <= 1'b1;
                        state <= DECODE;
                    end
                end
                
                DECODE: begin
                    if (bit_index >= bit_length) begin
                        state <= DONE_ST;
                    end else begin
                        current_symbol <= next_symbol;
                        current_duration <= next_duration;
                        current_tone_enable <= next_tone_enable;
                        current_bits_consumed <= next_bits_consumed;
                        play_timer <= 32'd0;
                        tone_counter <= 32'd0;
                        state <= PLAY;
                    end
                end
                
                PLAY: begin
                    if (play_timer >= current_duration - 1) begin
                        play_timer <= 32'd0;
                        tone_counter <= 32'd0;
                        piezo_out <= 1'b0;
                        bit_index <= bit_index + current_bits_consumed;
                        state <= DECODE;
                    end else begin
                        play_timer <= play_timer + 1;
                        
                        if (current_tone_enable) begin
                            if (current_symbol == 2'd0) begin
                                // Dit
                                if (play_timer < DitTime) begin
                                    if (tone_counter >= HALF_PERIOD - 1) begin
                                        tone_counter <= 32'd0;
                                        piezo_out <= ~piezo_out;
                                    end else begin
                                        tone_counter <= tone_counter + 1;
                                    end
                                end else begin
                                    piezo_out <= 1'b0;
                                end
                            end else begin
                                // Dah
                                if (play_timer < DahTime ) begin
                                    if (tone_counter >= HALF_PERIOD - 1) begin
                                        tone_counter <= 32'd0;
                                        piezo_out <= ~piezo_out;
                                    end else begin
                                        tone_counter <= tone_counter + 1;
                                    end
                                end else begin
                                    piezo_out <= 1'b0;
                                end
                            end
                        end else begin
                            piezo_out <= 1'b0;
                        end
                    end
                end
                
                DONE_ST: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    piezo_out <= 1'b0;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
