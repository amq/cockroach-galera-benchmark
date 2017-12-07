## Status

- did a *preliminary* single-node testing, see [cockroachdb/cockroach#17777](https://github.com/cockroachdb/cockroach/issues/17777#issuecomment-347243141)

## Warning

- testing in cloud means testing in a noisy environment. Fluctuations of up to 25% were observed with `m5.xlarge`

## Roadmap

- the performance of CockroachDB seems to be lower than expected, make sure I didn't miss something obvious
- investigate oltpbench compatibility issues, possibly add a dialect file
- evaluate special / pareto / zipfian distribution usage for sysbench
- launch the final testing, I expect it to last for a few days without pauses
- try querying all hosts instead of once, by load-balancing the traffic using nginx or haproxy

## Testing process

### 1. Launch instances

Choose the base hostname
```
export BASE_HOSTNAME=node
```

Make sure `docker-machine` version is `>= 0.13.0`
```
docker-machine -v
```

**Locally**

```
for i in {1..3}; do
    docker-machine create ${BASE_HOSTNAME:-node}-0$i
done
```

**AWS**

```
for i in {1..3}; do
    docker-machine create \
    --engine-storage-driver overlay2 \
    --driver amazonec2 \
    --amazonec2-region eu-west-1 \
    --amazonec2-zone a \
    --amazonec2-instance-type m5.xlarge \
    --amazonec2-volume-type gp2 \
    --amazonec2-root-size 500 \
    --amazonec2-ami ami-8fd760f6 \
    ${BASE_HOSTNAME:-node}-0$i
done
```

Refer to [https://docs.docker.com/machine/drivers/aws/](docs) on how to set up the credentials

Afterwards, add the following inbound rules for the `docker-machine` security group in AWS management console:
```
All traffic 172.0.0.0/8
All traffic your-ip/32
```

### 2. Install chrony and iostat

```
for i in {1..3}; do
    docker-machine ssh ${BASE_HOSTNAME:-node}-0$i -- "sudo apt update && sudo apt -y install chrony iostat"
done
```

`iostat` is useful for quick cpu and io monitoring, for documented values use grafana

### 3. Verify that system settings are above recommended

```
docker-machine ssh ${BASE_HOSTNAME:-node}-01
sudo su
```

Per-process file limit must be `>= 15000`
```
cat /proc/$(pidof dockerd)/limits | grep "Max open files"
```

Global open file limit mush be above `15000 * 10`
```
cat /proc/sys/fs/file-max
```

Storage driver must be `overlay2`
```
docker info | grep "Storage Driver"
```

Check `chrony` status
```
chronyc tracking
```

You should see `Leap status: Normal`

When done, exit from ssh

### 4. Initialize Swarm on first node

**Locally**

```
eval "$(docker-machine env ${BASE_HOSTNAME:-node}-01)"
docker swarm init --advertise-addr=eth1
```

**AWS**

```
eval "$(docker-machine env ${BASE_HOSTNAME:-node}-01)"
docker swarm init --advertise-addr=ens5
```

Get the join command:
```
docker swarm join-token worker | grep docker | xargs
```

### 5. Join Swarm on other nodes

```
eval "$(docker-machine env ${BASE_HOSTNAME:-node}-02)"
```

*Run the join command from last step and repeat for node-03*

### 6. Verify that Swarm works

```
eval "$(docker-machine env ${BASE_HOSTNAME:-node}-01)"
docker node ls
```

### 7. Create attachable network

```
docker network create --driver overlay --attachable mynet
```

### 8. Launch monitoring services

```
cd monitoring
docker stack deploy --compose-file=docker-compose.yml monitoring
```

Note: it will take a minute or so till Swarm downloads the image and deploys the service


### 9. Verify that monitoring works

- Prometheus: `http://ip-of-node-01:9090/`
- Grafana: `http://ip-of-node-01:3000/`

### 10. Import grafana dashboards

- [CockroachDB](https://github.com/cockroachdb/cockroach/tree/master/monitoring/grafana-dashboards)
- [MySQL and Galera](https://github.com/percona/grafana-dashboards/tree/master/dashboards)
- [System information](https://grafana.com/dashboards/405)
- [Docker Swarm](https://grafana.com/dashboards/2603)

Afterwards, change the timezone of all dashboards to either `Local browser time` or `UTC` to avoid confusion

### 11. Launch cockroachdb-01

```
cd ../cockroachdb-cluster
docker stack deploy --compose-file=docker-compose-1.yml cockroachdb
```

Verify that cockroachdb works
```
docker run -it --rm --network=mynet cockroachdb/cockroach:${COCKROACHDB_VERSION:-v1.1.3} node status --host=cockroachdb-01 --insecure
```

SQL console
```
docker run -it --rm --network=mynet cockroachdb/cockroach:${COCKROACHDB_VERSION:-v1.1.3} sql --host=cockroachdb-01 --insecure
```

Web console: `http://ip-of-node-01:8080/`

### 12. Build tester image

```
cd ../tester
docker build -t tester .
```

### 13. Run single-node cockroachdb tests

Run
```
docker run -it --network=mynet tester bash
cd /scripts
./sysbench.sh cockroachdb | tee cockroachdb-sysbench.log
./oltpbench.sh cockroachdb | tee cockroachdb-oltpbench.log
./ycsb.sh cockroachdb | tee cockroachdb-ycsb.log
exit
```

Copy results
```
docker cp container_id:/scripts/cockroachdb-sysbench.log ./results/cockroachdb-1/
docker cp container_id:/scripts/cockroachdb-oltpbench.log ./results/cockroachdb-1/
docker cp container_id:/scripts/cockroachdb-ycsb.log ./results/cockroachdb-1/
docker cp container_id:/scripts/oltpbench/results ./results/cockroachdb-1/oltpbench/
```

### 14. Launch cockroachdb-02 and 03

```
cd ../cockroachdb-cluster
docker stack deploy --compose-file=docker-compose-3.yml cockroachdb
```

Verify that cockroachdb cluster has 3 members
```
docker run -it --rm --network=mynet cockroachdb/cockroach:${COCKROACHDB_VERSION:-v1.1.3} node status --host=cockroachdb-01 --insecure
```

### 15. Run 3-node cockroachdb tests

*Repeat Run commands from 13*

Copy results
```
docker cp container_id:/scripts/cockroachdb-sysbench.log ./results/cockroachdb-3/
docker cp container_id:/scripts/cockroachdb-oltpbench.log ./results/cockroachdb-3/
docker cp container_id:/scripts/cockroachdb-ycsb.log ./results/cockroachdb-3/
docker cp container_id:/scripts/oltpbench/results ./results/cockroachdb-3/oltpbench/
```

### 16. Stop cockroachdb

```
docker stack rm cockroachdb
```

### 17. Launch galera-01

```
cd ../galera-cluster
docker stack deploy --compose-file=docker-compose-1.yml galera
```

Verify that galera works
```
docker run -it --rm --network=mynet mariadb:${MARIADB_VERSION:-10.2.11} mysql -h galera-01

SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size';
```

### 18. Run single-node galera tests

Run
```
docker run -it --network=mynet tester bash
cd /scripts
./sysbench.sh galera | tee galera-sysbench.log
./oltpbench.sh galera | tee galera-oltpbench.log
./ycsb.sh galera | tee galera-ycsb.log
exit
```

Copy results
```
docker cp container_id:/scripts/galera-sysbench.log ./results/galera-1/
docker cp container_id:/scripts/galera-oltpbench.log ./results/galera-1/
docker cp container_id:/scripts/galera-ycsb.log ./results/galera-1/
docker cp container_id:/scripts/oltpbench/results ./results/galera-1/oltpbench/
```

### 19. Launch galera-02 and 03

```
cd ../galera-cluster
docker stack deploy --compose-file=docker-compose-3.yml galera
```

Verify that galera cluster has 3 members
```
docker run -it --rm --network=mynet mariadb:${MARIADB_VERSION:-10.2.11} mysql -h galera-01

SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size';
```

### 20. Run 3-node galera tests

*Repeat Run commands from 18*

Copy results
```
docker cp container_id:/scripts/galera-sysbench.log ./results/galera-3/
docker cp container_id:/scripts/galera-oltpbench.log ./results/galera-3/
docker cp container_id:/scripts/galera-ycsb.log ./results/galera-3/
docker cp container_id:/scripts/oltpbench/results ./results/galera-3/oltpbench/
```

### Load balancing

You can run the tests while load balancing the queries among all nodes. An improvement of up to 60% has been observed for read workloads

There are 2 options included:

HAProxy (more flexibility)
```
load-balancer:26257
load-balancer:3306
```

Docker Swarm Mode (much lower overhead)
```
cockroachdb:26257
galera:3306
```

### How to clean up and start from scratch

Stacks
```
docker stack rm monitoring
docker stack rm cockroachdb
docker stack rm galera
```

Volumes
```
docker volume rm monitoring_prometheus
docker volume rm monitoring_grafana
docker volume rm cockroachdb_cockroachdb-01
docker volume rm cockroachdb_cockroachdb-02
docker volume rm cockroachdb_cockroachdb-03
docker volume rm galera_galera-01
docker volume rm galera_galera-02
docker volume rm galera_galera-03
```

Alternatively, remove all volumes and images
```
docker prune -af
```

### Parsing

Sysbench
```
cat sysbench.log | egrep "threads:|transactions:|queries:|min:|avg:|max:|percentile:" | tr -d "\n" | sed 's/Number of threads: /\n/g' | sed 's/[A-Za-z\/]\{1,\}://g' | sed -e 's/95th//g' -e 's/per sec.)//g' -e 's/ms//g' -e 's/(//g' | sed 's/ \{1,\}/,/g'
```

YCSB
```
cat ycsb.log | egrep "started.*(threads|tps)|Throughput|AverageLatency|95thPercentileLatency|99thPercentileLatency" | sed -e 's/\[CLEANUP\].*//g' -e 's/.*95thPercentileLatency(us),//g' -e 's/.*AverageLatency(us),//g' -e 's/.*99thPercentileLatency(us),//g' -e 's/.*Throughput(ops\/sec), //g' | sed 's/[A-Za-z\/]\{1,\}: //g' | sed 's/).*/\n/g' | tr -d "\n" | sed 's/(/\n/g' | sed 's/started.*//g' | sed 's/s/s,/g' | sed 's/ \{1,\}/,/g'
```

### Tests

- Sysbench OLTP Read-Write
- Sysbench OLTP Read-Only
- Sysbench OLTP Write-Only
- Sysbench OLTP Update-Non-Index
- YCSB Workload A Update-Heavy (50/50)
- YCSB Workload B Mostly-Reads (95/5)
- OLTP-Bench Linkbench (Facebook)
- OLTP-Bench Twitter

Each test will have following arrangements:
- Single node, 3-node cluster
- 1, 2, 4, 8, 16, 32, 64, 96, 128 concurrent clients

With YCSB we will have an additional arragement:
- 64 128 192 256 320 target transactions per second

### Metrics to look for

- data load speed
- throughput (transactions per second)
- latency (average and 95%) with a varying number of clients
- latency (average and 95%) with a varying number of transactions per second
- degradation over time
- iostat
- CPU usage
- database size

### Room for improvement

- merge galera and cockroachdb tests to avoid duplication
- a one-stop script which does all of the above
- parse results into json or csv
- global mysql_exporter instead of manual per-node
