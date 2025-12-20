`timescale 1ns / 1ps

module DecodeUI (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        is_active,
    
    input  wire [10:0] key_packet,
    input  wire        key_valid,
    
    input  wire        clear_buffer,
    
    input  wire [31:0] timeout_cycles,

    input  wire        lcd_busy,
    input  wire        lcd_done,
    output reg         lcd_req,
    output reg  [1:0]  lcd_row,
    output reg  [3:0]  lcd_col,
    output reg  [7:0]  lcd_char,

    output reg         change_req,
    output reg  [3:0]  next_ui_id,
    output reg         char_complete_beep,

    // 추가: LED 출력 (Top에서 led mux에 사용)
    output reg  [7:0]  led_out
);

    localparam TYPE_KEY   = 3'b001;
    localparam KEY_DOT    = 8'd1;
    localparam KEY_DASH   = 8'd2;
    localparam KEY_PAUSE  = 8'd12; 
    localparam UI_SELECT  = 4'h0;

    localparam ST_INIT          = 3'd0;
    localparam ST_IDLE          = 3'd1;
    localparam ST_DECODE        = 3'd2;
    localparam ST_WRITE_CHAR    = 3'd3;
    localparam ST_WRITE_SPACE   = 3'd4;
    localparam ST_CLEAR         = 3'd5;
    localparam ST_UPDATE_CURSOR = 3'd6;

    reg [2:0] state;
    reg [7:0] line0[0:15];
    reg [7:0] line1[0:15];

    reg [3:0] cursor;
    reg [5:0] morse_code;
    reg [2:0] morse_len;
    reg [31:0] idle_counter;
    
    reg [31:0] timeout_threshold;
    reg [31:0] space_threshold;

    reg [5:0] init_step;
    reg [4:0] write_pos;

    reg pause_pressed;
    reg pause_key_prev;
    
    reg pause_lcd_busy;
    reg [4:0] pause_write_pos;
    reg pause_lcd_req_pending;
    
    reg dot_key_prev;
    reg dash_key_prev;
    
    reg cursor_update_pending;
    reg [3:0] old_cursor_pos;

    // ========== initial 블록 (FPGA 합성 지원 가정) ==========
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
        space_threshold   = 32'd150_000_000;
        
        char_complete_beep = 1'b0;
        pause_pressed = 1'b0;
        pause_key_prev = 1'b0;
        
        pause_lcd_busy = 1'b0;
        pause_write_pos = 5'd0;
        pause_lcd_req_pending = 1'b0;
        
        dot_key_prev = 1'b0;
        dash_key_prev = 1'b0;
        
        cursor_update_pending = 1'b0;
        old_cursor_pos = 4'd0;

        led_out = 8'b0000_0111;
        
        // line0 초기화 (공백)
        line0[0] = 8'd32; line0[1] = 8'd32; line0[2] = 8'd32; line0[3] = 8'd32;
        line0[4] = 8'd32; line0[5] = 8'd32; line0[6] = 8'd32; line0[7] = 8'd32;
        line0[8] = 8'd32; line0[9] = 8'd32; line0[10] = 8'd32; line0[11] = 8'd32;
        line0[12] = 8'd32; line0[13] = 8'd32; line0[14] = 8'd32; line0[15] = 8'd32;
        
        // line1 기본 공백
        line1[0] = 8'd32; line1[1] = 8'd32; line1[2] = 8'd32; line1[3] = 8'd32;
        line1[4] = 8'd32; line1[5] = 8'd32; line1[6] = 8'd32; line1[7] = 8'd32;
        line1[8] = 8'd32; line1[9] = 8'd32; line1[10] = 8'd32; line1[11] = 8'd32;
        line1[12] = 8'd32; line1[13] = 8'd32; line1[14] = 8'd32; line1[15] = 8'd32;
        
        // "DECODE" 표시 (line1[0..5])
        line1[0] = 8'd68;  // D
        line1[1] = 8'd69;  // E
        line1[2] = 8'd67;  // C
        line1[3] = 8'd79;  // O
        line1[4] = 8'd68;  // D
        line1[5] = 8'd69;  // E
    end

    // ========== 키 디코드 ==========
    wire is_key_input = key_valid && (key_packet[10:8] == TYPE_KEY);
    wire [7:0] key_code = key_packet[7:0];
    
    wire pause_key_now = is_key_input && (key_code == KEY_PAUSE);
    wire dot_key_now   = is_key_input && (key_code == KEY_DOT);
    wire dash_key_now  = is_key_input && (key_code == KEY_DASH);

    function [7:0] morse_lookup;
        input [5:0] code;
        input [2:0] len;
        begin
            case(len)
                3'd1: morse_lookup = (code[0] == 1'b0) ? 8'd69 : 8'd84; // E / T
                3'd2: begin
                    case(code[1:0])
                        2'b00: morse_lookup = 8'd73; // I
                        2'b01: morse_lookup = 8'd78; // N
                        2'b10: morse_lookup = 8'd65; // A
                        2'b11: morse_lookup = 8'd77; // M
                    endcase
                end
                3'd3: begin
                    case(code[2:0])
                        3'b000: morse_lookup = 8'd83; // S
                        3'b001: morse_lookup = 8'd85; // U
                        3'b010: morse_lookup = 8'd82; // R
                        3'b011: morse_lookup = 8'd87; // W
                        3'b100: morse_lookup = 8'd68; // D
                        3'b101: morse_lookup = 8'd75; // K
                        3'b110: morse_lookup = 8'd71; // G
                        3'b111: morse_lookup = 8'd79; // O
                    endcase
                end
                3'd4: begin
                    case(code[3:0])
                        4'b0000: morse_lookup = 8'd72; // H
                        4'b0001: morse_lookup = 8'd86; // V
                        4'b0010: morse_lookup = 8'd70; // F
                        4'b0100: morse_lookup = 8'd76; // L
                        4'b0110: morse_lookup = 8'd80; // P
                        4'b0111: morse_lookup = 8'd74; // J
                        4'b1000: morse_lookup = 8'd66; // B
                        4'b1001: morse_lookup = 8'd88; // X
                        4'b1010: morse_lookup = 8'd67; // C
                        4'b1011: morse_lookup = 8'd89; // Y
                        4'b1100: morse_lookup = 8'd90; // Z
                        4'b1101: morse_lookup = 8'd81; // Q
                        default: morse_lookup = 8'd63; // '?'
                    endcase
                end
                3'd5: begin
                    case(code[4:0])
                        5'b00000: morse_lookup = 8'd53; // 5
                        5'b00001: morse_lookup = 8'd52; // 4
                        5'b00011: morse_lookup = 8'd51; // 3
                        5'b00111: morse_lookup = 8'd50; // 2
                        5'b01111: morse_lookup = 8'd49; // 1
                        5'b10000: morse_lookup = 8'd54; // 6
                        5'b11000: morse_lookup = 8'd55; // 7
                        5'b11100: morse_lookup = 8'd56; // 8
                        5'b11110: morse_lookup = 8'd57; // 9
                        5'b11111: morse_lookup = 8'd48; // 0
                        default:  morse_lookup = 8'd63; // '?'
                    endcase
                end
                default: morse_lookup = 8'd63;
            endcase
        end
    endfunction

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
            
            timeout_threshold <= 32'd150_000_000;
            space_threshold <= 32'd300_000_000;
            
            char_complete_beep <= 1'b0;
            pause_pressed <= 1'b0;
            pause_key_prev <= 1'b0;
            
            pause_lcd_busy <= 1'b0;
            pause_write_pos <= 5'd0;
            pause_lcd_req_pending <= 1'b0;
            
            dot_key_prev <= 1'b0;
            dash_key_prev <= 1'b0;
            
            cursor_update_pending <= 1'b0;
            old_cursor_pos <= 4'd0;
            
            // line0 리셋
            line0[0] <= 8'd32; line0[1] <= 8'd32; line0[2] <= 8'd32; line0[3] <= 8'd32;
            line0[4] <= 8'd32; line0[5] <= 8'd32; line0[6] <= 8'd32; line0[7] <= 8'd32;
            line0[8] <= 8'd32; line0[9] <= 8'd32; line0[10] <= 8'd32; line0[11] <= 8'd32;
            line0[12] <= 8'd32; line0[13] <= 8'd32; line0[14] <= 8'd32; line0[15] <= 8'd32;
            
            // line1 리셋 후 "DECODE"
            line1[0] <= 8'd32; line1[1] <= 8'd32; line1[2] <= 8'd32; line1[3] <= 8'd32;
            line1[4] <= 8'd32; line1[5] <= 8'd32; line1[6] <= 8'd32; line1[7] <= 8'd32;
            line1[8] <= 8'd32; line1[9] <= 8'd32; line1[10] <= 8'd32; line1[11] <= 8'd32;
            line1[12] <= 8'd32; line1[13] <= 8'd32; line1[14] <= 8'd32; line1[15] <= 8'd32;
            line1[0] <= 8'd68;
            line1[1] <= 8'd69;
            line1[2] <= 8'd67;
            line1[3] <= 8'd79;
            line1[4] <= 8'd68;
            line1[5] <= 8'd69;
        end
        else begin
            // timeout 임계값 업데이트
            timeout_threshold <= timeout_cycles;
            space_threshold   <= timeout_cycles << 1;

            // 기본 0 (펄스성)
            char_complete_beep <= 1'b0;

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
                pause_pressed <= 1'b0;
                pause_key_prev <= 1'b0;
                
                pause_lcd_busy <= 1'b0;
                pause_write_pos <= 5'd0;
                pause_lcd_req_pending <= 1'b0;
                
                dot_key_prev <= 1'b0;
                dash_key_prev <= 1'b0;
                
                cursor_update_pending <= 1'b0;
                old_cursor_pos <= 4'd0;

                led_out <= 8'b0000_0111;
                
                line0[0] <= 8'd32; line0[1] <= 8'd32; line0[2] <= 8'd32; line0[3] <= 8'd32;
                line0[4] <= 8'd32; line0[5] <= 8'd32; line0[6] <= 8'd32; line0[7] <= 8'd32;
                line0[8] <= 8'd32; line0[9] <= 8'd32; line0[10] <= 8'd32; line0[11] <= 8'd32;
                line0[12] <= 8'd32; line0[13] <= 8'd32; line0[14] <= 8'd32; line0[15] <= 8'd32;
            end
            else begin
                // prev 갱신
                pause_key_prev <= pause_key_now;
                dot_key_prev   <= dot_key_now;
                dash_key_prev  <= dash_key_now;

                // pause 토글
                if(pause_key_now && !pause_key_prev) begin
                    pause_pressed <= ~pause_pressed;
                    pause_lcd_busy <= 1'b1;
                    pause_write_pos <= 5'd0;
                    pause_lcd_req_pending <= 1'b0;
                end
                
                // morse_len 상한 5 제한
                if(dot_key_now && !dot_key_prev && morse_len < 5) begin
                    morse_code <= {morse_code[4:0], 1'b0};
                    morse_len <= morse_len + 3'd1;
                    idle_counter <= 32'd0;
                end
                else if(dash_key_now && !dash_key_prev && morse_len < 5) begin
                    morse_code <= {morse_code[4:0], 1'b1};
                    morse_len <= morse_len + 3'd1;
                    idle_counter <= 32'd0;
                end

                // pause 표시 LCD 처리 (row1 col10~15에 "PAUSE ")
                if(pause_lcd_busy) begin
                    if(pause_lcd_req_pending && lcd_done) begin
                        pause_lcd_req_pending <= 1'b0;
                        pause_write_pos <= pause_write_pos + 5'd1;
                        if(pause_write_pos >= 5) begin
                            pause_lcd_busy <= 1'b0;
                        end
                    end
                    else if(!pause_lcd_req_pending && !lcd_busy && !lcd_req && pause_write_pos < 6) begin
                        lcd_row <= 2'd1;
                        lcd_col <= 4'd10 + pause_write_pos[3:0];

                        if(pause_pressed) begin
                            case(pause_write_pos)
                                5'd0: lcd_char <= 8'd80; // P
                                5'd1: lcd_char <= 8'd65; // A
                                5'd2: lcd_char <= 8'd85; // U
                                5'd3: lcd_char <= 8'd83; // S
                                5'd4: lcd_char <= 8'd69; // E
                                5'd5: lcd_char <= 8'd32; // ' '
                                default: lcd_char <= 8'd32;
                            endcase
                        end
                        else begin
                            lcd_char <= 8'd32;
                        end

                        lcd_req <= 1'b1;
                        pause_lcd_req_pending <= 1'b1;
                    end
                end

                // IDLE에서 타임아웃/스페이스 판단
                if(state == ST_IDLE) begin
                    if(!pause_pressed && 
                       !(dot_key_now && !dot_key_prev) && 
                       !(dash_key_now && !dash_key_prev)) begin
                        
                        if(idle_counter < space_threshold) begin
                            idle_counter <= idle_counter + 32'd1;
                        end
                        
                        if(idle_counter >= timeout_threshold && morse_len > 0) begin
                            state <= ST_DECODE;
                        end
                        else if(idle_counter >= space_threshold && morse_len == 0 && cursor > 0 && cursor < 16) begin
                            old_cursor_pos <= cursor;
                            line0[cursor] <= 8'd32;
                            write_pos <= 5'd0;
                            state <= ST_WRITE_SPACE;
                        end
                    end
                end

                case(state)
                    ST_INIT: begin
                        if(lcd_req && lcd_done && !pause_lcd_req_pending) begin
                            lcd_req <= 1'b0;
                            init_step <= init_step + 1;
                        end
                        else if(!lcd_busy && !lcd_req && !pause_lcd_busy) begin
                            if(init_step < 16) begin
                                lcd_row <= 2'd0;
                                lcd_col <= init_step[3:0];
                                lcd_char <= (init_step[3:0] == cursor) ? 8'd95 : line0[init_step[3:0]];
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
                    end

                    ST_IDLE: begin
                        if(lcd_req && lcd_done && !pause_lcd_req_pending) begin
                            lcd_req <= 1'b0;
                        end
                        else if(clear_buffer) begin
                            line0[0] <= 8'd32; line0[1] <= 8'd32; line0[2] <= 8'd32; line0[3] <= 8'd32;
                            line0[4] <= 8'd32; line0[5] <= 8'd32; line0[6] <= 8'd32; line0[7] <= 8'd32;
                            line0[8] <= 8'd32; line0[9] <= 8'd32; line0[10] <= 8'd32; line0[11] <= 8'd32;
                            line0[12] <= 8'd32; line0[13] <= 8'd32; line0[14] <= 8'd32; line0[15] <= 8'd32;
                            
                            cursor <= 4'd0;
                            morse_code <= 6'd0;
                            morse_len <= 3'd0;
                            idle_counter <= 32'd0;
                            write_pos <= 5'd0;
                            
                            state <= ST_CLEAR;
                        end
                    end

                    ST_DECODE: begin
                        if(cursor < 16) begin
                            line0[cursor] <= morse_lookup(morse_code, morse_len);
                            
                            morse_code <= 6'd0;
                            morse_len  <= 3'd0;
                            write_pos  <= 5'd0;
                            state <= ST_WRITE_CHAR;
                        end
                        else begin
                            morse_code <= 6'd0;
                            morse_len  <= 3'd0;
                            idle_counter <= 32'd0;
                            state <= ST_IDLE;
                        end
                    end

                    ST_WRITE_CHAR: begin
                        if(lcd_req && lcd_done && !pause_lcd_req_pending) begin
                            lcd_req <= 1'b0;
                            old_cursor_pos <= cursor;
                            cursor <= cursor + 4'd1;
                            cursor_update_pending <= 1'b1;
                            state <= ST_UPDATE_CURSOR;
                        end
                        else if(!lcd_busy && !lcd_req) begin
                            lcd_row <= 2'd0;
                            lcd_col <= cursor;
                            lcd_char <= line0[cursor];
                            lcd_req <= 1'b1;
                            
                            char_complete_beep <= 1'b1;
                        end
                    end
                    
                    ST_WRITE_SPACE: begin
                        if(lcd_req && lcd_done && !pause_lcd_req_pending) begin
                            lcd_req <= 1'b0;
                        end
                        else if(!lcd_busy && !lcd_req) begin
                            if(write_pos < 16) begin
                                lcd_row <= 2'd0;
                                lcd_col <= write_pos[3:0];
                                lcd_char <= line0[write_pos[3:0]];
                                lcd_req <= 1'b1;
                                write_pos <= write_pos + 5'd1;
                            end
                            else begin
                                cursor <= cursor + 4'd1;
                                cursor_update_pending <= 1'b1;
                                state <= ST_UPDATE_CURSOR;
                            end
                        end
                    end

                    ST_CLEAR: begin
                        if(lcd_req && lcd_done && !pause_lcd_req_pending) begin
                            lcd_req <= 1'b0;
                        end
                        else if(!lcd_busy && !lcd_req) begin
                            if(write_pos < 16) begin
                                lcd_row <= 2'd0;
                                lcd_col <= write_pos[3:0];
                                lcd_char <= (write_pos[3:0] == cursor) ? 8'd95 : 8'd32;
                                lcd_req <= 1'b1;
                                write_pos <= write_pos + 5'd1;
                            end
                            else begin
                                write_pos <= 5'd0;
                                idle_counter <= 32'd0;
                                state <= ST_IDLE;
                            end
                        end
                    end

                    ST_UPDATE_CURSOR: begin
                        if(lcd_req && lcd_done && !pause_lcd_req_pending) begin
                            lcd_req <= 1'b0;
                            cursor_update_pending <= 1'b0;
                            idle_counter <= 32'd0;
                            state <= ST_IDLE;
                        end
                        else if(!lcd_busy && !lcd_req && cursor_update_pending) begin
                            if(cursor < 16) begin
                                lcd_row <= 2'd0;
                                lcd_col <= cursor;
                                lcd_char <= 8'd95;
                                lcd_req <= 1'b1;
                            end
                            else begin
                                cursor_update_pending <= 1'b0;
                                idle_counter <= 32'd0;
                                state <= ST_IDLE;
                            end
                        end
                    end

                    default: state <= ST_INIT;
                endcase
            end
        end
    end

endmodule
