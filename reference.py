"""Independent sequential RV32I/Zmmul interpreter for the lab execution environment.

The interpreter consumes raw instructions, not the RTL's internal operation codes.
Code is execute-only ROM [0,1024); data is little-endian RAM [0x1000,0x1400).
Exceptions stop execution and report (PC, cause, value); EBREAK is the test terminator.
"""
MASK=0xffffffff
def signed(x,bits=32):
    x &= (1<<bits)-1
    return x-(1<<bits) if x>>(bits-1) else x

def reference(words,data,enable_mul=False):
    regs=[0]*32;memory=bytearray().join((v&MASK).to_bytes(4,'little') for v in data)
    pc=0;pcs=[];instruction_names=[];fault=None
    for _ in range(20000):
        if pc&3:fault=(pc,0,pc);break
        if pc>=1024:fault=(pc,1,pc);break
        w=words[pc//4];code=w&127;rd=w>>7&31;f=w>>12&7;rs1=w>>15&31;rs2=w>>20&31;hi=w>>25
        a=regs[rs1];b=regs[rs2];im=signed(w>>20,12);nextpc=(pc+4)&MASK;write=False;value=0;name=''
        if code in (0x37,0x17):
            value=w&0xfffff000
            if code==0x17:value+=pc
            write=True;name='LUI' if code==0x37 else 'AUIPC'
        elif code==0x6f:
            off=signed((w>>31)<<20|(w>>12&255)<<12|(w>>20&1)<<11|(w>>21&1023)<<1,21)
            nextpc=(pc+off)&MASK;value=pc+4;write=True;name='JAL'
            if nextpc&3:fault=(pc,0,nextpc);break
        elif code==0x67 and f==0:
            nextpc=(a+im)&0xfffffffe;value=pc+4;write=True;name='JALR'
            if nextpc&3:fault=(pc,0,nextpc);break
        elif code==0x63 and f in (0,1,4,5,6,7):
            off=signed((w>>31)<<12|(w>>7&1)<<11|(w>>25&63)<<5|(w>>8&15)<<1,13)
            taken={0:a==b,1:a!=b,4:signed(a)<signed(b),5:signed(a)>=signed(b),6:a<b,7:a>=b}[f]
            name={0:'BEQ',1:'BNE',4:'BLT',5:'BGE',6:'BLTU',7:'BGEU'}[f]
            if taken:
                nextpc=(pc+off)&MASK
                if nextpc&3:fault=(pc,0,nextpc);break
        elif code in (0x03,0x23):
            load=code==3
            if (load and f not in (0,1,2,4,5)) or (not load and f not in (0,1,2)):
                fault=(pc,2,w);break
            if not load:im=signed((w>>25)<<5|(w>>7&31),12)
            address=(a+im)&MASK;size=1<<(f&3)
            if address%size:fault=(pc,4 if load else 6,address);break
            if not (0x1000<=address and address+size<=0x1400):
                fault=(pc,5 if load else 7,address);break
            offset=address-0x1000
            if load:
                value=int.from_bytes(memory[offset:offset+size],'little',signed=f<4);write=True
                name={0:'LB',1:'LH',2:'LW',4:'LBU',5:'LHU'}[f]
            else:
                memory[offset:offset+size]=(b&((1<<(8*size))-1)).to_bytes(size,'little')
                name={0:'SB',1:'SH',2:'SW'}[f]
        elif code in (0x13,0x33):
            write=True;y=im&MASK if code==0x13 else b
            if code==0x13 and f in (1,5):
                if hi not in ((0,) if f==1 else (0,32)):
                    fault=(pc,2,w);break
                y=w>>20&31
            if code==0x33 and hi==1:
                if not enable_mul or f>=4:fault=(pc,2,w);break
                if f==0:value=a*b;name='MUL'
                elif f==1:value=(signed(a)*signed(b))>>32;name='MULH'
                elif f==2:value=(signed(a)*b)>>32;name='MULHSU'
                else:value=(a*b)>>32;name='MULHU'
            elif code==0x33 and hi not in (0,32):fault=(pc,2,w);break
            elif code==0x33 and hi==32 and f not in (0,5):fault=(pc,2,w);break
            else:
                if f==0:value=a-y if code==0x33 and hi==32 else a+y;name='SUB' if code==0x33 and hi==32 else 'ADD'
                elif f==1:value=a<<(y&31);name='SLL'
                elif f==2:value=int(signed(a)<signed(y));name='SLT'
                elif f==3:value=int(a<y);name='SLTU'
                elif f==4:value=a^y;name='XOR'
                elif f==5:value=signed(a)>>(y&31) if hi==32 else a>>(y&31);name='SRA' if hi==32 else 'SRL'
                elif f==6:value=a|y;name='OR'
                else:value=a&y;name='AND'
                if code==0x13:name += 'I' if name not in ('SLT','SLTU') else ('I' if name=='SLT' else '')
                if code==0x13 and f==3:name='SLTIU'
        elif code==0x0f and f==0:name='FENCE'
        elif w==0x73:fault=(pc,11,0);break
        elif w==0x100073:fault=(pc,3,pc);break
        else:fault=(pc,2,w);break
        if write and rd:regs[rd]=value&MASK
        regs[0]=0;pcs.append(pc);instruction_names.append(name);pc=nextpc
    else:raise ValueError('reference did not terminate')
    return {'regs':regs,'memory':[int.from_bytes(memory[i:i+4],'little') for i in range(0,1024,4)],
            'pcs':pcs,'trap':fault[0],'cause':fault[1],'tval':fault[2],'instructions':instruction_names}
