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
Logs help measure execution times, detect bottlenecks, and analyze resource usage to optimize application performance.

# log_audit_event() - Deep Dive with Internal Function Calls

## Main Function

```python
log_audit_event(...)
```

This function does not work alone.

Inside it, the following functions are called:

```text
log_audit_event()
│
├── get_audit_client()
├── get_user_info()
├── get_request_info()
├── sanitize_details()
└── client.log_event()
```

---

# STEP 1 : get_audit_client()

Code inside log_audit_event:

```python
client = get_audit_client()

if not client:
    return
```

## Function Being Called

```python
def get_audit_client():
```

### What this function does

Responsible for creating or returning the audit client.

Flow:

```text
Check existing client
        │
        ▼
Already initialized ?
        │
   Yes ─────► Return client
        │
        No
        ▼
Check AUDIT_ENABLED
        │
        ▼
Import AuditClient
        │
        ▼
Create AuditClient
        │
        ▼
Return client
```

### Important code

```python
if _audit_client is not None:
    return _audit_client
```

If already created, reuse it.

---

```python
enabled = getattr(
    settings,
    'AUDIT_ENABLED',
    os.getenv('AUDIT_ENABLED', 'true').lower() == 'true'
)
```

Checks whether audit logging is enabled.

---

```python
AuditClient, EventType, EventSeverity = _import_audit_client()
```

Calls another function:

```python
_import_audit_client()
```

---

# Nested Function : _import_audit_client()

Code:

```python
def _import_audit_client():
```

Purpose:

Load audit library.

Flow:

```text
Try installed package
        │
 Success ?
        │
Yes ─────► Return classes
        │
 No
        ▼
Try local folders
        │
 Success ?
        │
Yes ─────► Return classes
        │
 No
        ▼
Raise ImportError
```

Example:

```python
from biochq_audit import (
    AuditClient,
    EventType,
    EventSeverity
)
```

---

# STEP 2 : get_user_info()

Code inside main function:

```python
user_info = get_user_info(request)
```

## Function Being Called

```python
def get_user_info(request):
```

Purpose:

Extract authenticated user information.

Code:

```python
if hasattr(request, 'user') and \
   request.user and \
   request.user.is_authenticated:
```

Checks:

- request has user
- user exists
- user logged in

---

Extracts:

```python
user_info['user_id']
user_info['username']
user_info['email']
```

Example Output

```python
{
    "user_id": "123",
    "username": "john",
    "email": "john@test.com"
}
```

---

# STEP 3 : get_request_info()

Code inside main function

```python
request_info = get_request_info(request)
```

## Function Being Called

```python
def get_request_info(request):
```

Purpose:

Collect API request metadata.

Extracts:

```python
request.META.get('REMOTE_ADDR')
request.META.get('HTTP_USER_AGENT')
request.method
request.path
request.query_params
```

Example Output

```python
{
    "ip_address": "10.1.1.1",
    "user_agent": "Chrome",
    "http_method": "POST",
    "request_path": "/api/gallery",
    "query_params": {}
}
```

---

# STEP 4 : sanitize_details()

Code inside main function

```python
safe_details = sanitize_details(
    details or {}
)
```

## Function Being Called

```python
def sanitize_details(details):
```

Purpose:

Remove sensitive data before logging.

---

Sensitive keys list

```python
SENSITIVE_KEYS = {
    'password',
    'token',
    'api_key',
    'encodedImage',
    'image_data',
    'vector',
    'embedding',
    'email',
    'phone'
}
```

---

Example Input

```python
{
    "gallery_id": "100",
    "password": "abc123",
    "encodedImage": "base64string"
}
```

Output

```python
{
    "gallery_id": "100",
    "password": "[REDACTED]",
    "encodedImage": "[REDACTED]"
}
```

---

### Recursive Processing

If nested dictionary found:

```python
if isinstance(value, dict):
    sanitized[key] = sanitize_details(value)
```

The same function calls itself.

Example:

```python
{
  "user": {
      "password": "123"
  }
}
```

becomes

```python
{
  "user": {
      "password": "[REDACTED]"
  }
}
```

---

# STEP 5 : Build Event Object

Code

```python
event_kwargs = {
    'event_type': event_type,
    'severity': severity,
    'action': action,
}
```

Example

```python
{
    "event_type": "BIOMETRIC_INSERT",
    "severity": "INFO",
    "action": "INSERT"
}
```

---

# STEP 6 : Add Resource Information

Code

```python
if resource_type:
    event_kwargs['resource'] = resource_type
```

Important:

```python
resource_type
```

is converted to

```python
resource
```

because AuditEvent expects:

```python
resource
```

not

```python
resource_type
```

---

# STEP 7 : Process kwargs

Code

```python
for key, value in kwargs.items():
```

Loop through all extra values.

---

Accepted fields:

```python
accepted_fields = {
    'ip_address',
    'user_agent',
    'request_id',
    'correlation_id',
    'session_id',
    'tenant_id'
}
```

If field is accepted:

```python
event_kwargs[key] = value
```

Else:

```python
final_details[key] = value
```

---

# STEP 8 : client.log_event()

Final code

```python
client.log_event(**event_kwargs)
```

Example Final Object

```python
{
    "event_type": "BIOMETRIC_INSERT",
    "severity": "INFO",
    "user_id": "123",
    "resource": "gallery",
    "resource_id": "100",
    "ip_address": "10.1.1.1",
    "details": {
        "username": "john",
        "gallery_id": "100"
    }
}
```

This is sent to Audit Service.

---

# Complete Call Tree

```text
log_audit_event()
│
├── get_audit_client()
│   │
│   └── _import_audit_client()
│
├── get_user_info()
│
├── get_request_info()
│
├── sanitize_details()
│   │
│   └── sanitize_details()
│       (recursive)
│
└── client.log_event()
```

