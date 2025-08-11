mongosh --host 127.0.0.1 --port 27017

rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "172.16.48.233:27017" },
    { _id: 1, host: "172.16.48.233:27018" },
    { _id: 2, host: "172.16.48.233:27019" }
  ]
})

rs.status()

use admin
db.createUser({
  user: "admin",
  pwd: "Secsmart#612",
  roles: ["root"]
})

use admin
db.auth("admin", "Secsmart#612")

mongosh --host 127.0.0.1 --port 27017 -u admin -p 'Secsmart#612' --authenticationDatabase admin
