"""Standard RISC-V instruction encoder/disassembler; no custom ISA opcodes."""
MASK = 0xffffffff
REG_OPS = {'ADD':(0,0),'SUB':(0,32),'SLL':(1,0),'SLT':(2,0),'SLTU':(3,0),'XOR':(4,0),'SRL':(5,0),'SRA':(5,32),'OR':(6,0),'AND':(7,0),
           'MUL':(0,1),'MULH':(1,1),'MULHSU':(2,1),'MULHU':(3,1)}
IMM_OPS = {'ADDI':0,'SLLI':1,'SLTI':2,'SLTIU':3,'XORI':4,'SRLI':5,'SRAI':5,'ORI':6,'ANDI':7}
LOADS = {'LB':0,'LH':1,'LW':2,'LBU':4,'LHU':5}
STORES = {'SB':0,'SH':1,'SW':2}
BRANCHES = {'BEQ':0,'BNE':1,'BLT':4,'BGE':5,'BLTU':6,'BGEU':7}

def enc(op, rd=0, a=0, b=0, imm=0):
    assert 0<=rd<32 and 0<=a<32 and 0<=b<32
    if op=='NOP':return 0x13
    if op in {'ECALL','EBREAK','FENCE'}:return {'ECALL':0x73,'EBREAK':0x100073,'FENCE':0x0ff0000f}[op]
    if op in REG_OPS:
        f3,f7=REG_OPS[op];return f7<<25|b<<20|a<<15|f3<<12|rd<<7|0x33
    if op in {'LUI','AUIPC'}:
        assert 0<=imm<1<<20
        return imm<<12|rd<<7|({'LUI':0x37,'AUIPC':0x17}[op])
    if op in BRANCHES:
        assert imm%2==0 and -4096<=imm<=4094
        u=imm&8191
        return (u>>12&1)<<31|(u>>5&63)<<25|b<<20|a<<15|BRANCHES[op]<<12|(u>>1&15)<<8|(u>>11&1)<<7|0x63
    if op=='JAL':
        assert imm%2==0 and -(1<<20)<=imm<(1<<20)
        u=imm&0x1fffff
        return (u>>20&1)<<31|(u>>1&1023)<<21|(u>>11&1)<<20|(u>>12&255)<<12|rd<<7|0x6f
    if op in STORES:
        assert -2048<=imm<=2047
        u=imm&4095
        return (u>>5)<<25|b<<20|a<<15|STORES[op]<<12|(u&31)<<7|0x23
    if op in IMM_OPS or op in LOADS or op=='JALR':
        assert -2048<=imm<=2047
        u=imm&4095
        if op in {'SLLI','SRLI','SRAI'}:
            assert 0<=imm<32
            u=imm | (0x400 if op=='SRAI' else 0)
        f3=IMM_OPS.get(op,LOADS.get(op,0));opcode=0x03 if op in LOADS else 0x67 if op=='JALR' else 0x13
        return u<<20|a<<15|f3<<12|rd<<7|opcode
    raise ValueError(op)

def sext(value,bits):return (value&((1<<(bits-1))-1))-(value&(1<<(bits-1)))

def disassemble(w):
    opcode=w&127;rd=w>>7&31;f3=w>>12&7;a=w>>15&31;b=w>>20&31;f7=w>>25
    if w in {0x73,0x100073,0x0ff0000f}:return {0x73:'ECALL',0x100073:'EBREAK',0x0ff0000f:'FENCE'}[w]
    if opcode==0x33:
        op=next((n for n,v in REG_OPS.items() if v==(f3,f7)),'ILLEGAL')
        return f'{op} x{rd}, x{a}, x{b}'
    if opcode==0x13:
        op=next((n for n,v in IMM_OPS.items() if v==f3 and n!='SRAI'),'ILLEGAL')
        if f3==5 and f7==32:op='SRAI'
        immediate=(w>>20&31) if f3 in (1,5) else sext(w>>20,12)
        return f'{op} x{rd}, x{a}, {immediate}'
    if opcode in (0x37,0x17):return f'{"LUI" if opcode==0x37 else "AUIPC"} x{rd}, 0x{w>>12:x}'
    if opcode==0x03:
        op=next((n for n,v in LOADS.items() if v==f3),'ILLEGAL');return f'{op} x{rd}, {sext(w>>20,12)}(x{a})'
    if opcode==0x23:
        op=next((n for n,v in STORES.items() if v==f3),'ILLEGAL');return f'{op} x{b}, {sext((w>>25)<<5|(w>>7&31),12)}(x{a})'
    if opcode==0x63:
        op=next((n for n,v in BRANCHES.items() if v==f3),'ILLEGAL')
        u=(w>>31)<<12|(w>>7&1)<<11|(w>>25&63)<<5|(w>>8&15)<<1
        return f'{op} x{a}, x{b}, pc{sext(u,13):+d}'
    if opcode==0x6f:
        u=(w>>31)<<20|(w>>12&255)<<12|(w>>20&1)<<11|(w>>21&1023)<<1
        return f'JAL x{rd}, pc{sext(u,21):+d}'
    if opcode==0x67:return f'JALR x{rd}, {sext(w>>20,12)}(x{a})'
    return f'ILLEGAL 0x{w:08x}'
