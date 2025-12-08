module DecodeUI (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        is_active,
    
    input  wire [10:0] key_packet,
    input  wire        key_valid,
    
    // ? 버퍼 클리어 신호 추가
    input  wire        clear_buffer,
    
    // 동적 타이밍 입력
    input  wire [31:0] timeout_cycles,

    input  wire        lcd_busy,
    input  wire        lcd_done,
    output reg         lcd_req,
    output reg  [1:0]  lcd_row,
    output reg  [3:0]  lcd_col,
    output reg  [7:0]  lcd_char,

    output reg         change_req,
    output reg  [3:0]  next_ui_id
);

    localparam TYPE_KEY   = 3'b001;
    localparam KEY_DOT    = 8'd1;
    localparam KEY_DASH   = 8'd2;
    localparam KEY_BACK   = 8'd11;
    localparam UI_SELECT  = 4'h0;

    localparam ST_INIT        = 3'd0;
    localparam ST_IDLE        = 3'd1;
    localparam ST_DECODE      = 3'd2;
    localparam ST_WRITE_CHAR  = 3'd3;
    localparam ST_WRITE_SPACE = 3'd4;
    localparam ST_CLEAR       = 3'd5;  // ? 클리어 상태 추가

    reg [2:0] state;
    reg [7:0] line0[0:15];
    reg [7:0] line1[0:15];
    integer i;

    reg [3:0] cursor;
    reg [5:0] morse_code;
    reg [2:0] morse_len;
    reg [31:0] idle_counter;
    
    reg [31:0] timeout_threshold;
    reg [31:0] space_threshold;

    reg [5:0] init_step;
    reg [4:0] write_pos;

    initial begin
        state = ST_INIT;
        lcd_req = 1'b0;
        lcd_row = 2'd0;
        lcd_col = 4'd0;
        lcd_char = 8'd0;
        
        cursor = 4'd0;
        morse_code = 6'd0;
        morse_len = 3'd0;
        idle_counter = 32'd0;
        
        change_req = 1'b0;
        next_ui_id = 4'd0;
        
        init_step = 6'd0;
        write_pos = 5'd0;
        
        timeout_threshold = 32'd150_000_000;
        space_threshold = 32'd150_000_000;
        
        for(i=0; i<16; i=i+1) begin
            line0[i] = 8'd32;
            line1[i] = 8'd32;
        end
        
        line1[0] = 8'd68;  // D
        line1[1] = 8'd69;  // E
        line1[2] = 8'd67;  // C
        line1[3] = 8'd79;  // O
        line1[4] = 8'd68;  // D
        line1[5] = 8'd69;  // E
    end

    // 타임아웃 임계값 업데이트
    always @(posedge clk) begin
        timeout_threshold <= timeout_cycles;
        space_threshold <= timeout_cycles << 1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_INIT;
            lcd_req <= 1'b0;
            lcd_row <= 2'd0;
            lcd_col <= 4'd0;
            lcd_char <= 8'd0;
            
            cursor <= 4'd0;
            morse_code <= 6'd0;
            morse_len <= 3'd0;
            idle_counter <= 32'd0;
            
            change_req <= 1'b0;
            next_ui_id <= 4'd0;
            
            init_step <= 6'd0;
            write_pos <= 5'd0;
            
            for(i=0; i<16; i=i+1) begin
                line0[i] <= 8'd32;
                line1[i] <= 8'd32;
            end
            
            line1[0] <= 8'd68;
            line1[1] <= 8'd69;
            line1[2] <= 8'd67;
            line1[3] <= 8'd79;
            line1[4] <= 8'd68;
            line1[5] <= 8'd69;
        end
        else begin
            if(!is_active) begin
                state <= ST_INIT;
                lcd_req <= 1'b0;
                init_step <= 6'd0;
                cursor <= 4'd0;
                morse_code <= 6'd0;
                morse_len <= 3'd0;
                idle_counter <= 32'd0;
                change_req <= 1'b0;
                write_pos <= 5'd0;
                
                for(i=0; i<16; i=i+1)
                    line0[i] <= 8'd32;
            end
            else begin
                change_req <= 1'b0;

                case(state)
                    ST_INIT: begin
                        if(!lcd_busy && !lcd_req) begin
                            if(init_step < 16) begin
                                lcd_row <= 2'd0;
                                lcd_col <= init_step[3:0];
                                lcd_char <= line0[init_step[3:0]];
                                lcd_req <= 1'b1;
                            end
                            else if(init_step < 32) begin
                                lcd_row <= 2'd1;
                                lcd_col <= init_step[3:0];
                                lcd_char <= line1[init_step[3:0]];
                                lcd_req <= 1'b1;
                            end
                            else begin
                                state <= ST_IDLE;
                                idle_counter <= 32'd0;
                            end
                        end
                        else if(lcd_req && lcd_done) begin
                            lcd_req <= 1'b0;
                            init_step <= init_step + 1;
                        end
                    end

                    ST_IDLE: begin
                        // ? 버퍼 클리어 체크 (최우선)
                        if(clear_buffer) begin
                            // 버퍼 초기화
                            for(i=0; i<16; i=i+1)
                                line0[i] <= 8'd32;
                            
                            cursor <= 4'd0;
                            morse_code <= 6'd0;
                            morse_len <= 3'd0;
                            idle_counter <= 32'd0;
                            write_pos <= 5'd0;
                            
                            state <= ST_CLEAR;
                        end
                        else if(key_valid && key_packet[10:8]==TYPE_KEY && key_packet[7:0]==KEY_BACK) begin
                            change_req <= 1'b1;
                            next_ui_id <= UI_SELECT;
                        end
                        else if(key_valid && key_packet[10:8]==TYPE_KEY) begin
                            case(key_packet[7:0])
                                KEY_DOT: begin
                                    if(morse_len < 6) begin
                                        morse_code <= {morse_code[4:0], 1'b0};
                                        morse_len <= morse_len + 3'd1;
                                        idle_counter <= 32'd0;
                                    end
                                end
                                
                                KEY_DASH: begin
                                    if(morse_len < 6) begin
                                        morse_code <= {morse_code[4:0], 1'b1};
                                        morse_len <= morse_len + 3'd1;
                                        idle_counter <= 32'd0;
                                    end
                                end
                            endcase
                        end
                        else begin
                            if(idle_counter < space_threshold) begin
                                idle_counter <= idle_counter + 32'd1;
                            end
                            
                            if(idle_counter == timeout_threshold && morse_len > 0) begin
                                state <= ST_DECODE;
                            end
                            
                            if(idle_counter == space_threshold && morse_len == 0 && cursor < 16) begin
                                line0[cursor] <= 8'd32;
                                write_pos <= 5'd0;
                                state <= ST_WRITE_SPACE;
                            end
                        end
                    end

                    ST_DECODE: begin
                        if(cursor < 16) begin
                            line0[cursor] <= morse_lookup(morse_code, morse_len);
                            morse_code <= 6'd0;
                            morse_len <= 3'd0;
                            write_pos <= 5'd0;
                            state <= ST_WRITE_CHAR;
                        end
                        else begin
                            morse_code <= 6'd0;
                            morse_len <= 3'd0;
                            idle_counter <= 32'd0;
                            state <= ST_IDLE;
                        end
                    end

                    ST_WRITE_CHAR: begin
                        if(!lcd_busy && !lcd_req) begin
                            if(write_pos < 16) begin
                                lcd_row <= 2'd0;
                                lcd_col <= write_pos[3:0];
                                lcd_char <= line0[write_pos[3:0]];
                                lcd_req <= 1'b1;
                                write_pos <= write_pos + 5'd1;
                            end
                            else begin
                                cursor <= cursor + 4'd1;
                                idle_counter <= 32'd0;
                                state <= ST_IDLE;
                            end
                        end
                        else if(lcd_req && lcd_done) begin
                            lcd_req <= 1'b0;
                        end
                    end

                    ST_WRITE_SPACE: begin
                        if(!lcd_busy && !lcd_req) begin
                            if(write_pos < 16) begin
                                lcd_row <= 2'd0;
                                lcd_col <= write_pos[3:0];
                                lcd_char <= line0[write_pos[3:0]];
                                lcd_req <= 1'b1;
                                write_pos <= write_pos + 5'd1;
                            end
                            else begin
                                cursor <= cursor + 4'd1;
                                idle_counter <= 32'd0;
                                state <= ST_IDLE;
                            end
                        end
                        else if(lcd_req && lcd_done) begin
                            lcd_req <= 1'b0;
                        end
                    end

                    // ? 버퍼 클리어 상태
                    ST_CLEAR: begin
                        if(!lcd_busy && !lcd_req) begin
                            if(write_pos < 16) begin
                                lcd_row <= 2'd0;
                                lcd_col <= write_pos[3:0];
                                lcd_char <= 8'd32;  // 공백으로 채우기
                                lcd_req <= 1'b1;
                                write_pos <= write_pos + 5'd1;
                            end
                            else begin
                                write_pos <= 5'd0;
                                state <= ST_IDLE;
                            end
                        end
                        else if(lcd_req && lcd_done) begin
                            lcd_req <= 1'b0;
                        end
                    end

                    default: state <= ST_INIT;
                endcase
            end
        end
    end

    function [7:0] morse_lookup;
        input [5:0] code;
        input [2:0] len;
        begin
            case(len)
                3'd1: morse_lookup = (code[0]==1'b0) ? 8'd69 : 8'd84;
                
                3'd2: begin
                    case(code[1:0])
                        2'b00: morse_lookup = 8'd73;
                        2'b01: morse_lookup = 8'd65;
                        2'b10: morse_lookup = 8'd78;
                        2'b11: morse_lookup = 8'd77;
                        default: morse_lookup = 8'd63;
                    endcase
                end
                
                3'd3: begin
                    case(code[2:0])
                        3'b000: morse_lookup = 8'd83;
                        3'b001: morse_lookup = 8'd85;
                        3'b010: morse_lookup = 8'd82;
                        3'b011: morse_lookup = 8'd87;
                        3'b100: morse_lookup = 8'd68;
                        3'b101: morse_lookup = 8'd75;
                        3'b110: morse_lookup = 8'd71;
                        3'b111: morse_lookup = 8'd79;
                        default: morse_lookup = 8'd63;
                    endcase
                end
                
                3'd4: begin
                    case(code[3:0])
                        4'b0000: morse_lookup = 8'd72;
                        4'b0001: morse_lookup = 8'd86;
                        4'b0010: morse_lookup = 8'd70;
                        4'b0100: morse_lookup = 8'd76;
                        4'b0110: morse_lookup = 8'd80;
                        4'b0111: morse_lookup = 8'd74;
                        4'b1000: morse_lookup = 8'd66;
                        4'b1001: morse_lookup = 8'd88;
                        4'b1010: morse_lookup = 8'd67;
                        4'b1011: morse_lookup = 8'd89;
                        4'b1100: morse_lookup = 8'd90;
                        4'b1101: morse_lookup = 8'd81;
                        default: morse_lookup = 8'd63;
                    endcase
                end
                
                3'd5: begin
                    case(code[4:0])
                        5'b00000: morse_lookup = 8'd53;
                        5'b00001: morse_lookup = 8'd52;
                        5'b00011: morse_lookup = 8'd51;
                        5'b00111: morse_lookup = 8'd50;
                        5'b01111: morse_lookup = 8'd49;
                        5'b10000: morse_lookup = 8'd54;
                        5'b11000: morse_lookup = 8'd55;
                        5'b11100: morse_lookup = 8'd56;
                        5'b11110: morse_lookup = 8'd57;
                        5'b11111: morse_lookup = 8'd48;
                        default: morse_lookup = 8'd63;
                    endcase
                end
                
                default: morse_lookup = 8'd63;
            endcase
        end
    endfunction

endmodule