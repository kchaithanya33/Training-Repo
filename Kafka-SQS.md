<h1 align="center">SQL Server CDC to Kafka and SQS Pipeline</h1>

<p align="center">
  SQL Server CDC → Kafka → SQS
</p>

## Overview

This project demonstrates a simple pipeline that captures change-data-capture (CDC) events from SQL Server, streams them into Kafka using Debezium, and forwards messages from Kafka to AWS SQS using a Camel-based Kafka Connect sink. It includes a Docker configuration to run Kafka, Zookeeper, Kafka Connect (with Debezium and Camel SQS connector), and Kafdrop for topic inspection.


<p align="center">
  <img src="https://github.com/kchaithanya33/Training-Repo/blob/c95ff7e75c8ced555df926286c14c86d0b59fd6a/SQL%20Server%20CDC%20to%20Kafka%20and%20SQS%20workflow.png?raw=true" width="300"/>
</p>

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

# Kafka to AWS SQS 


### Step 1: Create AWS SQS Queue

### Step 2: Create IAM Role for Lambda

We are creating an IAM role that allows Lambda to:

- Read from Kafka (if MSK is used)
- Send messages to SQS
- Write logs to CloudWatch

---

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```
### Step 3: Create Lambda Function

We are creating an AWS Lambda function that will receive messages from Kafka and forward them to SQS. This function acts as a processing layer between Kafka and SQS.

---

## Lambda Function Code (Print Event)

We are writing a simple Lambda function that prints the incoming Kafka event for debugging and verification.

### Python Code:
```python
import json

def lambda_handler(event, context):
    print("Received event from Kafka:")
    print(json.dumps(event, indent=2))

    return {
        "statusCode": 200,
        "body": "Event printed successfully"
    }
```


# Kafka to AWS SQS Configuration (JSON)

We are configuring Kafka Connect to send messages from a Kafka topic directly into AWS SQS using a Camel AWS SQS Sink Connector. This allows real-time streaming of Kafka data into SQS without custom code.

---

## Kafka Connect SQS Sink Configuration

### JSON Configuration 

```json
{
  "name": "kafka-to-sqs-sink",
  "config": {
    "connector.class": "org.apache.camel.kafkaconnector.aws2sqs.CamelAws2sqsSinkConnector",
    "tasks.max": "1",

    "topics": "sqlserver.CDC_Demo_DB.dbo.employees",

    "camel.sink.endpoint.queueNameOrArn": "kafka-to-sqs-queue",

    "camel.component.aws2-sqs.region": "ap-south-1",

    "camel.component.aws2-sqs.accessKey": "YOUR_AWS_ACCESS_KEY",

    "camel.component.aws2-sqs.secretKey": "YOUR_AWS_SECRET_KEY",

    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",

    "transforms": "unwrap",

    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "true",
    "transforms.unwrap.delete.handling.mode": "rewrite"
  }
}
