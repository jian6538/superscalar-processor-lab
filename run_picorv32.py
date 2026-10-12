"""Cross-check successful RV32I/Zmmul programs using pinned, unmodified PicoRV32.

This comparison uses the same code/data and cache. PicoRV32's scalar frontend and
bus protocol differ from the two-wide core, so it is not an isolated OoO A/B test.
"""
import argparse,json
from pathlib import Path
from run_lab import command
from reference import reference
from workloads import workloads
from isa import enc
ROOT=Path(__file__).resolve().parent

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--only');args=ap.parse_args()
    tests=workloads();runs=[];(ROOT/'build').mkdir(exist_ok=True);(ROOT/'results').mkdir(exist_ok=True)
    for mul in (False,True):
        chosen=[]
        for name,t in tests.items():
            if t['mul']!=mul or (args.only and name!=args.only):continue
            words=t['code']+[enc('EBREAK')]*(256-len(t['code']));ref=reference(words,t['data'],mul)
            if ref['cause']==3:chosen.append((name,t,ref,words))
        if not chosen:continue
        artifact=ROOT/'build'/f'picorv32_{int(mul)}.vvp';artifact.unlink(missing_ok=True)
        cmd=['iverilog','-g2012','-s','picorv32_tb','-o',str(artifact),f'-Ppicorv32_tb.ENABLE_MUL={int(mul)}',
             'third_party/picorv32/picorv32.v','rtl/data_cache.sv','rtl/picorv32_reference_system.sv','tb/picorv32_tb.sv']
        p=command(cmd)
        if not artifact.exists() or p.stderr.strip():raise RuntimeError(p.stdout+p.stderr)
        for name,t,ref,words in chosen:
            # Generate exactly the same standard instruction streams used by the lab.
            for suffix,values in (('.hex',words),('.data.hex',t['data'])):
                path=ROOT/'programs'/f'{name}{suffix}';content='\n'.join(f'{w:08x}' for w in values)+'\n'
                if not path.exists() or path.read_text()!=content:path.write_text(content)
            p=command(['vvp',str(artifact),f'+PROGRAM=programs/{name}.hex',f'+DATA=programs/{name}.data.hex'],60)
            (ROOT/'results'/f'{name}__picorv32.log').write_text(p.stdout.replace(str(ROOT),'.').replace(str(ROOT).replace('\\','/'),'.')+p.stderr)
            if p.returncode:raise RuntimeError(p.stdout+p.stderr)
            regs=[None]*32;mem=[None]*256;metrics=None
            for line in p.stdout.splitlines():
                parts=line.split(',')
                if parts[0]=='RESULT':metrics=dict(zip(('cycles','cache_hits','cache_misses'),map(int,parts[1:])))
                elif parts[0]=='REG':regs[int(parts[1])]=int(parts[2],16)
                elif parts[0]=='MEM':mem[int(parts[1])]=int(parts[2],16)
            if regs!=ref['regs']:raise AssertionError(f'{name}: Pico registers {regs} != {ref["regs"]}')
            if mem!=ref['memory']:raise AssertionError(f'{name}: Pico memory differs')
            runs.append(dict(workload=name,config='picorv32_zmmul' if mul else 'picorv32',metrics=metrics,regs=regs,memory=mem,verified=True))
            print(f'PASS PicoRV32 {name}: {metrics["cycles"]} cycles',flush=True)
    (ROOT/'results'/'picorv32_results.json').write_text(json.dumps(dict(upstream=json.loads((ROOT/'third_party'/'picorv32'/'UPSTREAM.json').read_text()),runs=runs),indent=2))
    print(f'{len(runs)} PicoRV32 cross-checks passed.',flush=True)
if __name__=='__main__':main()
