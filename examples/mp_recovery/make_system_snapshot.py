#!/usr/bin/env python3
"""Offline synthetic systems with unequal sizes, mixed labels and unlabelled-only systems."""
import argparse
import importlib.util
from pathlib import Path


def create(output):
    path=Path(__file__).resolve().parents[2]/"scripts/export_mp_pilot.py"
    spec=importlib.util.spec_from_file_location("mp_export",path)
    exporter=importlib.util.module_from_spec(spec);spec.loader.exec_module(exporter)
    docs=[]
    def add(counts,flag):
        docs.append(dict(material_id=f"mp-{len(docs)+1}",composition=counts,formula_pretty="synthetic",theoretical=flag,
                         database_IDs={"icsd":["synthetic"]} if flag is False else {},deprecated=False))
    for j,e in enumerate(("Li","K","Rb","Cs","Be","Mg","Ca","Sr","Ba","Al")):
        last=10 if j==0 else 5
        for i in range(1,last+1): add({e:i,"Na":1,"O":1},False)
        add({e:1,"Na":1,"O":1},True)
        for i in range(last+1,last+3): add({e:i,"Na":1,"O":1},True)
    add({"Mg":1,"Al":1,"O":1},True)
    add({"Fe":1,"Co":1,"O":1},None)
    exporter.write_snapshot(docs,output,database_version="synthetic-system-v2",client_version="not-used-offline",is_synthetic=True)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("output",type=Path)
    create(parser.parse_args().output)
