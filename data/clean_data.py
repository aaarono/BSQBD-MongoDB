#!/usr/bin/env python3
import pandas as pd
import re

"""
Script: clean_all.py
-------------------
Cleans TopAnime.csv, TopMovies.csv and TopNetflix.csv in the current directory
and outputs TopAnime_clean.csv, TopMovies_clean.csv, TopNetflix_clean.csv.
Remove empty columns startdate, enddate, japanesenames, and cast numeric fields episodes and rank to integers.
"""
# Map of dataset names to input filenames
datasets = {
    'TopAnime':   'TopAnime.csv',
    'TopMovies':  'TopMovies.csv',
    'TopNetflix': 'TopNetflix.csv'
}

# Cleaning TopAnime dataset
def clean_topanime(df):
    # Normalize column names: strip, lowercase, remove non-alphanumeric
    df.columns = (
        df.columns
          .str.strip()
          .str.lower()
          .str.replace(r'[^a-z0-9]', '', regex=True)
    )

    # Drop unused or empty columns
    df = df.drop(columns=['startdate', 'enddate', 'japanesenames'], errors='ignore')

    # Ensure expected columns exist (fill missing with NA)
    expected = [
        'animeid','animeurl','imageurl','name','englishname',
        'genres','synopsis','type','episodes','premiered','producers',
        'studios','source','duration','rating','rank','popularity',
        'favorites','scoredby','score','members'
    ]
    for col in expected:
        if col not in df.columns:
            df[col] = pd.NA

    # Numeric fields conversion
    num_fields = [
        'animeid','rank','episodes','score','members',
        'popularity','favorites','scoredby'
    ]
    for col in num_fields:
        df[col] = pd.to_numeric(df[col], errors='coerce')
    # Cast episodes and rank to integer type
    df['episodes'] = df['episodes'].round(0).astype('Int64')
    df['rank']     = df['rank'].round(0).astype('Int64')

    # URL validation
    url_re = re.compile(r'^https?://', re.IGNORECASE)
    df = df[df['animeurl'].astype(str).str.match(url_re)]
    df = df[df['imageurl'].astype(str).str.match(url_re)]

    # Text fields cleanup
    text_fields = [
        'name','englishname','genres','synopsis','type',
        'premiered','producers','studios','source','duration','rating'
    ]
    for col in text_fields:
        df[col] = df[col].astype(str).str.strip().replace({'nan': pd.NA})

    # Drop rows missing required fields
    required = [
        'animeid','animeurl','imageurl','name',
        'synopsis','type','rank','genres','episodes',
        'score','members','popularity','favorites','scoredby'
    ]
    df = df.dropna(subset=required)
    return df

# Cleaning TopMovies dataset
def clean_topmovies(df):
    # Rename and normalize columns
    df = df.rename(columns={
        'id': 'ID', 'title': 'Title', 'overview': 'Overview',
        'release_date': 'ReleaseDate', 'popularity': 'Popularity',
        'vote_average': 'VoteAverage', 'vote_count': 'VoteCount'
    })
    # Numeric conversions
    df['ID'] = pd.to_numeric(df['ID'], errors='coerce').astype('Int64')
    for col in ['Popularity', 'VoteAverage', 'VoteCount']:
        df[col] = pd.to_numeric(df[col], errors='coerce')
    # Date parsing
    df['ReleaseDate'] = pd.to_datetime(df['ReleaseDate'], errors='coerce')
    df['ReleaseDate'] = df['ReleaseDate'].dt.strftime('%Y-%m-%d')
    df['ReleaseDate'].replace('NaT', pd.NA, inplace=True)
    # Drop rows missing core fields
    df = df.dropna(subset=['ID', 'Title', 'ReleaseDate'])
    return df

# Cleaning TopNetflix dataset
def clean_topnetflix(df):
    # Rename and normalize columns
    df = df.rename(columns={
        'show_id': 'ShowID', 'type': 'Type', 'title': 'Title',
        'release_year': 'ReleaseYear', 'date_added': 'DateAdded',
        'listed_in': 'ListedIn', 'description': 'Description'
    })
    # Numeric year conversion
    df['ReleaseYear'] = pd.to_numeric(df['ReleaseYear'], errors='coerce').astype('Int64')
    # Drop rows missing core fields
    df = df.dropna(subset=['ShowID', 'Title', 'ReleaseYear'])
    return df

# Main execution: process each dataset and output cleaned CSV

def main():
    summary = []
    for name, filename in datasets.items():
        print(f"Processing {name} from {filename}...")
        df = pd.read_csv(filename)
        before = len(df)
        func = globals()[f'clean_{name.lower()}']
        cleaned = func(df)
        after = len(cleaned)
        out_fname = filename.replace('.csv', '_clean.csv')
        cleaned.to_csv(out_fname, index=False)
        summary.append({'Dataset': name, 'Original': before, 'Cleaned': after, 'Output': out_fname})
        print(f"  {before} → {after} rows, saved to {out_fname}\n")

    summary_df = pd.DataFrame(summary)
    print("Summary of cleaning:")
    print(summary_df.to_string(index=False))

if __name__ == '__main__':
    main()
