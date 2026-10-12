// Unmodified upstream PicoRV32 with the SAME instruction ROM/data cache as the lab.
// This is a separate reference CPU, not an OoO conversion of PicoRV32's internals.
module picorv32_reference_system #(parameter ENABLE_MUL=0)(
    input wire clk,reset,run,
    input wire instr_we,data_we,input wire [7:0] host_addr,input wire [31:0] host_data,
    input wire [7:0] debug_addr,output wire [31:0] debug_data,
    output wire trapped,output reg [31:0] cycle_count,
    output wire [31:0] cache_hits,cache_misses
);
reg [31:0] imem[0:255];
always @(posedge clk) if(instr_we) imem[host_addr]<=host_data;
wire mv,mi,ready;wire [31:0] ma,md,mrd;wire [3:0] ms;
wire cr,cv,cf;wire [31:0] cd;reg pending;
wire request=mv && !mi && !pending;
wire [31:0] instruction=(ma<1024 && ma[1:0]==0)?imem[ma[9:2]]:0;
assign ready=mi?mv:((ms!=0)?(mv && !pending && cr):(pending && cv));
assign mrd=mi?instruction:cd;
always @(posedge clk) begin
    if(reset) begin pending<=0;cycle_count<=0;end
    else begin
        if(run && !trapped) cycle_count<=cycle_count+1;
        if(request && cr && ms==0) pending<=1;
        if(pending && cv) pending<=0;
    end
end
picorv32 #(.ENABLE_COUNTERS(0),.ENABLE_COUNTERS64(0),.ENABLE_REGS_16_31(1),
    .ENABLE_REGS_DUALPORT(1),.BARREL_SHIFTER(1),.COMPRESSED_ISA(0),
    .ENABLE_FAST_MUL(ENABLE_MUL),.ENABLE_DIV(0),.REGS_INIT_ZERO(1)) cpu(
    .clk(clk),.resetn(!reset && run),.trap(trapped),
    .mem_valid(mv),.mem_instr(mi),.mem_ready(ready),.mem_addr(ma),.mem_wdata(md),.mem_wstrb(ms),.mem_rdata(mrd),
    .pcpi_wr(1'b0),.pcpi_rd(32'b0),.pcpi_wait(1'b0),.pcpi_ready(1'b0),.irq(32'b0)
);
data_cache memory(.clk(clk),.reset(reset),.host_we(data_we),.host_addr(host_addr),.host_data(host_data),
    .req_valid(request),.req_write(ms!=0),.req_addr(ma),.req_data(md),.req_wstrb(ms),.req_ready(cr),
    .resp_valid(cv),.resp_fault(cf),.resp_data(cd),.debug_addr(debug_addr),.debug_data(debug_data),
    .hit_count(cache_hits),.miss_count(cache_misses));
endmodule
