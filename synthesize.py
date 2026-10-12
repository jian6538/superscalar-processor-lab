"""Yosys process lowering, optimization, and structural checks for RTL configurations.
Usage: python synthesize.py [--yowasp-path PATH] [--config in_order|out_of_order|all_options]
Uses a native yosys executable by default; --yowasp-path selects an isolated package directory.
This is generic structural synthesis, not technology mapping or place/route.
"""
import argparse,json,subprocess,sys,re,hashlib,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parent

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--yowasp-path');ap.add_argument('--config');args=ap.parse_args()
    configs={'in_order':{'OOO':0},'out_of_order':{'OOO':1},'all_options':{'OOO':1,'MEM_SPEC':1,'REUSE':1,'VALUE_PRED':1,'PREDICTOR':5,'ENABLE_MUL':1},'out_of_order_zmmul':{'OOO':1,'ENABLE_MUL':1}}
    summary=[]
    for name,params in configs.items():
        if args.config and args.config!=name:continue
        log=f'results/synthesis_{name}.log'
        script='read_verilog -sv -defer rtl/core.sv rtl/data_cache.sv rtl/processor_system.sv; '
        script+='hierarchy -check -top processor_system '+ ' '.join(f'-chparam {k} {v}' for k,v in params.items())+'; '
        script+='proc; opt; check -assert; select -assert-none t:$dlatch; stat; '
        if args.yowasp_path:
            code='import sys;sys.path.insert(0,sys.argv.pop(1));import yowasp_yosys;sys.exit(yowasp_yosys.run_yosys(sys.argv[1:]))'
            cmd=[sys.executable,'-c',code,str(Path(args.yowasp_path).resolve()),'-Q','-T','-q','-l',log,'-p',script]
        else:cmd=['yosys','-Q','-T','-q','-l',log,'-p',script]
        print(f'Synthesizing {name}...',flush=True)
        p=subprocess.run(cmd,cwd=ROOT,text=True,capture_output=True,timeout=900)
        if p.returncode:raise RuntimeError(f'{name}: {p.stderr[-3000:]}\n{p.stdout[-1000:]}')
        text=(ROOT/log).read_text()
        summary.append({'config':name,'params':params,'passed':True,
            'check_problems':re.findall(r'Found and reported (\d+) problems',text),
            'no_latches':True,'rtl_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'rtl').glob('*.sv')},
            'log':log,'verification':'Yosys read_verilog + hierarchy + proc + opt + check -assert + no $dlatch'})
        (ROOT/'results'/'synthesis_summary.json').write_text(json.dumps(summary,indent=2))
        print(f'PASS {name}: process lowering, optimization, structural checks, no latches',flush=True)
if __name__=='__main__':main()
