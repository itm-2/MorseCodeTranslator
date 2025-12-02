module lcd_pos_control (
    input wire clk,           // 50MHz System Clock
    input wire rst_n,         // Active Low Reset
    
    // --- 사용자 입력 인터페이스 ---
    input wire start_btn,     // 1이 되면 동작 시작 (버튼 연결)
    input wire [3:0] in_col,  // 가로 좌표 (0 ~ 15) -> 스위치 연결
    input wire [0:0] in_row,  // 세로 좌표 (0: 윗줄, 1: 아랫줄) -> 스위치 연결
    
    // --- LCD 하드웨어 핀 ---
    output reg lcd_rs,
    output reg lcd_rw,
    output reg lcd_e,
    output reg [7:0] lcd_data
);

    // -------------------------------------------------------------------------
    // 파라미터 및 상수 정의 (50MHz 클럭 기준)
    // -------------------------------------------------------------------------
    parameter CLK_FREQ = 50_000_000;
    
    // 타이밍 상수
    localparam CNT_15MS  = 750_000; 
    localparam CNT_5MS   = 250_000; 
    localparam CNT_100US = 5_000;   
    localparam CNT_CMD   = 2_500;   // 50us (명령어 실행 시간)
    localparam CNT_CLR   = 100_000; // 2ms (Clear 명령어 실행 시간)

    // 명령어 정의
    localparam CMD_WAKEUP     = 8'h30;
    localparam CMD_FUNC_SET   = 8'h38; // 8-bit, 2-line, 5x8 font
    localparam CMD_DISP_OFF   = 8'h08; 
    localparam CMD_DISP_CLEAR = 8'h01; 
    localparam CMD_ENTRY_MODE = 8'h06; // Auto Increment
    localparam CMD_DISP_ON    = 8'h0C; // Display On, Cursor Off

    // 상태 머신 정의
    localparam S_PWR_WAIT   = 0;
    localparam S_INIT_1     = 1;
    localparam S_INIT_2     = 2;
    localparam S_INIT_3     = 3;
    localparam S_FUNC_SET   = 4;
    localparam S_DISP_OFF   = 5;
    localparam S_DISP_CLR   = 6;
    localparam S_ENTRY_MODE = 7;
    localparam S_DISP_ON    = 8;
    localparam S_IDLE       = 9;  // 입력 대기 상태
    localparam S_SET_ADDR   = 10; // 좌표 설정
    localparam S_WRITE_DATA = 11; // "HELLO WORLD" 출력
    localparam S_DONE_WAIT  = 12; // 버튼 뗄 때까지 대기 (중복 방지)

    reg [4:0] state;
    reg [31:0] wait_cnt;
    reg [3:0] char_idx; 

    // 출력할 메시지 저장 ("HELLO WORLD" - 11글자)
    reg [7:0] message [0:10];
    
    // 좌표 계산용 변수
    reg [6:0] target_addr;

    initial begin
        message[0] = "H"; message[1] = "E"; message[2] = "L"; message[3] = "L";
        message[4] = "O"; message[5] = " "; message[6] = "W"; message[7] = "O";
        message[8] = "R"; message[9] = "L"; message[10] = "D";
    end

    // -------------------------------------------------------------------------
    // 동작 로직
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_PWR_WAIT;
            wait_cnt <= 0;
            char_idx <= 0;
            lcd_e <= 0; lcd_rs <= 0; lcd_rw <= 0; lcd_data <= 0;
        end else begin
            case (state)
                // ============================================================
                // 1. 초기화 시퀀스 (전원 켜질 때 자동 실행)
                // ============================================================
                S_PWR_WAIT: begin
                    if (wait_cnt >= CNT_15MS) begin wait_cnt <= 0; state <= S_INIT_1; end
                    else wait_cnt <= wait_cnt + 1;
                end

                S_INIT_1: begin // 0x30
                    lcd_rs <= 0; lcd_rw <= 0; lcd_data <= CMD_WAKEUP;
                    if (wait_cnt == 2) lcd_e <= 1; else if (wait_cnt == 22) lcd_e <= 0; // Timing Fix
                    if (wait_cnt >= (CNT_5MS + 22)) begin wait_cnt <= 0; state <= S_INIT_2; end
                    else wait_cnt <= wait_cnt + 1;
                end

                S_INIT_2: begin // 0x30
                    lcd_rs <= 0; lcd_rw <= 0; lcd_data <= CMD_WAKEUP;
                    if (wait_cnt == 2) lcd_e <= 1; else if (wait_cnt == 22) lcd_e <= 0;
                    if (wait_cnt >= (CNT_100US + 22)) begin wait_cnt <= 0; state <= S_INIT_3; end
                    else wait_cnt <= wait_cnt + 1;
                end

                S_INIT_3: begin // 0x30
                    lcd_rs <= 0; lcd_rw <= 0; lcd_data <= CMD_WAKEUP;
                    if (wait_cnt == 2) lcd_e <= 1; else if (wait_cnt == 22) lcd_e <= 0;
                    if (wait_cnt >= (CNT_CMD + 22)) begin wait_cnt <= 0; state <= S_FUNC_SET; end
                    else wait_cnt <= wait_cnt + 1;
                end

                S_FUNC_SET: begin // 0x38
                    lcd_rs <= 0; lcd_rw <= 0; lcd_data <= CMD_FUNC_SET;
                    if (wait_cnt == 2) lcd_e <= 1; else if (wait_cnt == 22) lcd_e <= 0;
                    if (wait_cnt >= (CNT_CMD + 22)) begin wait_cnt <= 0; state <= S_DISP_OFF; end
                    else wait_cnt <= wait_cnt + 1;
                end

                S_DISP_OFF: begin // 0x08
                    lcd_rs <= 0; lcd_rw <= 0; lcd_data <= CMD_DISP_OFF;
                    if (wait_cnt == 2) lcd_e <= 1; else if (wait_cnt == 22) lcd_e <= 0;
                    if (wait_cnt >= (CNT_CMD + 22)) begin wait_cnt <= 0; state <= S_DISP_CLR; end
                    else wait_cnt <= wait_cnt + 1;
                end

                S_DISP_CLR: begin // 0x01
                    lcd_rs <= 0; lcd_rw <= 0; lcd_data <= CMD_DISP_CLEAR;
                    if (wait_cnt == 2) lcd_e <= 1; else if (wait_cnt == 22) lcd_e <= 0;
                    if (wait_cnt >= (CNT_CLR + 22)) begin wait_cnt <= 0; state <= S_ENTRY_MODE; end
                    else wait_cnt <= wait_cnt + 1;
                end

                S_ENTRY_MODE: begin // 0x06
                    lcd_rs <= 0; lcd_rw <= 0; lcd_data <= CMD_ENTRY_MODE;
                    if (wait_cnt == 2) lcd_e <= 1; else if (wait_cnt == 22) lcd_e <= 0;
                    if (wait_cnt >= (CNT_CMD + 22)) begin wait_cnt <= 0; state <= S_DISP_ON; end
                    else wait_cnt <= wait_cnt + 1;
                end

                S_DISP_ON: begin // 0x0C
                    lcd_rs <= 0; lcd_rw <= 0; lcd_data <= CMD_DISP_ON;
                    if (wait_cnt == 2) lcd_e <= 1; else if (wait_cnt == 22) lcd_e <= 0;
                    if (wait_cnt >= (CNT_CMD + 22)) begin wait_cnt <= 0; state <= S_IDLE; end
                    else wait_cnt <= wait_cnt + 1;
                end

                // ============================================================
                // 2. 대기 및 사용자 입력 처리
                // ============================================================
                S_IDLE: begin
                    lcd_e <= 0;
                    wait_cnt <= 0;
                    
                    // 버튼이 눌리면 좌표 계산 후 이동 시작
                    if (start_btn == 1'b1) begin
                        // [좌표 계산 로직]
                        // Row 0: 0x00 ~ 0x0F
                        // Row 1: 0x40 ~ 0x4F
                        if (in_row == 1'b0) target_addr <= {3'b000, in_col}; // 0x00 + col
                        else                target_addr <= {3'b100, in_col}; // 0x40 + col
                        
                        state <= S_SET_ADDR;
                    end
                end

                // 3. 커서 위치 설정 (Set DDRAM Address)
                S_SET_ADDR: begin
                    lcd_rs <= 0; lcd_rw <= 0;
                    lcd_data <= {1'b1, target_addr}; // Command: 0x80 | Address

                    if (wait_cnt == 2) lcd_e <= 1; else if (wait_cnt == 22) lcd_e <= 0;

                    if (wait_cnt >= (CNT_CMD + 22)) begin
                        wait_cnt <= 0;
                        char_idx <= 0;
                        state <= S_WRITE_DATA;
                    end else wait_cnt <= wait_cnt + 1;
                end

                // 4. "HELLO WORLD" 출력 루프
                S_WRITE_DATA: begin
                    lcd_rs <= 1; // Data 모드
                    lcd_rw <= 0;
                    lcd_data <= message[char_idx];

                    if (wait_cnt == 2) lcd_e <= 1; else if (wait_cnt == 22) lcd_e <= 0;

                    if (wait_cnt >= (CNT_CMD + 22)) begin
                        wait_cnt <= 0;
                        // 11글자 (0~10) 다 썼으면 종료
                        if (char_idx == 10) state <= S_DONE_WAIT;
                        else char_idx <= char_idx + 1;
                    end else wait_cnt <= wait_cnt + 1;
                end

                // 5. 버튼 뗄 때까지 대기 (중복 실행 방지)
                S_DONE_WAIT: begin
                    lcd_e <= 0;
                    if (start_btn == 1'b0) begin
                        state <= S_IDLE; // 버튼을 떼면 다시 입력 대기 상태로
                    end
                end

                default: state <= S_PWR_WAIT;
            endcase
        end
    end

endmodule