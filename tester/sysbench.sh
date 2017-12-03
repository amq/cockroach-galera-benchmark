#!/bin/bash

export WARMUP_TIME=10
export TABLES=4
export TABLE_SIZE=250000

export COCKROACHDB_HOST=cockroachdb-01
export COCKROACHDB_PORT=26257
export COCKROACHDB_USER=root
export COCKROACHDB_PASS=""
export COCKROACHDB_SYSBENCH="sysbench --db-driver=pgsql --pgsql-host=$COCKROACHDB_HOST --pgsql-port=$COCKROACHDB_PORT --pgsql-user=$COCKROACHDB_USER --mysql-password=$COCKROACHDB_PASS --tables=$TABLES --table-size=$TABLE_SIZE"

export GALERA_HOST=galera-01
export GALERA_PORT=3306
export GALERA_USER=root
export GALERA_PASS=""
export GALERA_SYSBENCH="sysbench --db-driver=mysql --mysql-host=$GALERA_HOST --mysql-port=$GALERA_PORT --mysql-user=$GALERA_USER --pgsql-password=$GALERA_PASS --tables=$TABLES --table-size=$TABLE_SIZE"

export PREPARATION_QUERY="
    DROP DATABASE IF EXISTS sbtest;
    CREATE DATABASE sbtest;"

cd sysbench

if [ "$1" == "cockroachdb" ]; then
    PGPASSWORD=$COCKROACHDB_PASS psql -h $COCKROACHDB_HOST -p $COCKROACHDB_PORT -U $COCKROACHDB_USER -c "$PREPARATION_QUERY"

    for test in oltp_read_write oltp_read_only oltp_write_only oltp_update_non_index; do
        echo "cockroachdb: loading $test"
        time $COCKROACHDB_SYSBENCH $test prepare

        for threads in 1 2 4 8 16 32 64 96 128; do
            sleep $WARMUP_TIME
            echo "cockroachdb: started sysbench $test ($threads threads) at $(date +'%H:%m')"
            time $COCKROACHDB_SYSBENCH $test --report-interval=10 --warmup-time=$WARMUP_TIME --rand-type=zipfian --time=60 --threads=$threads run
            echo "cockroachdb: finished sysbench $test ($threads threads) at $(date +'%H:%m')"
        done

        echo "cockroachdb: cleaning up $test"
        time $COCKROACHDB_SYSBENCH $test cleanup
    done

elif [ "$1" == "galera" ]; then
    mysql -h $GALERA_HOST -P $GALERA_PORT -u $GALERA_USER --password=$GALERA_PASS -e "$PREPARATION_QUERY"

    for test in oltp_read_write oltp_read_only oltp_write_only oltp_update_non_index; do
        echo "galera: loading $test"
        time $GALERA_SYSBENCH $test prepare

        for threads in 1 2 4 8 16 32 64 96 128; do
            sleep $WARMUP_TIME
            echo "galera: started sysbench $test ($threads threads) at $(date +'%H:%m')"
            time $GALERA_SYSBENCH $test --report-interval=10 --warmup-time=$WARMUP_TIME --rand-type=zipfian --time=60 --threads=$threads run
            echo "galera: finished sysbench $test ($threads threads) at $(date +'%H:%m')"
        done

        echo "galera: cleaning up $test"
        time $GALERA_SYSBENCH $test cleanup
    done
else
    echo "usage: ./sysbench.sh [cockroachdb|galera]"
fi
