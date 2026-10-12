// Load instruction/data RAM using host ports while reset is asserted.
// CPU PCs/data addresses are bytes. Host/debug memory addresses select 32-bit words.
module processor_system #(
    parameter OOO=1, RENAME=1, PREDICTOR=2, MEM_SPEC=0, REUSE=0, VALUE_PRED=0, ENABLE_MUL=0,
    parameter CACHE_ENABLE=1, HIT_LAT=2, MISS_LAT=12
)(
    input wire clk,reset,run,
    input wire instr_we,data_we,
    input wire [7:0] host_addr,
    input wire [31:0] host_data,
    input wire [4:0] debug_reg,
    output wire [31:0] debug_value,
    input wire [7:0] debug_addr,
    output wire [31:0] debug_data,
    output wire halted,trapped,
    output wire [4:0] fault_cause,
    output wire [31:0] fault_value,
    output wire [31:0] fault_pc,
    output wire [31:0] cycle_count,retire_count,issue_count,bypass_count,
    output wire [31:0] mispredict_count,branch_count,forward_count,replay_count,
    output wire [31:0] reuse_count,value_hit_count,value_miss_count,
    output wire [4:0] rob_occupancy,iq_occupancy,
    output wire [31:0] raw_stalls,memory_stalls,dispatch_stalls,
    output wire [13:0] events,
    output wire [447:0] event_pcs,
    output wire [447:0] event_ids,
    output wire flush_event,
    output wire [31:0] flush_id,
    output wire [31:0] cache_hits,cache_misses
);
reg [31:0] imem[0:255];
wire [31:0] pc0,pc1;
wire [3:0] ms;
wire [31:0] ins0=(pc0<1024 && pc0[1:0]==0)?imem[pc0[9:2]]:32'h00000000;
wire [31:0] ins1=(pc1<1024 && pc1[1:0]==0)?imem[pc1[9:2]]:32'h00000000;
wire mv,mw,mready,mresp,mfault;
wire [31:0] ma,md,mrd;
always @(posedge clk) if(instr_we) imem[host_addr]<=host_data;
core #(.OOO(OOO),.RENAME(RENAME),.PREDICTOR(PREDICTOR),.MEM_SPEC(MEM_SPEC),.REUSE(REUSE),.VALUE_PRED(VALUE_PRED),.ENABLE_MUL(ENABLE_MUL)) cpu(
    .clk(clk),.reset(reset),.run(run),.imem_pc0(pc0),.imem_pc1(pc1),.imem_ins0(ins0),.imem_ins1(ins1),
    .mem_valid(mv),.mem_write(mw),.mem_wstrb(ms),.mem_addr(ma),.mem_wdata(md),.mem_ready(mready),
    .mem_resp_valid(mresp),.mem_resp_fault(mfault),.mem_resp_data(mrd),
    .debug_reg(debug_reg),.debug_value(debug_value),.halted(halted),.trapped(trapped),.fault_pc(fault_pc),.fault_cause(fault_cause),.fault_value(fault_value),
    .cycle_count(cycle_count),.retire_count(retire_count),.issue_count(issue_count),.bypass_count(bypass_count),
    .mispredict_count(mispredict_count),.branch_count(branch_count),.forward_count(forward_count),.replay_count(replay_count),
    .reuse_count(reuse_count),.value_hit_count(value_hit_count),.value_miss_count(value_miss_count),
    .rob_occupancy(rob_occupancy),.iq_occupancy(iq_occupancy),.raw_stalls(raw_stalls),.memory_stalls(memory_stalls),.dispatch_stalls(dispatch_stalls),
    .events(events),.event_pcs(event_pcs),.event_ids(event_ids),.flush_event(flush_event),.flush_id(flush_id)
);
data_cache #(.CACHE_ENABLE(CACHE_ENABLE),.HIT_LAT(HIT_LAT),.MISS_LAT(MISS_LAT)) memory(
    .clk(clk),.reset(reset),.host_we(data_we),.host_addr(host_addr),.host_data(host_data),
    .req_valid(mv),.req_write(mw),.req_addr(ma),.req_data(md),.req_wstrb(ms),.req_ready(mready),
    .resp_valid(mresp),.resp_fault(mfault),.resp_data(mrd),.debug_addr(debug_addr),.debug_data(debug_data),
    .hit_count(cache_hits),.miss_count(cache_misses)
);
endmodule
