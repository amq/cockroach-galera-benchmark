#!/bin/bash

export WARMUP_TIME=10
export RECORD_COUNT=50000

export COCKROACHDB_HOST=cockroachdb-01
export COCKROACHDB_PORT=26257
export COCKROACHDB_USER=root
export COCKROACHDB_PASS=""

export GALERA_HOST=galera-01
export GALERA_PORT=3306
export GALERA_USER=root
export GALERA_PASS=""

export PREPARATION_QUERY="
    DROP DATABASE IF EXISTS ycsb;
    CREATE DATABASE ycsb;
    CREATE TABLE ycsb.usertable (
        YCSB_KEY VARCHAR (255) PRIMARY KEY,
        FIELD0 TEXT,
        FIELD1 TEXT,
        FIELD2 TEXT,
        FIELD3 TEXT,
        FIELD4 TEXT,
        FIELD5 TEXT,
        FIELD6 TEXT,
        FIELD7 TEXT,
        FIELD8 TEXT,
        FIELD9 TEXT
    );"

cd ycsb

if [ "$1" == "cockroachdb" ]; then

    # single loading for consequent worload A-D runs, as per https://github.com/brianfrankcooper/YCSB/wiki/Core-Workloads#running-the-workloads
    PGPASSWORD=$COCKROACHDB_PASS psql -h $COCKROACHDB_HOST -p $COCKROACHDB_PORT -U $COCKROACHDB_USER -c "$PREPARATION_QUERY"
    echo "cockroachdb: loading a"
    time ./bin/ycsb load jdbc -P workloads/workloada -p db.driver=org.postgresql.Driver -p db.url=jdbc:postgresql://$COCKROACHDB_HOST:$COCKROACHDB_PORT/ycsb -p db.user=$COCKROACHDB_USER -p db.passwd=$COCKROACHDB_PASS -p db.batchsize=1000 -p recordcount=$RECORD_COUNT

    for test in a b; do
        for threads in 1 2 4 8 16 32 64 96 128; do
            sleep $WARMUP_TIME
            echo "cockroachdb: started ycsb $test ($threads threads) at $(date +'%H:%m')"
            time ./bin/ycsb run jdbc -P workloads/workload$test -p db.driver=org.postgresql.Driver -p db.url=jdbc:postgresql://$COCKROACHDB_HOST:$COCKROACHDB_PORT/ycsb -p db.user=$COCKROACHDB_USER -p db.passwd=$COCKROACHDB_PASS -p operationcount=0 -p maxexecutiontime=60 -s -threads $threads
            echo "cockroachdb: finished ycsb $test ($threads threads) at $(date +'%H:%m')"
        done

        for tps in 64 128 192 256 320; do
            sleep $WARMUP_TIME
            echo "cockroachdb: started ycsb $test ($tps tps) at $(date +'%H:%m')"
            time ./bin/ycsb run jdbc -P workloads/workload$test -p db.driver=org.postgresql.Driver -p db.url=jdbc:postgresql://$COCKROACHDB_HOST:$COCKROACHDB_PORT/ycsb -p db.user=$COCKROACHDB_USER -p db.passwd=$COCKROACHDB_PASS -p operationcount=0 -p maxexecutiontime=60 -s -threads 16 -target $tps
            echo "cockroachdb: finished ycsb $test ($tps tps) at $(date +'%H:%m')"
        done
    done

elif [ "$1" == "galera" ]; then
    mysql -h $GALERA_HOST -P $GALERA_PORT -u $GALERA_USER --password=$GALERA_PASS -e "$PREPARATION_QUERY"
    echo "galera: loading a"
    time ./bin/ycsb load jdbc -P workloads/workloada -p db.driver=com.mysql.jdbc.Driver -p db.url=jdbc:mysql://$GALERA_HOST:$GALERA_PORT/ycsb -p db.user=$GALERA_USER -p db.passwd=$GALERA_PASS -p db.batchsize=1000 -p recordcount=$RECORD_COUNT

    for test in a b; do
        for threads in 1 2 4 8 16 32 64 96 128; do
            sleep $WARMUP_TIME
            echo "galera: started ycsb $test ($threads threads) at $(date +'%H:%m')"
            time ./bin/ycsb run jdbc -P workloads/workload$test -p db.driver=com.mysql.jdbc.Driver -p db.url=jdbc:mysql://$GALERA_HOST:$GALERA_PORT/ycsb -p db.user=$GALERA_USER -p db.passwd=$GALERA_PASS -p operationcount=0 -p maxexecutiontime=60 -s -threads $threads
            echo "galera: finished ycsb $test ($threads threads) at $(date +'%H:%m')"
        done

        for tps in 64 128 192 256 320; do
            sleep $WARMUP_TIME
            echo "galera: started ycsb $test ($tps tps) at $(date +'%H:%m')"
            time ./bin/ycsb run jdbc -P workloads/workload$test -p db.driver=com.mysql.jdbc.Driver -p db.url=jdbc:mysql://$GALERA_HOST:$GALERA_PORT/ycsb -p db.user=$GALERA_USER -p db.passwd=$GALERA_PASS -p operationcount=0 -p maxexecutiontime=60 -s -threads 16 -target $tps
            echo "galera: finished ycsb $test ($tps tps) at $(date +'%H:%m')"
        done
    done
else
    echo "usage: ./ycsb.sh [cockroachdb|galera]"
fi
