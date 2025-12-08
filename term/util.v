`timescale 1ns / 1ps

module ButtonMorseInput #(
    parameter integer DEBOUNCE_CYCLES             = 50_000,
    parameter integer LONG_PRESS_CYCLES           = 2_500_000,
    parameter integer AUTOREPEAT_DELAY_CYCLES     = 5_000_000,
    parameter integer AUTOREPEAT_INTERVAL_CYCLES  = 1_000_000
)(
    input  wire clk,
    input  wire rst_n,

    input  wire [4:0] btn,

    output reg        key_valid,
    output reg [10:0] key_packet,

    output wire       dot_pulse_btn0,
    output wire       dash_pulse_btn0,
    output wire       auto_dot_pulse,
    output wire       btn1_held
);

    localparam TYPE_KEY = 3'b001;
    localparam KEY_DOT  = 8'd1;
    localparam KEY_DASH = 8'd2;

    // =============================================
    // 1. Synchronizer (2-stage flip-flop)
    // =============================================
    reg [1:0] b0_sync, b1_sync;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            b0_sync <= 2'b00;
            b1_sync <= 2'b00;
        end else begin
            b0_sync <= {b0_sync[0], btn[0]};
            b1_sync <= {b1_sync[0], btn[1]};
        end
    end

    // =============================================
    // 2. Debouncer for btn[0]
    // =============================================
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

    assign btn1_held = b0_stable;

    // =============================================
    // 3. Edge detection & Press duration for btn[0]
    // =============================================
    reg        b0_prev;
    reg [31:0] press_duration;
    reg        dot_pulse_reg;
    reg        dash_pulse_reg;

    wire b0_rising  = (b0_stable && !b0_prev);
    wire b0_falling = (!b0_stable && b0_prev);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            b0_prev <= 1'b0;
            press_duration <= 32'd0;
            dot_pulse_reg <= 1'b0;
            dash_pulse_reg <= 1'b0;
        end else begin
            b0_prev <= b0_stable;
            dot_pulse_reg <= 1'b0;
            dash_pulse_reg <= 1'b0;

            if(b0_rising) begin
                press_duration <= 32'd0;
            end else if(b0_stable) begin
                if(press_duration < 32'hFFFFFFFF)
                    press_duration <= press_duration + 1;
            end

            if(b0_falling) begin
                if(press_duration >= LONG_PRESS_CYCLES) begin
                    dash_pulse_reg <= 1'b1;
                end else if(press_duration > DEBOUNCE_CYCLES) begin
                    dot_pulse_reg <= 1'b1;
                end
            end
        end
    end

    assign dot_pulse_btn0  = dot_pulse_reg;
    assign dash_pulse_btn0 = dash_pulse_reg;

    // =============================================
    // 4. Debouncer for btn[1]
    // =============================================
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

    // =============================================
    // 5. Auto-repeat for btn[1]
    // =============================================
    reg [1:0]  ar_state;
    reg [31:0] ar_counter;
    reg        auto_dot_reg;

    localparam AR_IDLE   = 2'd0;
    localparam AR_DELAY  = 2'd1;
    localparam AR_REPEAT = 2'd2;

    reg b1_prev;
    wire b1_rising = (b1_stable && !b1_prev);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            b1_prev <= 1'b0;
            ar_state <= AR_IDLE;
            ar_counter <= 32'd0;
            auto_dot_reg <= 1'b0;
        end else begin
            b1_prev <= b1_stable;
            auto_dot_reg <= 1'b0;

            case(ar_state)
                AR_IDLE: begin
                    if(b1_rising) begin
                        ar_state <= AR_DELAY;
                        ar_counter <= 32'd0;
                    end
                end

                AR_DELAY: begin
                    if(!b1_stable) begin
                        ar_state <= AR_IDLE;
                    end else if(ar_counter >= AUTOREPEAT_DELAY_CYCLES) begin
                        auto_dot_reg <= 1'b1;
                        ar_state <= AR_REPEAT;
                        ar_counter <= 32'd0;
                    end else begin
                        ar_counter <= ar_counter + 1;
                    end
                end

                AR_REPEAT: begin
                    if(!b1_stable) begin
                        ar_state <= AR_IDLE;
                    end else if(ar_counter >= AUTOREPEAT_INTERVAL_CYCLES) begin
                        auto_dot_reg <= 1'b1;
                        ar_counter <= 32'd0;
                    end else begin
                        ar_counter <= ar_counter + 1;
                    end
                end

                default: ar_state <= AR_IDLE;
            endcase
        end
    end

    assign auto_dot_pulse = auto_dot_reg;

    // =============================================
    // 6. Key packet generation
    // =============================================
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            key_valid <= 1'b0;
            key_packet <= 11'd0;
        end else begin
            key_valid <= 1'b0;

            if(dash_pulse_reg) begin
                key_valid <= 1'b1;
                key_packet <= {TYPE_KEY, KEY_DASH};
            end else if(dot_pulse_reg || auto_dot_reg) begin
                key_valid <= 1'b1;
                key_packet <= {TYPE_KEY, KEY_DOT};
            end
        end
    end

endmodule

module PiezoToneController (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        btn1_held,
    input  wire        auto_dot_pulse,
    input  wire        dash_pulse,
    
    // ? 동적 타이밍 입력
    input  wire [31:0] dash_cycles,
    input  wire [31:0] autorepeat_cycles,
    
    output reg         piezo_out
);

    // 톤 생성 (440Hz 예시)
    parameter CLK_HZ = 25_000_000;
    parameter TONE_HZ = 440;
    localparam TOGGLE_COUNT = CLK_HZ / (2 * TONE_HZ);
    
    reg [31:0] tone_counter;
    reg [31:0] beep_counter;
    reg        beeping;
    reg        tone_toggle;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tone_counter <= 32'd0;
            beep_counter <= 32'd0;
            beeping <= 1'b0;
            tone_toggle <= 1'b0;
            piezo_out <= 1'b0;
        end
        else begin
            // 비프 시작 트리거
            if(dash_pulse || auto_dot_pulse) begin
                beeping <= 1'b1;
                beep_counter <= 32'd0;
            end
            
            // 비프 중
            if(beeping) begin
                // ? 동적 사이클 사용
                if(beep_counter < (dash_pulse ? dash_cycles : autorepeat_cycles)) begin
                    beep_counter <= beep_counter + 1;
                    
                    // 톤 생성
                    if(tone_counter < TOGGLE_COUNT) begin
                        tone_counter <= tone_counter + 1;
                    end
                    else begin
                        tone_counter <= 32'd0;
                        tone_toggle <= ~tone_toggle;
                    end
                    
                    piezo_out <= tone_toggle;
                end
                else begin
                    beeping <= 1'b0;
                    piezo_out <= 1'b0;
                end
            end
        end
    end

endmodule

module RGB_LED_Controller (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        dash_pulse,
    
    // ? 동적 타이밍 입력
    input  wire [31:0] dash_display_cycles,
    
    output reg         led_r,
    output reg         led_g,
    output reg         led_b
);

    reg [31:0] display_counter;
    reg        displaying;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            led_r <= 1'b0;
            led_g <= 1'b0;
            led_b <= 1'b0;
            displaying <= 1'b0;
            display_counter <= 32'd0;
        end else begin
            if(dash_pulse) begin
                displaying <= 1'b1;
                display_counter <= 32'd0;
                led_r <= 1'b1;
                led_g <= 1'b0;
                led_b <= 1'b0;
            end
            
            if(displaying) begin
                // ? 동적 사이클 사용
                if(display_counter >= dash_display_cycles) begin
                    displaying <= 1'b0;
                    led_r <= 1'b0;
                end else begin
                    display_counter <= display_counter + 1;
                end
            end
        end
    end

endmodule

module AlwaysOnLEDs(
    output wire [9:0] led
);
    assign led[0] = 1'b0;
    assign led[1] = 1'b1;  // LED1 on
    assign led[2] = 1'b1;  // LED2 on
    assign led[3] = 1'b1;  // LED3 on
    assign led[4] = 1'b1;  // LED4 on
    assign led[5] = 1'b0;
    assign led[6] = 1'b1;  // LED6 on
    assign led[7] = 1'b0;
endmodule

module TimingController #(
    parameter CLK_HZ = 25_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        speed_up,      // btn[2] - 속도 증가
    input  wire        speed_down,    // btn[5] - 속도 감소
    
    output reg  [2:0]  speed_level,   // 0~4 단계
    output reg  [31:0] timeout_cycles,
    output reg  [31:0] dash_cycles,
    output reg  [31:0] autorepeat_cycles,
    output reg  [8:0]  servo_angle    // 0, 45, 90, 135, 180
);

    // 기준 타이밍 (0단계)
    localparam BASE_TIMEOUT = CLK_HZ / 2;           // 0.5초
    localparam BASE_DASH = CLK_HZ;                  // 1초
    localparam BASE_AUTOREPEAT = CLK_HZ / 2;        // 0.5초

    // 속도 배율 (고정소수점: 256 = 1.0배)
    reg [15:0] speed_multiplier[0:4];
    
    initial begin
        speed_multiplier[0] = 16'd256;   // 1.0배 (기준)
        speed_multiplier[1] = 16'd192;   // 0.75배
        speed_multiplier[2] = 16'd128;   // 0.5배
        speed_multiplier[3] = 16'd96;    // 0.375배
        speed_multiplier[4] = 16'd64;    // 0.25배
    end

    // 서보 각도 매핑
    reg [8:0] angle_map[0:4];
    
    initial begin
        angle_map[0] = 9'd0;
        angle_map[1] = 9'd45;
        angle_map[2] = 9'd90;
        angle_map[3] = 9'd135;
        angle_map[4] = 9'd180;
    end

    // 디바운스용
    reg [1:0] speed_up_sync;
    reg [1:0] speed_down_sync;
    reg speed_up_prev;
    reg speed_down_prev;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            speed_level <= 3'd0;
            speed_up_sync <= 2'b00;
            speed_down_sync <= 2'b00;
            speed_up_prev <= 1'b0;
            speed_down_prev <= 1'b0;
        end
        else begin
            // 동기화
            speed_up_sync <= {speed_up_sync[0], speed_up};
            speed_down_sync <= {speed_down_sync[0], speed_down};
            
            speed_up_prev <= speed_up_sync[1];
            speed_down_prev <= speed_down_sync[1];
            
            // 상승 엣지 감지
            if(speed_up_sync[1] && !speed_up_prev) begin
                if(speed_level < 3'd4)
                    speed_level <= speed_level + 3'd1;
            end
            
            if(speed_down_sync[1] && !speed_down_prev) begin
                if(speed_level > 3'd0)
                    speed_level <= speed_level - 3'd1;
            end
        end
    end

    // 타이밍 계산 (조합 논리)
    always @(*) begin
        // timeout_cycles = BASE_TIMEOUT * multiplier / 256
        timeout_cycles = (BASE_TIMEOUT * speed_multiplier[speed_level]) >> 8;
        
        // dash_cycles = BASE_DASH * multiplier / 256
        dash_cycles = (BASE_DASH * speed_multiplier[speed_level]) >> 8;
        
        // autorepeat_cycles = BASE_AUTOREPEAT * multiplier / 256
        autorepeat_cycles = (BASE_AUTOREPEAT * speed_multiplier[speed_level]) >> 8;
        
        // 서보 각도
        servo_angle = angle_map[speed_level];
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
