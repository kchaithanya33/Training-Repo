# Database Management Tools

| Database             | Management Tool              |
| -------------------- | ---------------------------- |
| Oracle Database      | Oracle SQL Developer         |
| PostgreSQL           | pgAdmin                      |
| Microsoft SQL Server | SQL Server Management Studio |
| MySQL                | MySQL Workbench              |
| SQLite               | DB Browser for SQLite        |


## Oracle Database

**Oracle SQL Developer** is installed and can be downloaded from the following link:

- Oracle SQL Developer (Version 24.3.1):  
  https://download.oracle.com/otn_software/java/sqldeveloper/sqldeveloper-24.3.1.347.1826-x64.zip

 # Oracle CDC with Debezium Setup Guide

This guide walks you through setting up **Change Data Capture (CDC)** for Oracle Database using **Debezium** with LogMiner.

## Prerequisites
- Oracle XE (with PDB `XEPDB1`)
- SQL Developer
- Docker + Docker Compose
- Debezium + Kafka + Zookeeper setup

---

# Oracle CDC using Debezium (with Audit Columns & Trigger)

## Step 1: Create SYS Connection in SQL Developer

**Connection Details:**

| Field          | Value          |
|----------------|----------------|
| Name           | SYS_XEPDB1     |
| Username       | SYS            |
| Password       | Your SYS Password |
| Hostname       | localhost      |
| Port           | 1521           |
| Service Name   | XEPDB1         |
| Role           | SYSDBA         |

Click **Test → Connect**.

## Step 2: Verify Current Container

```sql
SHOW CON_NAME;
```

If it is not `XEPDB1`:

```sql
ALTER SESSION SET CONTAINER = XEPDB1;
SHOW CON_NAME;
```

**Expected:** `XEPDB1`

## Step 3: Remove Existing Users (Optional)

```sql
DROP USER CDC_USER CASCADE;
DROP USER DEBEZIUM CASCADE;
```

(Ignore `ORA-01918: user does not exist`)

## Step 4: Create CDC_USER

```sql
CREATE USER CDC_USER IDENTIFIED BY cdc123;

GRANT CREATE SESSION TO CDC_USER;
GRANT CREATE TABLE TO CDC_USER;
GRANT CREATE TRIGGER TO CDC_USER;
GRANT CREATE SEQUENCE TO CDC_USER;
GRANT UNLIMITED TABLESPACE TO CDC_USER;
```

**Verify:**

```sql
SELECT privilege
FROM dba_sys_privs
WHERE grantee='CDC_USER';
```

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

## Step 7: Enable Archive Log Mode

**Check:**

```sql
ARCHIVE LOG LIST;
```

If disabled:

```sql
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
```

**Verify:**

```sql
ARCHIVE LOG LIST;
```

**Expected:** `Database log mode: Archive Mode`

## Step 8: Enable Supplemental Logging

```sql
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE FORCE LOGGING;
```

**Verify:**

```sql
SELECT supplemental_log_data_min, force_logging
FROM v$database;
```

**Expected:** `YES` for both.

## Step 9: Create CDC_USER Connection

| Field      | Value     |
|------------|-----------|
| Username   | CDC_USER  |
| Password   | cdc123    |
| Service    | XEPDB1    |
| Role       | Default   |

## Step 10: Create Employee Table (with Audit Columns)

```sql
CREATE TABLE EMPLOYEE (
    EMP_ID NUMBER PRIMARY KEY,
    EMP_NAME VARCHAR2(100),
    DEPARTMENT VARCHAR2(100),
    SALARY NUMBER,

    CREATED_BY VARCHAR2(100),
    CREATED_AT TIMESTAMP,

    UPDATED_BY VARCHAR2(100),
    UPDATED_AT TIMESTAMP,

    DELETED_BY VARCHAR2(100),
    DELETED_AT TIMESTAMP
);
```

## Step 11: Create Audit Trigger

```sql
CREATE OR REPLACE TRIGGER TRG_EMPLOYEE_AUDIT
BEFORE INSERT OR UPDATE ON EMPLOYEE
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        :NEW.CREATED_BY := USER;
        :NEW.CREATED_AT := SYSTIMESTAMP;
    ELSIF UPDATING THEN
        :NEW.UPDATED_BY := USER;
        :NEW.UPDATED_AT := SYSTIMESTAMP;
    END IF;
END;
/
```

## Step 12: Insert Sample Data

```sql
INSERT INTO EMPLOYEE (EMP_ID, EMP_NAME, DEPARTMENT, SALARY)
VALUES (1, 'John', 'IT', 50000);

INSERT INTO EMPLOYEE (EMP_ID, EMP_NAME, DEPARTMENT, SALARY)
VALUES (2, 'Sam', 'HR', 60000);

COMMIT;
```

(The trigger will automatically populate `CREATED_BY` and `CREATED_AT`.)

## Step 13: Grant Table Access

```sql
GRANT SELECT ON CDC_USER.EMPLOYEE TO DEBEZIUM;
```

## Step 14: Create DEBEZIUM Connection

| Field      | Value      |
|------------|------------|
| Username   | DEBEZIUM   |
| Password   | dbz123     |
| Service    | XEPDB1     |
| Role       | Default    |

## Step 15: Start Docker

```bash
docker compose down
docker compose up -d
docker ps
```

**Expected containers:** `zookeeper`, `kafka`, `connect`, `kafdrop`

## Step 16: Verify Oracle Connector

```bash
curl http://localhost:8083/connector-plugins
```

Look for: `io.debezium.connector.oracle.OracleConnector`

## Step 17: Create Oracle Debezium Connector

Save the following as `oracle-cdc.json`:

```json
{
  "name": "oracle-cdc-connector",
  "config": {
    "connector.class": "io.debezium.connector.oracle.OracleConnector",
    "tasks.max": "1",

    "database.hostname": "host.docker.internal",
    "database.port": "1521",

    "database.user": "DEBEZIUM",
    "database.password": "dbz123",

    "database.dbname": "XE",
    "database.pdb.name": "XEPDB1",

    "database.url": "jdbc:oracle:thin:@//host.docker.internal:1521/XEPDB1",

    "topic.prefix": "oracle",

    "schema.include.list": "CDC_USER",
    "table.include.list": "CDC_USER.EMPLOYEE",

    "database.connection.adapter": "logminer",

    "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
    "schema.history.internal.kafka.topic": "schema-changes.oracle",

    "snapshot.locking.mode": "none",
    "snapshot.mode": "initial",

    "poll.interval.ms": "500",

    "provide.transaction.metadata": "true"
  }
}
```


# PostgreSQL → Debezium → Kafka CDC Setup

PostgreSQL is an open-source Relational Database Management System (RDBMS).

## Step 1: Enable Logical Replication

Open:

`C:\Program Files\PostgreSQL\17\data\postgresql.conf`

Find:

``` conf
#wal_level = replica
```

Change to:

``` conf
wal_level = logical
```

Add:

``` conf
max_replication_slots = 10
max_wal_senders = 10
```

Save the file.

### Why wal_level should be logical?

PostgreSQL stores database changes in WAL (Write Ahead Log). Debezium
reads logical WAL entries to capture row-level INSERT, UPDATE and DELETE
operations.

Example:

``` sql
UPDATE employee
SET department='DevOps'
WHERE id=3;
```

WAL contains the old and new values. `wal_level=logical` is required so
Debezium can decode these row-level changes.

`max_replication_slots` stores WAL until Debezium consumes it.

`max_wal_senders` allows replication connections.

------------------------------------------------------------------------

## Step 2: Restart PostgreSQL

``` powershell
net stop postgresql-x64-17
net start postgresql-x64-17
```

------------------------------------------------------------------------

## Step 3: Verify

``` sql
SHOW wal_level;
SHOW max_replication_slots;
```

Expected:

    logical
    10

------------------------------------------------------------------------

## Step 4: Create Debezium User

``` sql
CREATE USER debezium
WITH PASSWORD 'debezium'
REPLICATION;
```

------------------------------------------------------------------------

## Step 5: Grant Permissions

``` sql
GRANT CONNECT ON DATABASE postgres TO debezium;
GRANT CREATE ON DATABASE postgres TO debezium;
GRANT USAGE ON SCHEMA public TO debezium;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO debezium;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO debezium;
```

------------------------------------------------------------------------

## Step 6: Create Tables

``` sql
CREATE TABLE employee
(
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    department VARCHAR(100)
);

CREATE TABLE employee_audit
(
    audit_id SERIAL PRIMARY KEY,
    emp_id INT,
    operation VARCHAR(10),
    db_user TEXT,
    changed_at TIMESTAMP,
    old_data JSONB,
    new_data JSONB
);

INSERT INTO employee(name,department)
VALUES
('John','IT'),
('Mary','HR');
```

### Create Trigger Function

``` sql
CREATE OR REPLACE FUNCTION audit_employee_changes()
RETURNS TRIGGER AS $$
BEGIN
IF TG_OP='INSERT' THEN
INSERT INTO employee_audit(emp_id,operation,db_user,changed_at,old_data,new_data)
VALUES(NEW.id,'INSERT',CURRENT_USER,NOW(),NULL,to_jsonb(NEW));
RETURN NEW;
ELSIF TG_OP='UPDATE' THEN
INSERT INTO employee_audit(emp_id,operation,db_user,changed_at,old_data,new_data)
VALUES(NEW.id,'UPDATE',CURRENT_USER,NOW(),to_jsonb(OLD),to_jsonb(NEW));
RETURN NEW;
ELSIF TG_OP='DELETE' THEN
INSERT INTO employee_audit(emp_id,operation,db_user,changed_at,old_data,new_data)
VALUES(OLD.id,'DELETE',CURRENT_USER,NOW(),to_jsonb(OLD),NULL);
RETURN OLD;
END IF;
END;
$$ LANGUAGE plpgsql;
```

### Create Trigger

``` sql
CREATE TRIGGER trg_employee_audit
AFTER INSERT OR UPDATE OR DELETE
ON employee
FOR EACH ROW
EXECUTE FUNCTION audit_employee_changes();
```

The trigger automatically records the PostgreSQL login (`CURRENT_USER`),
timestamp, operation and row values into `employee_audit`.

------------------------------------------------------------------------

## Step 7: Enable Before Images

``` sql
ALTER TABLE employee REPLICA IDENTITY FULL;
```

This allows Debezium to send complete `before` and `after` values.

------------------------------------------------------------------------

## Step 8: Create Publication

``` sql
CREATE PUBLICATION debezium_pub
FOR TABLE public.employee,
         public.employee_audit;
```

Verify:

``` sql
SELECT * FROM pg_publication_tables;
```

------------------------------------------------------------------------

## Step 9

``` bash
docker ps
```

------------------------------------------------------------------------

## Step 10

``` bash
curl http://localhost:8083/connector-plugins
```

Verify `io.debezium.connector.postgresql.PostgresConnector`.

------------------------------------------------------------------------

## Step 11: Connector

``` json
{
"name":"postgres-cdc-connector",
"config":{
"connector.class":"io.debezium.connector.postgresql.PostgresConnector",
"tasks.max":"1",
"database.hostname":"host.docker.internal",
"database.port":"5433",
"database.user":"debezium",
"database.password":"debezium",
"database.dbname":"postgres",
"topic.prefix":"postgres",
"plugin.name":"pgoutput",
"slot.name":"debezium_slot",
"publication.name":"debezium_pub",
"publication.autocreate.mode":"disabled",
"table.include.list":"public.employee,public.employee_audit",
"schema.history.internal.kafka.bootstrap.servers":"kafka:9092",
"schema.history.internal.kafka.topic":"schema-changes.postgres",
"poll.interval.ms":"1000",
"provide.transaction.metadata":"true"
}
}
```

`poll.interval.ms` controls how frequently the connector polls
PostgreSQL.

`provide.transaction.metadata` includes transaction metadata with CDC
events.

------------------------------------------------------------------------

## Step 12: Create Connector

POST the JSON to:

`http://localhost:8083/connectors`

Verify:

``` bash
curl http://localhost:8083/connectors/postgres-cdc-connector/status
```

Expected state:

``` json
{
 "connector":{"state":"RUNNING"},
 "tasks":[{"state":"RUNNING"}]
}
```
---


# SQLite CDC to Kafka Setup Guide

This guide explains how to implement Change Data Capture (CDC) for SQLite and stream changes to Kafka using triggers and a custom Python producer.

## Step 1: Download SQLite
Download and extract SQLite to:
`C:\Users\Chaitanya\Downloads\sqlite`

## Step 2: Open Database
```bash
cd C:\Users\Chaitanya\Downloads\sqlite
.\sqlite3.exe employee.db
```

Verify:
```sql
.databases
```

## Step 3: Create Employee Table
```sql
CREATE TABLE employee(
    id INTEGER PRIMARY KEY,
    name TEXT,
    salary INTEGER,
    modified_by TEXT
);
```

> **Note**: We add `modified_by` because the application knows who is logged in.

## Step 4: Create CDC Table
```sql
CREATE TABLE employee_changes(
    cdc_id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER,
    operation TEXT,
    changed_by TEXT,
    changed_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

## Step 5: Create Offset Table
```sql
CREATE TABLE producer_offset(
    last_cdc_id INTEGER
);

INSERT INTO producer_offset VALUES (0);
```

## Step 6: Create Triggers

### INSERT Trigger
```sql
CREATE TRIGGER employee_insert
AFTER INSERT ON employee
BEGIN
    INSERT INTO employee_changes(employee_id, operation, changed_by)
    VALUES(NEW.id, 'INSERT', NEW.modified_by);
END;
```

### UPDATE Trigger
```sql
CREATE TRIGGER employee_update
AFTER UPDATE ON employee
BEGIN
    INSERT INTO employee_changes(employee_id, operation, changed_by)
    VALUES(NEW.id, 'UPDATE', NEW.modified_by);
END;
```

### DELETE Trigger
```sql
CREATE TRIGGER employee_delete
AFTER DELETE ON employee
BEGIN
    INSERT INTO employee_changes(employee_id, operation, changed_by)
    VALUES(OLD.id, 'DELETE', OLD.modified_by);
END;
```

## Step 7: Verify Tables
```sql
.tables
```

**Expected Output:**
```
employee
employee_changes
producer_offset
```

## Step 8: Insert Sample Data
```sql
INSERT INTO employee VALUES(1, 'John', 50000, 'chaitanya');
```

Verify CDC:
```sql
SELECT * FROM employee_changes;
```

**Example Output:**
```
1|1|INSERT|chaitanya|2026-07-13 16:00:00
```

## Step 9: Docker Compose (Kafka Stack)
Create `docker-compose.yml`:

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
      - "29092:29092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_INTERNAL:PLAINTEXT
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:9092,PLAINTEXT_INTERNAL://0.0.0.0:29092
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092,PLAINTEXT_INTERNAL://kafka:29092
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT_INTERNAL
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
      BOOTSTRAP_SERVERS: kafka:29092
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
      KAFKA_BROKERCONNECT: kafka:29092

volumes:
  kafka_data:
```

## Step 10: Start Containers
```bash
docker compose down
docker compose up -d
```

Verify:
```bash
docker ps
```

## Step 11: Create Kafka Topic
```bash
docker exec -it kafka kafka-topics --create --topic sqlite.employee_changes --bootstrap-server localhost:9092
```

Verify topics:
```bash
docker exec -it kafka kafka-topics --list --bootstrap-server localhost:9092
```

## Step 12: Install Kafka Library
```bash
pip install kafka-python
```

## Step 13: Create Producer (`sqlite_kafka_producer.py`)
```python
import sqlite3
import json
import time
from kafka import KafkaProducer

producer = KafkaProducer(
    bootstrap_servers="localhost:9092",
    value_serializer=lambda x: json.dumps(x).encode("utf-8")
)

conn = sqlite3.connect("employee.db")
cursor = conn.cursor()

print("SQLite CDC Producer Started...")

while True:
    cursor.execute("SELECT last_cdc_id FROM producer_offset")
    last_id = cursor.fetchone()[0]

    cursor.execute("""
        SELECT cdc_id, employee_id, operation, changed_by, changed_at
        FROM employee_changes
        WHERE cdc_id > ?
        ORDER BY cdc_id
    """, (last_id,))

    rows = cursor.fetchall()

    for row in rows:
        data = {
            "cdc_id": row[0],
            "employee_id": row[1],
            "operation": row[2],
            "changed_by": row[3],
            "changed_at": row[4]
        }

        producer.send("sqlite.employee_changes", data)
        print("Sent:", data)
        last_id = row[0]

    producer.flush()

    cursor.execute("UPDATE producer_offset SET last_cdc_id=?", (last_id,))
    conn.commit()

    time.sleep(1)
```

## Step 14: Run Producer
```bash
python sqlite_kafka_producer.py
```

## Step 15: Start Consumer (for verification)
```bash
docker exec -it kafka kafka-console-consumer \
--topic sqlite.employee_changes \
--bootstrap-server localhost:9092 \
--from-beginning
```

## Step 16: Simulate Application Changes
```sql
INSERT INTO employee VALUES(2, 'David', 60000, 'chaitanya');

UPDATE employee SET salary = 70000, modified_by = 'admin' WHERE id = 2;

DELETE FROM employee WHERE id = 2;
```

**Expected Kafka Output:**
```json
{
  "cdc_id": 1,
  "employee_id": 2,
  "operation": "INSERT",
  "changed_by": "chaitanya",
  "changed_at": "2026-07-13 16:00:00"
}
{
  "cdc_id": 2,
  "employee_id": 2,
  "operation": "UPDATE",
  "changed_by": "admin",
  "changed_at": "2026-07-13 16:05:00"
}
```

---
---


# Microsoft SQL Server  CDC to Kafka Setup Guide


## Docker Setup

This project includes two Docker-related files. Below is a short explanation of what each file does, followed by the file contents so you can copy them directly.

- `Dockerfile`: Builds a Kafka Connect image that includes the Debezium SQL Server connector and the Camel AWS2 SQS Kafka connector. Use this when you want a single image with required plugins pre-installed.
- `docker-compose.yaml`: Starts the local services (Zookeeper, Kafka, Connect, and Kafdrop). It mounts the Connect image built by the `Dockerfile` and exposes the Connect REST API on port `8083`.

### Dockerfile

Copy the code below into a file named `Dockerfile` in the project root.

```Dockerfile
FROM confluentinc/cp-kafka-connect:7.5.0

# Debezium (SQL Server CDC)
RUN confluent-hub install --no-prompt debezium/debezium-connector-sqlserver:2.5.4

# Create plugin folder
RUN mkdir -p /usr/share/confluent-hub-components/camel-aws2-sqs

# Download Camel AWS2 SQS connector manually from Maven
RUN curl -L -o /tmp/camel-sqs.tar.gz \
  https://repo1.maven.org/maven2/org/apache/camel/kafkaconnector/camel-aws2-sqs-kafka-connector/0.11.0/camel-aws2-sqs-kafka-connector-0.11.0-package.tar.gz

# Extract it into Kafka Connect plugin path
RUN tar -xvzf /tmp/camel-sqs.tar.gz -C /usr/share/confluent-hub-components/camel-aws2-sqs

# cleanup
RUN rm /tmp/camel-sqs.tar.gz
```

### docker-compose.yaml

Copy the code below into a file named `docker-compose.yaml` in the project root.

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

      CONNECT_BOOTSTRAP_SERVERS: kafka:9092
      CONNECT_REST_PORT: 8083
      CONNECT_REST_ADVERTISED_HOST_NAME: connect

      CONNECT_GROUP_ID: connect-group

      CONNECT_CONFIG_STORAGE_TOPIC: connect-configs
      CONNECT_OFFSET_STORAGE_TOPIC: connect-offsets
      CONNECT_STATUS_STORAGE_TOPIC: connect-status

      CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: 1

      CONNECT_KEY_CONVERTER: org.apache.kafka.connect.storage.StringConverter
      CONNECT_VALUE_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE: "false"

      CONNECT_PLUGIN_PATH: /usr/share/java,/usr/share/confluent-hub-components

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

## How to run

1. Build and start the services (from the project root):

```bash
docker-compose up -d --build
```

2. Verify services are running:

```bash
docker ps
```

# SQL Server CDC Setup (Step-by-Step)

This document explains how to set up SQL Server, create login, database, table, and enable Change Data Capture (CDC).

---

## 1. Create Database

### SQL Code:
```sql
CREATE DATABASE CDC_Demo_DB;
GO
```
## 2. Create SQL Server Login (Username + Password)

### SQL Code:
```sql
CREATE LOGIN cdc_user WITH PASSWORD = 'StrongPass@123';
GO
```

## 3. Create Table

### SQL Code:
```sql
CREATE TABLE dbo.employees (
    emp_id INT PRIMARY KEY,
    emp_name VARCHAR(100),
    department VARCHAR(50),
    salary INT,
    created_at DATETIME DEFAULT GETDATE()
);
GO
```
## Step 4: Enable CDC on Database

### SQL Code:

```sql
EXEC sys.sp_cdc_enable_db;
GO
```

## 5. Enable CDC on Table

### SQL Code:
```sql
EXEC sys.sp_cdc_enable_table
@source_schema = N'dbo',
@source_name   = N'employees',
@role_name     = NULL;
GO
```

# SQL Server to Kafka (Debezium Source Connector)

---

## Debezium SQL Server Source Connector Configuration (JSON)

### Source Connector (SQL Server → Kafka)

```json
{
  "name": "sqlserver-debezium-source",
  "config": {
    "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
    "tasks.max": "1",

    "database.hostname": "host.docker.internal",
    "database.port": "1433",
    "database.user": "cdc_user",
    "database.password": "StrongPass@123",

    "database.names": "CDC_Demo_DB",

    "topic.prefix": "sqlserver",

    "table.include.list": "dbo.employees",

    "database.history.kafka.bootstrap.servers": "kafka:9092",
    "database.history.kafka.topic": "schema-changes.employees",

    "include.schema.changes": "true",

    "snapshot.mode": "initial",

    "tombstones.on.delete": "true"
  }
}
```


# MySQL → Debezium → Kafka CDC Setup

## Step 1: Enable Binary Logging

Open MySQL configuration.

**Windows:**
`C:\ProgramData\MySQL\MySQL Server 8.0\my.ini`

Find the `[mysqld]` section.

Add or modify:

```ini
[mysqld]

server-id=1
log_bin=mysql-bin
binlog_format=ROW
binlog_row_image=FULL
expire_logs_days=10
```

Save the file.

### Why?

- **server-id**: Every MySQL server participating in replication must have a unique ID.
- **log_bin**: Enables Binary Logs. Every database change (INSERT, UPDATE, DELETE) is written to the Binary Log. Debezium reads this Binary Log.
- **binlog_format=ROW**: Required by Debezium. Stores row-level changes instead of just the SQL statement.
- **binlog_row_image=FULL**: Stores the complete row before and after changes. Useful for UPDATE and DELETE.

## Step 2: Restart MySQL

**Windows**
```bash
net stop MySQL80
net start MySQL80
```

## Step 3: Verify Configuration

```sql
SHOW VARIABLES LIKE 'log_bin';
SHOW VARIABLES LIKE 'binlog_format';
SHOW VARIABLES LIKE 'binlog_row_image';
```

**Expected:**
- `log_bin = ON`
- `binlog_format = ROW`
- `binlog_row_image = FULL`

## Step 4: Create Debezium User

```sql
CREATE USER 'debezium' IDENTIFIED BY 'dbz123';
```

## Step 5: Grant Permissions

```sql
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT
ON *.*
TO 'debezium';

FLUSH PRIVILEGES;
```

## Step 6: Create Database

```sql
CREATE DATABASE company;
USE company;
```

## Step 7: Create Employee Table

```sql
CREATE TABLE employee (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100),
    department VARCHAR(100),
    salary DECIMAL(10,2)
);
```

## Step 8: Create Audit Table

```sql
CREATE TABLE employee_audit (
    audit_id INT AUTO_INCREMENT PRIMARY KEY,
    emp_id INT,
    operation VARCHAR(20),
    db_user VARCHAR(100),
    changed_at DATETIME,
    old_data JSON,
    new_data JSON
);
```

## Step 9: Create INSERT Trigger

```sql
DELIMITER $$

CREATE TRIGGER trg_employee_insert
AFTER INSERT ON employee
FOR EACH ROW
BEGIN
    INSERT INTO employee_audit (
        emp_id, operation, db_user, changed_at, old_data, new_data
    )
    VALUES (
        NEW.id,
        'INSERT',
        CURRENT_USER(),
        NOW(),
        NULL,
        JSON_OBJECT(
            'id', NEW.id,
            'name', NEW.name,
            'department', NEW.department,
            'salary', NEW.salary
        )
    );
END$$

DELIMITER ;
```

## Step 10: Create UPDATE Trigger

```sql
DELIMITER $$

CREATE TRIGGER trg_employee_update
AFTER UPDATE ON employee
FOR EACH ROW
BEGIN
    INSERT INTO employee_audit (
        emp_id, operation, db_user, changed_at, old_data, new_data
    )
    VALUES (
        NEW.id,
        'UPDATE',
        CURRENT_USER(),
        NOW(),
        JSON_OBJECT(
            'id', OLD.id,
            'name', OLD.name,
            'department', OLD.department,
            'salary', OLD.salary
        ),
        JSON_OBJECT(
            'id', NEW.id,
            'name', NEW.name,
            'department', NEW.department,
            'salary', NEW.salary
        )
    );
END$$

DELIMITER ;
```

## Step 11: Create DELETE Trigger

```sql
DELIMITER $$

CREATE TRIGGER trg_employee_delete
AFTER DELETE ON employee
FOR EACH ROW
BEGIN
    INSERT INTO employee_audit (
        emp_id, operation, db_user, changed_at, old_data, new_data
    )
    VALUES (
        OLD.id,
        'DELETE',
        CURRENT_USER(),
        NOW(),
        JSON_OBJECT(
            'id', OLD.id,
            'name', OLD.name,
            'department', OLD.department,
            'salary', OLD.salary
        ),
        NULL
    );
END$$

DELIMITER ;
```

## Step 12: Insert Sample Data

```sql
INSERT INTO employee (name, department, salary)
VALUES 
    ('John', 'IT', 50000),
    ('Mary', 'HR', 60000);
```

## Step 13: Verify Audit Table

```sql
SELECT * FROM employee_audit;
```

## Step 14: Create Debezium Connector

```json
{
  "name": "mysql-cdc-connector",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "tasks.max": "1",
    "database.hostname": "host.docker.internal",
    "database.port": "3306",
    "database.user": "debezium",
    "database.password": "dbz123",
    "database.server.id": "184054",
    "topic.prefix": "mysql",
    "database.include.list": "company",
    "table.include.list": "company.employee,company.employee_audit",
    "database.history.kafka.bootstrap.servers": "kafka:9092",
    "database.history.kafka.topic": "schema-changes.mysql",
    "poll.interval.ms": "1000",
    "provide.transaction.metadata": "true"
  }
}
```

Save this as `mysql-cdc.json`.

## Step 15: Register the Connector

```bash
curl -X POST http://localhost:8083/connectors \
-H "Content-Type: application/json" \
-d @mysql-cdc.json
```

## Step 16: Verify Connector Status

```bash
curl http://localhost:8083/connectors/mysql-cdc-connector/status
```

**Expected:**
```json
{
  "connector": {
    "state": "RUNNING"
  },
  "tasks": [
    {
      "state": "RUNNING"
    }
  ]
}
```

---



