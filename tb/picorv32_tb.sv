`timescale 1ns/1ps
module picorv32_tb;
parameter ENABLE_MUL=0;
reg clk=0;always #5 clk=~clk;
reg reset=1,run=0,instr_we=0,data_we=0;
reg [7:0] host_addr=0,debug_addr=0;reg [31:0] host_data=0;
wire [31:0] debug_data,cycle_count,cache_hits,cache_misses;wire trapped;
picorv32_reference_system #(.ENABLE_MUL(ENABLE_MUL)) dut(.*);
reg [31:0] program_words[0:255],data_words[0:255];
reg [4095:0] program_file,data_file;integer i,nargs,timeout;
initial begin
    nargs=$value$plusargs("PROGRAM=%s",program_file);nargs=$value$plusargs("DATA=%s",data_file);
    $readmemh(program_file,program_words);$readmemh(data_file,data_words);
    for(i=0;i<256;i=i+1) begin
        @(negedge clk);instr_we=1;data_we=0;host_addr=i;host_data=program_words[i];
    end
    @(negedge clk);instr_we=0;
    for(i=0;i<256;i=i+1) begin
        data_we=1;host_addr=i;host_data=data_words[i];@(negedge clk);
    end
    data_we=0;reset=0;run=1;timeout=0;
    while(!trapped && timeout<20000) begin @(posedge clk);#1;timeout=timeout+1;end
    if(timeout>=20000) $fatal(1,"PicoRV32 timeout");
    $display("RESULT,%0d,%0d,%0d",cycle_count,cache_hits,cache_misses);
    $display("REG,0,00000000");
    for(i=1;i<32;i=i+1) $display("REG,%0d,%h",i,dut.cpu.cpuregs[i]);
    for(i=0;i<256;i=i+1) begin debug_addr=i;#1;$display("MEM,%0d,%h",i,debug_data);end
    $finish;
end
endmodule
