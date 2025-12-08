`timescale 1ns / 1ps

module tb_MorseSystem_Fast;

    // 클럭 & 리셋
    reg clk;
    reg rst_n;
    
    // 입력 신호들 - 초기값 명시!
    reg [4:0] btn = 5'b00000;           // ← 초기값 추가
    reg [2:0] speed_sel = 3'b000;       // ← 초기값 추가
    reg is_active = 1'b0;               // ← 초기값 추가
    
    // 출력 신호들
    wire [9:0] led;
    wire [2:0] rgb_r, rgb_g, rgb_b;
    wire piezo;
    wire servo;
    wire lcd_e, lcd_rs, lcd_rw;
    wire [7:0] lcd_data;

    // DUT 인스턴스
    MorseSystemTop #(
        .CLK_HZ(100_000_000)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .btn(btn),
        .speed_sel(speed_sel),
        .is_active(is_active),
        .led(led),
        .rgb_r(rgb_r),
        .rgb_g(rgb_g),
        .rgb_b(rgb_b),
        .piezo(piezo),
        .servo(servo),
        .lcd_e(lcd_e),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_data(lcd_data)
    );

    // 클럭 생성 (100MHz = 10ns)
    initial begin
        clk = 0;  // ← 명시적 초기화
        forever #5 clk = ~clk;
    end

    // 리셋 시퀀스 강화
    initial begin
        // 초기 상태
        rst_n = 0;
        btn = 5'b00000;
        speed_sel = 3'b000;
        is_active = 0;
        
        // 충분한 리셋 시간
        #200;
        
        // 리셋 해제
        rst_n = 1;
        #100;
        
        // 시스템 활성화
        is_active = 1;
        #100;
        
        $display("=== Initialization Complete ===");
        $display("Time: %0t", $time);
        $display("rst_n: %b", rst_n);
        $display("is_active: %b", is_active);
        $display("LED: %b", led);
        
        // 간단한 테스트
        $display("\n=== Button Test ===");
        btn = 5'b00001;
        #100;
        btn = 5'b00000;
        #100;
        
        $display("Test complete!");
        $finish;
    end

    // 타임아웃
    initial begin
        #10000;
        $display("Timeout!");
        $finish;
    end

    // 신호 모니터링
    initial begin
        $monitor("Time=%0t rst_n=%b btn=%b led=%b", 
                 $time, rst_n, btn, led);
    end

endmodule