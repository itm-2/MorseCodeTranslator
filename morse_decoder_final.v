module morse_decoder_final (
    input wire clk,           // 50MHz System Clock
    input wire rst_n,         // Active Low Reset
    
    // --- Input Keys ---
    input wire btn_key,       // 모스 부호 입력 키 (Morse Input)
    input wire btn_enter,     // 결과 확인 / 모드 전환
    input wire btn_back,      // 뒤로 가기
    input wire btn_up,        // 페이지 업 (Result 화면용)
    input wire btn_down,      // 페이지 다운 (Result 화면용)

    // --- Output ---
    output reg [3:0] led,     // LED 출력 (WarnInvalid, KeyFeedback)
    
    // --- LCD Interface ---
    output wire lcd_rs,
    output wire lcd_rw,
    output wire lcd_e,
    output wire [7:0] lcd_data
);

    // =========================================================================
    // 1. 파라미터 및 상수 정의 (UserSetting 반영)
    // =========================================================================
    parameter CLK_FREQ = 50_000_000;
    
    // KeyMapping & Action Settings
    // 1ms = 50,000 clk
    localparam THRESHOLD_DIT_DAH = 10_000_000; // 200ms (이하: Dit, 초과: Dah)
    localparam THRESHOLD_GAP     = 25_000_000; // 500ms (문자 구분 Space 판정)
    
    // UI 상태 정의 (UUID 개념 대체)
    localparam S_INTRO      = 0; // "ENTER THE CODE..."
    localparam S_DECODE     = 1; // 실시간 입력 및 해독
    localparam S_RESULT     = 2; // 전체 결과 조회 (Paging)
    
    // =========================================================================
    // 2. 내부 변수 및 레지스터
    // =========================================================================
    reg [2:0]  ui_state;      // 현재 UI 상태
    
    // 타이머 및 키 처리
    reg [31:0] timer_press;   // KeyAction: 누름 시간
    reg [31:0] timer_gap;     // KeyAction: 뗌 시간 (AutoDitGap)
    reg key_prev;             // Edge Detection용
    
    // 모스 부호 누적 버퍼 (IBuffer 역할)
    // 최대 6개의 신호 (숫자/특수문자 포함) 저장. 0:Dit, 1:Dah
    reg [5:0] pattern_reg;    
    reg [2:0] pattern_len;    
    
    // 텍스트 버퍼 (Buffer 역할) - 최대 128글자 저장
    reg [7:0] text_buffer [0:127]; 
    reg [6:0] buf_head;       // 현재 쓰기 위치
    reg [6:0] page_idx;       // 결과 화면 페이징 인덱스

    // LCD 표시용 라인 버퍼
    reg [127:0] lcd_line1;
    reg [127:0] lcd_line2;

    // WarnInvalid (LED 제어)
    reg [31:0] warn_timer;
    reg is_warning;

    // 버튼 Debounce 및 One-shot 처리를 위한 레지스터
    reg btn_enter_prev, btn_back_prev, btn_up_prev, btn_down_prev;
    
    // =========================================================================
    // 3. 메인 로직 (Always Block)
    // =========================================================================
    
    // Translator Function (조합 논리)
    function [7:0] translate_morse;
        input [2:0] len;
        input [5:0] pat; // LSB가 첫 입력 (Shift됨)
        begin
            case ({len, pat})
                // Length 1
                {3'd1, 6'b00000_0}: translate_morse = "E"; // .
                {3'd1, 6'b00000_1}: translate_morse = "T"; // -
                // Length 2
                {3'd2, 6'b0000_01}: translate_morse = "A"; // .-
                {3'd2, 6'b0000_10}: translate_morse = "N"; // -.
                {3'd2, 6'b0000_00}: translate_morse = "I"; // ..
                {3'd2, 6'b0000_11}: translate_morse = "M"; // --
                // Length 3
                {3'd3, 6'b000_000}: translate_morse = "S"; // ...
                {3'd3, 6'b000_111}: translate_morse = "O"; // ---
                {3'd3, 6'b000_010}: translate_morse = "R"; // .-.
                {3'd3, 6'b000_100}: translate_morse = "D"; // -..
                {3'd3, 6'b000_101}: translate_morse = "K"; // -.-
                {3'd3, 6'b000_110}: translate_morse = "G"; // --.
                {3'd3, 6'b000_001}: translate_morse = "U"; // ..-
                {3'd3, 6'b000_011}: translate_morse = "W"; // .--
                // Length 4 (예시 일부)
                {3'd4, 6'b00_0000}: translate_morse = "H"; // ....
                {3'd4, 6'b00_1010}: translate_morse = "C"; // -.-.
                {3'd4, 6'b00_0111}: translate_morse = "J"; // .---
                {3'd4, 6'b00_1101}: translate_morse = "Q"; // --.-
                {3'd4, 6'b00_1011}: translate_morse = "Y"; // -.--
                {3'd4, 6'b00_0001}: translate_morse = "V"; // ...-
                {3'd4, 6'b00_1000}: translate_morse = "B"; // -...
                {3'd4, 6'b00_0100}: translate_morse = "L"; // .-..
                {3'd4, 6'b00_0010}: translate_morse = "F"; // ..-.
                {3'd4, 6'b00_0101}: translate_morse = "+"; // .-.- (AR)
                default: translate_morse = 0; // Invalid
            endcase
        end
    endfunction

    reg [7:0] decoded_char; // 번역 결과 임시 저장

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ui_state <= S_INTRO;
            timer_press <= 0; timer_gap <= 0;
            key_prev <= 0;
            pattern_reg <= 0; pattern_len <= 0;
            buf_head <= 0; page_idx <= 0;
            is_warning <= 0; warn_timer <= 0;
            // 버퍼 초기화 (합성 시엔 무시될 수 있음, 동작상 덮어쓰기 하므로 무관)
            for(i=0; i<128; i=i+1) text_buffer[i] <= " "; 
        end else begin
            // Edge Detection
            btn_enter_prev <= btn_enter;
            btn_back_prev <= btn_back;
            btn_up_prev <= btn_up;
            btn_down_prev <= btn_down;
            key_prev <= btn_key;

            // --- WarnInvalid Timer ---
            if (is_warning) begin
                if (warn_timer > 0) warn_timer <= warn_timer - 1;
                else is_warning <= 0;
            end

            // --- UI State Machine ---
            case (ui_state)
                // ------------------------------------------------------------
                // [화면 0] 초기 화면: "ENTER THE CODE..."
                // ------------------------------------------------------------
                S_INTRO: begin
                    if (btn_key || (btn_enter && !btn_enter_prev)) begin
                        // 아무 키나 누르면 디코딩 화면으로 전환
                        ui_state <= S_DECODE;
                        buf_head <= 0;
                        pattern_len <= 0;
                        pattern_reg <= 0;
                        // 버퍼 Clear
                        for(i=0; i<128; i=i+1) text_buffer[i] <= " ";
                    end
                end

                // ------------------------------------------------------------
                // [화면 1] Decoding: 실시간 입력 및 해독
                // ------------------------------------------------------------
                S_DECODE: begin
                    // 1. KeyAction Logic (Dit/Dah Detection)
                    if (btn_key) begin // 누르고 있을 때
                        timer_press <= timer_press + 1;
                        timer_gap <= 0; // 갭 타이머 리셋
                    end else begin // 떼고 있을 때
                        // Falling Edge 감지 (버튼 뗀 순간)
                        if (key_prev == 1'b1) begin
                            if (timer_press > THRESHOLD_DIT_DAH) begin
                                // Dah (10 -> 1로 저장)
                                pattern_reg <= {pattern_reg[4:0], 1'b1}; 
                            end else begin
                                // Dit (01 -> 0으로 저장)
                                pattern_reg <= {pattern_reg[4:0], 1'b0};
                            end
                            pattern_len <= pattern_len + 1;
                            timer_press <= 0;
                        end

                        // Gap Detection (Space 판정)
                        if (pattern_len > 0) begin
                            timer_gap <= timer_gap + 1;
                            
                            // UserSetting의 DitGap만큼 대기 후 판정
                            if (timer_gap > THRESHOLD_GAP) begin
                                // Translator 호출
                                decoded_char = translate_morse(pattern_len, pattern_reg);
                                
                                if (decoded_char != 0) begin
                                    // 유효한 문자 -> Buffer Push
                                    text_buffer[buf_head] <= decoded_char;
                                    buf_head <= buf_head + 1;
                                end else begin
                                    // Invalid (0 반환됨) -> warnInvalid
                                    is_warning <= 1;
                                    warn_timer <= CLK_FREQ / 2; // 0.5초
                                end
                                
                                // 모스 버퍼 초기화
                                pattern_reg <= 0;
                                pattern_len <= 0;
                                timer_gap <= 0;
                            end
                        end
                    end

                    // 2. Navigation
                    if (btn_enter && !btn_enter_prev) begin
                        ui_state <= S_RESULT;
                        page_idx <= 0; // 첫 페이지부터
                    end
                    if (btn_back && !btn_back_prev) begin
                        ui_state <= S_INTRO;
                    end
                end

                // ------------------------------------------------------------
                // [화면 2] Result: 전체 결과 확인 (Paging)
                // ------------------------------------------------------------
                S_RESULT: begin
                    // Navigation
                    if (btn_enter && !btn_enter_prev) begin
                        ui_state <= S_DECODE; // 다시 디코딩 화면으로
                    end
                    if (btn_back && !btn_back_prev) begin
                        ui_state <= S_DECODE; // 이전 화면으로
                    end

                    // Paging (UP/DOWN) - 15글자 단위
                    if (btn_down && !btn_down_prev) begin
                        if (page_idx + 15 < buf_head) 
                            page_idx <= page_idx + 15;
                    end
                    if (btn_up && !btn_up_prev) begin
                        if (page_idx >= 15)
                            page_idx <= page_idx - 15;
                        else
                            page_idx <= 0;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // 4. Output Logic (LED & LCD)
    // =========================================================================

    // LED: printLED (KeyMap) + warnInvalid
    always @(*) begin
        if (is_warning) begin
            led = 4'b1111; // 경고 시 전체 점멸
        end else begin
            // printLED: 사용 가능한 버튼 매칭
            // 예: Intro에선 Enter만, Decode에선 Key/Enter/Back 등
            case (ui_state)
                S_INTRO:  led = {btn_key, 3'b000}; 
                S_DECODE: led = {btn_key, 1'b0, 1'b0, 1'b0}; // 입력 시 반응
                S_RESULT: led = 4'b0000; // 결과 화면에선 소등
                default:  led = 4'b0000;
            endcase
        end
    end

    // LCD Buffer Mapping (showUI)
    always @(*) begin
        // 기본값 공백 채움
        lcd_line1 = {16{8'h20}};
        lcd_line2 = {16{8'h20}};

        case (ui_state)
            S_INTRO: begin
                lcd_line1 = "ENTER THE CODE.."; // 중앙 정렬 느낌
                lcd_line2 = "PRESS ANY KEY   ";
            end

            S_DECODE: begin
                // Row 1: 현재까지 입력된 텍스트의 끝부분 (최근 16자)
                // 15글자 이하일 땐 0부터, 넘어가면 스크롤
                for (i=0; i<16; i=i+1) begin
                    if (buf_head < 16) begin
                        if (i < buf_head) lcd_line1[127 - i*8 -: 8] = text_buffer[i];
                    end else begin
                        // 마지막 16글자 보여주기
                        lcd_line1[127 - i*8 -: 8] = text_buffer[buf_head - 16 + i];
                    end
                end

                // Row 2: 현재 입력 중인 모스 부호 패턴 (.-...)
                for (i=0; i<6; i=i+1) begin
                    if (i < pattern_len) begin
                        // LSB부터 입력되었으므로 순서 주의 (여기선 편의상 0부터 출력)
                        if (pattern_reg[pattern_len - 1 - i] == 1) 
                             lcd_line2[127 - i*8 -: 8] = "-"; // Dah
                        else lcd_line2[127 - i*8 -: 8] = "."; // Dit
                    end
                end
            end

            S_RESULT: begin
                // Row 1: page_idx 부터 15글자
                // Row 2: page_idx+15 부터 15글자 (prompt: "Buffer는 page 단위(15글자)")
                for (i=0; i<16; i=i+1) begin
                    // Line 1
                    if (page_idx + i < 128)
                        lcd_line1[127 - i*8 -: 8] = text_buffer[page_idx + i];
                    
                    // Line 2 (다음 페이지 미리보기 느낌 혹은 연속 출력)
                    if (page_idx + 15 + i < 128)
                        lcd_line2[127 - i*8 -: 8] = text_buffer[page_idx + 15 + i];
                end
            end
        endcase
    end

    // LCD Driver 인스턴스
    lcd_driver_ctrl u_lcd (
        .clk(clk),
        .rst_n(rst_n),
        .line1(lcd_line1),
        .line2(lcd_line2),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_e(lcd_e),
        .lcd_data(lcd_data)
    );

endmodule


// =============================================================================
// LCD Driver Module (업데이트된 데이터 지속 출력)
// =============================================================================
module lcd_driver_ctrl (
    input wire clk,
    input wire rst_n,
    input wire [127:0] line1,
    input wire [127:0] line2,
    output reg lcd_rs,
    output reg lcd_rw,
    output reg lcd_e,
    output reg [7:0] lcd_data
);
    // 타이밍 파라미터 (50MHz)
    localparam CNT_CMD = 2_500;   
    localparam CNT_INIT_WAIT = 2_000_000; // 40ms

    reg [3:0] state;
    reg [31:0] cnt;
    reg [3:0] char_idx; 
    reg line_sel;       

    localparam S_INIT_PWR  = 0;
    localparam S_FUNC_SET  = 1;
    localparam S_DISP_ON   = 2;
    localparam S_CLR       = 3;
    localparam S_MODE      = 4;
    localparam S_ADDR      = 5;
    localparam S_WRITE     = 6;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_INIT_PWR;
            cnt <= 0; char_idx <= 0; line_sel <= 0;
            lcd_e <= 0; lcd_rs <= 0; lcd_rw <= 0;
        end else begin
            case (state)
                S_INIT_PWR: begin // Power Wait
                    if (cnt > CNT_INIT_WAIT) begin cnt <= 0; state <= S_FUNC_SET; end
                    else cnt <= cnt + 1;
                end
                S_FUNC_SET: begin // 0x38
                    lcd_rs <= 0; lcd_rw <= 0; lcd_data <= 8'h38;
                    if (cnt == 2) lcd_e <= 1; else if (cnt == 22) lcd_e <= 0;
                    if (cnt > CNT_CMD + 22) begin cnt <= 0; state <= S_DISP_ON; end
                    else cnt <= cnt + 1;
                end
                S_DISP_ON: begin // 0x0C
                    lcd_rs <= 0; lcd_rw <= 0; lcd_data <= 8'h0C;
                    if (cnt == 2) lcd_e <= 1; else if (cnt == 22) lcd_e <= 0;
                    if (cnt > CNT_CMD + 22) begin cnt <= 0; state <= S_CLR; end
                    else cnt <= cnt + 1;
                end
                S_CLR: begin // 0x01
                    lcd_rs <= 0; lcd_rw <= 0; lcd_data <= 8'h01;
                    if (cnt == 2) lcd_e <= 1; else if (cnt == 22) lcd_e <= 0;
                    if (cnt > 100_000 + 22) begin cnt <= 0; state <= S_MODE; end // Clear is slow
                    else cnt <= cnt + 1;
                end
                S_MODE: begin // 0x06
                    lcd_rs <= 0; lcd_rw <= 0; lcd_data <= 8'h06;
                    if (cnt == 2) lcd_e <= 1; else if (cnt == 22) lcd_e <= 0;
                    if (cnt > CNT_CMD + 22) begin cnt <= 0; state <= S_ADDR; end
                    else cnt <= cnt + 1;
                end

                // --- Refresh Loop ---
                S_ADDR: begin
                    lcd_rs <= 0; lcd_rw <= 0;
                    if (line_sel == 0) lcd_data <= 8'h80 + char_idx; // Line 1
                    else               lcd_data <= 8'hC0 + char_idx; // Line 2

                    if (cnt == 2) lcd_e <= 1; else if (cnt == 22) lcd_e <= 0;
                    if (cnt > CNT_CMD + 22) begin cnt <= 0; state <= S_WRITE; end
                    else cnt <= cnt + 1;
                end
                S_WRITE: begin
                    lcd_rs <= 1; lcd_rw <= 0;
                    if (line_sel == 0) lcd_data <= line1[127 - char_idx*8 -: 8];
                    else               lcd_data <= line2[127 - char_idx*8 -: 8];

                    if (cnt == 2) lcd_e <= 1; else if (cnt == 22) lcd_e <= 0;
                    if (cnt > CNT_CMD + 22) begin 
                        cnt <= 0;
                        if (char_idx == 15) begin
                            char_idx <= 0;
                            line_sel <= ~line_sel; // 줄 바꿈
                        end else begin
                            char_idx <= char_idx + 1;
                        end
                        state <= S_ADDR;
                    end else cnt <= cnt + 1;
                end
            endcase
        end
    end
endmodule