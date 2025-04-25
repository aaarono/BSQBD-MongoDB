#!/usr/bin/env python3
"""
analyze_data.py

Skript pro načtení CSV souborů, převedení typů, základní analýzu a vizualizaci.
Výstup:
  - Statistické informace do konzole
  - Grafy uložené v adresáři `plots/`
Použití:
    python3 analyze_data.py file1.csv file2.csv ...
"""

import os
import sys
import pandas as pd
import matplotlib.pyplot as plt

def load_and_cast(path):
    df = pd.read_csv(path)
    # převod sloupců s datem/rokem/časem
    for col in df.columns:
        key = col.lower()
        if any(k in key for k in ['date', 'year', 'time']):
            df[col] = pd.to_datetime(df[col], errors='coerce')
    # převod číselných
    for col in df.select_dtypes(include=['object']).columns:
        df[col] = pd.to_numeric(df[col], errors='ignore')
    return df

def analyze_df(df, name):
    print(f"=== Analýza souboru: {name} ===")
    print("Tvar (řádky, sloupce):", df.shape)
    print("\nDatové typy sloupců:")
    print(df.dtypes)
    print("\nPočet chybějících hodnot na sloupec:")
    missing = df.isnull().sum()
    print(missing)
    print("\nZákladní statistiky pro číselné sloupce:")
    print(df.describe())
    print("\n" + "="*60 + "\n")

def plot_missing(df, name):
    missing = df.isnull().sum()
    if (missing>0).any():
        plt.figure()
        missing[missing>0].plot.bar()
        plt.title(f"Missing values per column: {os.path.basename(name)}")
        plt.xlabel("Column")
        plt.ylabel("Count")
        plt.tight_layout()
        plt.savefig(f"plots/{os.path.basename(name)}_missing.png")
        plt.close()

def plot_histograms(df, name):
    nums = df.select_dtypes(include=['number']).columns
    for col in nums:
        plt.figure()
        df[col].dropna().plot.hist(bins=30)
        plt.title(f"Histogram of {col}: {os.path.basename(name)}")
        plt.xlabel(col)
        plt.ylabel("Count")
        plt.tight_layout()
        plt.savefig(f"plots/{os.path.basename(name)}_{col}_hist.png")
        plt.close()

def plot_boxplot(df, name):
    nums = df.select_dtypes(include=['number']).columns
    if len(nums)>0:
        plt.figure()
        df[nums].plot.box()
        plt.title(f"Boxplot numeric columns: {os.path.basename(name)}")
        plt.ylabel("Value")
        plt.tight_layout()
        plt.savefig(f"plots/{os.path.basename(name)}_boxplot.png")
        plt.close()

def plot_top_categories(df, name):
    cats = df.select_dtypes(include=['object','category']).columns
    for col in cats:
        top = df[col].value_counts().head(10)
        if len(top)>0:
            plt.figure()
            top.plot.bar()
            plt.title(f"Top 10 in {col}: {os.path.basename(name)}")
            plt.xlabel(col)
            plt.ylabel("Count")
            plt.tight_layout()
            plt.savefig(f"plots/{os.path.basename(name)}_{col}_top10.png")
            plt.close()

def plot_comparison_summaries(missing_summary, record_summary):
    # Missing values comparison
    plt.figure()
    pd.Series(missing_summary).plot.bar()
    plt.title("Comparison of Total Missing Values")
    plt.xlabel("Dataset")
    plt.ylabel("Total Missing Count")
    plt.tight_layout()
    plt.savefig("plots/comparison_missing.png")
    plt.close()
    # Record counts comparison
    plt.figure()
    pd.Series(record_summary).plot.bar()
    plt.title("Comparison of Record Counts")
    plt.xlabel("Dataset")
    plt.ylabel("Number of Records")
    plt.tight_layout()
    plt.savefig("plots/comparison_records.png")
    plt.close()

def main():
    if len(sys.argv) < 2:
        print("Použití: python3 analyze_data.py file1.csv file2.csv ...")
        sys.exit(1)
    os.makedirs('plots', exist_ok=True)
    missing_summary = {}
    record_summary = {}
    for path in sys.argv[1:]:
        try:
            df = load_and_cast(path)
            name = os.path.basename(path)
            analyze_df(df, name)
            plot_missing(df, name)
            plot_histograms(df, name)
            plot_boxplot(df, name)
            plot_top_categories(df, name)
            # accumulate summaries
            missing_summary[name] = int(df.isnull().sum().sum())
            record_summary[name] = int(df.shape[0])
        except Exception as e:
            print(f"Chyba při analýze '{path}': {e}")
    # plots comparing all datasets
    plot_comparison_summaries(missing_summary, record_summary)
    print("Analýza dokončena. Grafy jsou ve složce 'plots/'.")

if __name__ == '__main__':
    main()

