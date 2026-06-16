# Logs

A log is a record of what happened in your application while it was running.

## Why do we use logs?

### 1. Debugging Issues
Logs help developers identify and fix problems by recording errors, exceptions, and application behavior during execution.

### 2. Monitoring Application Health
Logs provide insights into the application's status, such as request counts, failures, and system performance, helping ensure smooth operation.

### 3. Audit and Security
Logs maintain a record of user actions and system events, which is useful for security investigations, compliance, and tracking changes.

### 4. Performance Analysis
Logs help measure execution times, detect bottlenecks, and analyze resource usage to optimize application performance.## Audit Log

An audit log is a record of important actions performed in the system. It captures information such as who performed an action, what action was performed, when it occurred, and on which resource.

Examples:
- User login
- Face search
- Record creation
- Record deletion

Audit logs are primarily used for:
- Security monitoring
- Compliance
- User activity tracking
- Incident investigation

---

## Audit Service

The Audit Service is a dedicated microservice responsible for receiving, storing, and managing audit logs from different services in the system.

Instead of each service storing logs independently, all services send audit events to the Audit Service, which centralizes audit data.

Benefits:
- Centralized logging
- Improved security
- Easier monitoring and reporting
- Better compliance support

---

## Audit Service URL

The Audit Service URL specifies the network address of the Audit Service.

Example:

```python
AUDIT_SERVICE_URL = "http://audit-service:9600"


# log_audit_event() Function Explained

The `log_audit_event()` function is used to safely create and send audit logs to an external audit service without affecting the main application flow.

It ensures every important user action is recorded with context like user details, request data, and action metadata.

---

## What this function does

When called, it:
- Gets or creates the audit client
- Extracts user information from request
- Extracts request metadata (IP, user-agent, path, etc.)
- Sanitizes sensitive details
- Builds a structured audit event
- Sends the event to the audit service
- Fails safely without breaking the API if logging fails

---

## Step-by-step explanation

### 1. Get audit client

```python
client = get_audit_client()

Creates or returns a shared audit client used to send logs to the audit service.

## When it is called:
- First time audit logging happens
- If no existing client exists

## What it does internally:

### Step 1: Check existing client
```python
if _audit_client is not None:
    return _audit_client
