`timescale 1ns / 1ps

module MorseSystemTop #(
    parameter integer CLK_HZ = 100_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        is_active,

    input  wire [4:0]  btn,

    input  wire        lcd_busy,
    input  wire        lcd_done,
    output wire        lcd_req,
    output wire [1:0]  lcd_row,
    output wire [3:0]  lcd_col,
    output wire [7:0]  lcd_char,

    output wire [9:0]  led,
    output wire        led_r,
    output wire        led_g,
    output wire        led_b,

    output wire        piezo,
    output wire        servo_pwm
);

    // ================================================
    // 타이밍 컨트롤러
    // ================================================
    wire [2:0]  speed_level;
    wire [31:0] timeout_cycles;
    wire [31:0] dash_cycles;
    wire [31:0] autorepeat_cycles;
    wire [8:0]  servo_angle;

    TimingController #(
        .CLK_HZ(CLK_HZ)
    ) timing_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .speed_up(btn[2]),      // btn[2]: 속도 증가
        .speed_down(btn[4]),    // btn[4]: 속도 감소
        
        .speed_level(speed_level),
        .timeout_cycles(timeout_cycles),
        .dash_cycles(dash_cycles),
        .autorepeat_cycles(autorepeat_cycles),
        .servo_angle(servo_angle)
    );

    // ================================================
    // 버튼 입력 처리
    // ================================================
    wire key_valid;
    wire [10:0] key_packet;

    wire dot_pulse;
    wire dash_pulse;
    wire auto_dot;
    wire btn1_held;

    ButtonMorseInput #(
        .DEBOUNCE_CYCLES(CLK_HZ / 2000),
        .LONG_PRESS_CYCLES(CLK_HZ / 40),
        .AUTOREPEAT_DELAY_CYCLES(CLK_HZ / 20),
        .AUTOREPEAT_INTERVAL_CYCLES(CLK_HZ / 100)
    ) btn_input (
        .clk(clk),
        .rst_n(rst_n),
        .btn(btn),

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
    reg [1:0] clear_btn_sync;
    reg clear_btn_prev;
    wire clear_pulse;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            clear_btn_sync <= 2'b00;
            clear_btn_prev <= 1'b0;
        end
        else begin
            clear_btn_sync <= {clear_btn_sync[0], btn[3]};
            clear_btn_prev <= clear_btn_sync[1];
        end
    end

    // 상승 엣지 감지
    assign clear_pulse = clear_btn_sync[1] && !clear_btn_prev;

    // ================================================
    // 디코더 (? 버퍼 클리어 추가)
    // ================================================
    DecodeUI decode (
        .clk(clk),
        .rst_n(rst_n),
        .is_active(is_active),
        .key_packet(key_packet),
        .key_valid(key_valid),
        
        // ? 버퍼 클리어 신호 추가
        .clear_buffer(clear_pulse),
        
        // 동적 타이밍 파라미터
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
    // Piezo 컨트롤러
    // ================================================
    PiezoToneController piezo_ctl (
        .clk(clk),
        .rst_n(rst_n),
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
    RGB_LED_Controller rgb_ctl (
        .clk(clk),
        .rst_n(rst_n),
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
        .rst_n(rst_n),
        .angle(servo_angle),
        .pwm_out(servo_pwm)
    );

    // ================================================
    // Always-On LEDs
    // ================================================
    AlwaysOnLEDs always_led (
        .led(led)
    );

endmodule