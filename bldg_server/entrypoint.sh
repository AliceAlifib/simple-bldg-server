#!/bin/sh
# Docker entrypoint script.

# Wait until Postgres is ready
echo "Verifying DB connection with $DB_HOST:$DB_PORT"
while ! pg_isready -q -h $DB_HOST -p $DB_PORT -U $DB_USER
do
    echo "${date} - waiting for database to start"
    sleep 2
done


./dev/rel/bldg_server/bin/bldg_server eval BldgServer.Release.migrate

./dev/rel/bldg_server/bin/bldg_server start
