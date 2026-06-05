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