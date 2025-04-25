#!/usr/bin/env bash
set -euo pipefail

# Path to the keyfile inside container
KEYFILE="/data/mongodb-keyfile"

# Read keyfile content once
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

# Run JS on a host as __system
run_system() {
  local host="$1" js="$2"
  mongosh --quiet --host "$host" "${SYS_AUTH[@]}" --eval "$js"
}

# Run JS on a host as admin user
run_admin() {
  local host="$1" js="$2"
  mongosh --quiet --host "$host" "${ADMIN_AUTH[@]}" --eval "$js"
}

# Wait until TCP port opens
wait_for() {
  local host="$1" port="${2:-27017}"
  until bash -c ">/dev/tcp/$host/$port"; do sleep 1; done
}

# Node lists
CONFIG=(configsvr01 configsvr02 configsvr03)
SHARD1=(shard01-a shard01-b shard01-c)
SHARD2=(shard02-a shard02-b shard02-c)
SHARD3=(shard03-a shard03-b shard03-c)

# 1) Wait for all mongod instances (config & shards)
for node in "${CONFIG[@]}" "${SHARD1[@]}" "${SHARD2[@]}" "${SHARD3[@]}"; do
  wait_for "$node"
done

# 2) Initiate config server replica set (if not done)
run_system configsvr01 '
  try { rs.status(); }
  catch (e) {
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

# 3) Wait until configsvr01 becomes primary
until run_system configsvr01 'rs.isMaster().ismaster' | grep -q true; do
  sleep 1
done

# 4) Create admin user on config server primary
run_system configsvr01 "
  db.getSiblingDB('admin').createUser({
    user: '$ADMIN_USER',
    pwd: '$ADMIN_PASS',
    roles: [{ role: 'root', db: 'admin' }]
  });
"

# 5) Initialize each shard replica set and wait for its primary
init_shard() {
  local rsname="$1" a="$2" b="$3" c="$4"
  run_system "$a" "
    try { rs.status(); }
    catch (e) {
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
  until run_system "$a" 'rs.isMaster().ismaster' | grep -q true; do
    sleep 1
  done
}

init_shard rs-shard-01 "${SHARD1[@]}"
init_shard rs-shard-02 "${SHARD2[@]}"
init_shard rs-shard-03 "${SHARD3[@]}"

# 6) Wait for mongos on router01
wait_for router01 27017

# 7) Add shards to the cluster and enable sharding (as admin user)
run_admin router01 '
  ["rs-shard-01/shard01-a:27017",
   "rs-shard-02/shard02-a:27017",
   "rs-shard-03/shard03-a:27017"]
  .forEach(addr => sh.addShard(addr));
  sh.enableSharding("MyDatabase");
'

echo "? Cluster bootstrap complete"

