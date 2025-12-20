module EncoderUI(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        is_active,
    
    input  wire [9:0]  key_in,
    input  wire        btn_encode,
    input  wire        btn_clear,
    input  wire        btn_nxt,
    
    input  wire [31:0] dit_time,
    input  wire [31:0] dah_time,
    input  wire [31:0] dit_gap_time,
    
    input  wire        lcd_busy,
    input  wire        lcd_done,
    output reg         lcd_req,
    output reg  [1:0]  lcd_row,
    output reg  [3:0]  lcd_col,
    output reg  [7:0]  lcd_char,
    
    output wire        piezo_out,
    output reg  [7:0] led_out
);

    parameter REPEAT_DELAY = 32'd50_000_000;
    
    //==========================================================================
    // ????? ???? ??? (btn_encode, btn_clear)
    //==========================================================================
    localparam DEBOUNCE_CYCLES = 250_000; // 10ms
    
    // Synchronizer (2-stage flip-flop)
    reg [1:0] btn_encode_sync, btn_clear_sync;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_encode_sync <= 2'b00;
            btn_clear_sync <= 2'b00;
        end else begin
            btn_encode_sync <= {btn_encode_sync[0], btn_encode};
            btn_clear_sync <= {btn_clear_sync[0], btn_clear};
        end
    end
    
    reg [1:0] btn_nxt_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) btn_nxt_sync <= 2'b00;
        else        btn_nxt_sync <= {btn_nxt_sync[0], btn_nxt};
    end
    
    reg btn_nxt_stable;
    reg [31:0] btn_nxt_counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_nxt_stable <= 1'b0;
            btn_nxt_counter <= 32'd0;
        end else begin
            if (btn_nxt_sync[1] != btn_nxt_stable) begin
                if (btn_nxt_counter >= DEBOUNCE_CYCLES) begin
                    btn_nxt_stable <= btn_nxt_sync[1];
                    btn_nxt_counter <= 32'd0;
                end else begin
                    btn_nxt_counter <= btn_nxt_counter + 1;
                end
            end else begin
                btn_nxt_counter <= 32'd0;
            end
        end
    end
    
    // Debouncer for btn_encode
    reg btn_encode_stable;
    reg [31:0] btn_encode_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_encode_stable <= 1'b0;
            btn_encode_counter <= 32'd0;
        end else begin
            if (btn_encode_sync[1] != btn_encode_stable) begin
                if (btn_encode_counter >= DEBOUNCE_CYCLES) begin
                    btn_encode_stable <= btn_encode_sync[1];
                    btn_encode_counter <= 32'd0;
                end else begin
                    btn_encode_counter <= btn_encode_counter + 1;
                end
            end else begin
                btn_encode_counter <= 32'd0;
            end
        end
    end
    
    // Debouncer for btn_clear
    reg btn_clear_stable;
    reg [31:0] btn_clear_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_clear_stable <= 1'b0;
            btn_clear_counter <= 32'd0;
        end else begin
            if (btn_clear_sync[1] != btn_clear_stable) begin
                if (btn_clear_counter >= DEBOUNCE_CYCLES) begin
                    btn_clear_stable <= btn_clear_sync[1];
                    btn_clear_counter <= 32'd0;
                end else begin
                    btn_clear_counter <= btn_clear_counter + 1;
                end
            end else begin
                btn_clear_counter <= 32'd0;
            end
        end
    end
    
    // Edge detection for debounced buttons
    reg btn_encode_stable_prev, btn_clear_stable_prev;
    wire btn_enc_pulse = btn_encode_stable && !btn_encode_stable_prev;
    wire btn_clear_pulse = btn_clear_stable && !btn_clear_stable_prev;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_encode_stable_prev <= 1'b0;
            btn_clear_stable_prev <= 1'b0;
        end else begin
            btn_encode_stable_prev <= btn_encode_stable;
            btn_clear_stable_prev <= btn_clear_stable;
        end
    end
    
    reg btn_nxt_stable_prev;
    wire btn_nxt_pulse = btn_nxt_stable && !btn_nxt_stable_prev; // Rising Edge

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) btn_nxt_stable_prev <= 1'b0;
        else        btn_nxt_stable_prev <= btn_nxt_stable;
    end
    
    //==========================================================================
    // ???? ???? (?????? ??? ???)
    //==========================================================================
    
    // ========== Text Buffer ==========
    reg [7:0] text_mem [0:15];
    reg [3:0] cursor;
    reg [3:0] text_length;
    integer i;

    // ========== KeyMap State ==========
    reg [2:0] keymap_sel;

    // ========== Key Edge Detection ==========
    reg [9:0] key_in_r1, key_in_r2;
    wire [9:0] key_rising;
    wire [9:0] key_falling;
    reg [9:0] key_pressed;
    reg combo_used;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_in_r1 <= 10'h000;
            key_in_r2 <= 10'h000;
        end else begin
            key_in_r1 <= key_in;
            key_in_r2 <= key_in_r1;
        end
    end
    
    assign key_rising = key_in_r1 & ~key_in_r2;
    assign key_falling = ~key_in_r1 & key_in_r2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_pressed <= 10'h000;
        end else begin
            key_pressed <= key_in_r1;
        end
    end
    
    // ========== Key Decode ==========
    reg [3:0] key_idx;
    reg       key_valid;
    reg       key_space;
    reg       key_backspace;
    reg       key_next_map; // 콤보 제거로 인해 현재 사용 안 함 (필요 시 다른 키에 할당 필요)
    reg       key_prev_map; // 콤보 제거로 인해 현재 사용 안 함
    // reg       combo_used; // 더 이상 필요 없음

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_idx <= 4'd0;
            key_valid <= 1'b0;
            key_space <= 1'b0;
            key_backspace <= 1'b0;
            key_next_map <= 1'b0;
            key_prev_map <= 1'b0;
            // combo_used <= 1'b0; 
        end else begin
            key_valid <= 1'b0;
            key_space <= 1'b0;
            key_backspace <= 1'b0;
            key_next_map <= 1'b0;
            key_prev_map <= 1'b0;
            
            // -------------------------------------------------------------
            // [수정] 버튼 9: 콤보 및 Release 로직 제거 -> 단순히 누르면 SPACE
            // -------------------------------------------------------------
            if (key_rising[8]) begin
                key_space <= 1'b1;  // 누르는 순간 바로 Space 입력
            end
            
            // 버튼 10: BACKSPACE (기존 유지)
            if (key_rising[9]) begin
                key_backspace <= 1'b1;
            end
            
            // -------------------------------------------------------------
            // [수정] 버튼 1~8: 일반 문자 입력
            // (!key_pressed[8] 조건을 제거하여 9번 키 상태와 무관하게 동작)
            // -------------------------------------------------------------
            if (key_rising[7:0] != 8'h00) begin
                key_valid <= 1'b1;
                case (key_rising[7:0])
                    8'b00000001: key_idx <= 4'd0;
                    8'b00000010: key_idx <= 4'd1;
                    8'b00000100: key_idx <= 4'd2;
                    8'b00001000: key_idx <= 4'd3;
                    8'b00010000: key_idx <= 4'd4;
                    8'b00100000: key_idx <= 4'd5;
                    8'b01000000: key_idx <= 4'd6;
                    8'b10000000: key_idx <= 4'd7;
                    default:     key_idx <= 4'd0;
                endcase
            end
        end
    end

    // ========== Key Mapper ==========
    reg [7:0] mapped_char;
    
    always @(*) begin
        case (keymap_sel)
            3'd0: begin
                case (key_idx[2:0])
                    3'd0: mapped_char = "1";
                    3'd1: mapped_char = "2";
                    3'd2: mapped_char = "3";
                    3'd3: mapped_char = "4";
                    3'd4: mapped_char = "5";
                    3'd5: mapped_char = "6";
                    3'd6: mapped_char = "7";
                    3'd7: mapped_char = "8";
                endcase
            end
            3'd1: begin
                case (key_idx[2:0])
                    3'd0: mapped_char = "9";
                    3'd1: mapped_char = "0";
                    3'd2: mapped_char = "A";
                    3'd3: mapped_char = "B";
                    3'd4: mapped_char = "C";
                    3'd5: mapped_char = "D";
                    3'd6: mapped_char = "E";
                    3'd7: mapped_char = "F";
                endcase
            end
            3'd2: begin
                case (key_idx[2:0])
                    3'd0: mapped_char = "G";
                    3'd1: mapped_char = "H";
                    3'd2: mapped_char = "I";
                    3'd3: mapped_char = "J";
                    3'd4: mapped_char = "K";
                    3'd5: mapped_char = "L";
                    3'd6: mapped_char = "M";
                    3'd7: mapped_char = "N";
                endcase
            end
            3'd3: begin
                case (key_idx[2:0])
                    3'd0: mapped_char = "O";
                    3'd1: mapped_char = "P";
                    3'd2: mapped_char = "Q";
                    3'd3: mapped_char = "R";
                    3'd4: mapped_char = "S";
                    3'd5: mapped_char = "T";
                    3'd6: mapped_char = "U";
                    3'd7: mapped_char = "V";
                endcase
            end
            3'd4: begin
                case (key_idx[2:0])
                    3'd0: mapped_char = "W";
                    3'd1: mapped_char = "X";
                    3'd2: mapped_char = "Y";
                    3'd3: mapped_char = "Z";
                    3'd4: mapped_char = " ";
                    3'd5: mapped_char = " ";
                    3'd6: mapped_char = " ";
                    3'd7: mapped_char = " ";
                endcase
            end
            default: mapped_char = " ";
        endcase
    end

    // ========== Encoder ==========
    reg        enc_start;
    wire       enc_busy;
    wire       enc_done;
    wire [255:0] enc_bitstream;
    wire [8:0] enc_bitlen;
    
    Encoder #(
        .OUT_MAX_BITS(128)
    ) encoder (
        .clk(clk),
        .rst_n(rst_n),
        .start(enc_start),
        .text_length(text_length),
        .t0(text_mem[0]),   .t1(text_mem[1]),   .t2(text_mem[2]),   .t3(text_mem[3]),
        .t4(text_mem[4]),   .t5(text_mem[5]),   .t6(text_mem[6]),   .t7(text_mem[7]),
        .t8(text_mem[8]),   .t9(text_mem[9]),   .t10(text_mem[10]), .t11(text_mem[11]),
        .t12(text_mem[12]), .t13(text_mem[13]), .t14(text_mem[14]), .t15(text_mem[15]),
        .busy(enc_busy),
        .done(enc_done),
        .bitstream(enc_bitstream),
        .bitlen(enc_bitlen)
    );

    // ========== Piezo Player ==========
    reg        piezo_start;
    wire       piezo_busy;
    wire       piezo_done;
    
    EncoderPiezoPlayer #(
        .CLK_FREQ(50_000_000),
        .TONE_FREQ(440)
    ) piezo (
        .clk(clk),
        .rst_n(rst_n),
        .start(piezo_start),
        .bitstream(enc_bitstream),
        .bit_length(enc_bitlen),
        .DitTime(dit_time),
        .DahTime(dah_time),
        .DitGap(dit_gap_time),
        .busy(piezo_busy),
        .done(piezo_done),
        .piezo_out(piezo_out)
    );

    // ========== LCD 2?? ???? ?迭 ==========
    reg [7:0] lcd2_chars [0:15];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lcd2_chars[0]  <= "E";
            lcd2_chars[1]  <= "N";
            lcd2_chars[2]  <= "C";
            lcd2_chars[3]  <= "O";
            lcd2_chars[4]  <= "D";
            lcd2_chars[5]  <= "E";
            lcd2_chars[6]  <= "R";
            lcd2_chars[7]  <= " ";
            lcd2_chars[8]  <= " ";
            lcd2_chars[9]  <= " ";
            lcd2_chars[10] <= " ";
            lcd2_chars[11] <= " ";
            lcd2_chars[12] <= "1";
            lcd2_chars[13] <= "-";
            lcd2_chars[14] <= "8";
            lcd2_chars[15] <= " ";
        end else begin
            case (keymap_sel)
                3'd0: begin lcd2_chars[12] <= "1"; lcd2_chars[14] <= "8"; end
                3'd1: begin lcd2_chars[12] <= "9"; lcd2_chars[14] <= "F"; end
                3'd2: begin lcd2_chars[12] <= "G"; lcd2_chars[14] <= "N"; end
                3'd3: begin lcd2_chars[12] <= "O"; lcd2_chars[14] <= "V"; end
                3'd4: begin lcd2_chars[12] <= "W"; lcd2_chars[14] <= "Z"; end
            endcase
        end
    end
    // ========== FSM ==========
    localparam IDLE   = 3'd0;
    localparam INPUT  = 3'd1;
    localparam ENCODE = 3'd2;
    localparam PLAY   = 3'd3;
    localparam WAIT   = 3'd4;
    
    reg [2:0]  state;
    reg [31:0] wait_counter;
    reg        lcd_refresh_req;
    
    reg        lcd_refresh_req_r;    // ?? ???
    wire       lcd_refresh_edge;     // ?? ???
    
            always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lcd_refresh_req_r <= 1'b0;
        end else begin
            lcd_refresh_req_r <= lcd_refresh_req;
        end
    end
    
    assign lcd_refresh_edge = lcd_refresh_req && !lcd_refresh_req_r;

    //==========================================================================
// UI Activation Detection (FSM ???? ??)
//==========================================================================
reg is_active_prev;
wire just_activated;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        is_active_prev <= 1'b0;
    end else begin
        is_active_prev <= is_active;
    end
end

assign just_activated = is_active && !is_active_prev;

//==========================================================================
// FSM (???? ???? ????)
//==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            keymap_sel <= 3'd0;
            cursor <= 4'd0;
            text_length <= 4'd0;
            enc_start <= 1'b0;
            piezo_start <= 1'b0;
            wait_counter <= 32'd0;
            lcd_refresh_req <= 1'b0;  // ?? ???? ?????? ????
            led_out <= 8'h00;
            
            for (i = 0; i < 16; i = i + 1) begin
                text_mem[i] <= 8'd32;
            end
        end else begin
            enc_start <= 1'b0;
            piezo_start <= 1'b0;
            lcd_refresh_req <= 1'b0;
            
            // ========== UI ???? ???? (FSM ???? ?????? ???) ==========
            if (just_activated) begin
                lcd_refresh_req <= 1'b1;  // ?? ???? ???? ?? ??!
            end
            
            if (is_active) begin
                case (keymap_sel)
                    3'd0: led_out <= 8'b1111_1111;
                    3'd1: led_out <= 8'b1111_1111;
                    3'd2: led_out <= 8'b1111_1111;
                    3'd3: led_out <= 8'b1111_1111;
                    3'd4: led_out <= 8'b0000_1111;
                    default: led_out <= 8'h00;
                endcase
            end else begin
                led_out <= 8'h00;
            end
            
            case (state)
                IDLE: begin
                    if (is_active) begin
                        lcd_refresh_req <= 1'b1;
                        state <= INPUT;
                    end
                end
                
                INPUT: begin
                    if (btn_nxt_pulse) begin
                    if (keymap_sel >= 3'd4) begin
                        keymap_sel <= 3'd0; // 마지막 맵이면 처음으로
                    end else begin
                        keymap_sel <= keymap_sel + 3'd1; // 다음 맵으로
                    end
                    lcd_refresh_req <= 1'b1; // 맵이 바뀌었으니 LCD 갱신 요청
                end
                    
                    if (btn_clear_pulse) begin
                        for (i = 0; i < 16; i = i + 1) begin
                            text_mem[i] <= 8'd32;
                        end
                        cursor <= 4'd0;
                        text_length <= 4'd0;
                        lcd_refresh_req <= 1'b1;
                    end
                    
                    if (key_backspace && cursor > 4'd0) begin
                        cursor <= cursor - 4'd1;
                        text_mem[cursor - 4'd1] <= 8'd32;
                        if (text_length > 4'd0) begin
                            text_length <= text_length - 4'd1;
                        end
                        lcd_refresh_req <= 1'b1;
                    end
                    
                    if (key_space) begin
                        if (cursor < 4'd15) begin
                            text_mem[cursor] <= 8'd32;
                            cursor <= cursor + 4'd1;
                            if (cursor >= text_length) begin
                                text_length <= cursor + 4'd1;
                            end
                            lcd_refresh_req <= 1'b1;
                        end else begin
                            text_mem[15] <= 8'd32;
                            text_length <= 4'd15;
                            lcd_refresh_req <= 1'b1;
                        end
                    end
                    
                    if (key_valid) begin
                        if (cursor < 4'd15) begin
                            text_mem[cursor] <= mapped_char;
                            cursor <= cursor + 4'd1;
                            if (cursor >= text_length) begin
                                text_length <= cursor + 4'd1;
                            end
                            lcd_refresh_req <= 1'b1;
                        end else begin
                            text_mem[15] <= mapped_char;
                            text_length <= 4'd15;
                            lcd_refresh_req <= 1'b1;
                        end
                    end
                    
                    if (btn_enc_pulse && text_length > 4'd0) begin
                        enc_start <= 1'b1;
                        state <= ENCODE;
                    end
                    
                    if (!is_active) begin
                        state <= IDLE;
                    end
                end
                
                ENCODE: begin
                    if (key_valid || key_space || key_backspace) begin
                        state <= INPUT;
                    end else if (enc_done) begin
                        piezo_start <= 1'b1;
                        state <= PLAY;
                    end
                    
                    if (!is_active) begin
                        state <= IDLE;
                    end
                end
                
                PLAY: begin
                    if (key_valid || key_space || key_backspace) begin
                        state <= INPUT;
                    end else if (piezo_done) begin
                        wait_counter <= 32'd0;
                        state <= WAIT;
                    end
                    
                    if (!is_active) begin
                        state <= IDLE;
                    end
                end
                
                WAIT: begin
                    if (key_valid || key_space || key_backspace) begin
                        state <= INPUT;
                    end else if (key_valid || key_space || key_backspace) begin
                        state <= INPUT;
                    end else if (wait_counter >= REPEAT_DELAY) begin
                        piezo_start <= 1'b1;
                        state <= PLAY;
                    end else begin
                        wait_counter <= wait_counter + 32'd1;
                    end
                    
                    if (!is_active) begin
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

    // ========== LCD ??? ???? ??? ==========
    localparam LCD_IDLE = 2'd0;
    localparam LCD_WRITE = 2'd1;
    localparam LCD_WAIT = 2'd2;
    
    reg [1:0] lcd_state;
    reg [1:0] lcd_write_row;
    reg [3:0] lcd_write_col;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lcd_state <= LCD_IDLE;
            lcd_req <= 1'b0;
            lcd_row <= 2'd0;
            lcd_col <= 4'd0;
            lcd_char <= 8'h20;
            lcd_write_row <= 2'd0;
            lcd_write_col <= 4'd0;
        end else begin
            case (lcd_state)
                LCD_IDLE: begin
                    lcd_req <= 1'b0;
                    
                    if (is_active && lcd_refresh_edge) begin
                        lcd_write_row <= 2'd0;
                        lcd_write_col <= 4'd0;
                        lcd_state <= LCD_WRITE;
                    end
                end
                
                LCD_WRITE: begin
                    if (!lcd_busy) begin
                        lcd_req <= 1'b1;
                        lcd_row <= lcd_write_row;
                        lcd_col <= lcd_write_col;
                        
                        if (lcd_write_row == 2'd0) begin
                            lcd_char <= text_mem[lcd_write_col];
                        end else begin
                            lcd_char <= lcd2_chars[lcd_write_col];
                        end
                        
                        lcd_state <= LCD_WAIT;
                    end
                end
                
                LCD_WAIT: begin
                    lcd_req <= 1'b0;
                    
                    if (lcd_done) begin
                        if (lcd_write_col == 4'd15) begin
                            lcd_write_col <= 4'd0;
                            if (lcd_write_row == 2'd1) begin
                                lcd_state <= LCD_IDLE;
                            end else begin
                                lcd_write_row <= lcd_write_row + 2'd1;
                                lcd_state <= LCD_WRITE;
                            end
                        end else begin
                            lcd_write_col <= lcd_write_col + 4'd1;
                            lcd_state <= LCD_WRITE;
                        end
                    end
                end
                
                default: lcd_state <= LCD_IDLE;
            endcase
        end
    end

endmodule
