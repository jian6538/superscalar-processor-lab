// Synthesizable direct-mapped, single-word-line L1 with one outstanding miss.
// Backing RAM is on-chip in this lab. HIT_LAT/MISS_LAT are delay registers,
// not measured DRAM latency. CPU stores are write-through and write-allocate.
module data_cache #(parameter HIT_LAT=2, MISS_LAT=12, CACHE_ENABLE=1)(
    input wire clk, reset,
    input wire host_we,
    input wire [7:0] host_addr,
    input wire [31:0] host_data,
    input wire req_valid,req_write,
    input wire [31:0] req_addr,req_data,
    input wire [3:0] req_wstrb,
    output wire req_ready,
    output reg resp_valid,resp_fault,
    output reg [31:0] resp_data,
    input wire [7:0] debug_addr,
    output wire [31:0] debug_data,
    output reg [31:0] hit_count,miss_count
);
reg [31:0] ram[0:255];
reg [31:0] line_data[0:7];
reg [4:0] line_tag[0:7];
reg line_valid[0:7];
reg busy;
reg [7:0] countdown, pending_addr;
reg [31:0] pending_data;
reg pending_fault,pending_hit;
integer i,b;
reg [31:0] merged;
assign req_ready=!busy;
assign debug_data=ram[debug_addr];
always @(posedge clk) begin
    if(host_we) ram[host_addr]<=host_data;
    if(reset) begin
        busy<=0;countdown<=0;resp_valid<=0;resp_fault<=0;resp_data<=0;
        pending_addr<=0;pending_data<=0;pending_fault<=0;pending_hit<=0;
        hit_count<=0;miss_count<=0;
        for(i=0;i<8;i=i+1) begin line_valid[i]<=0;line_data[i]<=0;line_tag[i]<=0;end
    end else begin
        resp_valid<=0;
        if(busy) begin
            if(countdown==1) begin
                busy<=0;resp_valid<=1;resp_fault<=pending_fault;resp_data<=pending_data;
                if(!pending_fault && CACHE_ENABLE) begin
                    line_valid[pending_addr[2:0]]<=1;
                    line_tag[pending_addr[2:0]]<=pending_addr[7:3];
                    line_data[pending_addr[2:0]]<=pending_data;
                end
            end else countdown<=countdown-1'b1;
        end
        if(req_valid && req_ready) begin
            if(req_write) begin
                if((req_addr>=4096 && req_addr<5120)) begin
                    merged=ram[req_addr[9:2]];
                    for(b=0;b<4;b=b+1) if(req_wstrb[b]) merged[b*8+:8]=req_data[b*8+:8];
                    ram[req_addr[9:2]]<=merged;
                    if(CACHE_ENABLE) begin
                        line_valid[req_addr[4:2]]<=1;line_tag[req_addr[4:2]]<=req_addr[9:5];
                        line_data[req_addr[4:2]]<=merged;
                    end
                end
            end else begin
                busy<=1;pending_addr<=req_addr[9:2];pending_fault<=((req_addr<4096 || req_addr>=5120));
                if((req_addr>=4096 && req_addr<5120) && CACHE_ENABLE && line_valid[req_addr[4:2]] && line_tag[req_addr[4:2]]==req_addr[9:5]) begin
                    pending_data<=line_data[req_addr[4:2]];countdown<=HIT_LAT;hit_count<=hit_count+1;
                    pending_hit<=1;
                end else begin
                    pending_data<=((req_addr>=4096 && req_addr<5120))?ram[req_addr[9:2]]:0;countdown<=MISS_LAT;miss_count<=miss_count+1;
                    pending_hit<=0;
                end
            end
        end
    end
end
endmodule
