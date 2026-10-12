"""Run synthesizable RV32I/Zmmul RTL and compare every architectural result."""
import argparse,csv,hashlib,json,os,subprocess
from pathlib import Path
from isa import enc,disassemble
from reference import reference
from workloads import workloads

ROOT=Path(__file__).resolve().parent
CONFIGS={
 'in_order':dict(OOO=0), 'out_of_order':dict(OOO=1),
 'scoreboard':dict(OOO=1,RENAME=0), 'memory_speculation':dict(OOO=1,MEM_SPEC=1),
 'value_prediction':dict(OOO=1,VALUE_PRED=1), 'cache_disabled':dict(OOO=1,CACHE_ENABLE=0),
 **{f'predictor_{i}':dict(OOO=1,PREDICTOR=i) for i in (0,1,3,4,5)},
 'in_order_zmmul':dict(OOO=0,ENABLE_MUL=1),
 'out_of_order_zmmul':dict(OOO=1,ENABLE_MUL=1), 'reuse':dict(OOO=1,ENABLE_MUL=1,REUSE=1),
 'all_options':dict(OOO=1,MEM_SPEC=1,VALUE_PRED=1,REUSE=1,ENABLE_MUL=1,PREDICTOR=5)}
KEYS=['cycles','retired','issued','bypassed','mispredicts','branches','forwarded','replays','reuse_hits','value_hits','value_misses',
      'raw_stalls','memory_stalls','dispatch_stalls','cache_hits','cache_misses','halted','trapped','fault_pc']

def command(args,timeout=120):
    return subprocess.run(args,cwd=ROOT,text=True,capture_output=True,timeout=timeout)

def compile_config(name,params):
    output=ROOT/'build'/f'{name}.vvp'
    output.unlink(missing_ok=True)
    cmd=['iverilog','-g2012','-s','tb','-o',str(output)]
    cmd += [f'-Ptb.{k}={v}' for k,v in params.items()]
    cmd += [str(ROOT/x) for x in ['rtl/core.sv','rtl/data_cache.sv','rtl/processor_system.sv','tb/tb.sv']]
    p=command(cmd)
    # A Windows Icarus launcher can return1 after generating valid output.
    # Reject diagnostics/stale output; actual vvp execution validates the result.
    if not output.exists() or output.stat().st_size<1000 or p.stderr.strip():
        raise RuntimeError(f'compile {name}: {p.stdout}\n{p.stderr}')
    return output,dict(returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)

def parse_trace(path):
    rows=[];retired=[]
    with path.open() as f:
        for row in csv.DictReader(f):
            mask=int(row['events'],16);pcs=int(row['pcs'],16);ids=int(row['ids'],16);events=[];offset=0
            for stage,n in [('fetch',2),('decode',2),('dispatch',2),('issue',2),('wb',4),('retire',2)]:
                for lane in range(n):
                    bit=offset+lane
                    if mask>>bit&1:
                        pc=pcs>>(32*bit)&0xffffffff;seq=ids>>(32*bit)&0xffffffff
                        events.append([stage,seq,pc])
                        if stage=='retire':retired.append(pc)
                offset+=n
            rows.append(dict(cycle=int(row['cycle']),events=events,rob=int(row['rob']),iq=int(row['iq']),flush=int(row['flush']),cut=int(row['flush_id'])))
    return rows,retired

def eligible(config,test,name):
    if test['mul']:
        return config in ('in_order_zmmul','out_of_order_zmmul','reuse','all_options')
    if config in ('in_order','out_of_order','all_options'):return True
    if config in ('in_order_zmmul','out_of_order_zmmul','reuse'):return False
    if config=='scoreboard':return name in ('false_dependencies','all_registers','alu_semantics','nested_recovery','precise_store_fault','subword_memory','indirect_loop','random_0','random_1')
    if config=='memory_speculation':return name in ('memory_alias_replay','memory_no_alias','wrong_path_store','partial_forwarding','youngest_store','random_0','random_1','random_2')
    if config=='value_prediction':return name in ('value_prediction','cache_locality','random_0','precise_load_fault')
    if config=='cache_disabled':return name=='cache_locality'
    if config.startswith('predictor_'):return name in ('branch_loop','indirect_loop','indirect_control','nested_recovery') or name.startswith('branch_')
    return False

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--quick',action='store_true');ap.add_argument('--waves',action='store_true')
    ap.add_argument('--only');ap.add_argument('--config');args=ap.parse_args()
    if args.config and args.config not in CONFIGS:ap.error('unknown configuration')
    tests=workloads()
    if args.only and args.only not in tests:ap.error('unknown workload')
    for directory in ('build','results','programs'):(ROOT/directory).mkdir(exist_ok=True)
    refs={};runs=[];compiler={}
    for name,t in tests.items():
        if len(t['code'])>256:raise ValueError(f'{name}: instruction RAM capacity')
        words=t['code']+[enc('EBREAK')]*(256-len(t['code']))
        t['words']=words
        (ROOT/'programs'/f'{name}.hex').write_text('\n'.join(f'{w:08x}' for w in words)+'\n')
        (ROOT/'programs'/f'{name}.data.hex').write_text('\n'.join(f'{w:08x}' for w in t['data'])+'\n')
        (ROOT/'programs'/f'{name}.asm').write_text('\n'.join(f'{pc*4:08x}  {w:08x}  {disassemble(w)}' for pc,w in enumerate(t['code']))+'\n')
    for config,params in CONFIGS.items():
        if args.config and config!=args.config:continue
        if args.quick and config not in ('in_order','out_of_order'):continue
        selected=[(n,t) for n,t in tests.items() if (not args.only or n==args.only) and (not args.quick or not n.startswith('random_')) and
                  (args.only is not None or eligible(config,t,n))]
        if not selected:continue
        artifact,compiler[config]=compile_config(config,params)
        print(f'Compiled {config}',flush=True)
        for name,t in selected:
            key=(name,bool(params.get('ENABLE_MUL')))
            if key not in refs:refs[key]=reference(t['words'],t['data'],key[1])
            ref=refs[key]
            trace=ROOT/'results'/f'{name}__{config}.csv'
            cmd=['vvp',str(artifact),f'+PROGRAM=programs/{name}.hex',f'+DATA=programs/{name}.data.hex',f'+TRACE=results/{trace.name}']
            if args.waves and name=='independent_work' and config in ('in_order','out_of_order'):cmd.append(f'+WAVE=results/{name}__{config}.vcd')
            p=command(cmd,60)
            log=(p.stdout+p.stderr).replace(str(ROOT),' .').replace(str(ROOT).replace('\\','/'),'.')
            (ROOT/'results'/f'{name}__{config}.log').write_text(log)
            if p.returncode:raise RuntimeError(f'{name}/{config}\n{p.stdout[-3000:]}\n{p.stderr}')
            metric=None;regs=[None]*32;mem=[None]*256;cause=None;tval=None
            for line in p.stdout.splitlines():
                parts=line.split(',')
                if parts[0]=='RESULT':metric=dict(zip(KEYS,map(int,parts[1:])))
                elif parts[0]=='REG':regs[int(parts[1])]=int(parts[2],16)
                elif parts[0]=='MEM':mem[int(parts[1])]=int(parts[2],16)
                elif parts[0]=='FAULT':cause,tval=map(int,parts[1:])
            rows,retpcs=parse_trace(trace)
            if regs!=ref['regs']:raise AssertionError(f'{name}/{config} registers: {regs} != {ref["regs"]}')
            if mem!=ref['memory']:raise AssertionError(f'{name}/{config} memory: {[(i,a,b) for i,(a,b) in enumerate(zip(mem,ref["memory"])) if a!=b][:8]}')
            if retpcs!=ref['pcs']:raise AssertionError(f'{name}/{config} retirement order: {retpcs} != {ref["pcs"]}')
            if not metric['trapped'] or (metric['fault_pc'],cause,tval)!=(ref['trap'],ref['cause'],ref['tval']):
                raise AssertionError(f'{name}/{config} fault {(metric["fault_pc"],cause,tval)} != {(ref["trap"],ref["cause"],ref["tval"])}')
            if metric['retired']!=len(retpcs):raise AssertionError('retirement count mismatch')
            for feature,workload,counter in [('MEM_SPEC','memory_alias_replay','replays'),('REUSE','instruction_reuse','reuse_hits')]:
                if params.get(feature) and name==workload and not metric[counter]:raise AssertionError(f'{feature} not exercised')
            if params.get('VALUE_PRED') and name=='value_prediction' and not (metric['value_hits'] and metric['value_misses']):raise AssertionError('value validation and recovery not exercised')
            metric.update(fault_cause=cause,fault_value=tval)
            runs.append(dict(workload=name,config=config,params=params,isa='RV32I_Zmmul' if params.get('ENABLE_MUL') else 'RV32I',
                metrics=metric,regs=regs,memory=mem,verified=True,trace=rows))
            print(f'PASS {name:28} {config:20} {metric["cycles"]:4} cycles {metric["retired"]:3} retired fault={cause}',flush=True)
    result=dict(isa='RV32I (optional Zmmul)',runs=runs,compiler=compiler,
                workloads={n:dict(why=t['why'],code=[disassemble(w) for w in t['code']],hex=t['code'],requires_zmmul=t['mul'],
                    reference=reference(t['words'],t['data'],t['mul'])) for n,t in tests.items()})
    (ROOT/'results'/'results.json').write_text(json.dumps(result,indent=2))
    with (ROOT/'results'/'summary.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=['workload','config',*KEYS,'fault_cause','fault_value']);writer.writeheader()
        for run in runs:writer.writerow(dict(workload=run['workload'],config=run['config'],**run['metrics']))
    print(f'\n{len(runs)} RTL runs matched the independent RV32I interpreter.',flush=True)

if __name__=='__main__':main()
