`timescale 1ns / 1ps

module ButtonMorseInput #(
    parameter DEBOUNCE_CYCLES = 250_000           // 10ms 디바운스
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  btn,                        // btn[0]=버튼1, btn[1]=버튼2, btn[2]=PAUSE, btn[3]=CLEAR
    
    input wire [31:0] LONG_KEY_CYCLES,             // 500ms (DASH 판정)
    input wire [31:0] DIT_GAP_CYCLES,              // 250ms (자동 반복 주기)
    
    output reg         key_valid,
    output reg  [10:0] key_packet,
    
    output reg         btn1_held,                  // 버튼1 누르는 중 (피에조용)
    output reg         btn2_dot_pulse              // 버튼2 DOT 펄스 (피에조용)
);

    localparam TYPE_KEY = 3'b001;
    localparam KEY_DOT   = 8'd1;
    localparam KEY_DASH  = 8'd2;
    localparam KEY_CLEAR = 8'd11;
    localparam KEY_PAUSE = 8'd12;

    //==========================================================================
    // 1. Synchronizer (2-stage flip-flop)
    //==========================================================================
    reg [1:0] b0_sync, b1_sync, b2_sync, b3_sync;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            b0_sync <= 2'b00;
            b1_sync <= 2'b00;
            b2_sync <= 2'b00;
            b3_sync <= 2'b00;
        end else begin
            b0_sync <= {b0_sync[0], btn[0]};
            b1_sync <= {b1_sync[0], btn[1]};
            b2_sync <= {b2_sync[0], btn[2]};
            b3_sync <= {b3_sync[0], btn[3]};
        end
    end

    //==========================================================================
    // 2. Debouncer for btn[0] (버튼1)
    //==========================================================================
    reg        b0_stable;
    reg [31:0] b0_counter;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            b0_stable <= 1'b0;
            b0_counter <= 32'd0;
        end else begin
            if(b0_sync[1] != b0_stable) begin
                if(b0_counter >= DEBOUNCE_CYCLES) begin
                    b0_stable <= b0_sync[1];
                    b0_counter <= 32'd0;
                end else begin
                    b0_counter <= b0_counter + 1;
                end
            end else begin
                b0_counter <= 32'd0;
            end
        end
    end

    //==========================================================================
    // 3. Debouncer for btn[1] (버튼2)
    //==========================================================================
    reg        b1_stable;
    reg [31:0] b1_counter;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            b1_stable <= 1'b0;
            b1_counter <= 32'd0;
        end else begin
            if(b1_sync[1] != b1_stable) begin
                if(b1_counter >= DEBOUNCE_CYCLES) begin
                    b1_stable <= b1_sync[1];
                    b1_counter <= 32'd0;
                end else begin
                    b1_counter <= b1_counter + 1;
                end
            end else begin
                b1_counter <= 32'd0;
            end
        end
    end

    //==========================================================================
    // 4. Debouncer for btn[2] (PAUSE)
    //==========================================================================
    reg        b2_stable;
    reg [31:0] b2_counter;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            b2_stable <= 1'b0;
            b2_counter <= 32'd0;
        end else begin
            if(b2_sync[1] != b2_stable) begin
                if(b2_counter >= DEBOUNCE_CYCLES) begin
                    b2_stable <= b2_sync[1];
                    b2_counter <= 32'd0;
                end else begin
                    b2_counter <= b2_counter + 1;
                end
            end else begin
                b2_counter <= 32'd0;
            end
        end
    end

    //==========================================================================
    // 5. Debouncer for btn[3] (CLEAR)
    //==========================================================================
    reg        b3_stable;
    reg [31:0] b3_counter;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            b3_stable <= 1'b0;
            b3_counter <= 32'd0;
        end else begin
            if(b3_sync[1] != b3_stable) begin
                if(b3_counter >= DEBOUNCE_CYCLES) begin
                    b3_stable <= b3_sync[1];
                    b3_counter <= 32'd0;
                end else begin
                    b3_counter <= b3_counter + 1;
                end
            end else begin
                b3_counter <= 32'd0;
            end
        end
    end

    //==========================================================================
    // 6. 버튼 상태 변수
    //==========================================================================
    reg        b0_prev;
    reg [31:0] b0_hold_counter;
    reg        b0_long_triggered;

    reg        b1_prev;
    reg [31:0] b1_repeat_counter;
    reg        b1_first_dot_sent;

    reg        b2_prev;
    reg        b3_prev;

    wire b0_pressed = (b0_stable && !b0_prev);
    wire b0_released = (!b0_stable && b0_prev);
    wire b0_holding = b0_stable;

    wire b1_pressed = (b1_stable && !b1_prev);
    wire b1_released = (!b1_stable && b1_prev);
    wire b1_holding = b1_stable;

    wire b2_pressed = (b2_stable && !b2_prev);
    wire b3_pressed = (b3_stable && !b3_prev);

    //==========================================================================
    // 7. 통합 로직 (버튼0 + 버튼1 + 버튼2 + 버튼3)
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            b0_prev <= 1'b0;
            b0_hold_counter <= 32'd0;
            b0_long_triggered <= 1'b0;
            btn1_held <= 1'b0;
            
            b1_prev <= 1'b0;
            b1_repeat_counter <= 32'd0;
            b1_first_dot_sent <= 1'b0;
            
            b2_prev <= 1'b0;
            b3_prev <= 1'b0;
            
            key_valid <= 1'b0;
            key_packet <= 11'd0;
            btn2_dot_pulse <= 1'b0;
        end else begin
            b0_prev <= b0_stable;
            b1_prev <= b1_stable;
            b2_prev <= b2_stable;
            b3_prev <= b3_stable;
            
            // 기본값
            key_valid <= 1'b0;
            btn2_dot_pulse <= 1'b0;
            
            // ========== btn[2] 처리 (PAUSE) ==========
            if(b2_pressed) begin
                key_valid <= 1'b1;
                key_packet <= {TYPE_KEY, KEY_PAUSE};
            end
            
            // ========== btn[3] 처리 (CLEAR) ==========
            if(b3_pressed) begin
                key_valid <= 1'b1;
                key_packet <= {TYPE_KEY, KEY_CLEAR};
            end
            
            // ========== 버튼2 처리 (btn[1] - DOT 자동 반복) ==========
            if(b1_pressed) begin
                b1_repeat_counter <= 32'd0;
                b1_first_dot_sent <= 1'b1;
                
                key_valid <= 1'b1;
                key_packet <= {TYPE_KEY, KEY_DOT};
                btn2_dot_pulse <= 1'b1;
            end
            else if(b1_holding && b1_first_dot_sent) begin
                if(b1_repeat_counter >= DIT_GAP_CYCLES) begin
                    b1_repeat_counter <= 32'd0;
                    
                    key_valid <= 1'b1;
                    key_packet <= {TYPE_KEY, KEY_DOT};
                    btn2_dot_pulse <= 1'b1;
                end else begin
                    b1_repeat_counter <= b1_repeat_counter + 1;
                end
            end
            else if(b1_released) begin
                b1_repeat_counter <= 32'd0;
                b1_first_dot_sent <= 1'b0;
            end
            
            // ========== 버튼1 처리 (btn[0] - DOT/DASH) ==========
            if(b0_pressed) begin
                btn1_held <= 1'b1;
                b0_hold_counter <= 32'd0;
                b0_long_triggered <= 1'b0;
            end
            else if(b0_holding) begin
                if(!b0_long_triggered) begin
                    if(b0_hold_counter >= LONG_KEY_CYCLES) begin
                        b0_long_triggered <= 1'b1;
                        btn1_held <= 1'b0;
                        
                        key_valid <= 1'b1;
                        key_packet <= {TYPE_KEY, KEY_DASH};
                    end else begin
                        b0_hold_counter <= b0_hold_counter + 1;
                    end
                end
            end
            else if(b0_released) begin
                btn1_held <= 1'b0;
                
                if(!b0_long_triggered) begin
                    key_valid <= 1'b1;
                    key_packet <= {TYPE_KEY, KEY_DOT};
                end
                
                b0_hold_counter <= 32'd0;
                b0_long_triggered <= 1'b0;
            end
        end
    end

endmodule

//==========================================================================
// PiezoToneController - 피에조 컨트롤러 (수정 버전)
//==========================================================================
module PiezoToneController (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        btn1_held,                  // 버튼1 누르는 중
    input  wire        btn2_dot_pulse,             // 버튼2 DOT 펄스
    
    input  wire [31:0] dash_cycles,                // 사용 안 함
    input  wire [31:0] autorepeat_cycles,          // 사용 안 함
    
    input  wire        char_complete_beep,         // 문자 완료 비프음
    
    output reg         piezo_out
);

    parameter CLK_HZ = 25_000_000;
    
    // 440Hz 톤 (버튼1 누르는 중, 버튼2 DOT)
    parameter TONE_440HZ = 440;
    localparam TOGGLE_COUNT_440 = CLK_HZ / (2 * TONE_440HZ);
    
    // 220Hz 톤 (문자 완료)
    parameter TONE_220HZ = 220;
    localparam TOGGLE_COUNT_220 = CLK_HZ / (2 * TONE_220HZ);
    
    // 비프음 지속 시간
    localparam CHAR_BEEP_DURATION = CLK_HZ / 10;      // 100ms (문자 완료)
    localparam DOT_BEEP_DURATION = CLK_HZ / 20;       // 50ms (버튼2 DOT)
    
    reg [31:0] tone_counter;
    reg        tone_toggle;
    
    reg        char_beep_active;
    reg [31:0] char_beep_counter;
    
    reg        dot_beep_active;
    reg [31:0] dot_beep_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tone_counter <= 32'd0;
            tone_toggle <= 1'b0;
            piezo_out <= 1'b0;
            char_beep_active <= 1'b0;
            char_beep_counter <= 32'd0;
            dot_beep_active <= 1'b0;
            dot_beep_counter <= 32'd0;
        end
        else begin
            // 문자 완료 비프음 트리거 (최우선)
            if(char_complete_beep) begin
                char_beep_active <= 1'b1;
                char_beep_counter <= 32'd0;
                dot_beep_active <= 1'b0;      // ← 추가
                dot_beep_counter <= 32'd0;    // ← 추가
                tone_counter <= 32'd0;
                tone_toggle <= 1'b0;
            end
            // 버튼2 DOT 비프음 트리거
            else if(btn2_dot_pulse) begin     // ← if → else if 변경
                dot_beep_active <= 1'b1;
                dot_beep_counter <= 32'd0;
                tone_counter <= 32'd0;
                tone_toggle <= 1'b0;
            end
            
            // 우선순위: 문자 완료 비프음 > 버튼2 DOT 비프음 > 버튼1 연속음
            if(char_beep_active) begin
                // 문자 완료 비프음 (220Hz, 100ms)
                if(char_beep_counter < CHAR_BEEP_DURATION) begin
                    char_beep_counter <= char_beep_counter + 1;
                    
                    if(tone_counter < TOGGLE_COUNT_220) begin
                        tone_counter <= tone_counter + 1;
                    end
                    else begin
                        tone_counter <= 32'd0;
                        tone_toggle <= ~tone_toggle;
                    end
                    piezo_out <= tone_toggle;
                end
                else begin
                    char_beep_active <= 1'b0;
                    piezo_out <= 1'b0;
                    tone_counter <= 32'd0;
                    tone_toggle <= 1'b0;
                end
            end
            else if(dot_beep_active) begin
                // 버튼2 DOT 비프음 (440Hz, 50ms)
                if(dot_beep_counter < DOT_BEEP_DURATION) begin
                    dot_beep_counter <= dot_beep_counter + 1;
                    
                    if(tone_counter < TOGGLE_COUNT_440) begin
                        tone_counter <= tone_counter + 1;
                    end
                    else begin
                        tone_counter <= 32'd0;
                        tone_toggle <= ~tone_toggle;
                    end
                    piezo_out <= tone_toggle;
                end
                else begin
                    dot_beep_active <= 1'b0;
                    piezo_out <= 1'b0;
                    tone_counter <= 32'd0;
                    tone_toggle <= 1'b0;
                end
            end
            else if(btn1_held) begin
                // 버튼1 연속음 (440Hz)
                if(tone_counter < TOGGLE_COUNT_440) begin
                    tone_counter <= tone_counter + 1;
                end
                else begin
                    tone_counter <= 32'd0;
                    tone_toggle <= ~tone_toggle;
                end
                piezo_out <= tone_toggle;
            end
            else begin
                tone_counter <= 32'd0;
                tone_toggle <= 1'b0;
                piezo_out <= 1'b0;
            end
        end
    end

endmodule

module ServoController #(
    parameter CLK_HZ = 25_000_000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [8:0] angle,      // 0~180도
    output reg        pwm_out
);

    // PWM 주기: 20ms (50Hz)
    localparam PWM_PERIOD = CLK_HZ / 50;  // 2,000,000 cycles
    
    // 펄스 폭: 1ms(0도) ~ 2ms(180도) - 표준 서보
    localparam MIN_PULSE = CLK_HZ / 1000;  // 1ms = 100,000 cycles
    localparam MAX_PULSE = CLK_HZ / 500;   // 2ms = 200,000 cycles
    localparam PULSE_RANGE = MAX_PULSE - MIN_PULSE;  // 100,000 cycles
    
    reg [31:0] counter;
    reg [31:0] pulse_width;
    
    // 각도 → 펄스 폭 변환 (고정소수점 연산)
    // pulse_width = MIN_PULSE + (angle * PULSE_RANGE / 180)
    always @(*) begin
        // 정밀도 향상: (angle * PULSE_RANGE) 먼저 계산
        pulse_width = MIN_PULSE + ((angle * PULSE_RANGE) / 180);
    end
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            counter <= 32'd0;
            pwm_out <= 1'b0;
        end
        else begin
            if(counter < PWM_PERIOD - 1) begin
                counter <= counter + 1;
            end
            else begin
                counter <= 32'd0;
            end
            
            // PWM 출력
            pwm_out <= (counter < pulse_width) ? 1'b1 : 1'b0;
        end
    end

endmodule

`timescale 1ns / 1ps

//==============================================================================
// LCD_Controller.v
// 16x2 Character LCD 제어 모듈 (HD44780 호환)
//==============================================================================
// 기능:
// - DecodeUI로부터 문자 출력 요청 수신
// - LCD 초기화 및 문자 출력
// - 4비트 모드 동작
//==============================================================================

`timescale 1ns / 1ps

module LCD_Controller #(
    parameter integer CLK_HZ = 25_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    
    // DecodeUI 인터페이스
    input  wire        lcd_req,
    input  wire [1:0]  lcd_row,
    input  wire [3:0]  lcd_col,
    input  wire [7:0]  lcd_char,
    
    output reg         lcd_busy,
    output reg         lcd_done,
    
    // LCD 하드웨어 핀 (8비트 모드)
    output reg         lcd_e,
    output reg         lcd_rs,
    output reg         lcd_rw,
    output reg  [7:0]  lcd_data
);

    //==========================================================================
    // 타이밍 상수 (CLK_HZ 기준)
    //==========================================================================
    localparam integer CNT_15MS  = (CLK_HZ / 1000) * 15;      // 15ms
    localparam integer CNT_5MS   = (CLK_HZ / 1000) * 5;       // 5ms
    localparam integer CNT_100US = (CLK_HZ / 1_000_000) * 100; // 100us
    localparam integer CNT_CMD   = (CLK_HZ / 1_000_000) * 50;  // 50us
    localparam integer CNT_CLR   = (CLK_HZ / 1000) * 2;       // 2ms
    
    localparam integer E_PULSE_START = 2;
    localparam integer E_PULSE_END   = 22;
    localparam integer E_PULSE_TOTAL = E_PULSE_END + CNT_CMD;

    //==========================================================================
    // 명령어 정의
    //==========================================================================
    localparam [7:0] CMD_WAKEUP     = 8'h30;
    localparam [7:0] CMD_FUNC_SET   = 8'h38; // 8-bit, 2-line, 5x8 font
    localparam [7:0] CMD_DISP_OFF   = 8'h08;
    localparam [7:0] CMD_DISP_CLEAR = 8'h01;
    localparam [7:0] CMD_ENTRY_MODE = 8'h06; // Auto Increment
    localparam [7:0] CMD_DISP_ON    = 8'h0C; // Display On, Cursor Off

    //==========================================================================
    // 상태 머신
    //==========================================================================
    localparam [4:0] ST_PWR_WAIT   = 0;
    localparam [4:0] ST_INIT_1     = 1;
    localparam [4:0] ST_INIT_2     = 2;
    localparam [4:0] ST_INIT_3     = 3;
    localparam [4:0] ST_FUNC_SET   = 4;
    localparam [4:0] ST_DISP_OFF   = 5;
    localparam [4:0] ST_DISP_CLR   = 6;
    localparam [4:0] ST_ENTRY_MODE = 7;
    localparam [4:0] ST_DISP_ON    = 8;
    localparam [4:0] ST_IDLE       = 9;
    localparam [4:0] ST_SET_ADDR   = 10;
    localparam [4:0] ST_WRITE_CHAR = 11;

    reg [4:0]  state;
    reg [31:0] wait_cnt;
    reg [6:0]  target_addr;

    //==========================================================================
    // 초기화 및 상태 머신
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_PWR_WAIT;
            wait_cnt <= 0;
            lcd_e <= 0;
            lcd_rs <= 0;
            lcd_rw <= 0;
            lcd_data <= 0;
            lcd_busy <= 1;
            lcd_done <= 0;
            target_addr <= 0;
        end else begin
            // 기본값
            lcd_done <= 0;
            
            case (state)
                //==============================================================
                // 초기화 시퀀스 (당신의 코드 스타일)
                //==============================================================
                ST_PWR_WAIT: begin
                    lcd_busy <= 1;
                    if (wait_cnt >= CNT_15MS) begin
                        wait_cnt <= 0;
                        state <= ST_INIT_1;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                ST_INIT_1: begin // 0x30
                    lcd_rs <= 0;
                    lcd_rw <= 0;
                    lcd_data <= CMD_WAKEUP;
                    
                    if (wait_cnt == E_PULSE_START) lcd_e <= 1;
                    else if (wait_cnt == E_PULSE_END) lcd_e <= 0;
                    
                    if (wait_cnt >= (CNT_5MS + E_PULSE_END)) begin
                        wait_cnt <= 0;
                        state <= ST_INIT_2;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                ST_INIT_2: begin // 0x30
                    lcd_rs <= 0;
                    lcd_rw <= 0;
                    lcd_data <= CMD_WAKEUP;
                    
                    if (wait_cnt == E_PULSE_START) lcd_e <= 1;
                    else if (wait_cnt == E_PULSE_END) lcd_e <= 0;
                    
                    if (wait_cnt >= (CNT_100US + E_PULSE_END)) begin
                        wait_cnt <= 0;
                        state <= ST_INIT_3;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                ST_INIT_3: begin // 0x30
                    lcd_rs <= 0;
                    lcd_rw <= 0;
                    lcd_data <= CMD_WAKEUP;
                    
                    if (wait_cnt == E_PULSE_START) lcd_e <= 1;
                    else if (wait_cnt == E_PULSE_END) lcd_e <= 0;
                    
                    if (wait_cnt >= E_PULSE_TOTAL) begin
                        wait_cnt <= 0;
                        state <= ST_FUNC_SET;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                ST_FUNC_SET: begin // 0x38
                    lcd_rs <= 0;
                    lcd_rw <= 0;
                    lcd_data <= CMD_FUNC_SET;
                    
                    if (wait_cnt == E_PULSE_START) lcd_e <= 1;
                    else if (wait_cnt == E_PULSE_END) lcd_e <= 0;
                    
                    if (wait_cnt >= E_PULSE_TOTAL) begin
                        wait_cnt <= 0;
                        state <= ST_DISP_OFF;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                ST_DISP_OFF: begin // 0x08
                    lcd_rs <= 0;
                    lcd_rw <= 0;
                    lcd_data <= CMD_DISP_OFF;
                    
                    if (wait_cnt == E_PULSE_START) lcd_e <= 1;
                    else if (wait_cnt == E_PULSE_END) lcd_e <= 0;
                    
                    if (wait_cnt >= E_PULSE_TOTAL) begin
                        wait_cnt <= 0;
                        state <= ST_DISP_CLR;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                ST_DISP_CLR: begin // 0x01
                    lcd_rs <= 0;
                    lcd_rw <= 0;
                    lcd_data <= CMD_DISP_CLEAR;
                    
                    if (wait_cnt == E_PULSE_START) lcd_e <= 1;
                    else if (wait_cnt == E_PULSE_END) lcd_e <= 0;
                    
                    if (wait_cnt >= (CNT_CLR + E_PULSE_END)) begin
                        wait_cnt <= 0;
                        state <= ST_ENTRY_MODE;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                ST_ENTRY_MODE: begin // 0x06
                    lcd_rs <= 0;
                    lcd_rw <= 0;
                    lcd_data <= CMD_ENTRY_MODE;
                    
                    if (wait_cnt == E_PULSE_START) lcd_e <= 1;
                    else if (wait_cnt == E_PULSE_END) lcd_e <= 0;
                    
                    if (wait_cnt >= E_PULSE_TOTAL) begin
                        wait_cnt <= 0;
                        state <= ST_DISP_ON;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                ST_DISP_ON: begin // 0x0C
                    lcd_rs <= 0;
                    lcd_rw <= 0;
                    lcd_data <= CMD_DISP_ON;
                    
                    if (wait_cnt == E_PULSE_START) lcd_e <= 1;
                    else if (wait_cnt == E_PULSE_END) lcd_e <= 0;
                    
                    if (wait_cnt >= E_PULSE_TOTAL) begin
                        wait_cnt <= 0;
                        lcd_busy <= 0;
                        state <= ST_IDLE;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                //==============================================================
                // 대기 및 문자 출력
                //==============================================================
                ST_IDLE: begin
                    lcd_e <= 0;
                    lcd_busy <= 0;
                    wait_cnt <= 0;
                    
                    if (lcd_req) begin
                        lcd_busy <= 1;
                        
                        // 좌표 계산
                        if (lcd_row == 2'b00) begin
                            target_addr <= {3'b000, lcd_col}; // 0x00 + col
                        end else begin
                            target_addr <= {3'b100, lcd_col}; // 0x40 + col
                        end
                        
                        state <= ST_SET_ADDR;
                    end
                end

                ST_SET_ADDR: begin
                    lcd_rs <= 0;
                    lcd_rw <= 0;
                    lcd_data <= {1'b1, target_addr}; // 0x80 | Address
                    
                    if (wait_cnt == E_PULSE_START) lcd_e <= 1;
                    else if (wait_cnt == E_PULSE_END) lcd_e <= 0;
                    
                    if (wait_cnt >= E_PULSE_TOTAL) begin
                        wait_cnt <= 0;
                        state <= ST_WRITE_CHAR;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                ST_WRITE_CHAR: begin
                    lcd_rs <= 1; // Data 모드
                    lcd_rw <= 0;
                    lcd_data <= lcd_char;
                    
                    if (wait_cnt == E_PULSE_START) lcd_e <= 1;
                    else if (wait_cnt == E_PULSE_END) lcd_e <= 0;
                    
                    if (wait_cnt >= E_PULSE_TOTAL) begin
                        wait_cnt <= 0;
                        lcd_done <= 1;
                        lcd_busy <= 0;
                        state <= ST_IDLE;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                default: state <= ST_PWR_WAIT;
            endcase
        end
    end

endmodule
