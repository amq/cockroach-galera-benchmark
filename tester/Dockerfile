FROM ubuntu:xenial

ENV SYSBENCH_VERSION=master
ENV YCSB_VERSION=0.12.0
ENV MYSQL_DRIVER_VERSION=5.1.44
ENV POSTGRESQL_DRIVER_VERSION=42.1.4

RUN apt-get update && \
    apt-get -y install \
        git \
        wget \
        make \
        automake \
        libtool \
        pkg-config \
        libaio-dev \
        vim-common \
        libmysqlclient-dev \
        libpq-dev \
        python \
        default-jdk \
        ant \
        mysql-client \
        postgresql-client && \
    apt-get clean

RUN mkdir /scripts

RUN cd /tmp && git clone https://github.com/akopytov/sysbench.git && \
    mv sysbench /scripts/sysbench && \
    cd /scripts/sysbench && \
    git checkout ${SYSBENCH_VERSION} && \
    ./autogen.sh && \
    LDFLAGS=-L/usr/local/opt/openssl/lib ./configure --with-pgsql && \
    make -j && \
    make install

RUN cd /tmp && wget https://github.com/brianfrankcooper/YCSB/releases/download/${YCSB_VERSION}/ycsb-${YCSB_VERSION}.tar.gz && \
    tar -zxvf ycsb-${YCSB_VERSION}.tar.gz && \
    mv ycsb-${YCSB_VERSION} /scripts/ycsb && \
    cd /scripts/ycsb && \
    wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-${MYSQL_DRIVER_VERSION}.tar.gz && \
    tar -zxvf mysql-connector-java-${MYSQL_DRIVER_VERSION}.tar.gz && \
    mv mysql-connector-java-${MYSQL_DRIVER_VERSION}/mysql-connector-java-${MYSQL_DRIVER_VERSION}-bin.jar lib && \
    wget https://jdbc.postgresql.org/download/postgresql-${POSTGRESQL_DRIVER_VERSION}.jar && \
    mv postgresql-${POSTGRESQL_DRIVER_VERSION}.jar lib

RUN cd /tmp && git clone https://github.com/oltpbenchmark/oltpbench.git && \
    mv oltpbench /scripts/oltpbench && \
    cd /scripts/oltpbench && \
    ant

COPY . /scripts
