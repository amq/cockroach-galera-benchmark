## Status

- did a *preliminary* single-node testing, see [cockroachdb/cockroach#17777](https://github.com/cockroachdb/cockroach/issues/17777#issuecomment-347243141)

## Roadmap

- the performance of CockroachDB seems to be too low, make sure I didn't miss something obvious
- investigate oltpbench compatibility issues, possibly add a dialect file
- evaluate special / pareto / zipfian distribution usage for sysbench
- try MaxScale load balancer to balance reads while sending writes to a single node
- launch the final testing, I expect it to last for a few days without pauses

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
    --amazonec2-region eu-central-1 \
    --amazonec2-zone a \
    --amazonec2-instance-type r4.xlarge \
    --amazonec2-volume-type gp2 \
    --amazonec2-root-size 500 \
    --amazonec2-ami ami-3d2bab52 \
    ${BASE_HOSTNAME:-node}-0$i
done
```

Refer to [https://docs.docker.com/machine/drivers/aws/](docs) on how to set up the credentials

### 2. Verify that system settings are above recommended

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

When done, exit from ssh.

### 3. Initialize Swarm on first node

**Locally**

```
eval "$(docker-machine env ${BASE_HOSTNAME:-node}-01)"
docker swarm init --advertise-addr=eth1
```

**AWS**

```
eval "$(docker-machine env ${BASE_HOSTNAME:-node}-01)"
docker swarm init --advertise-addr=ens3
```

Get the join command:
```
docker swarm join-token worker | grep docker | xargs
```

### 4. Join Swarm on other nodes

```
eval "$(docker-machine env ${BASE_HOSTNAME:-node}-02)"
```

*Run the join command from last step and repeat for node-03*

### 5. Create attachable network

```
docker network create --driver overlay --attachable mynet
```

### 6. Launch monitoring services

```
cd monitoring
docker stack deploy --compose-file=docker-compose.yml monitoring
```

### 7. Load prometheus configuration

```
docker cp monitoring/prometheus.yml monitoring_prometheus.1.$(docker service ps --no-trunc -f 'desired-state=running' -f 'name=monitoring_prometheus.1' monitoring_prometheus -q):/etc/prometheus/prometheus.yml
docker service scale monitoring_prometheus=0
docker service scale monitoring_prometheus=1
```

### 8. Verify that monitoring works

Prometheus  
http://ip-of-node-01:9090/

Grafana  
http://ip-of-node-01:3000/

### 9. Import grafana dashboards

[CockroachDB](https://github.com/cockroachdb/cockroach/tree/master/monitoring/grafana-dashboards)

[MySQL and Galera](https://github.com/percona/grafana-dashboards/tree/master/dashboards)

[System information](https://grafana.com/dashboards/405)

[Docker Swarm](https://grafana.com/dashboards/2603)

### 10. Launch cockroachdb-01

```
cd ../cockroachdb-cluster
docker stack deploy --compose-file=docker-compose-1.yml cockroachdb
```

### 11. Initialize cockroachdb cluster

```
docker run -it --rm --network=mynet cockroachdb/cockroach:${COCKROACHDB_VERSION:-v1.1.2} init --host=cockroachdb-01 --insecure
```

### 12. Verify that cockroachdb works

Web console  
http://ip-of-node-01:8080/

```
docker run -it --rm --network=mynet cockroachdb/cockroach:${COCKROACHDB_VERSION:-v1.1.2} node status --host=cockroachdb-01 --insecure

docker run -it --rm --network=mynet cockroachdb/cockroach:${COCKROACHDB_VERSION:-v1.1.2} sql --host=cockroachdb-01 --insecure
```

### 13. Launch galera-01

```
cd ../galera-cluster
docker stack deploy --compose-file=docker-compose-1.yml galera
```

### 14. Verify that galera works

```
docker run -it --rm --network=mynet mariadb:${MARIADB_VERSION:-10.2} mysql -h galera-01

SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size';
```

### 15. How to clean up and start from scratch

```
docker stack rm monitoring
docker stack rm cockroachdb
docker stack rm galera
docker volume rm monitoring_prometheus
docker volume rm monitoring_prometheus-config
docker volume rm monitoring_grafana
docker volume rm cockroachdb_cockroachdb-01
docker volume rm galera_galera-01
```

The volume commands can be shortened. This will remove all unused volumes and images:
```
docker prune -af
```

### 16. Run single-node tests

```
cd ../tester
docker build -t tester .

docker run -i --rm --network=mynet tester /scripts/sysbench.sh > sysbench-1.log
docker run -i --rm --network=mynet tester /scripts/ycsb.sh > ycsb-1.log
docker run -i --rm --network=mynet tester /scripts/oltpbench.sh > oltpbench-1.log
```

### 17. Launch cockroachdb-02 and 03

```
cd ../cockroachdb-cluster
docker stack deploy --compose-file=docker-compose-3.yml cockroachdb
```

### 18. Verify that cockroachdb cluster has 3 members

```
docker run -it --rm --network=mynet cockroachdb/cockroach:${COCKROACHDB_VERSION:-v1.1.2} node status --host=cockroachdb-01 --insecure
```

### 19. Launch galera-02 and 03

```
cd ../galera-cluster
docker stack deploy --compose-file=docker-compose-3.yml galera
```

### 20. Verify that galera cluster has 3 members

```
docker run -it --rm --network=mynet mariadb:${MARIADB_VERSION:-10.2} mysql -h galera-01

SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size';
```

### 21. Run testes on 3 nodes

```
docker run -i --rm tester /scripts/sysbench.sh > sysbench-3.log
docker run -i --rm tester /scripts/ycsb.sh > ycsb-3.log
docker run -i --rm tester /scripts/oltpbench.sh > oltpbench-3.log
```

### Parsing

Sysbench
```
cat sysbench-1.log | egrep "threads:|transactions:|queries:|min:|avg:|max:|percentile:" | tr -d "\n" | sed 's/Number of threads: /\n/g' | sed 's/[A-Za-z\/]\{1,\}://g' | sed -e 's/95th//g' -e 's/per sec.)//g' -e 's/ms//g' -e 's/(//g' | sed 's/ \{1,\}/,/g'
```

### Tests

- Sysbench OLTP Read-Write
- Sysbench OLTP Read-Only
- Sysbench OLTP Write-Only
- Sysbench OLTP Update-Non-Index
- YCSB Workload A Update-Heavy (50/50)
- YCSB Workload B Mostly-Reads (95/5)
- YCSB Workload D Read-Latest (95/5)
- OLTP-Bench Linkbench (Facebook)
- OLTP-Bench Twitter

Each test will have following arrangements:
- Single node, 3-node cluster
- 1, 2, 4, 8, 16, 32, 64, 96, 128, 192, 256 concurrent clients

With YCSB we will have an additional arragement:
- 500, 1000, ..., 10000 target transactions per second

### Metrics to look for

- data load speed
- throughput (transactions per second)
- latency (average and 95%) with a varying number of clients
- latency (average and 95%) with a varying number of transactions per second
- iostat
- CPU usage
- database size

### Room for improvement

- simplify galera initialization
- merge galera and cockroachdb tests to avoid duplication
- a one-stop script which does all of the above
- parse results into json or csv
- global mysql_exporter instead of manual per-node
