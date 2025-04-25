#!/usr/bin/env bash
set -euo pipefail

YELLOW="\e[33m"; GREEN="\e[32m"; NC="\e[0m"

USER=${ADMIN_USER:-user}
PASS=${ADMIN_PASS:-pass}
AUTHDB=admin
MONGOS_HOST=router01
MONGOS_PORT=27017
DB=${TARGET_DB:-MyDatabase}

URI="mongodb://${USER}:${PASS}@${MONGOS_HOST}:${MONGOS_PORT}/?authSource=${AUTHDB}&authMechanism=SCRAM-SHA-256"

# 1) ???? mongos
until bash -c ">/dev/tcp/${MONGOS_HOST}/${MONGOS_PORT}"; do
  sleep 1
done

# 2) ???? ??????????? ???? ?? ?????? ?????
while :; do
  COUNT=$(mongosh "${URI}" --quiet \
    --eval "db.getSiblingDB('config').shards.countDocuments()" | tr -dc '0-9')
  (( COUNT >= 1 )) && break
  sleep 1
done

# 3) ??????? ????????? ? ??????? JSON-Schema ????????????
declare -A SCHEMAS
SCHEMAS[TopAnime]='{
  bsonType: "object",
  required: ["Rank","Title","Genre","Episodes","StartDate","EndDate","Score","Members"],
  properties: {
    Rank:      { bsonType: "int"    },
    Title:     { bsonType: "string" },
    Genre:     { bsonType: "string" },
    Episodes:  { bsonType: "int"    },
    StartDate: { bsonType: "string" },
    EndDate:   { bsonType: ["string","null"] },
    Score:     { bsonType: "double" },
    Members:   { bsonType: "int"    }
  }
}'
SCHEMAS[TopMovies]='{
  bsonType: "object",
  required: ["Rank","Title","Year","Rating","Director","Runtime","Genre","Votes","Revenue","Metascore"],
  properties: {
    Rank:      { bsonType: "int"    },
    Title:     { bsonType: "string" },
    Year:      { bsonType: "int"    },
    Rating:    { bsonType: "double" },
    Director:  { bsonType: "string" },
    Runtime:   { bsonType: "string" },
    Genre:     { bsonType: "string" },
    Votes:     { bsonType: "int"    },
    Revenue:   { bsonType: ["double","null"] },
    Metascore: { bsonType: ["int","null"] }
  }
}'
SCHEMAS[TopNetflix]='{
  bsonType: "object",
  required: ["show_id","type","title","director","cast","country","date_added","release_year","rating","duration","listed_in","description"],
  properties: {
    show_id:      { bsonType: "string" },
    type:         { bsonType: "string" },
    title:        { bsonType: "string" },
    director:     { bsonType: ["string","null"] },
    cast:         { bsonType: ["string","null"] },
    country:      { bsonType: ["string","null"] },
    date_added:   { bsonType: "string" },
    release_year: { bsonType: "int"    },
    rating:       { bsonType: "string" },
    duration:     { bsonType: "string" },
    listed_in:    { bsonType: "string" },
    description:  { bsonType: "string" }
  }
}'

echo -e "${YELLOW}? Creating collections with full validators${NC}"
for coll in "${!SCHEMAS[@]}"; do
  echo "    $coll"
  mongosh --quiet --host "${MONGOS_HOST}:${MONGOS_PORT}" \
    --username "$USER" --password "$PASS" --authenticationDatabase "$AUTHDB" \
    --eval "db.getSiblingDB('${DB}').createCollection(
      '${coll}',
      {
        validator: { \$jsonSchema: ${SCHEMAS[$coll]} },
        validationLevel: 'strict'
      }
    )"
done

# 4) ??????????? CSV (??? --drop, ????? ?? ???????? ?????)
echo -e "${YELLOW}? Importing CSV files${NC}"
for FILE in /Data/TopAnime.csv /Data/TopMovies.csv /Data/TopNetflix.csv; do
  NAME=$(basename "$FILE" .csv)
  echo -e "${YELLOW}[import] $NAME ? ${DB}.$NAME${NC}"
  mongoimport \
    --uri "$URI" \
    --db "$DB" \
    --collection "$NAME" \
    --type csv \
    --headerline \
    --file "$FILE"
  CNT=$(mongosh "$URI" --quiet \
    --eval "db.getSiblingDB('${DB}').${NAME}.countDocuments()" | tr -dc '0-9')
  echo -e "${GREEN}[ok]   Loaded $CNT docs${NC}"
done

echo -e "${GREEN}? All done${NC}"

