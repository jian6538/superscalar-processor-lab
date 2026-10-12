// Educational two-wide RV32I core with optional complete Zmmul extension.
// Fixed bounds: ROB=16, IQ=16, PRF=64, architectural registers=32.
// No delays, file I/O, initial blocks, or simulation-only constructs in this module.
module core #(
    parameter OOO=1, RENAME=1, PREDICTOR=2,
    parameter MEM_SPEC=0, REUSE=0, VALUE_PRED=0, ENABLE_MUL=0
)(
    input wire clk, reset, run,
    output wire [31:0] imem_pc0, imem_pc1,
    input wire [31:0] imem_ins0, imem_ins1,
    output reg mem_valid, mem_write,
    output reg [3:0] mem_wstrb,
    output reg [31:0] mem_addr, mem_wdata,
    input wire mem_ready, mem_resp_valid, mem_resp_fault,
    input wire [31:0] mem_resp_data,
    input wire [4:0] debug_reg,
    output wire [31:0] debug_value,
    output wire halted, trapped,
    output wire [4:0] fault_cause,
    output wire [31:0] fault_value,
    output wire [31:0] fault_pc,
    output wire [31:0] cycle_count, retire_count, issue_count,
    output wire [31:0] bypass_count, mispredict_count, branch_count,
    output wire [31:0] forward_count, replay_count,
    output wire [31:0] reuse_count, value_hit_count, value_miss_count,
    output wire [4:0] rob_occupancy,
    output wire [4:0] iq_occupancy,
    output wire [31:0] raw_stalls, memory_stalls, dispatch_stalls,
    output wire [13:0] events,
    output wire [447:0] event_pcs,
    output wire [447:0] event_ids,
    output wire flush_event,
    output wire [31:0] flush_id
);
localparam NOP=0, ADD=1, ADDI=2, MUL=3, LD=4, ST=5, BNE=6,
           JAL=7, JR=8, HALT=9, XOR_=10, SUB=11, OR_=12, AND_=13,
           SLT=14, SLTU=15, SLL=16, SRL=17, SRA=18, LUI=19, AUIPC=20,
           FENCE=21, ECALL=22, EBREAK=23, MULH=24, MULHSU=25, MULHU=26, ILLEGAL=31;

reg [31:0] pc_q, pc_n;
reg [4:0] trap_cause_q,trap_cause_n;
reg [31:0] trap_value_q,trap_value_n;
assign fault_cause=trap_cause_q;
assign fault_value=trap_value_q;
reg [31:0] seq_q, seq_n;
reg [3:0] head_q, head_n;
reg [3:0] tail_q, tail_n;
reg [4:0] rcount_q, rcount_n;
reg [2:0] fc_q, fc_n;
reg [2:0] dc_q, dc_n;
reg stop_q, stop_n;
reg halt_q, halt_n;
reg trap_q, trap_n;
reg [31:0] trap_pc_q, trap_pc_n;
reg load_busy_q, load_busy_n;
reg [3:0] load_slot_q, load_slot_n;
reg [31:0] load_seq_q, load_seq_n;
reg [5:0] ghr_q, ghr_n;
reg [31:0] cycles_q, cycles_n;
reg [31:0] retired_q, retired_n;
reg [31:0] issued_q, issued_n;
reg [31:0] bypassed_q, bypassed_n;
reg [31:0] mispredicts_q, mispredicts_n;
reg [31:0] branches_q, branches_n;
reg [31:0] forwarded_q, forwarded_n;
reg [31:0] replays_q, replays_n;
reg [31:0] stall_raw_q, stall_raw_n;
reg [31:0] stall_mem_q, stall_mem_n;
reg [31:0] stall_dispatch_q, stall_dispatch_n;
reg [31:0] reuse_hits_q, reuse_hits_n;
reg [31:0] value_hits_q, value_hits_n;
reg [31:0] value_misses_q, value_misses_n;
reg [1:0] ev_fetch_q, ev_fetch_n;
reg [63:0] pc_fetch_q, pc_fetch_n;
reg [63:0] id_fetch_q, id_fetch_n;
reg [1:0] ev_decode_q, ev_decode_n;
reg [63:0] pc_decode_q, pc_decode_n;
reg [63:0] id_decode_q, id_decode_n;
reg [1:0] ev_dispatch_q, ev_dispatch_n;
reg [63:0] pc_dispatch_q, pc_dispatch_n;
reg [63:0] id_dispatch_q, id_dispatch_n;
reg [1:0] ev_issue_q, ev_issue_n;
reg [63:0] pc_issue_q, pc_issue_n;
reg [63:0] id_issue_q, id_issue_n;
reg [3:0] ev_wb_q, ev_wb_n;
reg [127:0] pc_wb_q, pc_wb_n;
reg [127:0] id_wb_q, id_wb_n;
reg [1:0] ev_retire_q, ev_retire_n;
reg [63:0] pc_retire_q, pc_retire_n;
reg [63:0] id_retire_q, id_retire_n;
reg ev_flush_q, ev_flush_n;
reg [31:0] flush_seq_q, flush_seq_n;
reg [5:0] rat_q [0:31], rat_n [0:31];
reg [5:0] commap_q [0:31], commap_n [0:31];
reg [31:0] arch_q [0:31], arch_n [0:31];
reg [31:0] pv_q [0:63], pv_n [0:63];
reg ready_q [0:63], ready_n [0:63];
reg free_q [0:63], free_n [0:63];
reg [31:0] f_ins_q [0:3], f_ins_n [0:3];
reg [31:0] f_pc_q [0:3], f_pc_n [0:3];
reg [31:0] f_id_q [0:3], f_id_n [0:3];
reg [31:0] f_pred_q [0:3], f_pred_n [0:3];
reg [5:0] f_hist_q [0:3], f_hist_n [0:3];
reg [31:0] d_ins_q [0:3], d_ins_n [0:3];
reg [31:0] d_pc_q [0:3], d_pc_n [0:3];
reg [31:0] d_id_q [0:3], d_id_n [0:3];
reg [31:0] d_pred_q [0:3], d_pred_n [0:3];
reg [5:0] d_hist_q [0:3], d_hist_n [0:3];
reg r_valid_q [0:15], r_valid_n [0:15];
reg r_done_q [0:15], r_done_n [0:15];
reg r_fault_q [0:15], r_fault_n [0:15];
reg [31:0] r_pc_q [0:15], r_pc_n [0:15];
reg [31:0] r_seq_q [0:15], r_seq_n [0:15];
reg [4:0] r_op_q [0:15], r_op_n [0:15];
reg [4:0] r_dst_q [0:15], r_dst_n [0:15];
reg [5:0] r_phy_q [0:15], r_phy_n [0:15];
reg [5:0] r_old_q [0:15], r_old_n [0:15];
reg [31:0] r_result_q [0:15], r_result_n [0:15];
reg [31:0] r_addr_q [0:15], r_addr_n [0:15];
reg [31:0] r_data_q [0:15], r_data_n [0:15];
reg r_addr_ready_q [0:15], r_addr_ready_n [0:15];
reg [31:0] r_pred_q [0:15], r_pred_n [0:15];
reg [5:0] r_hist_q [0:15], r_hist_n [0:15];
reg r_load_exec_q [0:15], r_load_exec_n [0:15];
reg q_valid_q [0:15], q_valid_n [0:15];
reg [3:0] q_slot_q [0:15], q_slot_n [0:15];
reg [31:0] q_seq_q [0:15], q_seq_n [0:15];
reg [4:0] q_op_q [0:15], q_op_n [0:15];
reg [5:0] q_a_q [0:15], q_a_n [0:15];
reg [5:0] q_b_q [0:15], q_b_n [0:15];
reg [31:0] q_imm_q [0:15], q_imm_n [0:15];
reg q_use_a_q [0:15], q_use_a_n [0:15];
reg q_use_b_q [0:15], q_use_b_n [0:15];
reg [31:0] q_pc_q [0:15], q_pc_n [0:15];
reg [31:0] q_a_val_q [0:15], q_a_val_n [0:15];
reg [31:0] q_b_val_q [0:15], q_b_val_n [0:15];
reg q_ar_q [0:15], q_ar_n [0:15];
reg q_br_q [0:15], q_br_n [0:15];
reg m_valid_q [0:3], m_valid_n [0:3];
reg [3:0] m_slot_q [0:3], m_slot_n [0:3];
reg [31:0] m_seq_q [0:3], m_seq_n [0:3];
reg [31:0] m_value_q [0:3], m_value_n [0:3];
reg [31:0] m_pc_q [0:3], m_pc_n [0:3];
reg [31:0] m_a_q [0:3], m_a_n [0:3];
reg [31:0] m_b_q [0:3], m_b_n [0:3];
reg [1:0] bim_q [0:63], bim_n [0:63];
reg [1:0] gsh_q [0:63], gsh_n [0:63];
reg [5:0] local_hist_q [0:63], local_hist_n [0:63];
reg [1:0] local_ctr_q [0:63], local_ctr_n [0:63];
reg [1:0] chooser_q [0:63], chooser_n [0:63];
reg btb_valid_q [0:63], btb_valid_n [0:63];
reg [23:0] btb_tag_q [0:63], btb_tag_n [0:63];
reg [31:0] btb_target_q [0:63], btb_target_n [0:63];
reg reuse_valid_q [0:15], reuse_valid_n [0:15];
reg [31:0] reuse_pc_q [0:15], reuse_pc_n [0:15];
reg [31:0] reuse_a_q [0:15], reuse_a_n [0:15];
reg [31:0] reuse_b_q [0:15], reuse_b_n [0:15];
reg [31:0] reuse_value_q [0:15], reuse_value_n [0:15];
reg vp_valid_q [0:15], vp_valid_n [0:15];
reg [31:0] vp_pc_q [0:15], vp_pc_n [0:15];
reg [31:0] vp_value_q [0:15], vp_value_n [0:15];
reg [1:0] vp_conf_q [0:15], vp_conf_n [0:15];
reg r_vpred_q [0:15], r_vpred_n [0:15];
reg [31:0] r_predval_q [0:15], r_predval_n [0:15];

reg [31:0] r_ins_q [0:15], r_ins_n [0:15];
reg [3:0] r_mask_q [0:15], r_mask_n [0:15];
reg [4:0] r_cause_q [0:15], r_cause_n [0:15];
reg [31:0] r_tval_q [0:15], r_tval_n [0:15];
assign imem_pc0 = pc_q;
assign imem_pc1 = pc_q + 32'd4;
assign debug_value = arch_q[debug_reg];
assign halted = halt_q; assign trapped = trap_q; assign fault_pc = trap_pc_q;
assign cycle_count = cycles_q; assign retire_count = retired_q;
assign issue_count = issued_q; assign bypass_count = bypassed_q;
assign mispredict_count = mispredicts_q; assign branch_count = branches_q;
assign forward_count = forwarded_q; assign replay_count = replays_q;
assign reuse_count = reuse_hits_q; assign value_hit_count = value_hits_q;
assign value_miss_count = value_misses_q;
assign rob_occupancy = rcount_q;
assign raw_stalls=stall_raw_q; assign memory_stalls=stall_mem_q;
assign dispatch_stalls=stall_dispatch_q;
assign events={ev_retire_q,ev_wb_q,ev_issue_q,ev_dispatch_q,ev_decode_q,ev_fetch_q};
assign event_pcs={pc_retire_q,pc_wb_q,pc_issue_q,pc_dispatch_q,pc_decode_q,pc_fetch_q};
assign event_ids={id_retire_q,id_wb_q,id_issue_q,id_dispatch_q,id_decode_q,id_fetch_q};
assign flush_event=ev_flush_q;assign flush_id=flush_seq_q;
reg [4:0] iq_sum;
integer zz;
always @* begin
    iq_sum=0;
    for(zz=0;zz<16;zz=zz+1) iq_sum=iq_sum+q_valid_q[zz];
end
assign iq_occupancy=iq_sum;

function [1:0] train;
input [1:0] counter; input taken;
begin
    if(taken) train=(counter==3)?3:counter+1'b1;
    else train=(counter==0)?0:counter-1'b1;
end
endfunction

// Predictor selection: 0 not-taken, 1 BTFNT, 2 bimodal, 3 gshare,
// 4 local two-level, 5 local/gshare tournament.
function predict_taken;
input [31:0] pc; input [31:0] target; input [5:0] hist;
begin
    case(PREDICTOR)
    0: predict_taken=0;
    1: predict_taken=target<pc;
    2: predict_taken=bim_q[pc[7:2]][1];
    3: predict_taken=gsh_q[pc[7:2]^hist][1];
    4: predict_taken=local_ctr_q[local_hist_q[pc[7:2]]][1];
    default: predict_taken=chooser_q[pc[7:2]][1] ?
        gsh_q[pc[7:2]^hist][1] : local_ctr_q[local_hist_q[pc[7:2]]][1];
    endcase
end
endfunction


function is_mul;
input [4:0] operation;
begin is_mul=(operation==MUL || operation==MULH || operation==MULHSU || operation==MULHU);end
endfunction

function [3:0] byte_mask;
input [31:0] address;input [2:0] kind;
begin
    case(kind)
    0,4:byte_mask=4'b0001<<address[1:0];
    1,5:byte_mask=4'b0011<<address[1:0];
    default:byte_mask=4'b1111;
    endcase
end
endfunction
function misaligned;
input [31:0] address;input [2:0] kind;
begin misaligned=((kind==1 || kind==5) && address[0]) || (kind==2 && address[1:0]!=0);end
endfunction
function [31:0] load_value;
input [31:0] word_value,address;input [2:0] kind;
reg [31:0] shifted;
begin
    shifted=word_value>>(8*address[1:0]);
    case(kind)
    0:load_value={{24{shifted[7]}},shifted[7:0]};
    1:load_value={{16{shifted[15]}},shifted[15:0]};
    4:load_value={24'b0,shifted[7:0]};
    5:load_value={16'b0,shifted[15:0]};
    default:load_value=shifted;
    endcase
end
endfunction

// Decode standard R/I/S/B/U/J encodings into internal operations.
// Zicsr, Zifencei, division, compressed and privileged opcodes are not RV32I.
function [55:0] decode_rv;
input [31:0] instruction;
reg bad,wd,ua,ub;reg [4:0] operation;
reg [31:0] immediate;
begin
    bad=0;wd=0;ua=0;ub=0;operation=ILLEGAL;
    immediate={{20{instruction[31]}},instruction[31:20]};
    case(instruction[6:0])
    7'h37:begin operation=LUI;wd=1;immediate={instruction[31:12],12'b0};end
    7'h17:begin operation=AUIPC;wd=1;immediate={instruction[31:12],12'b0};end
    7'h6f:begin operation=JAL;wd=1;immediate={{11{instruction[31]}},instruction[31],instruction[19:12],instruction[20],instruction[30:21],1'b0};end
    7'h67:begin operation=JR;wd=1;ua=1;if(instruction[14:12]!=0) bad=1;end
    7'h63:begin
        operation=BNE;ua=1;ub=1;
        immediate={{19{instruction[31]}},instruction[31],instruction[7],instruction[30:25],instruction[11:8],1'b0};
        if(instruction[14:12]==2 || instruction[14:12]==3) bad=1;
    end
    7'h03:begin operation=LD;ua=1;wd=1;
        if(instruction[14:12]==3 || instruction[14:12]>=6) bad=1;
    end
    7'h23:begin operation=ST;ua=1;ub=1;
        immediate={{20{instruction[31]}},instruction[31:25],instruction[11:7]};
        if(instruction[14:12]>2) bad=1;
    end
    7'h13,7'h33:begin
        ua=1;wd=1;ub=(instruction[6:0]==7'h33);
        case(instruction[14:12])
        0:operation=ADD;1:operation=SLL;2:operation=SLT;3:operation=SLTU;
        4:operation=XOR_;5:operation=SRL;6:operation=OR_;7:operation=AND_;
        endcase
        if(ub) begin
            if(instruction[31:25]==7'h20 && instruction[14:12]==0) operation=SUB;
            else if(instruction[31:25]==7'h20 && instruction[14:12]==5) operation=SRA;
            else if(instruction[31:25]==1 && ENABLE_MUL && instruction[14:12]<4)
                case(instruction[14:12])
                0:operation=MUL;1:operation=MULH;2:operation=MULHSU;3:operation=MULHU;
                endcase
            else if(instruction[31:25]!=0) bad=1;
        end else if(instruction[14:12]==1 || instruction[14:12]==5) begin
            immediate={27'b0,instruction[24:20]};
            if(instruction[14:12]==5 && instruction[31:25]==7'h20) operation=SRA;
            else if(instruction[31:25]!=0) bad=1;
        end
    end
    7'h0f:begin operation=FENCE;if(instruction[14:12]!=0) bad=1;end
    7'h73:begin
        if(instruction==32'h00000073) operation=ECALL;
        else if(instruction==32'h00100073) operation=EBREAK;
        else bad=1;
    end
    default:bad=1;
    endcase
    if(bad) begin operation=ILLEGAL;wd=0;ua=0;ub=0;end
    decode_rv={bad,wd,ua,ub,operation,instruction[11:7],instruction[19:15],instruction[24:20],immediate};
end
endfunction

integer i,j,k,l,slot,chosen,oldest,phy,iqslot,idx,offset;
integer wb_lane,issue_lane,dispatch_lane,decode_lane,fetch_lane,retire_lane;
integer shift_d,shift_f,remaining,free_count,occupied;
reg [31:0] a,b,value,address,best_age,oldest_age,forward_age,ins,imm;
reg [4:0] op,rd,rs1,rs2;
reg [55:0] decoded;
reg illegal;
reg [31:0] operand_b,forwarded_word;
reg [3:0] wanted_mask;
reg signed [65:0] product;
reg use_a,use_b,write_dst,ok,blocked,forward_ok,unknown_store;
reg alu_used,mul_used,ls_used,taken,do_flush,keep_branch;
reg [31:0] cut_seq;
reg [31:0] redirect,target,pred,fetch_pc;
reg [5:0] fetch_hist;
reg [1:0] local_pred,global_pred;
reg [31:0] issue_limit;
always @* begin

    pc_n=pc_q;trap_cause_n=trap_cause_q;trap_value_n=trap_value_q;
    seq_n=seq_q;
    head_n=head_q;
    tail_n=tail_q;
    rcount_n=rcount_q;
    fc_n=fc_q;
    dc_n=dc_q;
    stop_n=stop_q;
    halt_n=halt_q;
    trap_n=trap_q;
    trap_pc_n=trap_pc_q;
    load_busy_n=load_busy_q;
    load_slot_n=load_slot_q;
    load_seq_n=load_seq_q;
    ghr_n=ghr_q;
    cycles_n=cycles_q;
    retired_n=retired_q;
    issued_n=issued_q;
    bypassed_n=bypassed_q;
    mispredicts_n=mispredicts_q;
    branches_n=branches_q;
    forwarded_n=forwarded_q;
    replays_n=replays_q;
    stall_raw_n=stall_raw_q;
    stall_mem_n=stall_mem_q;
    stall_dispatch_n=stall_dispatch_q;
    reuse_hits_n=reuse_hits_q;
    value_hits_n=value_hits_q;
    value_misses_n=value_misses_q;
    ev_fetch_n=ev_fetch_q;
    pc_fetch_n=pc_fetch_q;
    id_fetch_n=id_fetch_q;
    ev_decode_n=ev_decode_q;
    pc_decode_n=pc_decode_q;
    id_decode_n=id_decode_q;
    ev_dispatch_n=ev_dispatch_q;
    pc_dispatch_n=pc_dispatch_q;
    id_dispatch_n=id_dispatch_q;
    ev_issue_n=ev_issue_q;
    pc_issue_n=pc_issue_q;
    id_issue_n=id_issue_q;
    ev_wb_n=ev_wb_q;
    pc_wb_n=pc_wb_q;
    id_wb_n=id_wb_q;
    ev_retire_n=ev_retire_q;
    pc_retire_n=pc_retire_q;
    id_retire_n=id_retire_q;
    ev_flush_n=ev_flush_q;
    flush_seq_n=flush_seq_q;
    for(i=0;i<32;i=i+1) rat_n[i]=rat_q[i];
    for(i=0;i<32;i=i+1) commap_n[i]=commap_q[i];
    for(i=0;i<32;i=i+1) arch_n[i]=arch_q[i];
    for(i=0;i<64;i=i+1) pv_n[i]=pv_q[i];
    for(i=0;i<64;i=i+1) ready_n[i]=ready_q[i];
    for(i=0;i<64;i=i+1) free_n[i]=free_q[i];
    for(i=0;i<4;i=i+1) f_ins_n[i]=f_ins_q[i];
    for(i=0;i<4;i=i+1) f_pc_n[i]=f_pc_q[i];
    for(i=0;i<4;i=i+1) f_id_n[i]=f_id_q[i];
    for(i=0;i<4;i=i+1) f_pred_n[i]=f_pred_q[i];
    for(i=0;i<4;i=i+1) f_hist_n[i]=f_hist_q[i];
    for(i=0;i<4;i=i+1) d_ins_n[i]=d_ins_q[i];
    for(i=0;i<4;i=i+1) d_pc_n[i]=d_pc_q[i];
    for(i=0;i<4;i=i+1) d_id_n[i]=d_id_q[i];
    for(i=0;i<4;i=i+1) d_pred_n[i]=d_pred_q[i];
    for(i=0;i<4;i=i+1) d_hist_n[i]=d_hist_q[i];
    for(i=0;i<16;i=i+1) r_valid_n[i]=r_valid_q[i];
    for(i=0;i<16;i=i+1) r_done_n[i]=r_done_q[i];
    for(i=0;i<16;i=i+1) r_fault_n[i]=r_fault_q[i];
    for(i=0;i<16;i=i+1) r_pc_n[i]=r_pc_q[i];
    for(i=0;i<16;i=i+1) r_seq_n[i]=r_seq_q[i];
    for(i=0;i<16;i=i+1) r_op_n[i]=r_op_q[i];
    for(i=0;i<16;i=i+1) r_dst_n[i]=r_dst_q[i];
    for(i=0;i<16;i=i+1) r_phy_n[i]=r_phy_q[i];
    for(i=0;i<16;i=i+1) r_old_n[i]=r_old_q[i];
    for(i=0;i<16;i=i+1) r_result_n[i]=r_result_q[i];
    for(i=0;i<16;i=i+1) r_addr_n[i]=r_addr_q[i];
    for(i=0;i<16;i=i+1) r_data_n[i]=r_data_q[i];
    for(i=0;i<16;i=i+1) r_addr_ready_n[i]=r_addr_ready_q[i];
    for(i=0;i<16;i=i+1) r_pred_n[i]=r_pred_q[i];
    for(i=0;i<16;i=i+1) r_hist_n[i]=r_hist_q[i];
    for(i=0;i<16;i=i+1) r_load_exec_n[i]=r_load_exec_q[i];
    for(i=0;i<16;i=i+1) q_valid_n[i]=q_valid_q[i];
    for(i=0;i<16;i=i+1) q_slot_n[i]=q_slot_q[i];
    for(i=0;i<16;i=i+1) q_seq_n[i]=q_seq_q[i];
    for(i=0;i<16;i=i+1) q_op_n[i]=q_op_q[i];
    for(i=0;i<16;i=i+1) q_a_n[i]=q_a_q[i];
    for(i=0;i<16;i=i+1) q_b_n[i]=q_b_q[i];
    for(i=0;i<16;i=i+1) q_imm_n[i]=q_imm_q[i];
    for(i=0;i<16;i=i+1) q_use_a_n[i]=q_use_a_q[i];
    for(i=0;i<16;i=i+1) q_use_b_n[i]=q_use_b_q[i];
    for(i=0;i<16;i=i+1) q_pc_n[i]=q_pc_q[i];
    for(i=0;i<16;i=i+1) q_a_val_n[i]=q_a_val_q[i];
    for(i=0;i<16;i=i+1) q_b_val_n[i]=q_b_val_q[i];
    for(i=0;i<16;i=i+1) q_ar_n[i]=q_ar_q[i];
    for(i=0;i<16;i=i+1) q_br_n[i]=q_br_q[i];
    for(i=0;i<4;i=i+1) m_valid_n[i]=m_valid_q[i];
    for(i=0;i<4;i=i+1) m_slot_n[i]=m_slot_q[i];
    for(i=0;i<4;i=i+1) m_seq_n[i]=m_seq_q[i];
    for(i=0;i<4;i=i+1) m_value_n[i]=m_value_q[i];
    for(i=0;i<4;i=i+1) m_pc_n[i]=m_pc_q[i];
    for(i=0;i<4;i=i+1) m_a_n[i]=m_a_q[i];
    for(i=0;i<4;i=i+1) m_b_n[i]=m_b_q[i];
    for(i=0;i<64;i=i+1) bim_n[i]=bim_q[i];
    for(i=0;i<64;i=i+1) gsh_n[i]=gsh_q[i];
    for(i=0;i<64;i=i+1) local_hist_n[i]=local_hist_q[i];
    for(i=0;i<64;i=i+1) local_ctr_n[i]=local_ctr_q[i];
    for(i=0;i<64;i=i+1) chooser_n[i]=chooser_q[i];
    for(i=0;i<64;i=i+1) btb_valid_n[i]=btb_valid_q[i];
    for(i=0;i<64;i=i+1) btb_tag_n[i]=btb_tag_q[i];
    for(i=0;i<64;i=i+1) btb_target_n[i]=btb_target_q[i];
    for(i=0;i<16;i=i+1) reuse_valid_n[i]=reuse_valid_q[i];
    for(i=0;i<16;i=i+1) reuse_pc_n[i]=reuse_pc_q[i];
    for(i=0;i<16;i=i+1) reuse_a_n[i]=reuse_a_q[i];
    for(i=0;i<16;i=i+1) reuse_b_n[i]=reuse_b_q[i];
    for(i=0;i<16;i=i+1) reuse_value_n[i]=reuse_value_q[i];
    for(i=0;i<16;i=i+1) vp_valid_n[i]=vp_valid_q[i];
    for(i=0;i<16;i=i+1) vp_pc_n[i]=vp_pc_q[i];
    for(i=0;i<16;i=i+1) vp_value_n[i]=vp_value_q[i];
    for(i=0;i<16;i=i+1) vp_conf_n[i]=vp_conf_q[i];
    for(i=0;i<16;i=i+1) r_vpred_n[i]=r_vpred_q[i];
    for(i=0;i<16;i=i+1) r_predval_n[i]=r_predval_q[i];
    for(i=0;i<16;i=i+1) r_ins_n[i]=r_ins_q[i];
    for(i=0;i<16;i=i+1) r_mask_n[i]=r_mask_q[i];
    for(i=0;i<16;i=i+1) r_cause_n[i]=r_cause_q[i];
    for(i=0;i<16;i=i+1) r_tval_n[i]=r_tval_q[i];
    // Default pulse outputs; state events register the work done at this edge.
    ev_fetch_n=0; ev_decode_n=0; ev_dispatch_n=0; ev_issue_n=0;
    ev_wb_n=0; ev_retire_n=0;ev_flush_n=0;
    pc_fetch_n=0;pc_decode_n=0;pc_dispatch_n=0;pc_issue_n=0;pc_wb_n=0;pc_retire_n=0;
    id_fetch_n=0;id_decode_n=0;id_dispatch_n=0;id_issue_n=0;id_wb_n=0;id_retire_n=0;
    mem_valid=0;mem_write=0;mem_addr=0;mem_wdata=0;mem_wstrb=0;
    decoded=0;illegal=0;operand_b=0;product=0;wanted_mask=0;forwarded_word=0;
    i=0;j=0;k=0;l=0;slot=0;chosen=-1;oldest=-1;phy=-1;iqslot=-1;idx=0;offset=0;
    wb_lane=0;issue_lane=0;dispatch_lane=0;decode_lane=0;fetch_lane=0;retire_lane=0;
    shift_d=0;shift_f=0;remaining=0;free_count=0;occupied=0;
    a=0;b=0;value=0;address=0;best_age=32'hffffffff;oldest_age=32'hffffffff;
    forward_age=0;ins=0;imm=0;op=0;rd=0;rs1=0;rs2=0;
    use_a=0;use_b=0;write_dst=0;ok=0;blocked=0;forward_ok=0;unknown_store=0;
    alu_used=0;mul_used=0;ls_used=0;taken=0;do_flush=0;keep_branch=0;
    cut_seq=0;redirect=0;target=0;pred=0;fetch_pc=0;fetch_hist=0;
    local_pred=0;global_pred=0;issue_limit=0;
    if(run && !halt_q && !trap_q) begin
        cycles_n=cycles_q+1;
        // Unrenamed scoreboard captures a ready old source value independently
        // from destination busy state (e.g. ADDI r1,r1,1 must not wait on itself).
        if(!RENAME) begin
            for(j=0;j<16;j=j+1) begin
                if(q_valid_q[j] && !q_ar_q[j] && ready_q[q_a_q[j]]) begin
                    q_ar_n[j]=1;q_a_val_n[j]=pv_q[q_a_q[j]];
                end
                if(q_valid_q[j] && !q_br_q[j] && ready_q[q_b_q[j]]) begin
                    q_br_n[j]=1;q_b_val_n[j]=pv_q[q_b_q[j]];
                end
            end
        end
        // RETIRE: only completed entries at the head become architectural state.
        // Stores are sent to memory here, never when issued speculatively.
        blocked=0;
        for(l=0;l<2;l=l+1) begin
            slot=head_n;
            if(!blocked && rcount_n!=0 && r_valid_n[slot] && r_done_q[slot]) begin
                if(r_fault_n[slot]) begin
                    trap_n=1;trap_pc_n=r_pc_n[slot];trap_cause_n=r_cause_n[slot];trap_value_n=r_tval_n[slot];blocked=1;
                    do_flush=1;cut_seq=r_seq_n[slot]-1;redirect=r_pc_n[slot];
                end else if(r_op_n[slot]==ST && (!mem_ready || mem_valid)) begin
                    blocked=1;
                end else begin
                    if(r_op_n[slot]==ST) begin
                        mem_valid=1;mem_write=1;mem_addr=r_addr_n[slot];mem_wdata=r_data_n[slot];mem_wstrb=r_mask_n[slot];
                    end
                    if(r_dst_n[slot]!=0) begin
                        arch_n[r_dst_n[slot]]=r_result_n[slot];
                        commap_n[r_dst_n[slot]]=r_phy_n[slot];
                        if(RENAME) free_n[r_old_n[slot]]=1;
                    end
                    ev_retire_n[l]=1;pc_retire_n[l*32+:32]=r_pc_n[slot];
                    id_retire_n[l*32+:32]=r_seq_n[slot];
                    retired_n=retired_n+1;
                    if(r_op_n[slot]==HALT) begin halt_n=1;blocked=1;end
                    r_valid_n[slot]=0;head_n=head_n+1'b1;rcount_n=rcount_n-1'b1;
                end
            end else blocked=1;
        end
        // WRITEBACK: multiplier and single-outstanding read response.
        // ALU completion is registered by the issue block below.
        if(m_valid_q[3] && r_valid_n[m_slot_q[3]] && r_seq_n[m_slot_q[3]]==m_seq_q[3]) begin
            slot=m_slot_q[3];value=m_value_q[3];
            r_result_n[slot]=value;r_done_n[slot]=1;
            if(r_dst_n[slot]!=0) begin pv_n[r_phy_n[slot]]=value;ready_n[r_phy_n[slot]]=1;end
            ev_wb_n[wb_lane]=1;pc_wb_n[wb_lane*32+:32]=r_pc_n[slot];
            id_wb_n[wb_lane*32+:32]=r_seq_n[slot];wb_lane=wb_lane+1;
            idx=r_pc_n[slot][5:2];
            reuse_valid_n[idx]=1;reuse_pc_n[idx]=m_pc_q[3];reuse_value_n[idx]=value;
            reuse_a_n[idx]=m_a_q[3];reuse_b_n[idx]=m_b_q[3];
        end
        for(j=3;j>0;j=j-1) begin
            m_valid_n[j]=m_valid_q[j-1];m_slot_n[j]=m_slot_q[j-1];
            m_seq_n[j]=m_seq_q[j-1];m_value_n[j]=m_value_q[j-1];
            m_pc_n[j]=m_pc_q[j-1];m_a_n[j]=m_a_q[j-1];m_b_n[j]=m_b_q[j-1];
        end
        m_valid_n[0]=0;
        if(load_busy_q && mem_resp_valid) begin
            load_busy_n=0;slot=load_slot_q;
            if(r_valid_n[slot] && r_seq_n[slot]==load_seq_q) begin
                value=load_value(mem_resp_data,r_addr_n[slot],r_ins_n[slot][14:12]);r_result_n[slot]=value;r_done_n[slot]=1;
                r_fault_n[slot]=mem_resp_fault;
                if(mem_resp_fault) begin r_cause_n[slot]=5;r_tval_n[slot]=r_addr_n[slot];end
                if(r_vpred_n[slot] && value!=r_predval_n[slot] && !mem_resp_fault) begin
                    value_misses_n=value_misses_n+1;
                    if(!do_flush || r_seq_n[slot]<cut_seq) begin
                        do_flush=1;keep_branch=1;cut_seq=r_seq_n[slot];redirect=r_pc_n[slot]+4;
                    end
                end else if(r_vpred_n[slot] && !mem_resp_fault) value_hits_n=value_hits_n+1;
                if(r_dst_n[slot]!=0) begin pv_n[r_phy_n[slot]]=value;ready_n[r_phy_n[slot]]=1;end
                ev_wb_n[wb_lane]=1;pc_wb_n[wb_lane*32+:32]=r_pc_n[slot];
                id_wb_n[wb_lane*32+:32]=r_seq_n[slot];wb_lane=wb_lane+1;
                idx=r_pc_n[slot][5:2];
                if(vp_valid_n[idx] && vp_pc_n[idx]==r_pc_n[slot] && vp_value_n[idx]==value)
                    vp_conf_n[idx]=train(vp_conf_n[idx],1);
                else vp_conf_n[idx]=0;
                vp_valid_n[idx]=1;vp_pc_n[idx]=r_pc_n[slot];vp_value_n[idx]=value;
            end
        end
        // ISSUE: pick oldest ready instruction (OOO) or the oldest waiting one.
        // Operand readiness is a tag-indexed wakeup table, fed by writeback/bypass.
        // Two-wide global selection. Resources: 2 ALUs, 1 MUL, 1 LSU.
        // Issued operands are sampled before any issue result: no zero-cycle ALU chain.
        issue_limit=seq_q;
        for(l=0;l<2;l=l+1) begin
            chosen=-1;oldest=-1;best_age=32'hffffffff;oldest_age=32'hffffffff;
            for(j=0;j<16;j=j+1) begin
                if(q_valid_n[j] && q_seq_n[j]<oldest_age) begin oldest=j;oldest_age=q_seq_n[j];end
            end
            for(j=0;j<16;j=j+1) begin
                ok=q_valid_n[j] && (!q_use_a_n[j] || (RENAME?ready_q[q_a_n[j]]:q_ar_q[j])) &&
                   (!q_use_b_n[j] || (RENAME?ready_q[q_b_n[j]]:q_br_q[j]));
                op=q_op_n[j];slot=q_slot_n[j];
                if(is_mul(op) && mul_used) ok=0;
                if((op==LD || op==ST) && ls_used) ok=0;
                if(op==FENCE && q_seq_n[j]!=r_seq_n[head_n]) ok=0;
                if(op==LD || op==ST) begin
                    for(k=0;k<16;k=k+1)
                        if(r_valid_n[k] && r_seq_n[k]<q_seq_n[j] && r_op_n[k]==FENCE) ok=0;
                end
                if(op==LD) begin
                    if(load_busy_n || mem_valid || !mem_ready) ok=0;
                    address=(RENAME?pv_q[q_a_n[j]]:q_a_val_q[j])+q_imm_n[j];
                    wanted_mask=byte_mask(address,r_ins_n[slot][14:12]);
                    for(k=0;k<16;k=k+1) begin
                        if(r_valid_n[k] && r_seq_n[k]<q_seq_n[j] && r_op_n[k]==ST &&
                           !r_addr_ready_n[k] && !MEM_SPEC) ok=0;
                        // A partially overlapping store waits for retirement; do not
                        // manufacture a full word from incomplete forwarded bytes.
                        if(r_valid_n[k] && r_seq_n[k]<q_seq_n[j] && r_op_n[k]==ST && r_addr_ready_n[k] &&
                           r_addr_n[k][31:2]==address[31:2] &&
                           (r_mask_n[k] & wanted_mask)!=0 &&
                           (r_mask_n[k] & wanted_mask)!=wanted_mask) ok=0;
                    end
                end
                if(!OOO && j!=oldest) ok=0;
                if(do_flush || halt_n || trap_n) ok=0;
                if(ok && q_seq_n[j]<best_age) begin chosen=j;best_age=q_seq_n[j];end
            end
            if(chosen>=0) begin
                j=chosen;slot=q_slot_n[j];op=q_op_n[j];
                a=RENAME?pv_q[q_a_n[j]]:q_a_val_q[j];
                b=RENAME?pv_q[q_b_n[j]]:q_b_val_q[j];imm=q_imm_n[j];value=0;
                operand_b=q_use_b_n[j]?b:imm;
                q_valid_n[j]=0;
                ev_issue_n[l]=1;pc_issue_n[l*32+:32]=q_pc_n[j];
                id_issue_n[l*32+:32]=q_seq_n[j];issued_n=issued_n+1;
                if(q_seq_n[j]>oldest_age) bypassed_n=bypassed_n+1;
                case(op)
                    ADD:value=a+operand_b;
                    ADDI:value=a+imm;
                    XOR_:value=a^operand_b;
                    OR_:value=a|operand_b;
                    AND_:value=a&operand_b;
                    SLT:value=($signed(a)<$signed(operand_b));
                    SLTU:value=(a<operand_b);
                    SLL:value=a<<operand_b[4:0];
                    SRL:value=a>>operand_b[4:0];
                    SRA:value=$signed(a)>>>operand_b[4:0];
                    LUI:value=imm;
                    AUIPC:value=q_pc_n[j]+imm;
                    SUB:value=a-b;
                    MUL,MULH,MULHSU,MULHU:begin
                        mul_used=1;idx=q_pc_n[j][5:2];
                        if(REUSE && reuse_valid_q[idx] && reuse_pc_q[idx]==q_pc_n[j] &&
                           reuse_a_q[idx]==a && reuse_b_q[idx]==b) begin
                            value=reuse_value_q[idx];reuse_hits_n=reuse_hits_n+1;
                        end else begin
                            m_valid_n[0]=1;m_slot_n[0]=slot;m_seq_n[0]=q_seq_n[j];
                            if(op==MULHU) product=$signed({1'b0,a})*$signed({1'b0,b});
                            else if(op==MULHSU) product=$signed({a[31],a})*$signed({1'b0,b});
                            else product=$signed({a[31],a})*$signed({b[31],b});
                            m_value_n[0]=(op==MUL)?product[31:0]:product[63:32];
                            m_pc_n[0]=q_pc_n[j];m_a_n[0]=a;m_b_n[0]=b;
                        end
                    end
                    LD:begin
                        ls_used=1;address=a+imm;r_mask_n[slot]=byte_mask(address,r_ins_n[slot][14:12]);
                        r_addr_n[slot]=address;r_addr_ready_n[slot]=1;r_load_exec_n[slot]=1;
                        forward_ok=0;forward_age=0;forwarded_word=0;
                        for(k=0;k<16;k=k+1) begin
                            if(r_valid_n[k] && r_seq_n[k]<q_seq_n[j] && r_op_n[k]==ST &&
                               r_addr_ready_n[k] && r_addr_n[k][31:2]==address[31:2] &&
                               (r_mask_n[k] & r_mask_n[slot])==r_mask_n[slot] && r_seq_n[k]>forward_age) begin
                                forward_ok=1;forward_age=r_seq_n[k];forwarded_word=r_data_n[k];
                            end
                        end
                        // Cannot forward through an unresolved intervening store.
                        for(k=0;k<16;k=k+1) begin
                            if(r_valid_n[k] && r_seq_n[k]<q_seq_n[j] && r_op_n[k]==ST &&
                               !r_addr_ready_n[k] && r_seq_n[k]>forward_age) forward_ok=0;
                        end
                        if(misaligned(address,r_ins_n[slot][14:12]) || (address<4096 || address>=5120)) begin
                            r_fault_n[slot]=1;r_cause_n[slot]=misaligned(address,r_ins_n[slot][14:12])?4:5;
                            r_tval_n[slot]=address;value=0;
                        end else if(forward_ok) begin forwarded_n=forwarded_n+1;value=load_value(forwarded_word,address,r_ins_n[slot][14:12]);end
                        else begin
                            mem_valid=1;mem_write=0;mem_addr=address;
                            load_busy_n=1;load_slot_n=slot;load_seq_n=q_seq_n[j];
                            idx=q_pc_n[j][5:2];
                            if(VALUE_PRED && RENAME && vp_valid_q[idx] && vp_pc_q[idx]==q_pc_n[j] && vp_conf_q[idx]==3 && r_dst_n[slot]!=0) begin
                                r_vpred_n[slot]=1;r_predval_n[slot]=vp_value_q[idx];
                                pv_n[r_phy_n[slot]]=vp_value_q[idx];ready_n[r_phy_n[slot]]=1;
                            end
                        end
                    end
                    ST:begin
                        ls_used=1;address=a+imm;r_mask_n[slot]=byte_mask(address,r_ins_n[slot][14:12]);r_addr_n[slot]=address;r_data_n[slot]=b<<(8*address[1:0]);r_addr_ready_n[slot]=1;
                        r_fault_n[slot]=misaligned(address,r_ins_n[slot][14:12]) || (address<4096 || address>=5120);
                        r_cause_n[slot]=misaligned(address,r_ins_n[slot][14:12])?6:7;r_tval_n[slot]=address;
                        // An older store discovered an alias with a younger executed load.
                        if(MEM_SPEC) begin
                            for(k=0;k<16;k=k+1) begin
                                if(r_valid_n[k] && r_op_n[k]==LD && r_load_exec_n[k] &&
                                   r_seq_n[k]>q_seq_n[j] && r_addr_n[k][31:2]==address[31:2] &&
                                   (r_mask_n[k] & r_mask_n[slot])!=0) begin
                                    if(!do_flush || r_seq_n[k]-1<cut_seq) begin
                                        do_flush=1;keep_branch=0;cut_seq=r_seq_n[k]-1;
                                        redirect=r_pc_n[k];replays_n=replays_n+1;
                                    end
                                end
                            end
                        end
                    end
                    BNE,JAL,JR:begin
                        taken=1;
                        if(op==BNE) case(r_ins_n[slot][14:12])
                            0:taken=(a==b);1:taken=(a!=b);
                            4:taken=($signed(a)<$signed(b));5:taken=($signed(a)>=$signed(b));
                            6:taken=(a<b);7:taken=(a>=b);
                            default:taken=0;
                        endcase
                        if(op==JR) target=(a+imm)&32'hfffffffe;
                        else target=q_pc_n[j]+imm;
                        if(!taken) target=q_pc_n[j]+4;
                        if(op==JAL || op==JR) value=q_pc_n[j]+4;
                        if(target[1:0]!=0) begin r_fault_n[slot]=1;r_cause_n[slot]=0;r_tval_n[slot]=target;end
                        branches_n=branches_n+1;idx=q_pc_n[j][7:2];
                        if(op==BNE) begin
                            local_pred={1'b0,local_ctr_q[local_hist_q[idx]][1]};
                            global_pred={1'b0,gsh_q[idx^r_hist_n[slot]][1]};
                            bim_n[idx]=train(bim_n[idx],taken);
                            gsh_n[idx^r_hist_n[slot]]=train(gsh_n[idx^r_hist_n[slot]],taken);
                            local_ctr_n[local_hist_q[idx]]=train(local_ctr_n[local_hist_q[idx]],taken);
                            local_hist_n[idx]={local_hist_q[idx][4:0],taken};
                            if(local_pred!=global_pred) chooser_n[idx]=train(chooser_n[idx],global_pred[0]==taken);
                        end
                        btb_valid_n[idx]=1;btb_tag_n[idx]=q_pc_n[j][31:8];btb_target_n[idx]=target;
                        if(target!=r_pred_n[slot]) begin
                            mispredicts_n=mispredicts_n+1;
                            if(!do_flush || q_seq_n[j]<cut_seq) begin
                                do_flush=1;keep_branch=1;cut_seq=q_seq_n[j];redirect=target;
                                ghr_n=(op==BNE)?{r_hist_n[slot][4:0],taken}:r_hist_n[slot];
                            end
                        end
                    end
                    default:value=0;
                endcase
                if((!is_mul(op) || !m_valid_n[0] || m_seq_n[0]!=q_seq_n[j]) &&
                   (op!=LD || !load_busy_n || load_seq_n!=q_seq_n[j])) begin
                    r_result_n[slot]=value;r_done_n[slot]=1;
                    if(r_dst_n[slot]!=0) begin pv_n[r_phy_n[slot]]=value;ready_n[r_phy_n[slot]]=1;end
                    ev_wb_n[wb_lane]=1;pc_wb_n[wb_lane*32+:32]=r_pc_n[slot];
                    id_wb_n[wb_lane*32+:32]=r_seq_n[slot];wb_lane=wb_lane+1;
                end
            end else if(oldest>=0 && l==0) begin
                if(!ready_q[q_a_n[oldest]] || !ready_q[q_b_n[oldest]]) stall_raw_n=stall_raw_n+1;
                else stall_mem_n=stall_mem_n+1;
            end
        end
        // DISPATCH / RENAME: bind sources before changing destination mappings.
        // OOO=0 still retains renaming and the ROB for a controlled scheduling comparison.
        blocked=0;shift_d=0;
        for(l=0;l<2;l=l+1) begin
            if(l<dc_q && !blocked && !do_flush && !halt_n && !trap_n) begin
                ins=d_ins_q[l];decoded=decode_rv(ins);
                {illegal,write_dst,use_a,use_b,op,rd,rs1,rs2,imm}=decoded;
                write_dst=write_dst && rd!=0 && !illegal;
                iqslot=-1;phy=-1;
                for(j=15;j>=0;j=j-1) if(!q_valid_n[j]) iqslot=j;
                for(j=63;j>=1;j=j-1) if(free_n[j]) phy=j;
                ok=(rcount_n<16 && iqslot>=0 && (!write_dst || !RENAME || phy>=0));
                // Scoreboard mode removes renaming and blocks WAR and WAW at dispatch.
                if(!RENAME && write_dst) begin
                    phy=rd;
                    for(j=0;j<16;j=j+1) begin
                        if(r_valid_n[j] && r_dst_n[j]==rd) ok=0;
                        if(q_valid_n[j] && ((q_use_a_n[j] && q_a_n[j]==rd) || (q_use_b_n[j] && q_b_n[j]==rd))) ok=0;
                    end
                end
                if(ok) begin
                    slot=tail_n;tail_n=tail_n+1'b1;rcount_n=rcount_n+1'b1;
                    r_valid_n[slot]=1;r_done_n[slot]=0;
                    r_ins_n[slot]=ins;r_fault_n[slot]=illegal || op==ECALL || op==EBREAK || d_pc_q[l][1:0]!=0 || d_pc_q[l]>=1024;
                    r_cause_n[slot]=illegal?2:op==EBREAK?3:11;r_tval_n[slot]=illegal?ins:op==EBREAK?d_pc_q[l]:0;
                    if(d_pc_q[l]>=1024) begin r_cause_n[slot]=1;r_tval_n[slot]=d_pc_q[l];end
                    if(d_pc_q[l][1:0]!=0) begin r_cause_n[slot]=0;r_tval_n[slot]=d_pc_q[l];end
                    r_pc_n[slot]=d_pc_q[l];r_seq_n[slot]=d_id_q[l];r_op_n[slot]=op;
                    r_dst_n[slot]=write_dst?rd:0;r_phy_n[slot]=write_dst?phy:0;
                    r_old_n[slot]=write_dst?rat_n[rd]:0;
                    r_pred_n[slot]=d_pred_q[l];r_hist_n[slot]=d_hist_q[l];
                    r_addr_ready_n[slot]=0;r_load_exec_n[slot]=0;r_vpred_n[slot]=0;
                    q_valid_n[iqslot]=1;q_slot_n[iqslot]=slot;q_seq_n[iqslot]=d_id_q[l];
                    q_op_n[iqslot]=op;q_a_n[iqslot]=use_a?rat_n[rs1]:0;
                    q_b_n[iqslot]=use_b?rat_n[rs2]:0;
                    q_use_a_n[iqslot]=use_a;q_use_b_n[iqslot]=use_b;
                    q_ar_n[iqslot]=!use_a || ready_n[q_a_n[iqslot]];
                    q_br_n[iqslot]=!use_b || ready_n[q_b_n[iqslot]];
                    q_a_val_n[iqslot]=pv_n[q_a_n[iqslot]];q_b_val_n[iqslot]=pv_n[q_b_n[iqslot]];
                    q_imm_n[iqslot]=imm;q_pc_n[iqslot]=d_pc_q[l];
                    if(write_dst) begin rat_n[rd]=phy;ready_n[phy]=0;free_n[phy]=0;end
                    ev_dispatch_n[l]=1;pc_dispatch_n[l*32+:32]=d_pc_q[l];id_dispatch_n[l*32+:32]=d_id_q[l];
                    shift_d=shift_d+1;
                end else begin blocked=1;stall_dispatch_n=stall_dispatch_n+1;end
            end
        end
        if(!do_flush) begin
            for(j=0;j<4;j=j+1) begin
                if(j+shift_d<4) begin
                    d_ins_n[j]=d_ins_q[j+shift_d];d_pc_n[j]=d_pc_q[j+shift_d];d_id_n[j]=d_id_q[j+shift_d];
                    d_pred_n[j]=d_pred_q[j+shift_d];d_hist_n[j]=d_hist_q[j+shift_d];
                end
            end
            dc_n=dc_q-shift_d;
            // DECODE: fixed 32-bit RISC encoding, one instruction -> one operation.
            shift_f=0;
            for(l=0;l<2;l=l+1) begin
                if(l<fc_q && dc_n<4 && !halt_n && !trap_n) begin
                    idx=dc_n;d_ins_n[idx]=f_ins_q[l];d_pc_n[idx]=f_pc_q[l];d_id_n[idx]=f_id_q[l];
                    d_pred_n[idx]=f_pred_q[l];d_hist_n[idx]=f_hist_q[l];dc_n=dc_n+1;
                    ev_decode_n[l]=1;pc_decode_n[l*32+:32]=f_pc_q[l];id_decode_n[l*32+:32]=f_id_q[l];shift_f=shift_f+1;
                end
            end
            for(j=0;j<4;j=j+1) begin
                if(j+shift_f<4) begin
                    f_ins_n[j]=f_ins_q[j+shift_f];f_pc_n[j]=f_pc_q[j+shift_f];f_id_n[j]=f_id_q[j+shift_f];
                    f_pred_n[j]=f_pred_q[j+shift_f];f_hist_n[j]=f_hist_q[j+shift_f];
                end
            end
            fc_n=fc_q-shift_f;
            // FETCH: two contiguous instructions, end bundle at any control transfer.
            blocked=stop_q;fetch_pc=pc_q;fetch_hist=ghr_n;
            for(l=0;l<2;l=l+1) begin
                if(!blocked && fc_n<4 && !halt_n && !trap_n) begin
                    ins=(l==0)?imem_ins0:imem_ins1;decoded=decode_rv(ins);
                    {illegal,write_dst,use_a,use_b,op,rd,rs1,rs2,imm}=decoded;
                    target=fetch_pc+imm;pred=fetch_pc+4;
                    if(op==BNE) begin
                        taken=predict_taken(fetch_pc,target,fetch_hist);
                        pred=taken?target:fetch_pc+4;fetch_hist={fetch_hist[4:0],taken};blocked=1;
                    end else if(op==JAL) begin pred=target;blocked=1;end
                    else if(op==JR) begin
                        idx=fetch_pc[7:2];
                        if(btb_valid_q[idx] && btb_tag_q[idx]==fetch_pc[31:8]) pred=btb_target_q[idx];
                        blocked=1;
                    end else if(op==ECALL || op==EBREAK || illegal) begin stop_n=1;blocked=1;end
                    idx=fc_n;f_ins_n[idx]=ins;f_pc_n[idx]=fetch_pc;f_id_n[idx]=seq_n;
                    f_pred_n[idx]=pred;f_hist_n[idx]=ghr_n;ghr_n=fetch_hist;fc_n=fc_n+1;
                    ev_fetch_n[l]=1;pc_fetch_n[l*32+:32]=fetch_pc;id_fetch_n[l*32+:32]=seq_n;
                    seq_n=seq_n+1;fetch_pc=pred;pc_n=pred;
                end
            end
        end
        // RECOVERY: squash younger work, kill multiplier entries, rebuild rename/free
        // state from the committed map and surviving ROB in program order.
        // Sequence check rejects a late response from a squashed load (single MSHR).
        if(do_flush) begin
            ev_flush_n=1;flush_seq_n=cut_seq;fc_n=0;dc_n=0;pc_n=redirect;stop_n=0;
            remaining=0;
            for(j=0;j<16;j=j+1) begin
                if(r_valid_n[j] && r_seq_n[j]>cut_seq) r_valid_n[j]=0;
                if(q_valid_n[j] && q_seq_n[j]>cut_seq) q_valid_n[j]=0;
                if(r_valid_n[j]) remaining=remaining+1;
            end
            for(j=0;j<4;j=j+1) if(m_valid_n[j] && m_seq_n[j]>cut_seq) m_valid_n[j]=0;
            rcount_n=remaining;tail_n=head_n+remaining;
            for(j=0;j<64;j=j+1) free_n[j]=(j!=0);
            for(j=0;j<32;j=j+1) begin
                rat_n[j]=commap_n[j];free_n[commap_n[j]]=0;
                if(!RENAME) begin pv_n[j]=arch_n[j];ready_n[j]=1;end
            end
            for(j=0;j<16;j=j+1) begin
                slot=(head_n+j)&15;
                if(j<remaining && r_valid_n[slot] && r_dst_n[slot]!=0) begin
                    rat_n[r_dst_n[slot]]=r_phy_n[slot];free_n[r_phy_n[slot]]=0;
                    if(RENAME) free_n[r_old_n[slot]]=0;
                    else begin
                        pv_n[r_phy_n[slot]]=r_result_n[slot];ready_n[r_phy_n[slot]]=r_done_n[slot];
                    end
                end
            end
        end
        pv_n[0]=0;ready_n[0]=1;rat_n[0]=0;commap_n[0]=0;arch_n[0]=0;free_n[0]=0;
    end

end
integer state_i;
always @(posedge clk) begin
    if(reset) begin
        for(state_i=0;state_i<16;state_i=state_i+1) r_ins_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_mask_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_cause_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_tval_q[state_i]<=0;
        pc_q<=0;trap_cause_q<=0;trap_value_q<=0;
        seq_q<=1;
        head_q<=0;
        tail_q<=0;
        rcount_q<=0;
        fc_q<=0;
        dc_q<=0;
        stop_q<=0;
        halt_q<=0;
        trap_q<=0;
        trap_pc_q<=0;
        load_busy_q<=0;
        load_slot_q<=0;
        load_seq_q<=0;
        ghr_q<=0;
        cycles_q<=0;
        retired_q<=0;
        issued_q<=0;
        bypassed_q<=0;
        mispredicts_q<=0;
        branches_q<=0;
        forwarded_q<=0;
        replays_q<=0;
        stall_raw_q<=0;
        stall_mem_q<=0;
        stall_dispatch_q<=0;
        reuse_hits_q<=0;
        value_hits_q<=0;
        value_misses_q<=0;
        ev_fetch_q<=0;
        pc_fetch_q<=0;
        id_fetch_q<=0;
        ev_decode_q<=0;
        pc_decode_q<=0;
        id_decode_q<=0;
        ev_dispatch_q<=0;
        pc_dispatch_q<=0;
        id_dispatch_q<=0;
        ev_issue_q<=0;
        pc_issue_q<=0;
        id_issue_q<=0;
        ev_wb_q<=0;
        pc_wb_q<=0;
        id_wb_q<=0;
        ev_retire_q<=0;
        pc_retire_q<=0;
        id_retire_q<=0;
        ev_flush_q<=0;
        flush_seq_q<=0;
        for(state_i=0;state_i<32;state_i=state_i+1) rat_q[state_i]<=state_i;
        for(state_i=0;state_i<32;state_i=state_i+1) commap_q[state_i]<=state_i;
        for(state_i=0;state_i<32;state_i=state_i+1) arch_q[state_i]<=0;
        for(state_i=0;state_i<64;state_i=state_i+1) pv_q[state_i]<=0;
        for(state_i=0;state_i<64;state_i=state_i+1) ready_q[state_i]<=1;
        for(state_i=0;state_i<64;state_i=state_i+1) free_q[state_i]<=(state_i >= 32);
        for(state_i=0;state_i<4;state_i=state_i+1) f_ins_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) f_pc_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) f_id_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) f_pred_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) f_hist_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) d_ins_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) d_pc_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) d_id_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) d_pred_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) d_hist_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_valid_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_done_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_fault_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_pc_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_seq_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_op_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_dst_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_phy_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_old_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_result_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_addr_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_data_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_addr_ready_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_pred_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_hist_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_load_exec_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_valid_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_slot_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_seq_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_op_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_a_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_b_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_imm_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_use_a_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_use_b_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_pc_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_a_val_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_b_val_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_ar_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) q_br_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) m_valid_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) m_slot_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) m_seq_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) m_value_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) m_pc_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) m_a_q[state_i]<=0;
        for(state_i=0;state_i<4;state_i=state_i+1) m_b_q[state_i]<=0;
        for(state_i=0;state_i<64;state_i=state_i+1) bim_q[state_i]<=1;
        for(state_i=0;state_i<64;state_i=state_i+1) gsh_q[state_i]<=1;
        for(state_i=0;state_i<64;state_i=state_i+1) local_hist_q[state_i]<=0;
        for(state_i=0;state_i<64;state_i=state_i+1) local_ctr_q[state_i]<=1;
        for(state_i=0;state_i<64;state_i=state_i+1) chooser_q[state_i]<=1;
        for(state_i=0;state_i<64;state_i=state_i+1) btb_valid_q[state_i]<=0;
        for(state_i=0;state_i<64;state_i=state_i+1) btb_tag_q[state_i]<=0;
        for(state_i=0;state_i<64;state_i=state_i+1) btb_target_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) reuse_valid_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) reuse_pc_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) reuse_a_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) reuse_b_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) reuse_value_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) vp_valid_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) vp_pc_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) vp_value_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) vp_conf_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_vpred_q[state_i]<=0;
        for(state_i=0;state_i<16;state_i=state_i+1) r_predval_q[state_i]<=0;
    end else begin
        for(state_i=0;state_i<16;state_i=state_i+1) r_ins_q[state_i]<=r_ins_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_mask_q[state_i]<=r_mask_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_cause_q[state_i]<=r_cause_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_tval_q[state_i]<=r_tval_n[state_i];
        pc_q<=pc_n;trap_cause_q<=trap_cause_n;trap_value_q<=trap_value_n;
        seq_q<=seq_n;
        head_q<=head_n;
        tail_q<=tail_n;
        rcount_q<=rcount_n;
        fc_q<=fc_n;
        dc_q<=dc_n;
        stop_q<=stop_n;
        halt_q<=halt_n;
        trap_q<=trap_n;
        trap_pc_q<=trap_pc_n;
        load_busy_q<=load_busy_n;
        load_slot_q<=load_slot_n;
        load_seq_q<=load_seq_n;
        ghr_q<=ghr_n;
        cycles_q<=cycles_n;
        retired_q<=retired_n;
        issued_q<=issued_n;
        bypassed_q<=bypassed_n;
        mispredicts_q<=mispredicts_n;
        branches_q<=branches_n;
        forwarded_q<=forwarded_n;
        replays_q<=replays_n;
        stall_raw_q<=stall_raw_n;
        stall_mem_q<=stall_mem_n;
        stall_dispatch_q<=stall_dispatch_n;
        reuse_hits_q<=reuse_hits_n;
        value_hits_q<=value_hits_n;
        value_misses_q<=value_misses_n;
        ev_fetch_q<=ev_fetch_n;
        pc_fetch_q<=pc_fetch_n;
        id_fetch_q<=id_fetch_n;
        ev_decode_q<=ev_decode_n;
        pc_decode_q<=pc_decode_n;
        id_decode_q<=id_decode_n;
        ev_dispatch_q<=ev_dispatch_n;
        pc_dispatch_q<=pc_dispatch_n;
        id_dispatch_q<=id_dispatch_n;
        ev_issue_q<=ev_issue_n;
        pc_issue_q<=pc_issue_n;
        id_issue_q<=id_issue_n;
        ev_wb_q<=ev_wb_n;
        pc_wb_q<=pc_wb_n;
        id_wb_q<=id_wb_n;
        ev_retire_q<=ev_retire_n;
        pc_retire_q<=pc_retire_n;
        id_retire_q<=id_retire_n;
        ev_flush_q<=ev_flush_n;
        flush_seq_q<=flush_seq_n;
        for(state_i=0;state_i<32;state_i=state_i+1) rat_q[state_i]<=rat_n[state_i];
        for(state_i=0;state_i<32;state_i=state_i+1) commap_q[state_i]<=commap_n[state_i];
        for(state_i=0;state_i<32;state_i=state_i+1) arch_q[state_i]<=arch_n[state_i];
        for(state_i=0;state_i<64;state_i=state_i+1) pv_q[state_i]<=pv_n[state_i];
        for(state_i=0;state_i<64;state_i=state_i+1) ready_q[state_i]<=ready_n[state_i];
        for(state_i=0;state_i<64;state_i=state_i+1) free_q[state_i]<=free_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) f_ins_q[state_i]<=f_ins_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) f_pc_q[state_i]<=f_pc_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) f_id_q[state_i]<=f_id_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) f_pred_q[state_i]<=f_pred_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) f_hist_q[state_i]<=f_hist_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) d_ins_q[state_i]<=d_ins_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) d_pc_q[state_i]<=d_pc_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) d_id_q[state_i]<=d_id_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) d_pred_q[state_i]<=d_pred_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) d_hist_q[state_i]<=d_hist_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_valid_q[state_i]<=r_valid_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_done_q[state_i]<=r_done_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_fault_q[state_i]<=r_fault_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_pc_q[state_i]<=r_pc_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_seq_q[state_i]<=r_seq_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_op_q[state_i]<=r_op_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_dst_q[state_i]<=r_dst_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_phy_q[state_i]<=r_phy_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_old_q[state_i]<=r_old_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_result_q[state_i]<=r_result_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_addr_q[state_i]<=r_addr_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_data_q[state_i]<=r_data_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_addr_ready_q[state_i]<=r_addr_ready_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_pred_q[state_i]<=r_pred_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_hist_q[state_i]<=r_hist_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_load_exec_q[state_i]<=r_load_exec_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_valid_q[state_i]<=q_valid_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_slot_q[state_i]<=q_slot_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_seq_q[state_i]<=q_seq_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_op_q[state_i]<=q_op_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_a_q[state_i]<=q_a_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_b_q[state_i]<=q_b_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_imm_q[state_i]<=q_imm_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_use_a_q[state_i]<=q_use_a_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_use_b_q[state_i]<=q_use_b_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_pc_q[state_i]<=q_pc_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_a_val_q[state_i]<=q_a_val_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_b_val_q[state_i]<=q_b_val_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_ar_q[state_i]<=q_ar_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) q_br_q[state_i]<=q_br_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) m_valid_q[state_i]<=m_valid_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) m_slot_q[state_i]<=m_slot_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) m_seq_q[state_i]<=m_seq_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) m_value_q[state_i]<=m_value_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) m_pc_q[state_i]<=m_pc_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) m_a_q[state_i]<=m_a_n[state_i];
        for(state_i=0;state_i<4;state_i=state_i+1) m_b_q[state_i]<=m_b_n[state_i];
        for(state_i=0;state_i<64;state_i=state_i+1) bim_q[state_i]<=bim_n[state_i];
        for(state_i=0;state_i<64;state_i=state_i+1) gsh_q[state_i]<=gsh_n[state_i];
        for(state_i=0;state_i<64;state_i=state_i+1) local_hist_q[state_i]<=local_hist_n[state_i];
        for(state_i=0;state_i<64;state_i=state_i+1) local_ctr_q[state_i]<=local_ctr_n[state_i];
        for(state_i=0;state_i<64;state_i=state_i+1) chooser_q[state_i]<=chooser_n[state_i];
        for(state_i=0;state_i<64;state_i=state_i+1) btb_valid_q[state_i]<=btb_valid_n[state_i];
        for(state_i=0;state_i<64;state_i=state_i+1) btb_tag_q[state_i]<=btb_tag_n[state_i];
        for(state_i=0;state_i<64;state_i=state_i+1) btb_target_q[state_i]<=btb_target_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) reuse_valid_q[state_i]<=reuse_valid_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) reuse_pc_q[state_i]<=reuse_pc_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) reuse_a_q[state_i]<=reuse_a_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) reuse_b_q[state_i]<=reuse_b_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) reuse_value_q[state_i]<=reuse_value_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) vp_valid_q[state_i]<=vp_valid_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) vp_pc_q[state_i]<=vp_pc_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) vp_value_q[state_i]<=vp_value_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) vp_conf_q[state_i]<=vp_conf_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_vpred_q[state_i]<=r_vpred_n[state_i];
        for(state_i=0;state_i<16;state_i=state_i+1) r_predval_q[state_i]<=r_predval_n[state_i];
    end
end
endmodule
