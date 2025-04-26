#!/usr/bin/env bash
set -euo pipefail

# Colors
DEBUG_COLOR="\e[36m"   # cyan
YELLOW="\e[33m"
GREEN="\e[32m"
NC="\e[0m"

echo -e "${DEBUG_COLOR}==> bootstrap.sh started${NC}"

# Path to the keyfile inside container
KEYFILE="/data/mongodb-keyfile"
echo -e "${DEBUG_COLOR}Reading keyfile...${NC}"
MASTER_KEY=$(<"$KEYFILE" tr -d '\r\n')

# Internal auth (system user)
SYS_AUTH=(
  --username "__system"
  --password "$MASTER_KEY"
  --authenticationDatabase "local"
  --authenticationMechanism "SCRAM-SHA-256"
)

# Admin auth (the user we will create)
ADMIN_USER=${ADMIN_USER:-user}
ADMIN_PASS=${ADMIN_PASS:-pass}
ADMIN_AUTH=(
  --username "$ADMIN_USER"
  --password "$ADMIN_PASS"
  --authenticationDatabase "admin"
)

# Helpers to run JS
run_system() {
  local host="$1" js="$2"
  echo -e "${DEBUG_COLOR}[DEBUG] run_system on $host: $js${NC}"
  mongosh --quiet --host "$host" "${SYS_AUTH[@]}" --eval "$js"
}
run_admin() {
  local host="$1" js="$2"
  echo -e "${DEBUG_COLOR}[DEBUG] run_admin on $host: $js${NC}"
  mongosh --quiet --host "$host" "${ADMIN_AUTH[@]}" --eval "$js"
}

# Wait until TCP port opens
wait_for() {
  local host="$1" port="${2:-27017}"
  echo -e "${DEBUG_COLOR}[DEBUG] waiting for $host:$port${NC}"
  until bash -c ">/dev/tcp/$host/$port"; do sleep 1; done
  echo -e "${DEBUG_COLOR}[DEBUG] $host:$port is available${NC}"
}

# Node lists
CONFIG=(configsvr01 configsvr02 configsvr03)
SHARD1=(shard01-a shard01-b shard01-c)
SHARD2=(shard02-a shard02-b shard02-c)
SHARD3=(shard03-a shard03-b shard03-c)

echo -e "${DEBUG_COLOR}==> Step 1: Waiting for all mongod instances${NC}"
for node in "${CONFIG[@]}" "${SHARD1[@]}" "${SHARD2[@]}" "${SHARD3[@]}"; do
  wait_for "$node"
done

echo -e "${DEBUG_COLOR}==> Step 2: Initiating config server replica set${NC}"
run_system configsvr01 '
  try { rs.status(); } catch (e) {
    rs.initiate({
      _id: "rs-config-server",
      configsvr: true,
      members: [
        { _id: 0, host: "configsvr01:27017" },
        { _id: 1, host: "configsvr02:27017" },
        { _id: 2, host: "configsvr03:27017" }
      ]
    });
  }
'
echo -e "${DEBUG_COLOR}==> Config server replicaset initiated${NC}"

echo -e "${DEBUG_COLOR}==> Step 3: Waiting for configsvr01 to become primary${NC}"
until run_system configsvr01 'rs.isMaster().ismaster' | grep -q true; do
  sleep 1
done
echo -e "${DEBUG_COLOR}==> configsvr01 is primary${NC}"

echo -e "${DEBUG_COLOR}==> Step 4: Creating admin user on config server primary${NC}"
run_system configsvr01 "
  db.getSiblingDB('admin').createUser({
    user: '$ADMIN_USER',
    pwd: '$ADMIN_PASS',
    roles: [{ role: 'root', db: 'admin' }]
  });
"
echo -e "${DEBUG_COLOR}==> Admin user created on configsvr01${NC}"

echo -e "${DEBUG_COLOR}==> Step 5: Initializing shard replica sets${NC}"
init_shard() {
  local rsname="$1" a="$2" b="$3" c="$4"
  echo -e "${DEBUG_COLOR}  [DEBUG] Initializing replicaset $rsname on $a,$b,$c${NC}"
  run_system "$a" "
    try { rs.status(); } catch (e) {
      rs.initiate({
        _id: '$rsname',
        members: [
          { _id: 0, host: '$a:27017' },
          { _id: 1, host: '$b:27017' },
          { _id: 2, host: '$c:27017' }
        ]
      });
    }
  "
  echo -e "${DEBUG_COLOR}  [DEBUG] Waiting for primary of $rsname${NC}"
  until run_system "$a" 'rs.isMaster().ismaster' | grep -q true; do
    sleep 1
  done
  echo -e "${DEBUG_COLOR}  [DEBUG] $rsname primary is on $a${NC}"
}
init_shard rs-shard-01 "${SHARD1[@]}"
init_shard rs-shard-02 "${SHARD2[@]}"
init_shard rs-shard-03 "${SHARD3[@]}"

echo -e "${DEBUG_COLOR}==> Step 6: Waiting for mongos on router01${NC}"
wait_for router01 27017

echo -e "${DEBUG_COLOR}==> Step 7: Adding shards to cluster and enabling sharding${NC}"
run_admin router01 '
  ["rs-shard-01/shard01-a:27017",
   "rs-shard-02/shard02-a:27017",
   "rs-shard-03/shard03-a:27017"]
  .forEach(addr => sh.addShard(addr));
  sh.enableSharding("MyDatabase");
'
echo -e "${DEBUG_COLOR}==> Shards added, database MyDatabase enabled for sharding${NC}"

echo -e "${YELLOW}==> Step 8: Creating initial chunks for sharded collections${NC}"

# Массив вида "CollectionName shardKeyField"
pairs=(
  "TopAnime   animeid"
  "TopMovies  ID"
  "TopNetflix ShowID"
)

for pair in "${pairs[@]}"; do
  coll=$(echo "$pair"  | awk '{print $1}')
  key=$(echo  "$pair"  | awk '{print $2}')
  echo -e "[DEBUG] Sharding ${coll} by { ${key}: hashed }"
  mongosh --quiet --host router01 \
    --username "$ADMIN_USER" --password "$ADMIN_PASS" --authenticationDatabase admin \
    --eval "printjson(
      sh.shardCollection(
        'MyDatabase.${coll}',
        { ${key}: 'hashed' },
        false,
        { numInitialChunks: 8 }
      )
    );"
done

echo -e "${GREEN}==> Initial chunks created${NC}"

echo -e "${DEBUG_COLOR}==> bootstrap_debug.sh complete${NC}"
