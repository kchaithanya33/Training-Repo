<details>
<summary><b>API: POST /reenroll</b></summary>

### Operation Type

```text
Re-enroll existing students by resetting their enrollment
status and queuing them for enrollment again.
```

### Request

```json
{
  "all": true
}
```

OR

```json
{
  "all": false,
  "student_ids": ["S101", "S102"]
}
```

---

<details>
<summary><b>Path 1: all = true</b></summary>

### Step 1

```python
students = db.query(Student).order_by(
    Student.student_id.asc()
).all()
```

Fetch all students.

### Step 2

```python
_queue_reenroll_students(
    db,
    students,
    reset_collections=True
)
```

<details>
<summary><b>Expand _queue_reenroll_students()</b></summary>

### reset_collections = True

```python
scopes = sorted(
    {s.class_section for s in students}
)
```

Get unique class sections.

Example:

```text
10A
10B
10C
```

### Drop Milvus Collections

```python
vector_svc.drop_collection("10A")
vector_svc.drop_collection("10B")
vector_svc.drop_collection("10C")
```

### Process Each Student

```python
for s in students:
```

#### Reset Enrollment State

```python
s.enrollment_status = NEW
s.enrollment_started_at = None
s.enrollment_stored_at = None
s.enrollment_error = None
```

#### Collect Photos

```python
photos = _collect_student_photos(db, s)
```

<details>
<summary><b>Expand _collect_student_photos()</b></summary>

### Query StudentFaceImage

```python
rows = (
    db.query(StudentFaceImage)
    .filter(
        StudentFaceImage.student_id
        == student.student_id
    )
    .all()
)
```

### Photos Found?

#### YES

Return:

```python
[
  (
    angle_index,
    is_primary,
    minio_object_key
  )
]
```

Example:

```python
[
  (0, True, "front.jpg"),
  (1, False, "left.jpg"),
  (2, False, "right.jpg")
]
```

#### NO

Check:

```python
student.minio_object_key
```

##### Exists

Return:

```python
[(0, True, key)]
```

##### Doesn't Exist

Return:

```python
[]
```

</details>

### Photos Empty?

#### YES

```python
s.enrollment_status = ERROR
s.enrollment_error = "No stored photos"
```

Add failed result.

#### NO

Add success result:

```python
reason = "Queued"
```

### Save

```python
db.commit()
```

### Return

```python
{
  "total": ...,
  "success_count": ...,
  "failed_count": ...,
  "results": [...]
}
```

</details>

</details>

---

<details>
<summary><b>Path 2: all = false</b></summary>

### Validate IDs

```python
ids = [
    x.strip()
    for x in body.student_ids
]
```

### IDs Empty?

#### YES

```python
HTTP 400
```

```json
{
  "detail":
  "student_ids is required when all=false"
}
```

#### NO

### Fetch Selected Students

```python
students = (
    db.query(Student)
    .filter(
        Student.student_id.in_(ids)
    )
    .all()
)
```

### Call

```python
_queue_reenroll_students(
    db,
    students,
    reset_collections=False
)
```

<details>
<summary><b>Expand _queue_reenroll_students()</b></summary>

### reset_collections = False

Skip:

```python
vector_svc.drop_collection(...)
```

No Milvus collections are deleted.

### Process Each Student

```python
for s in students:
```

#### Reset Enrollment State

```python
s.enrollment_status = NEW
s.enrollment_started_at = None
s.enrollment_stored_at = None
s.enrollment_error = None
```

#### Collect Photos

```python
photos = _collect_student_photos(db, s)
```

#### Photos Found?

##### NO

```python
s.enrollment_status = ERROR
```

##### YES

```python
reason = "Queued"
```

### Save

```python
db.commit()
```

### Return Summary

```python
AdminReenrollResponse
```

</details>

</details>

</details>


<details>
<summary><b>API: POST /processing-status</b></summary>

# API: GET /processing-status

## Operation Type

```text
CRUD Operation: READ
HTTP Method: GET

Purpose:
Returns a summary of enrollment processing statuses
for all students.
```

<details>
<summary><b>GET /processing-status</b></summary>

### Authentication

```python
_user = RequireAdmin
```

Only Admin users can access this API.

---

### Step 1: Query Status Counts

```python
status_counts = (
    db.query(
        Student.enrollment_status,
        func.count(Student.id)
    )
    .group_by(Student.enrollment_status)
    .all()
)
```

Equivalent SQL:

```sql
SELECT
    enrollment_status,
    COUNT(id)
FROM student
GROUP BY enrollment_status;
```

Example Result:

```python
[
    ("NEW", 20),
    ("PROCESSING", 5),
    ("STORED", 100),
    ("ERROR", 2)
]
```

---

### Step 2: Normalize Status Values

```python
for raw, cnt in status_counts:
```

<details>
<summary><b>Expand Status Normalization Logic</b></summary>

#### Handle NULL Values

```python
key = (raw or "").strip() or ENROLLMENT_STATUS_NEW
```

Examples:

```text
None    -> NEW
""      -> NEW
"NEW"   -> NEW
```

#### Convert To Uppercase

```python
key = key.upper()
```

Examples:

```text
new         -> NEW
stored      -> STORED
processing  -> PROCESSING
```

#### Validate Status

Allowed values:

```text
NEW
PROCESSING
STORED
ERROR
```

If an unknown status is found:

```python
key = ERROR
```

Example:

```text
"PENDING" -> ERROR
"ABC"     -> ERROR
```

#### Store Count

```python
counts[key] = counts.get(key, 0) + int(cnt)
```

Example:

```python
{
    "NEW": 20,
    "PROCESSING": 5,
    "STORED": 100,
    "ERROR": 2
}
```

</details>

---

### Step 3: Count Total Students

```python
total_all = int(
    db.query(
        func.count(Student.id)
    ).scalar() or 0
)
```

Equivalent SQL:

```sql
SELECT COUNT(id)
FROM student;
```

Example:

```text
127
```

---

### Step 4: Build Response

```python
return {
    "success": True,
    "data": {
        "processing_status": {
            ...
        }
    }
}
```

Example Response:

```json
{
  "success": true,
  "data": {
    "processing_status": {
      "NEW": 20,
      "PROCESSING": 5,
      "STORED": 100,
      "ERROR": 2,
      "total_records": 127
    },
    "timestamp": "2026-06-21T10:30:00Z"
  }
}
```

---

<details>
<summary><b>Visual Flow</b></summary>

```text
GET /processing-status
        │
        ▼
Query Student Table
        │
        ▼
GROUP BY enrollment_status
        │
        ▼
NEW         -> Count
PROCESSING  -> Count
STORED      -> Count
ERROR       -> Count
        │
        ▼
Count Total Students
        │
        ▼
Return JSON Response
```

</details>

---


</details>
