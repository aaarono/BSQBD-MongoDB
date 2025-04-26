#!/usr/bin/env bash
set -euo pipefail

# Colored output
YELLOW="\e[33m"; GREEN="\e[32m"; CYAN="\e[36m"; RED="\e[31m"; NC="\e[0m"

USER=${ADMIN_USER:-user}
PASS=${ADMIN_PASS:-pass}
AUTHDB=admin
MONGOS_HOST=router01
MONGOS_PORT=27017
DB=${TARGET_DB:-MyDatabase}

URI="mongodb://${USER}:${PASS}@${MONGOS_HOST}:${MONGOS_PORT}/?authSource=${AUTHDB}&authMechanism=SCRAM-SHA-256"

# Wait for mongos
echo -e "${YELLOW}==> load-data_debug.sh started${NC}"
echo -e "${YELLOW}==> Waiting for mongos on ${MONGOS_HOST}:${MONGOS_PORT}${NC}"
until bash -c ">/dev/tcp/${MONGOS_HOST}/${MONGOS_PORT}"; do
  echo -e "${CYAN}[DEBUG] mongos not available yet, retrying...${NC}"
  sleep 1
done
echo -e "${GREEN}[INFO] mongos is available${NC}"

# Ensure shards are registered
echo -e "${YELLOW}==> Checking shard registration${NC}"
while :; do
  SHARD_COUNT=$(mongosh "${URI}" --quiet --eval "db.getSiblingDB('config').shards.countDocuments()")
  echo -e "${CYAN}[DEBUG] Shard count: ${SHARD_COUNT}${NC}"
  (( SHARD_COUNT >= 1 )) && break
  sleep 1
done
echo -e "${GREEN}[INFO] Shards are registered${NC}"

# Define JSON-Schema validators
declare -A SCHEMAS
SCHEMAS[TopAnime]='{ "bsonType":"object","required":["animeid","animeurl","imageurl","name","score","members"],"properties":{"animeid":{"bsonType":"int","minimum":1},"animeurl":{"bsonType":"string","pattern":"^https?://.*"},"imageurl":{"bsonType":"string","pattern":"^https?://.*"},"name":{"bsonType":"string","minLength":1},"englishname":{"bsonType":["string","null"]},"genres":{"bsonType":["string","null"]},"synopsis":{"bsonType":["string","null"]},"type":{"bsonType":["string","null"]},"episodes":{"bsonType":["int","null"],"minimum":0},"premiered":{"bsonType":["string","null"]},"producers":{"bsonType":["string","null"]},"studios":{"bsonType":["string","null"]},"source":{"bsonType":["string","null"]},"duration":{"bsonType":["string","null"]},"rating":{"bsonType":["string","null"]},"rank":{"bsonType":["int","null"],"minimum":0},"popularity":{"bsonType":["int","null"],"minimum":0},"favorites":{"bsonType":["int","null"],"minimum":0},"scoredby":{"bsonType":["int","null"],"minimum":0},"score":{"bsonType":"double","minimum":0,"maximum":10},"members":{"bsonType":"int","minimum":0}}}'
SCHEMAS[TopMovies]='{ "bsonType":"object","required":["ID","Title","ReleaseDate"],"properties":{"ID":{"bsonType":"int","minimum":1},"Title":{"bsonType":"string","minLength":1},"Overview":{"bsonType":["string","null"]},"ReleaseDate":{"bsonType":"string","pattern":"^\\d{4}-\\d{2}-\\d{2}$"},"Popularity":{"bsonType":["double","null"],"minimum":0},"VoteAverage":{"bsonType":["double","null"],"minimum":0,"maximum":10},"VoteCount":{"bsonType":["int","null"],"minimum":0}}}'
SCHEMAS[TopNetflix]='{ "bsonType":"object","required":["ShowID","Title","ReleaseYear"],"properties":{"ShowID":{"bsonType":"string","minLength":1},"Type":{"bsonType":["string","null"]},"Title":{"bsonType":"string","minLength":1},"Director":{"bsonType":["string","null"]},"cast":{"bsonType":["string","null"]},"country":{"bsonType":["string","null"]},"DateAdded":{"bsonType":["string","null"]},"ReleaseYear":{"bsonType":"int","minimum":1900,"maximum":2025},"rating":{"bsonType":["string","null"]},"duration":{"bsonType":["string","null"]},"ListedIn":{"bsonType":["string","null"]},"Description":{"bsonType":["string","null"]}}}'

# Create or update validators without dropping sharded collections
for coll in "${!SCHEMAS[@]}"; do
  echo -e "${YELLOW}* Processing collection ${coll}${NC}"
  EXISTS=$(mongosh "${URI}" --quiet --eval "db.getSiblingDB('${DB}').getCollectionInfos({name: '${coll}'}).length")
  if [[ "$EXISTS" -eq 1 ]]; then
    echo -e "${CYAN}[DEBUG] Collection ${coll} exists, applying validator via collMod${NC}"
    mongosh "${URI}" --quiet --eval "db.getSiblingDB('${DB}').runCommand({ collMod: '${coll}', validator: { \$jsonSchema: ${SCHEMAS[$coll]} }, validationLevel: 'strict' })"
  else
    echo -e "${CYAN}[DEBUG] Collection ${coll} does not exist, creating with validator${NC}"
    mongosh "${URI}" --quiet --eval "db.getSiblingDB('${DB}').createCollection('${coll}', { validator: { \$jsonSchema: ${SCHEMAS[$coll]} }, validationLevel: 'strict' })"
  fi
done

echo -e "${YELLOW}==> Importing cleaned CSV files${NC}"
for FILE in /Data/TopAnime.csv /Data/TopMovies.csv /Data/TopNetflix.csv; do
  NAME=$(basename "$FILE" .csv)
  echo -e "${CYAN}[DEBUG] Importing file: ${FILE} into collection: ${NAME}${NC}"
  mongoimport --uri "$URI" --db "$DB" --collection "$NAME" --type csv --headerline --file "$FILE" || echo -e "${RED}[ERROR] mongoimport failed for $NAME${NC}"
  COUNT=$(mongosh "$URI" --quiet --eval "db.getSiblingDB('${DB}').${NAME}.countDocuments()")
  echo -e "${GREEN}[INFO] Loaded ${COUNT} documents into ${NAME}${NC}"
done

echo -e "${GREEN}==> load-data_debug.sh complete${NC}"
