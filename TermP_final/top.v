`timescale 1ns / 1ps

module MorseSystemTop #(
    parameter integer CLK_HZ = 25_000_000  // 25MHz
)(
    // ========================================
    // 외부 입력 (FPGA 핀)
    // ========================================
    input  wire        clk,
    input  wire        rst_n,
    input  wire        is_active,
    input  wire [4:0]  btn,

    // ========================================
    // 외부 출력 (FPGA 핀)
    // ========================================
    output wire [7:0]  led,
    output wire        led_r,
    output wire        led_g,
    output wire        led_b,
    output wire        piezo,
    output wire        servo_pwm,
    
    // LCD 출력 (8비트 모드) ← 변경!
    output wire        lcd_e,
    output wire        lcd_rs,
    output wire        lcd_rw,
    output wire [7:0]  lcd_data  // ← 8비트로 변경!
);

    //==========================================================================
    // 파워온 리셋 생성 (Power-On Reset)
    //==========================================================================
    reg [7:0] por_counter = 8'h00;
    reg por_rst_n = 1'b0;
    
    always @(posedge clk) begin
        if (por_counter < 8'hFF) begin
            por_counter <= por_counter + 1;
            por_rst_n <= 1'b0;
        end else begin
            por_rst_n <= 1'b1;
        end
    end
    
    // 내부 리셋 신호: 파워온 리셋 + 외부 리셋 버튼
    wire internal_rst_n;
    assign internal_rst_n = por_rst_n & rst_n;

    //==========================================================================
    // 버튼 입력 동기화 (2단 플립플롭)
    //==========================================================================
    reg [4:0] btn_sync1 = 5'b00000;
    reg [4:0] btn_sync2 = 5'b00000;
    
    always @(posedge clk or negedge internal_rst_n) begin
        if (!internal_rst_n) begin
            btn_sync1 <= 5'b00000;
            btn_sync2 <= 5'b00000;
        end else begin
            btn_sync1 <= btn;
            btn_sync2 <= btn_sync1;
        end
    end
    
    wire [4:0] btn_synced = btn_sync2;

    //==========================================================================
    // is_active 신호 동기화
    //==========================================================================
    reg is_active_sync1 = 1'b0;
    reg is_active_sync2 = 1'b0;
    
    always @(posedge clk or negedge internal_rst_n) begin
        if (!internal_rst_n) begin
            is_active_sync1 <= 1'b0;
            is_active_sync2 <= 1'b0;
        end else begin
            is_active_sync1 <= is_active;
            is_active_sync2 <= is_active_sync1;
        end
    end
    
    wire is_active_synced = is_active_sync2;

    // ========================================
    // 내부 신호 (모듈 간 연결)
    // ========================================
    
    // 타이밍 관련
    wire [2:0]  speed_level;
    wire [31:0] timeout_cycles;
    wire [31:0] dash_cycles;
    wire [31:0] autorepeat_cycles;
    wire [8:0]  servo_angle;
    
    // 버튼 입력 관련
    wire        key_valid;
    wire [10:0] key_packet;
    wire        dot_pulse;
    wire        dash_pulse;
    wire        auto_dot;
    wire        btn1_held;
    
    // LCD 내부 신호
    wire        lcd_busy;
    wire        lcd_done;
    wire        lcd_req;
    wire [1:0]  lcd_row;
    wire [3:0]  lcd_col;
    wire [7:0]  lcd_char;

    // ================================================
    // 타이밍 컨트롤러
    // ================================================
    TimingController #(
        .CLK_HZ(CLK_HZ)
    ) timing_ctrl (
        .clk(clk),
        .rst_n(internal_rst_n),
        .speed_up(btn_synced[2]),
        .speed_down(btn_synced[4]),
        
        .speed_level(speed_level),
        .timeout_cycles(timeout_cycles),
        .dash_cycles(dash_cycles),
        .autorepeat_cycles(autorepeat_cycles),
        .servo_angle(servo_angle)
    );

    // ================================================
    // 버튼 입력 처리
    // ================================================
    ButtonMorseInput #(
        .DEBOUNCE_CYCLES(250_000),              // 10ms
        .LONG_PRESS_CYCLES(12_500_000),         // 사용 안 함
        .AUTOREPEAT_DELAY_CYCLES(12_500_000),   // 사용 안 함
        .AUTOREPEAT_INTERVAL_CYCLES(2_500_000)  // 사용 안 함
    ) btn_input (
        .clk(clk),
        .rst_n(internal_rst_n),
        .btn(btn_synced),
        .key_valid(key_valid),
        .key_packet(key_packet),
        .dot_pulse_btn0(dot_pulse),
        .dash_pulse_btn0(dash_pulse),
        .auto_dot_pulse(auto_dot),
        .btn1_held(btn1_held)
    );

    // ================================================
    // 버퍼 클리어 신호 생성
    // ================================================
    reg clear_btn_prev = 1'b0;
    wire clear_pulse;

    always @(posedge clk or negedge internal_rst_n) begin
        if(!internal_rst_n) begin
            clear_btn_prev <= 1'b0;
        end
        else begin
            clear_btn_prev <= btn_synced[3];
        end
    end

    assign clear_pulse = btn_synced[3] && !clear_btn_prev;

    // ================================================
    // 디코더
    // ================================================
    DecodeUI decode (
        .clk(clk),
        .rst_n(internal_rst_n),
        .is_active(is_active_synced),
        .key_packet(key_packet),
        .key_valid(key_valid),
        
        .clear_buffer(clear_pulse),
        .timeout_cycles(timeout_cycles),

        .lcd_busy(lcd_busy),
        .lcd_done(lcd_done),
        .lcd_req(lcd_req),
        .lcd_row(lcd_row),
        .lcd_col(lcd_col),
        .lcd_char(lcd_char),

        .change_req(),
        .next_ui_id()
    );

    // ================================================
    // LCD 컨트롤러 (8비트 모드)
    // ================================================
    LCD_Controller #(
        .CLK_HZ(CLK_HZ)
    ) lcd_ctrl (
        .clk(clk),
        .rst_n(internal_rst_n),
        
        .lcd_req(lcd_req),
        .lcd_row(lcd_row),
        .lcd_col(lcd_col),
        .lcd_char(lcd_char),
        
        .lcd_busy(lcd_busy),
        .lcd_done(lcd_done),
        
        .lcd_e(lcd_e),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_data(lcd_data)  // ← 직접 연결!
    );

    // ================================================
    // Piezo 컨트롤러
    // ================================================
    PiezoToneController piezo_ctrl (
        .clk(clk),
        .rst_n(internal_rst_n),
        .btn1_held(btn1_held),
        .auto_dot_pulse(auto_dot),
        .dash_pulse(dash_pulse),
        
        .dash_cycles(dash_cycles),
        .autorepeat_cycles(autorepeat_cycles),
        
        .piezo_out(piezo)
    );

    // ================================================
    // RGB LED 컨트롤러
    // ================================================
    RGB_LED_Controller rgb_ctrl (
        .clk(clk),
        .rst_n(internal_rst_n),
        .dash_pulse(dash_pulse),
        
        .dash_display_cycles(dash_cycles),
        
        .led_r(led_r),
        .led_g(led_g),
        .led_b(led_b)
    );

    // ================================================
    // 서보 모터 컨트롤러
    // ================================================
    ServoController #(
        .CLK_HZ(CLK_HZ)
    ) servo_ctrl (
        .clk(clk),
        .rst_n(internal_rst_n),
        .angle(servo_angle),
        .pwm_out(servo_pwm)
    );

    // ================================================
    // Always-On LEDs
    // ================================================
    AlwaysOnLEDs always_leds (
        .led(led)
    );

endmodule