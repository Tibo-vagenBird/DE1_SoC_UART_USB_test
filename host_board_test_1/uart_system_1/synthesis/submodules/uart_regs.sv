// uart_regs.sv : Avalon-MM slave "soft UART endpoint" for HPS bridge.
// No physical UART pins. HPS writes bytes into TX_DATA; on newline, the
// module echoes the complete line to an output FIFO, readable at RX_DATA.

module uart_regs #(
    parameter int DATA_WIDTH = 8,
    parameter int LINE_DEPTH = 256,  // max chars per line
    parameter int FIFO_DEPTH = 512   // output fifo depth
)(
    input  logic         clk,
    input  logic         reset_n,

    // Avalon-MM slave
    input  logic  [3:0]  address,      // we’ll use address[3:2] for 16B window
    input  logic         read,
    output logic [31:0]  readdata,
    input  logic         write,
    input  logic [31:0]  writedata,
    input  logic  [3:0]  byteenable,   // ignored, expect 0xF
    output logic         waitrequest   // always 0
);

    assign waitrequest = 1'b0;

    // Registers (word offsets):
    // 0x00 STATUS [bit0]=rx_ready (out_fifo not empty)
    // 0x04 RX_DATA (read pops one byte)
    // 0x08 TX_DATA (write pushes one byte)
    // 0x0C CTRL    [bit0]=clr_out_fifo (self-clear)

    logic rx_ready;            // out_fifo not empty
    logic clr_out_fifo_req;

    // --------------------------
    // Line buffer (accumulate until CR or LF)
    // --------------------------
    logic [7:0] line_mem [0:LINE_DEPTH-1];
    logic [$clog2(LINE_DEPTH):0] line_len;

    // --------------------------
    // Output FIFO (for echoed line)
    // --------------------------
    logic [7:0] fifo_mem [0:FIFO_DEPTH-1];
    logic [$clog2(FIFO_DEPTH):0] fifo_wr, fifo_rd;
    logic [$clog2(FIFO_DEPTH):0] fifo_count;

    wire fifo_empty = (fifo_count == 0);
    wire fifo_full  = (fifo_count == FIFO_DEPTH);
    assign rx_ready = !fifo_empty;

    // push to FIFO
    task automatic fifo_push(input logic [7:0] b);
    begin
        if (!fifo_full) begin
            fifo_mem[fifo_wr] <= b;
            fifo_wr           <= fifo_wr + 1'b1;
            fifo_count        <= fifo_count + 1'b1;
        end
    end
    endtask

    // pop from FIFO
    function automatic logic [7:0] fifo_pop();
        fifo_pop = fifo_mem[fifo_rd];
    endfunction

    // address decode (use word address)
    wire [1:0] waddr = address[3:2];

    // Read path
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            readdata <= 32'h0;
        end else if (read) begin
            unique case (waddr)
            2'b00: readdata <= {31'b0, rx_ready};  // STATUS
            2'b01: begin                           // RX_DATA (pop)
                logic [7:0] b;
                if (!fifo_empty) begin
                    b         = fifo_pop();
                    readdata  <= {24'h0, b};
                end else begin
                    readdata  <= 32'hFFFF_FFFF; // empty mark
                end
            end
            2'b10: readdata <= 32'h0;           // TX_DATA (writes only)
            2'b11: readdata <= 32'h0;           // CTRL
            endcase
        end
    end

    // Write path
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            line_len        <= '0;
            fifo_wr         <= '0;
            fifo_rd         <= '0;
            fifo_count      <= '0;
            clr_out_fifo_req<= 1'b0;
        end else begin
            clr_out_fifo_req <= 1'b0;

            if (write) begin
                unique case (waddr)
                2'b10: begin // TX_DATA -> incoming byte from HPS
                    logic [7:0] ch = writedata[7:0];
                    if (ch == 8'h0A || ch == 8'h0D) begin
                        // newline => copy the line buffer into out FIFO + newline
                        automatic int i;
                        for (i = 0; i < line_len; i++) begin
                            fifo_push(line_mem[i]);
                        end
                        // add '\n' to the echoed line for clarity
                        fifo_push(8'h0A);
                        line_len <= '0;
                    end else begin
                        if (line_len < LINE_DEPTH) begin
                            line_mem[line_len] <= ch;
                            line_len           <= line_len + 1'b1;
                        end
                        // else: silently truncate (could add overflow flag)
                    end
                end
                2'b11: begin // CTRL
                    if (writedata[0]) clr_out_fifo_req <= 1'b1; // clr_out_fifo
                end
                default: ; // STATUS/RX_DATA are read-only
                endcase
            end

            // Clear out FIFO if requested
            if (clr_out_fifo_req) begin
                fifo_wr    <= '0;
                fifo_rd    <= '0;
                fifo_count <= '0;
            end
        end
    end

    // Pop on read of RX_DATA (only when read asserted and not empty)
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // already cleared above
        end else if (read && waddr==2'b01 && !fifo_empty) begin
            fifo_rd    <= fifo_rd + 1'b1;
            fifo_count <= fifo_count - 1'b1;
        end
    end

endmodule
