`timescale 1ns/1ps
module tb;
parameter OOO=1,RENAME=1,PREDICTOR=2,MEM_SPEC=0,REUSE=0,VALUE_PRED=0,CACHE_ENABLE=1,ENABLE_MUL=0;
reg clk=0;always #5 clk=~clk;
reg reset=1,run=0,instr_we=0,data_we=0;
reg [7:0] host_addr=0,debug_addr=0;
reg [31:0] host_data=0;
reg [4:0] debug_reg=0;
wire [31:0] debug_value,debug_data;
wire halted,trapped;wire [4:0] fault_cause;wire [31:0] fault_value;wire [31:0] fault_pc;
wire [31:0] cycle_count,retire_count,issue_count,bypass_count,mispredict_count,branch_count;
wire [31:0] forward_count,replay_count,reuse_count,value_hit_count,value_miss_count;
wire [4:0] rob_occupancy,iq_occupancy;
wire [31:0] raw_stalls,memory_stalls,dispatch_stalls,cache_hits,cache_misses;
wire [13:0] events;wire [447:0] event_pcs;wire [447:0] event_ids;
wire flush_event;wire [31:0] flush_id;
processor_system #(.OOO(OOO),.RENAME(RENAME),.PREDICTOR(PREDICTOR),.MEM_SPEC(MEM_SPEC),
    .REUSE(REUSE),.VALUE_PRED(VALUE_PRED),.CACHE_ENABLE(CACHE_ENABLE),.ENABLE_MUL(ENABLE_MUL)) dut(.*);
reg [31:0] program_words[0:255],data_words[0:255];
reg [4095:0] program_file,data_file,trace_file,wave_file;
integer f,i,j,active,timeout,nargs,initializing;
initial begin
    initializing=1;
    nargs=$value$plusargs("PROGRAM=%s",program_file);
    nargs=$value$plusargs("DATA=%s",data_file);
    nargs=$value$plusargs("TRACE=%s",trace_file);
    if($value$plusargs("WAVE=%s",wave_file)) begin
        $dumpfile(wave_file);$dumpvars(0,tb.dut);
    end
    $readmemh(program_file,program_words);$readmemh(data_file,data_words);
    f=$fopen(trace_file,"w");if(!f) $fatal(1,"cannot create trace");
    $fdisplay(f,"cycle,events,pcs,ids,rob,iq,flush,flush_id");
    for(i=0;i<256;i=i+1) begin
        @(negedge clk);instr_we=1;data_we=0;host_addr=i;host_data=program_words[i];
    end
    @(negedge clk);instr_we=0;
    for(i=0;i<256;i=i+1) begin
        data_we=1;host_addr=i;host_data=data_words[i];@(negedge clk);
    end
    data_we=0;reset=0;run=1;initializing=0;timeout=0;
    while(!halted && !trapped && timeout<4000) begin
        @(posedge clk);#1;timeout=timeout+1;
        $fdisplay(f,"%0d,%h,%h,%h,%0d,%0d,%0d,%0d",cycle_count,events,event_pcs,event_ids,rob_occupancy,iq_occupancy,flush_event,flush_id);
        // Architectural invariants independent of the workload's expected values.
        active=0;
        for(j=0;j<16;j=j+1) begin
            if(dut.cpu.r_valid_q[j]) active=active+1;
            if(dut.cpu.q_valid_q[j] && (!dut.cpu.r_valid_q[dut.cpu.q_slot_q[j]] ||
              dut.cpu.r_seq_q[dut.cpu.q_slot_q[j]]!=dut.cpu.q_seq_q[j])) $fatal(1,"orphan issue entry");
        end
        for(j=0;j<32;j=j+1) begin
            if(dut.cpu.rat_q[j]>=64) $fatal(1,"rename map out of range");
            if(dut.cpu.free_q[dut.cpu.rat_q[j]]) $fatal(1,"mapped physical register on free list");
        end
        if(active!=rob_occupancy) $fatal(1,"ROB occupancy mismatch");
        if(dut.cpu.pv_q[0]!=0 || dut.cpu.arch_q[0]!=0) $fatal(1,"zero register changed");
    end
    if(timeout>=4000) $fatal(1,"timeout");
    $fclose(f);
    $display("RESULT,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
        cycle_count,retire_count,issue_count,bypass_count,mispredict_count,branch_count,forward_count,replay_count,
        reuse_count,value_hit_count,value_miss_count,raw_stalls,memory_stalls,dispatch_stalls,cache_hits,cache_misses,halted,trapped,fault_pc);
    $display("FAULT,%0d,%0d",fault_cause,fault_value);
    run=0;
    for(i=0;i<32;i=i+1) begin debug_reg=i;#1;$display("REG,%0d,%h",i,debug_value);end
    for(i=0;i<256;i=i+1) begin debug_addr=i;#1;$display("MEM,%0d,%h",i,debug_data);end
    $finish;
end
endmodule
