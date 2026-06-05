<h1 align="center">SQL Server CDC to Kafka and SQS Pipeline</h1>

<p align="center">
  <img src="https://github.com/kchaithanya33/Training-Repo/blob/c95ff7e75c8ced555df926286c14c86d0b59fd6a/SQL%20Server%20CDC%20to%20Kafka%20and%20SQS%20workflow.png?raw=true" width="500"/>
</p>

1. Kafka is a message streaming system  
It stores data temporarily in topics  
It lets systems send and receive data in real-time  
To connect Kafka with other systems, we use Kafka Connector Plugins  

2. Inside Kafka Connect plugins, we have:  

a. Source Connectors -> Bring data INTO Kafka  
Example: Debezium (SQL Server, MySQL, etc.)  
Flow: Database → Kafka Topic  

b. Sink Connectors: Send data OUT of Kafka  
Example: AWS SQS connector (Camel)  
Flow: Kafka Topic → External System  

