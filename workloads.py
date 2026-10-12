"""Directed RV32I tests, seeded random programs and explicit Zmmul experiments."""
import random
from isa import enc as E,REG_OPS,IMM_OPS

def workloads():
    tests={}
    def add(name,code,why,data=None,mul=False,base=True):
        if base:code=[E('LUI',31,imm=1)]+code
        tests[name]=dict(code=code,why=why,data=list(data) if data is not None else [i*3+7 for i in range(256)],mul=mul)
    def L(rd,off=0,kind='LW',a=31):return E(kind,rd,a,imm=off)
    def S(b,off=0,kind='SW',a=31):return E(kind,a=a,b=b,imm=off)
    end=E('EBREAK')
    add('independent_work',[
        E('ADDI',7,imm=3),E('ADDI',8,imm=5),L(1),E('ADD',2,1,1),
        E('ADDI',5,imm=15),*[E('ADDI',5,5,imm=15) for _ in range(14)],
        E('ADDI',9,imm=19),E('ADDI',10,imm=23),E('ADD',6,2,5),S(6,256),end],
        'Pure RV32I: independent arithmetic can pass a cold-load-dependent instruction. Both modes produce x6=239 and RAM word64=239.')
    add('dependency_chain',[E('ADDI',1,imm=1),*[E('ADDI',1,1,imm=1) for _ in range(26)],end],
        'A true RAW dependence on every addition cannot be removed by scheduling.')
    add('retirement_bound',[L(1),E('ADD',2,1,1),*[E('ADDI',r,imm=r*7) for r in range(3,25)],S(2,256),end],
        'An old miss and two-wide retirement can dominate even when younger arithmetic executes early.')
    add('false_dependencies',[L(1),E('ADD',2,1,1),E('ADDI',1,imm=11),E('ADD',3,1,1),
        E('ADDI',1,imm=17),E('ADD',4,1,1),E('ADD',5,2,3),E('ADD',6,5,4),end],
        'Different live values reuse x1. Renaming preserves each producer while eliminating false dependencies.')
    add('branch_loop',[E('ADDI',1,imm=16),E('ADDI',2,imm=0),E('ADDI',3,imm=1),
        E('ADD',2,2,3),E('ADDI',1,1,imm=-1),E('BNE',a=1,imm=-8),S(2,256),end],
        'A backward loop trains direction prediction and then takes a not-taken exit.')
    add('wrong_path_store',[L(1),E('BNE',a=1,imm=16),E('ADDI',2,imm=999),S(2,256),
        E('ADDI',3,imm=333),E('ADDI',2,imm=23),S(2,260),end],
        'A store on the mispredicted path must never alter architectural memory.')
    add('store_forwarding',[L(1),E('ADD',2,1,1),E('ADDI',3,imm=77),S(3,128),L(4,128),E('ADD',5,2,4),end],
        'A load receives data from an older uncommitted matching store.')
    data=[i*3+7 for i in range(256)];data[0]=0x1040
    addrchain=[L(1),*[E('ADDI',2,1 if i==0 else 2,imm=0) for i in range(5)],E('ADDI',3,imm=91),S(3,a=2)]
    add('memory_alias_replay',addrchain+[L(4,64),E('ADD',5,4,4),end],
        'An unknown older store eventually aliases an executed load; memory speculation must replay it.',data)
    add('memory_no_alias',addrchain+[L(4,128),E('ADD',5,4,4),end],
        'An unknown older store resolves to a different word, allowing useful memory speculation.',data)
    add('cache_locality',[E('ADDI',1,imm=12),L(2,32),E('ADD',3,3,2),E('ADDI',1,1,imm=-1),E('BNE',a=1,imm=-12),end],
        'Repeated accesses to one address expose the data-cache hit delay.')
    add('value_prediction',[E('ADDI',1,imm=20),E('ADDI',6,imm=6),E('ADDI',7,imm=99),
        L(2,32),E('ADD',3,2,2),E('ADD',3,3,2),E('ADD',4,4,3),E('ADDI',1,1,imm=-1),
        E('BNE',a=1,b=6,imm=8),S(7,32),E('BNE',a=1,imm=-28),end],
        'Repeated loads train value prediction; a changed word exercises validation and consumer squash.')
    add('precise_load_fault',[E('ADDI',1,imm=13),S(1,256),L(0,1024),E('ADDI',3,imm=999),S(3,260),end],
        'Even a load into x0 must fault. Older stores commit and younger writes are suppressed.')
    add('precise_store_fault',[E('ADDI',1,imm=13),S(1,256),S(1,1024),E('ADDI',3,imm=999),S(3,260),end],
        'An out-of-range store faults precisely before younger architectural changes.')
    add('nested_recovery',[L(1),E('BNE',a=1,imm=20),E('ADDI',2,imm=1),E('BNE',a=2,imm=8),
        S(2,256),E('ADD',3,2,2),E('ADDI',4,imm=17),end],
        'A younger branch can resolve first; later recovery preserves the correct older prefix.')
    add('indirect_control',[E('JAL',1,imm=16),E('ADDI',2,imm=5),S(2,256),end,
        E('ADDI',3,imm=42),E('JALR',0,1,imm=1)],
        'JAL links to PC+4; JALR clears target bit0 before returning.')
    add('indirect_loop',[E('ADDI',2,imm=8),E('JAL',1,imm=20),E('ADDI',2,2,imm=-1),E('BNE',a=2,imm=-8),
        end,E('NOP'),E('ADDI',3,3,imm=1),E('JALR',0,1)],
        'Repeated calls and indirect returns exercise tagged BTB prediction.')
    add('squashed_load_response',[L(1),E('ADDI',2,1,imm=1),E('ADDI',2,2,imm=1),E('BNE',a=2,imm=16),
        L(3,32),S(3,256),end,L(4,36),E('ADDI',5,imm=23),end],
        'A read issued before branch resolution must not corrupt a reused ROB slot after squash.')
    add('all_registers',[*[E('ADDI',r,imm=r*11) for r in range(1,32)],
        *[E('ADD',1,1,r) for r in range(2,32)],E('ADDI',0,imm=999),end],
        'Exercise every x1..x31 register and hardwired x0.',base=False)
    alu=[E('LUI',1,imm=0x80000),E('ADDI',2,imm=-1),E('ADDI',3,imm=31),E('ADDI',4,imm=1),E('ADDI',5,imm=32)]
    for op in REG_OPS:
        if not op.startswith('MUL'):alu += [E(op,6,1,2),S(6,128),E(op,7,2,3),S(7,132),E(op,8,1,5),S(8,136)]
    for op in IMM_OPS:
        immediate=31 if op.endswith('LI') or op=='SRAI' else -1
        alu += [E(op,9,1,imm=immediate),S(9,140)]
    alu += [E('AUIPC',10,imm=0x80000),E('LUI',11,imm=0xfffff),E('ADDI',11,11,imm=2047),E('SLTI',12,11,imm=-2048),end]
    add('alu_semantics',alu,'Signed/unsigned comparisons, overflow, shifts masked to five bits, all immediate and register ALU forms, LUI and AUIPC.')
    for op,pairs in {'BEQ':[(1,2),(1,1)],'BNE':[(1,2),(1,1)],'BLT':[(1,2),(2,1)],
                      'BGE':[(1,2),(2,1)],'BLTU':[(1,2),(2,1)],'BGEU':[(1,2),(2,1)]}.items():
        code=[E('ADDI',1,imm=-1),E('ADDI',2,imm=1)]
        for a,b in pairs:code += [E(op,a=a,b=b,imm=8),E('ADDI',3,3,imm=1),E('ADDI',4,4,imm=2)]
        add('branch_'+op.lower(),code+[end],f'{op} exercised both taken and not taken with signed/unsigned boundary operands.')
    data=[i*3+7 for i in range(256)];data[0]=0x80ff7f01
    code=[]
    for kind,offsets in {'LB':range(4),'LBU':range(4),'LH':(0,2),'LHU':(0,2),'LW':(0,)}.items():
        for off in offsets:code += [L(2,off,kind),S(2,128+4*len(code)//2)]
    code += [E('ADDI',3,imm=-1),S(3,65,'SB'),L(4,64),S(3,66,'SH'),L(5,64),S(3,64),L(6,64),end]
    add('subword_memory',code,'Little-endian byte lanes, sign/zero extension, partial-store merge, and mixed-width ordering.',data)
    add('partial_forwarding',[L(1),E('ADDI',3,imm=-1),S(3,129,'SB'),L(4,129,'LB'),L(5,128),S(3,130,'SH'),L(6,128),end],
        'Forward a matching byte, but wait for retirement when a load needs additional bytes.')
    add('youngest_store',[L(1),E('ADDI',2,imm=11),S(2,128),E('ADDI',2,imm=77),S(2,128),L(3,128),end],
        'The youngest matching older store supplies the load, including WAW renaming.')
    add('fence_ordering',[L(1),E('ADDI',2,imm=73),S(2,128),E('FENCE'),L(3,128),S(3,132),end],
        'FENCE waits at the ROB head and prevents younger memory operations from passing it.')
    for kind in ('LH','LW'):
        add('misaligned_'+kind.lower(),[E('ADDI',2,imm=55),S(2,256),L(0,1,kind),S(2,260),end],'Misaligned loads report the load PC and effective byte address, including x0.')
    for kind in ('SH','SW'):
        add('misaligned_'+kind.lower(),[E('ADDI',2,imm=55),S(2,256),S(2,1,kind),S(2,260),end],'Misaligned stores trap without modifying any byte.')
    add('misaligned_jal',[E('ADDI',1,imm=55),E('JAL',1,imm=2),E('ADDI',1,imm=999),end], 'A misaligned taken jump faults on the jump; its link register remains unchanged.')
    add('misaligned_jalr',[E('ADDI',1,imm=55),E('ADDI',2,imm=2),E('JALR',1,2),end],'JALR clears bit0 but still checks four-byte instruction alignment.')
    add('misaligned_taken_branch',[E('ADDI',1,imm=1),E('BNE',a=1,imm=2),end],'A taken conditional branch reports a misaligned target.')
    add('misaligned_untaken_branch',[E('BNE',a=0,b=0,imm=2),E('ADDI',1,imm=77),end],'A not-taken branch does not raise target misalignment.')
    add('instruction_access_fault',[E('JAL',1,imm=1024)],'A valid jump commits its link before the target instruction-access fault.',base=False)
    add('negative_address',[E('LW',1,imm=-4),end],'Address addition wraps to 32 bits and an unmapped high address faults.',base=False)
    add('ecall',[E('ADDI',1,imm=42),E('ECALL'),E('ADDI',1,imm=999),end],'ECALL stops at retirement with the lab EEI cause11 and preserves older state.')
    for idx,w in enumerate([0,0xffffffff,0x02004033,0x0000100f,0x00002063,0x00003003,0x02001013,0x40006033,0xc0002073,0x00001067]):
        add(f'illegal_{idx}',[E('ADDI',1,imm=13),w,E('ADDI',1,imm=999),end], 'Reserved/unsupported encoding produces an illegal-instruction fault with the original instruction word.')
    add('multiply_disabled',[E('ADDI',1,imm=7),E('MUL',2,1,1),end],'Strict RV32I mode rejects multiply instructions.')
    add('multiply_semantics',[E('LUI',1,imm=0x80000),E('ADDI',2,imm=-1),
        *[E(op,r,1,2) for r,op in enumerate(('MUL','MULH','MULHSU','MULHU'),3)],
        *[E(op,r,2,2) for r,op in enumerate(('MUL','MULH','MULHSU','MULHU'),7)],end],
        'Optional Zmmul supports all four low/high signed/unsigned multiply forms.',mul=True)
    add('instruction_reuse',[E('ADDI',1,imm=14),E('ADDI',2,imm=9),E('ADDI',3,imm=11),
        E('MUL',4,2,3),E('ADD',5,5,4),E('ADDI',1,1,imm=-1),E('BNE',a=1,imm=-12),end],
        'Zmmul experiment: repeated identical products exercise exact reuse.',mul=True)
    for seed in range(12):
        rng=random.Random(seed);code=[E('LUI',1,imm=0x80000),E('ADDI',2,imm=-1)]
        for i in range(100):
            choice=rng.randrange(4);rd=rng.randint(1,30);a=rng.randrange(31);b=rng.randrange(31)
            if choice==0:code.append(E(rng.choice([n for n in REG_OPS if not n.startswith('MUL')]),rd,a,b))
            elif choice==1:
                op=rng.choice(list(IMM_OPS));im=rng.randrange(32) if op in ('SLLI','SRLI','SRAI') else rng.randint(-2048,2047)
                code.append(E(op,rd,a,imm=im))
            elif choice==2:
                op=rng.choice(('LB','LBU','LH','LHU','LW'));size=1 if op in ('LB','LBU') else 2 if op in ('LH','LHU') else 4
                code.append(L(rd,rng.randrange(128//size)*size,op))
            else:
                op=rng.choice(('SB','SH','SW'));size={'SB':1,'SH':2,'SW':4}[op]
                code.append(S(b,128+rng.randrange(128//size)*size,op))
        add(f'random_{seed}',code+[end],'Seeded full-register RV32I ALU and mixed-width memory regression with ROB wraparound.')
    return tests
