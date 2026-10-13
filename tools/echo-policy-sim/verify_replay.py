"""Compare a bounded replay byte-for-field with matching rows in a full study."""
import argparse
import csv
import subprocess


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('study')
    p.add_argument('replay')
    p.add_argument('--command',nargs='+',help='Optionally generate the replay CSV with this local trial command')
    args=p.parse_args()
    if args.command:
        with open(args.replay,'w',encoding='utf-8',newline='') as stream:
            subprocess.run(args.command,stdout=stream,check=True)
    fields=('profile','scenario','seed','policy')
    def key(row): return tuple(row[f] for f in fields)
    with open(args.replay,encoding='utf-8',newline='') as stream:
        rows=list(csv.DictReader(stream))
    replay={key(r):r for r in rows}
    assert replay and len(replay)==len(rows),'empty or duplicate replay'
    matched=set()
    with open(args.study,encoding='utf-8',newline='') as stream:
        for row in csv.DictReader(stream):
            k=key(row)
            if k in replay:
                assert row==replay[k],(k,row,replay[k])
                matched.add(k)
    assert len(matched)==len(replay),'replay keys absent from study'
    print(f'PASS exact replay: {len(matched)} complete runs, all recorded fields identical')


if __name__=='__main__':
    main()
