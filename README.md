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





