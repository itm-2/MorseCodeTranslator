`timescale 1ns / 1ps

//==========================================================================
// Top Module
//==========================================================================
module Top (
    input wire clk,
    input wire rst_n,
    input wire [1:0] dip_switch,
    input wire [11:0] btn,
    output wire lcd_e,
    output wire lcd_rs,
    output wire lcd_rw,
    output wire [7:0] lcd_data,
    output wire piezo_out,
    output wire [7:0] led,
    output wire servo_pwm
);

    localparam UI_DECODE  = 2'd0;
    localparam UI_ENCODE  = 2'd1;
    localparam UI_SETTING = 2'd2;
    
    reg [1:0] current_ui;
    reg [1:0] current_ui_prev;
    
    reg [31:0] long_key_cycles;
    reg [31:0] dit_gap_cycles;
    reg [31:0] timeout_cycles;
    reg [31:0] space_cycles;
    reg [31:0] dit_time;
    reg [31:0] dah_time;
    reg [31:0] dit_gap;
    reg [15:0] tone_freq;
    
    wire [31:0] new_long_key_cycles;
    wire [31:0] new_dit_gap_cycles;
    wire [31:0] new_timeout_cycles;
    wire [31:0] new_space_cycles;
    wire [31:0] new_dit_time;
    wire [31:0] new_dah_time;
    wire [31:0] new_dit_gap;
    wire [15:0] new_tone_freq;
    wire [127:0] setting_display_text;
    wire setting_text_valid;
    wire setting_piezo_out;
    wire setting_settings_applied;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_ui <= UI_DECODE;
            current_ui_prev <= 2'b11;
            long_key_cycles <= 32'd25_000_000;
            dit_gap_cycles  <= 32'd12_500_000;
            timeout_cycles  <= 32'd75_000_000;
            space_cycles    <= 32'd150_000_000;
            dit_time        <= 32'd12_500_000;
            dah_time        <= 32'd37_500_000;
            dit_gap         <= 32'd12_500_000;
            tone_freq       <= 16'd440;
        end else begin
            current_ui_prev <= current_ui;
            case (dip_switch)
                2'b00:   current_ui <= UI_DECODE;
                2'b01:   current_ui <= UI_ENCODE;
                2'b10:   current_ui <= UI_SETTING;
                default: current_ui <= UI_DECODE;
            endcase
            if (setting_settings_applied) begin
                long_key_cycles <= new_long_key_cycles;
                dit_gap_cycles  <= new_dit_gap_cycles;
                timeout_cycles  <= new_timeout_cycles;
                space_cycles    <= new_space_cycles;
                dit_time        <= new_dit_time;
                dah_time        <= new_dah_time;
                dit_gap         <= new_dit_gap;
                tone_freq       <= new_tone_freq;
            end
        end
    end
    
    reg [11:0] btn_prev;
    wire [11:0] btn_pressed;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) btn_prev <= 12'b0;
        else btn_prev <= btn;
    end
    assign btn_pressed = btn & ~btn_prev;
    
    wire key_valid;
    wire [10:0] key_packet;
    wire btn1_held;
    wire btn2_dot_pulse;
    
    ButtonMorseInput #(.DEBOUNCE_CYCLES(250_000)) btn_morse_input (
        .clk(clk), .rst_n(rst_n),
        .btn({btn[4], btn[3], btn[2], btn[1], btn[0]}),
        .LONG_KEY_CYCLES(long_key_cycles),
        .DIT_GAP_CYCLES(dit_gap_cycles),
        .key_valid(key_valid),
        .key_packet(key_packet),
        .btn1_held(btn1_held),
        .btn2_dot_pulse(btn2_dot_pulse)
    );
    
    wire decode_lcd_req;
    wire [1:0] decode_lcd_row;
    wire [3:0] decode_lcd_col;
    wire [7:0] decode_lcd_char;
    wire decode_lcd_busy;
    wire decode_lcd_done;
    wire decode_char_complete_beep;
    wire [7:0] decode_led;
    
    DecodeUI decode_ui (
        .clk(clk), .rst_n(rst_n),
        .is_active(current_ui == UI_DECODE),
        .key_packet(key_packet),
        .key_valid(key_valid),
        .clear_buffer(1'b0),
        .timeout_cycles(timeout_cycles),
        .lcd_busy(decode_lcd_busy),
        .lcd_done(decode_lcd_done),
        .lcd_req(decode_lcd_req),
        .lcd_row(decode_lcd_row),
        .lcd_col(decode_lcd_col),
        .lcd_char(decode_lcd_char),
        .change_req(),
        .next_ui_id(),
        .char_complete_beep(decode_char_complete_beep),
        .led_out(decode_led)
    );
    
    wire encode_lcd_req;
    wire [1:0] encode_lcd_row;
    wire [3:0] encode_lcd_col;
    wire [7:0] encode_lcd_char;
    wire encode_lcd_busy;
    wire encode_lcd_done;
    wire encode_piezo_out;
    wire [7:0] encode_led;
    
    EncoderUI encoder_ui (
        .clk(clk), .rst_n(rst_n),
        .is_active(current_ui == UI_ENCODE),
        .key_in(btn_pressed[9:0]),
        .btn_encode(btn[11]),
        .btn_nxt(btn[10]),
        .btn_clear(1'b0),
        .dit_time(dit_time),
        .dah_time(dah_time),
        .dit_gap_time(dit_gap),
        .lcd_busy(encode_lcd_busy),
        .lcd_done(encode_lcd_done),
        .lcd_req(encode_lcd_req),
        .lcd_row(encode_lcd_row),
        .lcd_col(encode_lcd_col),
        .lcd_char(encode_lcd_char),
        .piezo_out(encode_piezo_out),
        .led_out(encode_led)
    );
    
    wire [8:0] setting_servo_angle;
    wire [7:0] setting_led;
    
    ManualTimingSettingUI #(.CLK_HZ(50_000_000)) setting_ui (
        .clk(clk), .rst_n(rst_n),
        .ui_active(current_ui == UI_SETTING),
        .btn1_pressed(btn_pressed[0]),
        .btn2_pressed(btn_pressed[1]),
        .btn12_pressed(btn_pressed[11]),
        .ext_level_set(1'b0),
        .ext_level(2'b0),
        .display_text(setting_display_text),
        .text_valid(setting_text_valid),
        .long_key_cycles(new_long_key_cycles),
        .dit_gap_cycles(new_dit_gap_cycles),
        .timeout_cycles(new_timeout_cycles),
        .space_cycles(new_space_cycles),
        .dit_time(new_dit_time),
        .dah_time(new_dah_time),
        .dit_gap(new_dit_gap),
        .tone_freq(new_tone_freq),
        .settings_applied(setting_settings_applied),
        .piezo_out(setting_piezo_out),
        .led_out(setting_led),
        .servo_angle(setting_servo_angle)
    );
   
    //==========================================================================
    // Setting UI LCD FSM (???ο? ????)
    //==========================================================================
    localparam ST_SETTING_IDLE  = 3'd0;
    localparam ST_SETTING_CLEAR = 3'd1;
    localparam ST_SETTING_WRITE = 3'd2;
    localparam ST_SETTING_WAIT  = 3'd3;
    
    reg [2:0] setting_lcd_state;
    reg [5:0] setting_char_index;  // 0~31 (6???)
    reg [127:0] setting_text_buffer;
    reg setting_lcd_req;
    reg [1:0] setting_lcd_row;
    reg [3:0] setting_lcd_col;
    reg [7:0] setting_lcd_char;
    reg setting_clear_done;  // CLEAR ??? ?÷???
    wire setting_lcd_busy;
    wire setting_lcd_done;
    
    reg [127:0] prev_setting_text;
    reg setting_ui_prev;
    
    wire setting_text_changed = (setting_display_text != prev_setting_text) && setting_text_valid;
    wire setting_just_activated = (current_ui == UI_SETTING) && (current_ui_prev != UI_SETTING);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_setting_text <= 128'h0;
            setting_ui_prev <= 1'b0;
        end else begin
            prev_setting_text <= setting_display_text;
            setting_ui_prev <= (current_ui == UI_SETTING);
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            setting_lcd_state <= ST_SETTING_IDLE;
            setting_lcd_req <= 1'b0;
            setting_lcd_row <= 2'd0;
            setting_lcd_col <= 4'd0;
            setting_lcd_char <= 8'h20;
            setting_char_index <= 6'd0;
            setting_text_buffer <= 128'h0;
            setting_clear_done <= 1'b0;
        end else begin
            case (setting_lcd_state)
                // ========================================
                // IDLE: ????? ???
                // ========================================
                ST_SETTING_IDLE: begin
                    setting_lcd_req <= 1'b0;
                    setting_char_index <= 6'd0;
                    setting_clear_done <= 1'b0;
                    
                    if (setting_just_activated || setting_text_changed) begin
                        setting_text_buffer <= setting_display_text;
                        setting_lcd_state <= ST_SETTING_CLEAR;
                    end
                end
                
                // ========================================
                // CLEAR: ??? ??? ????? (32????)
                // ========================================
                ST_SETTING_CLEAR: begin
                    if (!setting_lcd_busy && !setting_lcd_req) begin
                        setting_lcd_req <= 1'b1;
                        setting_lcd_row <= (setting_char_index < 6'd16) ? 2'd0 : 2'd1;
                        setting_lcd_col <= setting_char_index[3:0];
                        setting_lcd_char <= 8'h20;  // ????
                        setting_lcd_state <= ST_SETTING_WAIT;
                    end
                end
                
                // ========================================
                // WRITE: ???? ???? (32????)
                // ========================================
                ST_SETTING_WRITE: begin
                    if (!setting_lcd_busy && !setting_lcd_req) begin
                        setting_lcd_req <= 1'b1;
                        setting_lcd_row <= (setting_char_index < 6'd16) ? 2'd0 : 2'd1;
                        setting_lcd_col <= setting_char_index[3:0];
                        
                        // ???? ??????? ??? ???? ???? (Row 0??)
                        case (setting_char_index)
                            6'd0:  setting_lcd_char <= setting_text_buffer[127:120];
                            6'd1:  setting_lcd_char <= setting_text_buffer[119:112];
                            6'd2:  setting_lcd_char <= setting_text_buffer[111:104];
                            6'd3:  setting_lcd_char <= setting_text_buffer[103:96];
                            6'd4:  setting_lcd_char <= setting_text_buffer[95:88];
                            6'd5:  setting_lcd_char <= setting_text_buffer[87:80];
                            6'd6:  setting_lcd_char <= setting_text_buffer[79:72];
                            6'd7:  setting_lcd_char <= setting_text_buffer[71:64];
                            6'd8:  setting_lcd_char <= setting_text_buffer[63:56];
                            6'd9:  setting_lcd_char <= setting_text_buffer[55:48];
                            6'd10: setting_lcd_char <= setting_text_buffer[47:40];
                            6'd11: setting_lcd_char <= setting_text_buffer[39:32];
                            6'd12: setting_lcd_char <= setting_text_buffer[31:24];
                            6'd13: setting_lcd_char <= setting_text_buffer[23:16];
                            6'd14: setting_lcd_char <= setting_text_buffer[15:8];
                            6'd15: setting_lcd_char <= setting_text_buffer[7:0];
                            default: setting_lcd_char <= 8'h20;  // Row1?? ????
                        endcase
                        
                        // NULL ????? ???????? ???
                        if (setting_lcd_char == 8'h00) 
                            setting_lcd_char <= 8'h20;
                        
                        setting_lcd_state <= ST_SETTING_WAIT;
                    end
                end
                
                // ========================================
                // WAIT: LCD ??? ???
                // ========================================
                ST_SETTING_WAIT: begin
                    setting_lcd_req <= 1'b0;
                    
                    if (lcd_done_shared) begin
                        if (setting_char_index == 6'd31) begin
                            // 32???? ???
                            setting_char_index <= 6'd0;
                            if (!setting_clear_done) begin
                                // CLEAR ??? ?? WRITE??
                                setting_clear_done <= 1'b1;
                                setting_lcd_state <= ST_SETTING_WRITE;
                            end else begin
                                // WRITE ??? ?? IDLE??
                                setting_lcd_state <= ST_SETTING_IDLE;
                            end
                        end else begin
                            // ???? ????
                            setting_char_index <= setting_char_index + 6'd1;
                            setting_lcd_state <= setting_clear_done ? ST_SETTING_WRITE : ST_SETTING_CLEAR;
                        end
                    end
                end
                
                default: setting_lcd_state <= ST_SETTING_IDLE;
            endcase
        end
    end
    
    //==========================================================================
    // LCD Multiplexer
    //==========================================================================
    wire lcd_req_mux  = (current_ui == UI_DECODE)  ? decode_lcd_req  : 
                        (current_ui == UI_ENCODE)  ? encode_lcd_req  : 
                        (current_ui == UI_SETTING) ? setting_lcd_req  : 1'b0;
    
    wire [1:0] lcd_row_mux  = (current_ui == UI_DECODE)  ? decode_lcd_row  : 
                               (current_ui == UI_ENCODE)  ? encode_lcd_row  : 
                               (current_ui == UI_SETTING) ? setting_lcd_row  : 2'd0;
    
    wire [3:0] lcd_col_mux  = (current_ui == UI_DECODE)  ? decode_lcd_col  : 
                               (current_ui == UI_ENCODE)  ? encode_lcd_col  : 
                               (current_ui == UI_SETTING) ? setting_lcd_col  : 4'd0;
    
    wire [7:0] lcd_char_mux = (current_ui == UI_DECODE)  ? decode_lcd_char : 
                               (current_ui == UI_ENCODE)  ? encode_lcd_char : 
                               (current_ui == UI_SETTING) ? setting_lcd_char : 8'h20;
    
    assign led = (current_ui == UI_DECODE) ? decode_led : 
                 (current_ui == UI_ENCODE) ? encode_led : 
                 (current_ui == UI_SETTING) ? setting_led : 8'h00;
    
    wire lcd_busy_shared;
    
    assign decode_lcd_busy  = lcd_busy_shared;
    assign decode_lcd_done  = (current_ui == UI_DECODE)  ? lcd_done_shared : 1'b0;
    assign encode_lcd_busy  = lcd_busy_shared;
    assign encode_lcd_done  = (current_ui == UI_ENCODE)  ? lcd_done_shared : 1'b0;
    assign setting_lcd_busy = lcd_busy_shared;
    assign setting_lcd_done = (current_ui == UI_SETTING) ? lcd_done_shared : 1'b0;
    
    LCD_Controller #(.CLK_HZ(25_000_000)) lcd_ctrl (
        .clk(clk), .rst_n(rst_n),
        .lcd_req(lcd_req_mux),
        .lcd_row(lcd_row_mux),
        .lcd_col(lcd_col_mux),
        .lcd_char(lcd_char_mux),
        .lcd_busy(lcd_busy_shared),
        .lcd_done(lcd_done_shared),
        .lcd_e(lcd_e),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_data(lcd_data)
    );
    
    wire decode_piezo_out;
    PiezoToneController #(.CLK_HZ(25_000_000)) piezo_tone_ctrl (
        .clk(clk), .rst_n(rst_n),
        .btn1_held(btn1_held && (current_ui == UI_DECODE)),
        .btn2_dot_pulse(btn2_dot_pulse && (current_ui == UI_DECODE)),
        .dash_cycles(long_key_cycles),
        .autorepeat_cycles(dit_gap),
        .char_complete_beep(decode_char_complete_beep),
        .piezo_out(decode_piezo_out)
    );
    
    assign piezo_out = (current_ui == UI_DECODE) ? decode_piezo_out : 
                       (current_ui == UI_ENCODE) ? encode_piezo_out : 
                       (current_ui == UI_SETTING) ? setting_piezo_out : 1'b0;
    
    ServoController #(.CLK_HZ(25_000_000)) servo_ctrl (
        .clk(clk), .rst_n(rst_n),
        .angle(setting_servo_angle),
        .pwm_out(servo_pwm)
    );

endmodule
