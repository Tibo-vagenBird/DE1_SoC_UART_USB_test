module uart_rx
#(
	parameter CLK_FRE = 50,
	parameter DATA_WIDTH = 8,
	parameter PARITY_ON = 1,
	parameter PARITY_TYPE = 0,
	parameter BAUD_RATE = 57600
)

(
	input logic i_clk_sys,
	input logic i_rst_n,
	input logic i_uart_rx,
	output logic [DATA_WIDTH-1:0] o_uart_data,
	output logic o_led_parity,
	output logic o_rx_done
);
	
	logic sync_uart_rx;
	
	// 将uart输入同步到fpga内部的时钟域
	always_ff @(posedge i_clk_sys) begin 
		if (!i_rst_n) 
			sync_uart_rx <= 1'b1;
		else 
			sync_uart_rx <= i_uart_rx;
	end
	
	// 1 to 2的信号， 拿5个输入，减少噪音影响
	logic [4:0] r_flag_rcv_start;
	always_ff @(posedge i_clk_sys) begin 
		if (!i_rst_n) 
			r_flag_rcv_start <= 5'b11111;
		else
			r_flag_rcv_start <= {r_flag_rcv_start[3:0], sync_uart_rx};	
	end
	
	wire w_rcv_start = (r_flag_rcv_start[4:3] == 2'b10);
	
	// 一个symbol的传输要CYCLE这么多的clk脉冲
	localparam CYCLE = CLK_FRE * 1000000 / BAUD_RATE;
	
	logic baud_valid;
	logic [15:0] clk_cnt; // clk pulse counting to 1 bp 
	logic baud_pulse;
	
	logic [3:0] r_rcv_cnt;
	
	always_ff @(posedge i_clk_sys) begin
		if (!i_rst_n) 
			clk_cnt <= 16'h0000;
		else if (!baud_valid) 
			clk_cnt <= 16'h0000;
		else if (clk_cnt == CYCLE-1)
			clk_cnt <= 16'h0000;
		else 
			clk_cnt <= clk_cnt + 1'b1;
	end
	
	always_ff @(posedge i_clk_sys) begin 
		if (!i_rst_n) 
			baud_pulse <= 1'b0;
		else if (clk_cnt == CYCLE/2-1)
			baud_pulse <= 1'b1;
		else 
			baud_pulse <= 1'b0;
	end
	
	// 状态机设置
	typedef enum logic [2:0]{
		s_IDLE,
		s_START,
		s_DATA,
		s_PARITY,
		s_END
	} states_t;
	
	states_t r_present_state, r_next_state;
	
	always_ff @(posedge i_clk_sys) begin 
		if (!i_rst_n)
			r_present_state <= s_IDLE;
		else if (!baud_valid)
			r_present_state <= s_IDLE;
		else 
			r_present_state <= r_next_state;
	end
	
	always_ff @(posedge i_clk_sys) begin
		begin
			case(r_present_state)
				s_IDLE:
					r_next_state <= s_START;
				s_START:
					r_next_state <= s_DATA;
				s_DATA: begin
					if (r_rcv_cnt == DATA_WIDTH) begin
						if (PARITY_ON == 1) 
							r_next_state <= s_PARITY;
						else 
							r_next_state <= s_END;
					end 
					else begin
						r_next_state <= s_DATA;
					end
				end
				s_PARITY:
					r_next_state <= s_END;
				s_END:
					r_next_state <= s_IDLE;
			endcase
		end
	end
	
	logic [DATA_WIDTH-1:0] r_data_rcv;
	logic r_parity_check;
	
	always_ff @(posedge i_clk_sys) begin 
		if (!i_rst_n) begin 
			baud_valid <= 1'b0;
			r_data_rcv <= 'd0;
			r_rcv_cnt <= 4'd0;
			r_parity_check <= 1'b0;
			o_uart_data <= 'd0;
			o_led_parity <= 1'b0;
			o_rx_done <= 1'b0;
		end
		
		case (r_present_state)
			s_IDLE: begin 
				r_data_rcv <= 'd0;
				r_rcv_cnt <= 4'd0;
				r_parity_check <= 1'b0;
				o_rx_done <= 1'b0;
				
				if (w_rcv_start) 
					baud_valid <= 1'b1;
				else 
					baud_valid <= 1'b0;
					
			end
			
			s_START: begin
				if (baud_pulse) begin
					if (sync_uart_rx) baud_valid <= 1'b0;
				end
			end
			
			s_DATA:begin
				if (baud_pulse) begin 
					r_data_rcv <= {sync_uart_rx, r_data_rcv[DATA_WIDTH-1:1]};
					r_rcv_cnt <= r_rcv_cnt + 1'b1;
					r_parity_check <= r_parity_check + sync_uart_rx;
				end
			end

			s_PARITY: begin
				if(baud_pulse) begin 
					if (r_parity_check + sync_uart_rx == PARITY_TYPE) 
						o_led_parity <= 1'b1;
					else 
						o_led_parity <= 1'b0;
				end
				else 
					o_led_parity <= o_led_parity;
			end 
			
			s_END: begin
				if (baud_pulse) begin
					if(PARITY_ON == 0| o_led_parity) begin 
						o_uart_data <= r_data_rcv;
						o_rx_done <= 1'b1;
					end
				end
				else 
					o_rx_done <= 1'b0;
					
				if (clk_cnt == 16'h0000)
					baud_valid <= 1'b0;
			end
		
		endcase
	end
	
endmodule


	
	