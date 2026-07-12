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

**Note:** Adjust passwords and hostnames as needed for your environment. Always test connections and permissions thoroughly.
