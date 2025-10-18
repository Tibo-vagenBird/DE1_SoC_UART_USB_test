module top (
	input logic CLOCK_50,
	input logic [0:0] KEY,
	output logic [9:0] LEDR
);

	wire rst_n = KEY[0];

	uart_system u_sys (
		.clk (CLOCK_50),
		.reset_reset_n (rst_n)
	);

	assign LEDR[0] = 1'b1;

endmodule