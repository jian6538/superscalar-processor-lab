"""Embed measured RTL traces into a standalone HTML report. No dependencies."""
import json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parent
def main():
    data=json.loads((ROOT/'results'/'results.json').read_text(encoding='utf-8'))
    synth=ROOT/'results'/'synthesis_summary.json'
    if synth.exists():
        checked=json.loads(synth.read_text(encoding='utf-8'))
        current={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'rtl').glob('*.sv')}
        data['synthesis']=[s for s in checked if s['rtl_sha256']==current]
    pico=ROOT/'results'/'picorv32_results.json'
    if pico.exists():data['picorv32']=json.loads(pico.read_text(encoding='utf-8'))
    encoded=json.dumps(data,separators=(',',':')).replace('</','<\\/')
    html=(ROOT/'report_template.html').read_text(encoding='utf-8').replace('__DATA__',encoded)
    (ROOT/'report.html').write_text(html,encoding='utf-8')
    print(f'Report built with {len(data["runs"])} measured RTL runs.')
if __name__=='__main__':main()
