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

This guide walks you through setting up **Change Data Capture (CDC)** for Oracle Database using **Debezium** with LogMiner.

## Prerequisites
- Oracle XE (with PDB `XEPDB1`)
- SQL Developer
- Docker + Docker Compose
- Debezium + Kafka + Zookeeper setup

---

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

Click **Test** → **Connect**.

---

## Step 2: Verify Current Container

```sql
SHOW CON_NAME;
```

If not `XEPDB1`:

```sql
ALTER SESSION SET CONTAINER = XEPDB1;
SHOW CON_NAME;
```

**Expected:** `XEPDB1`

---

## Step 3: Remove Existing Users (Optional)

```sql
DROP USER CDC_USER CASCADE;
DROP USER DEBEZIUM CASCADE;
```

(Ignore `ORA-01918: User does not exist`)

---

## Step 4: Create CDC_USER

```sql
CREATE USER CDC_USER IDENTIFIED BY cdc123;

GRANT CREATE SESSION TO CDC_USER;
GRANT CREATE TABLE TO CDC_USER;
GRANT UNLIMITED TABLESPACE TO CDC_USER;
```

**Verify:**

```sql
SELECT privilege 
FROM dba_sys_privs 
WHERE grantee='CDC_USER';
```

**Expected:** `CREATE SESSION`, `CREATE TABLE`, `UNLIMITED TABLESPACE`

---

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

---

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

---

## Step 7: Enable Archive Log Mode

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

---

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

**Expected:** `YES` / `YES`

---

## Step 9: Create CDC_USER Connection

| Field     | Value     |
|-----------|-----------|
| Username  | CDC_USER  |
| Password  | cdc123    |
| Service   | XEPDB1    |
| Role      | Default   |

---

## Step 10: Create Employee Table

```sql
CREATE TABLE EMPLOYEE (
    EMP_ID NUMBER PRIMARY KEY,
    EMP_NAME VARCHAR2(100),
    DEPARTMENT VARCHAR2(100),
    SALARY NUMBER,
    CREATED_BY VARCHAR2(100),
    UPDATED_BY VARCHAR2(100),
    DELETED_BY VARCHAR2(100)
);
```

---

## Step 11: Insert Sample Data

```sql
INSERT INTO EMPLOYEE VALUES (1, 'John', 'IT', 50000, 'Chaitanya', NULL, NULL);
INSERT INTO EMPLOYEE VALUES (2, 'Sam', 'HR', 60000, 'Chaitanya', NULL, NULL);
COMMIT;
```

---

## Step 12: Verify Data

```sql
SELECT * FROM EMPLOYEE;
```

---

## Step 13: Update Example

```sql
UPDATE EMPLOYEE 
SET SALARY = 65000, UPDATED_BY = 'Manager1' 
WHERE EMP_ID = 2;
COMMIT;
```

---

## Step 14: Delete Example

```sql
UPDATE EMPLOYEE SET DELETED_BY = 'AdminUser' WHERE EMP_ID = 1;
COMMIT;

DELETE FROM EMPLOYEE WHERE EMP_ID = 1;
COMMIT;
```

---

## Step 15: Grant Access to Table

```sql
GRANT SELECT ON CDC_USER.EMPLOYEE TO DEBEZIUM;
```

---

## Step 16: Create DEBEZIUM Connection

| Field     | Value      |
|-----------|------------|
| Username  | DEBEZIUM   |
| Password  | dbz123     |
| Service   | XEPDB1     |
| Role      | Default    |

---

## Step 17: Start Docker Services

```bash
docker compose down
docker compose up -d
docker ps
```

**Expected containers:** zookeeper, kafka, connect, kafdrop

---

## Step 18: Verify Oracle Connector

```bash
curl http://localhost:8083/connector-plugins
```

Look for: `io.debezium.connector.oracle.OracleConnector`

---

## Step 19: Create Oracle Debezium Connector

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
    "database.url": "jdbc:oracle:thin:@//host.docker.internal:1521/xepdb1",
    "topic.prefix": "oracle",
    "schema.include.list": "CDC_USER",
    "table.include.list": "CDC_USER.EMPLOYEE",
    "database.connection.adapter": "logminer",
    "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
    "schema.history.internal.kafka.topic": "schema-changes.oracle",
    "snapshot.locking.mode": "none",
    "snapshot.mode": "schema_only_recovery",
    "poll.interval.ms": "1000",
    "provide.transaction.metadata": "true"
  }
}
```

---


# PostgreSQL → Debezium → Kafka CDC Setup

PostgreSQL is an open-source Relational Database Management System (RDBMS).

## Step 1: Enable Logical Replication

Open:

`C:\Program Files\PostgreSQL\17\data\postgresql.conf`

Find:

```conf
#wal_level = replica
```

Change to:

```conf
wal_level = logical
```

Add:

```conf
max_replication_slots = 10
max_wal_senders = 10
```

Save the file.

### Why wal_level should be logical?

PostgreSQL stores database changes in WAL.

**WAL** means: **Write Ahead Log**

**Example:**

When we run:

```sql
UPDATE employee
SET department='DevOps'
WHERE id=3;
```

PostgreSQL writes:

**WAL Entry:**

- Old value: Security
- New value: DevOps

By default: `wal_level = replica` supports only **physical replication**.

**Example:**

Primary Database → Replica Database

But Debezium needs **row-level changes**:

**Before:** Security  
**After:** DevOps

Therefore, `wal_level = logical` is required.

Logical replication converts WAL changes into a format Debezium understands.

### Why max_replication_slots?

Replication slots remember how much WAL Debezium consumed.

**Example:**

WAL: 1 2 3 4 5 6

Debezium consumed till 4

PostgreSQL will keep remaining WAL until Debezium reads it.

### Why max_wal_senders?

Allows PostgreSQL to create replication connections.

**Example:**

PostgreSQL  
├── Debezium  
└── Other Replicas

## Step 2: Restart PostgreSQL service

Open PowerShell as Administrator:

```powershell
net stop postgresql-x64-17
```

Then:

```powershell
net start postgresql-x64-17
```

## Step 3: Verify WAL settings

In pgAdmin Query Tool:

Run:

```sql
SHOW wal_level;
```

**Output:** `logical`

Check:

```sql
SHOW max_replication_slots;
```

**Output:** `10`

## Step 4: Create Debezium user

Run as postgres user:

```sql
CREATE USER debezium
WITH PASSWORD 'debezium'
REPLICATION;
```

### Why create Debezium user?

Debezium needs a PostgreSQL account to connect.

The user answers: **WHO** can connect to PostgreSQL?

**Example:**

Debezium Connector → username/password → PostgreSQL

The user `debezium` is used in connector configuration:

`"database.user":"debezium"`

## Step 5: Give permissions to Debezium user

Run:

```sql
GRANT CONNECT ON DATABASE postgres TO debezium;

GRANT CREATE ON DATABASE postgres TO debezium;

GRANT USAGE ON SCHEMA public TO debezium;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO debezium;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO debezium;
```

- `GRANT CONNECT` - Allows database connection.
- `GRANT CREATE` - Allows required database operations.
- `GRANT USAGE` - Allows access to schema.
- `GRANT SELECT` - Allows reading tables.
- `ALTER DEFAULT PRIVILEGES` - Automatically gives permission for future tables.

## Step 6: Create sample table

```sql
CREATE TABLE employee
(
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    department VARCHAR(100)
);

INSERT INTO employee(name,department)
VALUES
('John','IT'),
('Mary','HR');
```

## Step 7: Enable old value capture for UPDATE

```sql
ALTER TABLE employee REPLICA IDENTITY FULL;
```

### Why REPLICA IDENTITY FULL?

By default PostgreSQL sends only changed values.

**Without:**

```json
{
  "before": null,
  "after": {
    "department": "DevOps"
  }
}
```

**With:**

```json
{
  "before": {
    "department": "Security"
  },
  "after": {
    "department": "DevOps"
  }
}
```

This allows Debezium to send complete **before {}** and **after {}** records.

## Step 8: Create Debezium publication

Run as postgres:

```sql
CREATE PUBLICATION debezium_pub
FOR TABLE public.employee;
```

Verify:

```sql
SELECT * FROM pg_publication_tables;
```

**Output:**

| pubname       | schemaname | tablename |
|---------------|------------|-----------|
| debezium_pub  | public     | employee  |

### Why create publication?

Publication decides: **WHAT DATA SHOULD BE CAPTURED?**

**Example database:**

- employee
- customer
- orders

**Publication:** `debezium_pub` → ONLY employee

Debezium reads changes from this publication.

### Difference between Debezium User and Publication

| Component       | Purpose                  |
|-----------------|--------------------------|
| debezium user   | Who can connect          |
| debezium_pub    | What tables can be captured |

**Example:**

- User `debezium` = Employee ID card
- Publication `debezium_pub` = Permission list

Both are required.

## Step 9: Verify Kafka Connect is running

```bash
docker ps
```

Running containers: `kafka`, `connect`, `zookeeper`

## Step 10: Verify Debezium PostgreSQL plugin

```bash
curl http://localhost:8083/connector-plugins
```

Check for: `io.debezium.connector.postgresql.PostgresConnector`

## Step 11: Create Debezium connector JSON

**File:** `postgres-cdc.json`

```json
{
  "name": "postgres-cdc-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",

    "database.hostname": "host.docker.internal",
    "database.port": "5433",
    "database.user": "debezium",
    "database.password": "debezium",
    "database.dbname": "postgres",

    "topic.prefix": "postgres",

    "plugin.name": "pgoutput",

    "slot.name": "debezium_slot",
    "publication.name": "debezium_pub",
    "publication.autocreate.mode": "disabled",

    "table.include.list": "public.employee",

    "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
    "schema.history.internal.kafka.topic": "schema-changes.postgres"
  }
}
```

## Step 14: Create connector

```bash
http://localhost:8083/connectors
```

**Response:** `201 Created`

### Check connector status

```bash
curl http://localhost:8083/connectors/postgres-cdc-connector/status
```

**Successful output:**

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


