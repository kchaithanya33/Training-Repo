# Database Management Tools

| Database             | Management Tool              |
| -------------------- | ---------------------------- |
| Microsoft SQL Server | SQL Server Management Studio |
| Oracle Database      | Oracle SQL Developer         |
| PostgreSQL           | pgAdmin                      |
| MySQL                | MySQL Workbench              |
| MariaDB              | HeidiSQL or DBeaver          |
| IBM Db2              | IBM Data Studio              |
| SAP HANA             | SAP HANA Studio              |

## Oracle Database

**Oracle SQL Developer** is installed and can be downloaded from the following link:

- Oracle SQL Developer (Version 24.3.1):  
  https://download.oracle.com/otn_software/java/sqldeveloper/sqldeveloper-24.3.1.347.1826-x64.zip

  # Oracle CDC with Debezium Setup Guide

This guide provides a complete step-by-step setup for Oracle Change Data Capture (CDC) using Debezium, including troubleshooting for common issues like "Failed to resolve Oracle database version" and ORA-01045.

## Prerequisites
- Oracle XE database running
- SQL Developer
- Docker environment for Debezium

# Oracle Debezium Docker Setup Guide

This document contains the complete **Docker Compose** and **Dockerfile** configuration for running Debezium with Oracle CDC support, including Kafka, Zookeeper, Kafka Connect, and Kafdrop.

## 1. Dockerfile (for Oracle)

```dockerfile
FROM quay.io/debezium/connect:2.5

USER root

# Oracle JDBC Driver
COPY ojdbc11.jar /usr/share/java/ojdbc11.jar

# Camel AWS SQS connector
RUN mkdir -p /usr/share/confluent-hub-components/camel-aws2-sqs

RUN curl -L -o /tmp/camel-sqs.tar.gz \
  https://repo1.maven.org/maven2/org/apache/camel/kafkaconnector/camel-aws2-sqs-kafka-connector/0.11.0/camel-aws2-sqs-kafka-connector-0.11.0-package.tar.gz

RUN tar -xvzf /tmp/camel-sqs.tar.gz \
  -C /usr/share/confluent-hub-components/camel-aws2-sqs

RUN rm /tmp/camel-sqs.tar.gz

USER 1001
```

### Important Notes
- Download `ojdbc11.jar` from: [Oracle JDBC Downloads](https://www.oracle.com/database/technologies/appdev/jdbc-downloads.html)
- Place `ojdbc11.jar` in the same directory as the Dockerfile before building.


## 2. docker-compose.yml

```yaml
version: '3.8'

services:

  zookeeper:
    image: confluentinc/cp-zookeeper:7.5.0
    container_name: zookeeper
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
    ports:
      - "2181:2181"

  kafka:
    image: confluentinc/cp-kafka:7.5.0
    container_name: kafka
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:9092
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
    volumes:
      - kafka_data:/var/lib/kafka/data

  connect:
    build: .
    container_name: connect
    depends_on:
      - kafka
    ports:
      - "8083:8083"
    environment:
      BOOTSTRAP_SERVERS: kafka:9092
      GROUP_ID: connect-group
      CONFIG_STORAGE_TOPIC: connect-configs
      OFFSET_STORAGE_TOPIC: connect-offsets
      STATUS_STORAGE_TOPIC: connect-status
      CONFIG_STORAGE_REPLICATION_FACTOR: 1
      OFFSET_STORAGE_REPLICATION_FACTOR: 1
      STATUS_STORAGE_REPLICATION_FACTOR: 1
      KEY_CONVERTER: org.apache.kafka.connect.storage.StringConverter
      VALUE_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      VALUE_CONVERTER_SCHEMAS_ENABLE: "false"
      PLUGIN_PATH: /kafka/connect

  kafdrop:
    image: obsidiandynamics/kafdrop
    container_name: kafdrop
    depends_on:
      - kafka
    ports:
      - "9000:9000"
    environment:
      KAFKA_BROKERCONNECT: kafka:9092

volumes:
  kafka_data:
```

## How to Run

1. Place `ojdbc11.jar` next to the Dockerfile.
2. Build the custom Connect image:
   ```bash
   docker build -t debezium-connect-oracle:2.5 .
   ```
3. Start the services:
   ```bash
   docker compose up -d
   ```
4. Verify containers:
   ```bash
   docker ps
   ```
5. Access Kafdrop UI: http://localhost:9000
6. Check connectors: http://localhost:8083/connector-plugins

---

## Oracle CDC with Debezium Setup Guide

## Step 1: Open SQL Developer and Create SYS Connection

| Field       | Value      |
|-------------|------------|
| Name        | SYS_XEPDB1 |
| Username    | SYS        |
| Password    | Your SYS password |
| Hostname    | localhost  |
| Port        | 1521       |
| Service Name| XEPDB1     |
| Role        | SYSDBA     |

- Click **Test** → **Connect**.

## Step 2: Verify Container

```sql
SHOW CON_NAME;
```

If not in XEPDB1:

```sql
ALTER SESSION SET CONTAINER = XEPDB1;
SHOW CON_NAME;
```

**Expected:** `XEPDB1`

## Step 3: Remove Old Users (Optional)

```sql
DROP USER CDC_USER CASCADE;
DROP USER DEBEZIUM CASCADE;
```

Ignore errors: `ORA-01918: user does not exist`

## Step 4: Create CDC_USER

```sql
CREATE USER CDC_USER IDENTIFIED BY cdc123;

GRANT CREATE SESSION TO CDC_USER;
GRANT CREATE TABLE TO CDC_USER;
GRANT UNLIMITED TABLESPACE TO CDC_USER;
```

Verify:

```sql
SELECT privilege FROM dba_sys_privs WHERE grantee='CDC_USER';
```

**Expected privileges:** `CREATE SESSION`, `CREATE TABLE`, `UNLIMITED TABLESPACE`

## Step 5: Create DEBEZIUM User

```sql
CREATE USER DEBEZIUM IDENTIFIED BY dbz123;

GRANT CREATE SESSION TO DEBEZIUM;
GRANT SET CONTAINER TO DEBEZIUM;
GRANT SELECT ANY TABLE TO DEBEZIUM;
GRANT FLASHBACK ANY TABLE TO DEBEZIUM;
GRANT SELECT ANY DICTIONARY TO DEBEZIUM;
GRANT LOGMINING TO DEBEZIUM;
GRANT EXECUTE_CATALOG_ROLE TO DEBEZIUM;
GRANT SELECT_CATALOG_ROLE TO DEBEZIUM;
GRANT CREATE TABLE TO DEBEZIUM;
GRANT UNLIMITED TABLESPACE TO DEBEZIUM;
```

## Step 6: Grant V$ Permissions

```sql
GRANT SELECT ON V_$DATABASE TO DEBEZIUM;
GRANT SELECT ON V_$LOG TO DEBEZIUM;
GRANT SELECT ON V_$LOGFILE TO DEBEZIUM;
GRANT SELECT ON V_$ARCHIVED_LOG TO DEBEZIUM;
GRANT SELECT ON V_$LOGMNR_LOGS TO DEBEZIUM;
GRANT SELECT ON V_$LOGMNR_CONTENTS TO DEBEZIUM;
GRANT SELECT ON V_$TRANSACTION TO DEBEZIUM;
GRANT SELECT ON V_$PARAMETER TO DEBEZIUM;
GRANT SELECT ON V_$PDBS TO DEBEZIUM;
GRANT SELECT ON V_$INSTANCE TO DEBEZIUM;
GRANT SELECT ON V_$THREAD TO DEBEZIUM;
GRANT SELECT ON V_$CONTAINERS TO DEBEZIUM;
GRANT SELECT ON V_$NLS_PARAMETERS TO DEBEZIUM;
GRANT SELECT ON V_$TIMEZONE_NAMES TO DEBEZIUM;
```

## Step 7: Grant Access to CDC_USER Table

After creating the table:

```sql
GRANT SELECT ON CDC_USER.EMPLOYEE TO DEBEZIUM;
```

## Step 8: Enable Archive Log Mode

Check:

```sql
ARCHIVE LOG LIST;
```

**Expected:** Database log mode: Archive Mode

If not enabled:

```sql
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
```

Verify again with `ARCHIVE LOG LIST;`

## Step 9: Enable Supplemental Logging

```sql
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE FORCE LOGGING;
```

Verify:

```sql
SELECT supplemental_log_data_min, force_logging FROM v$database;
```

**Expected:** `YES YES`

## Step 10: Create CDC_USER Connection in SQL Developer

| Field       | Value     |
|-------------|-----------|
| Name        | CDC_USER  |
| Username    | CDC_USER  |
| Password    | cdc123    |
| Hostname    | localhost |
| Port        | 1521      |
| Service Name| XEPDB1    |
| Role        | Default   |

## Step 11: Create Table (as CDC_USER)

```sql
CREATE TABLE EMPLOYEE (
    EMP_ID NUMBER PRIMARY KEY,
    EMP_NAME VARCHAR2(100),
    DEPARTMENT VARCHAR2(100),
    SALARY NUMBER
);
```

## Step 12: Insert Sample Data

```sql
INSERT INTO EMPLOYEE VALUES (1, 'John', 'IT', 50000);
COMMIT;
```

Verify:

```sql
SELECT * FROM EMPLOYEE;
```

**Expected output:**

| EMP_ID | EMP_NAME | DEPARTMENT | SALARY |
|--------|----------|------------|--------|
| 1      | John     | IT         | 50000  |

## Step 13: Create DEBEZIUM Connection in SQL Developer

| Field       | Value     |
|-------------|-----------|
| Name        | DEBEZIUM  |
| Username    | DEBEZIUM  |
| Password    | dbz123    |
| Hostname    | localhost |
| Port        | 1521      |
| Service Name| XEPDB1    |
| Role        | Default   |

## Step 14: Start Docker Services

```bash
docker compose down
docker compose up -d
docker ps
```

**Expected:** zookeeper, kafka, connect, kafdrop containers running.

## Step 15: Verify Oracle Connector

```bash
curl http://localhost:8083/connector-plugins
```

Look for: `io.debezium.connector.oracle.OracleConnector`

## Step 16: Create Debezium Connector

```json
{
  "name": "oracle-cdc-connector",
  "config": {
    "connector.class": "io.debezium.connector.oracle.OracleConnector",
    "tasks.max": "1",

    "database.hostname": "host.docker.internal",
    "database.port": "1521",
    "database.user": "C##DBZ",
    "database.password": "password",
    "database.dbname": "XE",
    "database.pdb.name": "XEPDB1",
    "database.url": "jdbc:oracle:thin:@//host.docker.internal:1521/xepdb1",

    "topic.prefix": "oracle",

    "schema.include.list": "CDC_USER",
    "table.include.list": "CDC_USER.EMPLOYEE",

    "database.connection.adapter": "logminer",

    "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
    "schema.history.internal.kafka.topic": "schema-changes.oracle",

   
    "snapshot.locking.mode": "none",
    "snapshot.mode": "schema_only_recovery"
  }
}
```

---

