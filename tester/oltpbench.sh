#!/bin/bash

export COCKROACHDB_HOST=cockroachdb-01
export COCKROACHDB_PORT=26257
export COCKROACHDB_USER=root
export COCKROACHDB_PASS=""

export GALERA_HOST=galera-01
export GALERA_PORT=3306
export GALERA_USER=root
export GALERA_PASS=""

export WARMUP_TIME=10

export PREPARATION_QUERY="
    DROP DATABASE IF EXISTS linkbench;
    DROP DATABASE IF EXISTS twitter;
    CREATE DATABASE linkbench;
    CREATE DATABASE twitter;"

cd oltpbench

PGPASSWORD=$COCKROACHDB_PASS psql -h $COCKROACHDB_HOST -p $COCKROACHDB_PORT -U $COCKROACHDB_USER -c "$PREPARATION_QUERY"

for test in linkbench twitter; do
    sed -i \
        -e "/<dbtype>/c\<dbtype>postgres</dbtype>" \
        -e "/<driver>/c\<driver>org.postgresql.Driver</driver>" \
        -e "/<DBUrl>/c\<DBUrl>jdbc:postgresql://${COCKROACHDB_HOST}:${COCKROACHDB_PORT}/${test}</DBUrl>" \
        -e "/<username>/c\<username>${COCKROACHDB_USER}</username>" \
        -e "/<password>/c\<password>${COCKROACHDB_PASS}</password>" \
        -e "/<isolation>/c\<isolation>TRANSACTION_REPEATABLE_READ</isolation>" \
        -e "/<terminals>/c\<terminals>64</terminals>" \
        -e "/<scalefactor>/c\<scalefactor>16</scalefactor>" \
        -e "/<rate>/c\<rate>unlimited</rate>" \
        -e "/<time>/c\<time>300</time>" \
        "config/sample_${test}_config.xml";

    echo "cockroachdb: loading $test"
    time ./oltpbenchmark -b $test -c config/sample_${test}_config.xml --create=true --load=true

    for attempt in {1..3}; do
        sleep $WARMUP_TIME
        echo "cockroachdb: started oltpbench $test (attempt $attempt) at $(date +'%H:%m')"
        time ./oltpbenchmark -b $test -c config/sample_${test}_config.xml --execute=true -s 1
        echo "cockroachdb: finished oltpbench $test (attempt $attempt) at $(date +'%H:%m')"
    done
done

#####

mysql -h $GALERA_HOST -P $GALERA_PORT -u $GALERA_USER --password=$GALERA_PASS -e "$PREPARATION_QUERY"

for test in linkbench twitter; do
    sed -i \
        -e "/<dbtype>/c\<dbtype>mysql</dbtype>" \
        -e "/<driver>/c\<driver>com.mysql.jdbc.Driver</driver>" \
        -e "/<DBUrl>/c\<DBUrl>jdbc:mysql://${GALERA_HOST}:${GALERA_PORT}/${test}</DBUrl>" \
        -e "/<username>/c\<username>${GALERA_USER}</username>" \
        -e "/<password>/c\<password>${GALERA_PASS}</password>" \
        -e "/<isolation>/c\<isolation>TRANSACTION_REPEATABLE_READ</isolation>" \
        -e "/<terminals>/c\<terminals>64</terminals>" \
        -e "/<scalefactor>/c\<scalefactor>16</scalefactor>" \
        -e "/<rate>/c\<rate>unlimited</rate>" \
        -e "/<time>/c\<time>300</time>" \
        "config/sample_${test}_config.xml";

    echo "galera: loading $test"
    time ./oltpbenchmark -b $test -c config/sample_${test}_config.xml --create=true --load=true

    for attempt in {1..3}; do
        sleep $WARMUP_TIME
        echo "galera: started oltpbench $test (attempt $attempt) at $(date +'%H:%m')"
        time ./oltpbenchmark -b $test -c config/sample_${test}_config.xml --execute=true -s 1
        echo "galera: finished oltpbench $test (attempt $attempt) at $(date +'%H:%m')"
    done
done
