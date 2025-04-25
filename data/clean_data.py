#!/usr/bin/env python3
"""
clean_data.py

Skript pro čištění CSV souborů od nežádoucích znaků a nadbytečných mezer.
Použití:
    python3 clean_data.py file1.csv file2.csv ...
Výsledky:
    Vytvoří soubory file1_clean.csv, file2_clean.csv, ... ve stejném adresáři.
"""

import pandas as pd
import re
import os
import sys

def clean_dataframe(df):
    # Pro každý textový sloupec odstraníme neviditelné znaky a přebytečné mezery
    for col in df.select_dtypes(include=['object']).columns:
        # Převedení na řetězec a odstranění okrajových mezer
        df[col] = df[col].astype(str).str.strip()
        # Odebrání všech ne-tisknutelných znaků (mimo běžné ASCII 0x20–0x7E)
        df[col] = df[col].apply(lambda x: re.sub(r'[^\x20-\x7E]+', '', x))
        # Nahrazení vícenásobných mezer jednou mezerou
        df[col] = df[col].str.replace(r'\s+', ' ', regex=True)
    return df

def main():
    if len(sys.argv) < 2:
        print("Použití: python3 clean_data.py file1.csv file2.csv ...")
        sys.exit(1)

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            print(f"Soubor '{path}' nenalezen. Přeskakuji.")
            continue

        df = pd.read_csv(path, dtype=str)
        df_clean = clean_dataframe(df)
        base, ext = os.path.splitext(path)
        out_path = f"{base}_clean{ext}"
        df_clean.to_csv(out_path, index=False)
        print(f"Vyčištěno '{path}' → '{out_path}'")

if __name__ == '__main__':
    main()
