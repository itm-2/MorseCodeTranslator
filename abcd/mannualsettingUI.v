//==========================================================================
// ManualTimingSettingUI - 서보모터 각도 제어 추가 버전
//==========================================================================
module ManualTimingSettingUI #(
    parameter CLK_HZ = 25_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ui_active,
    input  wire        btn1_pressed,
    input  wire        btn2_pressed,
    input  wire        btn12_pressed,
    input  wire        ext_level_set,
    input  wire [1:0]  ext_level,
    output reg  [127:0] display_text,
    output reg         text_valid,
    output reg  [31:0] long_key_cycles,
    output reg  [31:0] dit_gap_cycles,
    output reg  [31:0] timeout_cycles,
    output reg  [31:0] space_cycles,
    output reg  [31:0] dit_time,
    output reg  [31:0] dah_time,
    output reg  [31:0] dit_gap,
    output reg  [15:0] tone_freq,
    output reg         settings_applied,
    output wire        piezo_out,
    output reg  [7:0]  led_out,
    output reg  [8:0]  servo_angle
);

    localparam [1:0] LEVEL_BEGINNER     = 2'd0;
    localparam [1:0] LEVEL_INTERMEDIATE = 2'd1;
    localparam [1:0] LEVEL_ADVANCED     = 2'd2;
    localparam [1:0] LEVEL_EXPERT       = 2'd3;
    
    localparam [31:0] BASE_LONG_KEY = 32'd2_200_000;  // 0.1초 꾹 누르면 Dash (민감함)
    localparam [31:0] BASE_DIT_GAP  = 32'd1_250_000;  // 0.05초 간격 연사
    localparam [31:0] BASE_DIT_TIME = 32'd500_000;  // 점 길이 0.05초
    localparam [31:0] BASE_DAH_TIME = 32'd2_000_000;  // 선 길이 0.15초
    localparam [15:0] BASE_TONE_FREQ = 16'd440;
    
    localparam [255:0] DEMO_BITSTREAM = {
        2'b10, 1'b0, 2'b10, 1'b0, 2'b11,
        2'b10, 2'b10, 1'b0, 2'b10, 2'b11,
        4'b1111,
        2'b10, 1'b0, 1'b0, 2'b11,
        1'b0, 2'b11,
        4'b1111,
        1'b0, 2'b10, 2'b10, 2'b10, 2'b10, 2'b11,
        1'b0, 1'b0, 2'b10, 2'b10, 2'b10, 2'b11,
        1'b0, 1'b0, 1'b0, 2'b10, 2'b10, 2'b11,
        56'b0
    };
    
    localparam [8:0] DEMO_BIT_LENGTH = 9'd72;
    
    reg [1:0] current_level;
    reg [1:0] saved_level;
    reg [1:0] prev_level;
    
    localparam [127:0] STR_BEGINNER     = "BEGINNER        ";
    localparam [127:0] STR_INTERMEDIATE = "INTERMEDIATE    ";
    localparam [127:0] STR_ADVANCED     = "ADVANCED        ";
    localparam [127:0] STR_EXPERT       = "EXPERT          ";
    
    always @(*) begin
        case (current_level)
            LEVEL_BEGINNER:     servo_angle = 9'd0;
            LEVEL_INTERMEDIATE: servo_angle = 9'd60;
            LEVEL_ADVANCED:     servo_angle = 9'd120;
            LEVEL_EXPERT:       servo_angle = 9'd180;
            default:            servo_angle = 9'd0;
        endcase
    end
    
    reg [31:0] multiplier_num;
    reg [31:0] multiplier_den;
    
    always @(*) begin
        case (current_level)
            LEVEL_BEGINNER:     begin multiplier_num = 32'd12;  multiplier_den = 32'd2; end
            LEVEL_INTERMEDIATE: begin multiplier_num = 32'd6;  multiplier_den = 32'd2; end
            LEVEL_ADVANCED:     begin multiplier_num = 32'd4;  multiplier_den = 32'd2; end
            LEVEL_EXPERT:       begin multiplier_num = 32'd3; multiplier_den = 32'd2; end
            default:            begin multiplier_num = 32'd3;  multiplier_den = 32'd2; end
        endcase
    end
    
    wire [31:0] calc_long_key = (BASE_LONG_KEY * multiplier_num) / multiplier_den;
    wire [31:0] calc_dit_gap  = (BASE_DIT_GAP  * multiplier_num) / multiplier_den;
    wire [31:0] calc_dit_time = (BASE_DIT_TIME * multiplier_num) / multiplier_den;
    wire [31:0] calc_dah_time = (BASE_DAH_TIME * multiplier_num) / multiplier_den;
    wire [31:0] calc_timeout  = calc_dit_gap * 32'd6;
    wire [31:0] calc_space    = calc_timeout * 32'd2;
    
    reg        player_start;
    wire       player_busy;
    wire       player_done;
    reg        playback_enabled;
    
    localparam ST_IDLE    = 2'd0;
    localparam ST_WAIT    = 2'd1;
    localparam ST_PLAYING = 2'd2;
    
    reg [1:0]  play_state;
    reg [31:0] wait_counter;
    localparam RESTART_DELAY = 32'd2_500_000;
    
    reg ui_active_prev;
    wire ui_just_activated = ui_active && !ui_active_prev;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ui_active_prev <= 1'b0;
        end else begin
            ui_active_prev <= ui_active;
        end
    end
    
    //==========================================================================
    // ★ 핵심 수정: text_valid를 1 cycle pulse로 변경
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saved_level   <= LEVEL_BEGINNER;
            current_level <= LEVEL_BEGINNER;
            prev_level    <= LEVEL_BEGINNER;
            play_state       <= ST_IDLE;
            player_start     <= 1'b0;
            wait_counter     <= 32'd0;
            playback_enabled <= 1'b0;
            led_out <= 8'h00;
            text_valid <= 1'b0;  // ← 추가
        end else begin
            player_start <= 1'b0;
            text_valid <= 1'b0;  // ← 기본값
            
            if (ui_active) begin
                led_out <= 8'b0000_0011;
            end else begin
                led_out <= 8'h00;
            end
            
            if (ext_level_set) begin
                saved_level <= ext_level;
                if (ui_active) begin
                    current_level <= ext_level;
                    text_valid <= 1'b1;  // ← 텍스트 변경 시 펄스
                end
            end
            else if (ui_just_activated) begin
                current_level    <= saved_level;
                prev_level       <= saved_level;
                playback_enabled <= 1'b1;
                play_state       <= ST_IDLE;
                wait_counter     <= 32'd0;
                text_valid <= 1'b1;  // ← UI 활성화 시 펄스
            end
            else if (!ui_active) begin
                play_state       <= ST_IDLE;
                prev_level       <= current_level;
                playback_enabled <= 1'b0;
            end
            else begin
                playback_enabled <= 1'b1;
                
                if (btn12_pressed) begin
                    saved_level <= current_level;
                    play_state  <= ST_IDLE;
                end
                else if (btn2_pressed && current_level != LEVEL_EXPERT) begin
                    current_level <= current_level + 2'd1;
                    text_valid <= 1'b1;  // ← 난이도 변경 시 펄스
                end
                else if (btn1_pressed && current_level != LEVEL_BEGINNER) begin
                    current_level <= current_level - 2'd1;
                    text_valid <= 1'b1;  // ← 난이도 변경 시 펄스
                end
                
                case (play_state)
                    ST_IDLE: begin
                        if (current_level != prev_level) begin
                            prev_level   <= current_level;
                            wait_counter <= 32'd0;
                            play_state   <= ST_WAIT;
                        end
                    end
                    ST_WAIT: begin
                        if (current_level != prev_level) begin
                            prev_level   <= current_level;
                            wait_counter <= 32'd0;
                        end else if (wait_counter >= RESTART_DELAY) begin
                            player_start <= 1'b1;
                            play_state   <= ST_PLAYING;
                        end else begin
                            wait_counter <= wait_counter + 32'd1;
                        end
                    end
                    ST_PLAYING: begin
                        if (current_level != prev_level) begin
                            prev_level   <= current_level;
                            wait_counter <= 32'd0;
                            play_state   <= ST_WAIT;
                        end else if (player_done) begin
                            player_start <= 1'b1;
                        end
                    end
                    default: play_state <= ST_IDLE;
                endcase
            end
        end
    end
    
    // ========== 디스플레이 텍스트 출력 (조합 논리 유지) ==========
    always @(*) begin
        case (current_level)
            LEVEL_BEGINNER:     display_text = STR_BEGINNER;
            LEVEL_INTERMEDIATE: display_text = STR_INTERMEDIATE;
            LEVEL_ADVANCED:     display_text = STR_ADVANCED;
            LEVEL_EXPERT:       display_text = STR_EXPERT;
            default:            display_text = STR_BEGINNER;
        endcase
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            long_key_cycles <= BASE_LONG_KEY;
            dit_gap_cycles  <= BASE_DIT_GAP;
            timeout_cycles  <= BASE_DIT_GAP * 32'd6;
            space_cycles    <= BASE_DIT_GAP * 32'd12;
            dit_time        <= BASE_DIT_TIME;
            dah_time        <= BASE_DAH_TIME;
            dit_gap         <= BASE_DIT_GAP;
            tone_freq       <= BASE_TONE_FREQ;
            settings_applied <= 1'b0;
        end else if (ui_active && btn12_pressed) begin
            long_key_cycles <= calc_long_key;
            dit_gap_cycles  <= calc_dit_gap;
            timeout_cycles  <= calc_timeout;
            space_cycles    <= calc_space;
            dit_time        <= calc_dit_time;
            dah_time        <= calc_dah_time;
            dit_gap         <= calc_dit_gap;
            tone_freq       <= BASE_TONE_FREQ;
            settings_applied <= 1'b1;
        end else begin
            settings_applied <= 1'b0;
        end
    end
    
    wire piezo_internal;
    
    EncoderPiezoPlayer #(
        .CLK_FREQ(CLK_HZ),
        .TONE_FREQ(BASE_TONE_FREQ)
    ) demo_player (
        .clk(clk),
        .rst_n(rst_n),
        .start(player_start),
        .bitstream(DEMO_BITSTREAM),
        .bit_length(DEMO_BIT_LENGTH),
        .DitTime(calc_dit_time),
        .DahTime(calc_dah_time),
        .DitGap(calc_dit_gap),
        .busy(player_busy),
        .done(player_done),
        .piezo_out(piezo_internal)
    );
    
    assign piezo_out = (ui_active && playback_enabled) ? piezo_internal : 1'b0;

endmodule
