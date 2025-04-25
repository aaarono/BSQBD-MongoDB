#!/bin/bash

mongosh <<EOF
use admin;
db.createUser({user: "user", pwd: "pass", roles:[{role: "root", db: "admin"}]});
exit;
EOF
