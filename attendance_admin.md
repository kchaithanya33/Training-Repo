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
</details>

---
</details>

<details>
<summary><b>API: GET /export/students</b></summary>

### Operation Type

```text
Export student records and photos from the system
into a ZIP file for backup, migration, or re-import.
```

### Authentication

```python
_user = RequireAdmin
```

Only Admin users can access this API.

---

### Request Options

#### Export All Students

```http
GET /export/students
```

---

#### Export Single Student

```http
GET /export/students?student_id=S101
```

---

#### Export Multiple Students

```http
GET /export/students?student_ids=S101,S102,S103
```

---

### Get Storage Service

```python
storage_svc = get_storage_service()
```

Used for:

```text
Downloading student photos
from MinIO / S3 / Local Storage
```

---

### Parse Student IDs

```python
ids = [
    x.strip()
    for x in (student_ids or "").split(",")
    if x.strip()
]
```

Example:

```python
student_ids = "S101,S102,S103"
```

Result:

```python
[
    "S101",
    "S102",
    "S103"
]
```

---

### Fetch Students

#### Multiple IDs Provided

```python
students = (
    db.query(Student)
    .filter(Student.student_id.in_(ids))
    .order_by(Student.student_id.asc())
    .all()
)
```

---

#### Single ID Provided

```python
students = (
    db.query(Student)
    .filter(
        Student.student_id == student_id.strip()
    )
    .all()
)
```

---

#### No IDs Provided

```python
students = (
    db.query(Student)
    .order_by(Student.student_id.asc())
    .all()
)
```

Fetch all students.

---

### No Students Found?

```python
if not students:
```

Return:

```python
HTTP 404
```

```json
{
  "detail": "No students found to export"
}
```

---

### Create ZIP In Memory

```python
mem = io.BytesIO()
```

Creates a temporary ZIP file in memory.

---

### Initialize Export Structures

```python
students_payload = []
photo_count = 0
```

---

### Create ZIP Archive

```python
with zipfile.ZipFile(
    mem,
    "w",
    compression=zipfile.ZIP_DEFLATED
) as zf:
```

---

### Process Each Student

```python
for s in students:
```

---

### Collect Student Photos

```python
photos = _collect_student_photos(db, s)
```

Example Return:

```python
[
    (
        0,
        True,
        "10-A/S101/faces/0.jpg"
    ),
    (
        1,
        False,
        "10-A/S101/faces/1.jpg"
    )
]
```

---

### Photos Found?

#### NO

```python
continue
```

Skip student.

---

#### YES

Continue exporting.

---

### Find Primary Photo

```python
primary_angle_index = next(
    (
        a
        for a, is_p, _
        in photos
        if is_p
    ),
    0
)
```

Example:

```python
[
    (0, False, ...),
    (1, True, ...)
]
```

Result:

```python
primary_angle_index = 1
```

---

### Export Each Photo

```python
for angle_index,
    is_primary,
    object_key in photos:
```

---

### Download Photo

```python
data = storage_svc.download_image(
    object_key
)
```

Example:

```text
10-A/S101/faces/0.jpg
```

---

### Create Export Filename

```python
export_name = (
    f"photos/{s.student_id}/"
    f"angle_{angle_index}.jpg"
)
```

Example:

```text
photos/S101/angle_0.jpg
```

---

### Add Photo To ZIP

```python
zf.writestr(
    export_name,
    data
)
```

ZIP Structure:

```text
photos/
└── S101/
    └── angle_0.jpg
```

---

### Build Photo Metadata

```python
record_photos.append(
    {
        "angle_index": angle_index,
        "is_primary": is_primary,
        "file": export_name
    }
)
```

Example:

```json
{
  "angle_index": 0,
  "is_primary": true,
  "file": "photos/S101/angle_0.jpg"
}
```

---

### Count Exported Photos

```python
photo_count += 1
```

---

### Build Student Payload

```python
students_payload.append(
    {
        "student_id": s.student_id,
        "name": s.name,
        "student_class": s.student_class,
        "section": s.section or "",
        "primary_angle_index":
            primary_angle_index,
        "photos": record_photos
    }
)
```

Example:

```json
{
  "student_id": "S101",
  "name": "John",
  "student_class": "10",
  "section": "A",
  "primary_angle_index": 0,
  "photos": [...]
}
```

---

### Create Manifest

```python
manifest = {
    "version": "1.0",
    "student_count":
        len(students_payload),
    "photo_count":
        photo_count,
}
```

Example:

```json
{
  "version": "1.0",
  "student_count": 100,
  "photo_count": 350
}
```

---

### Write students.json

```python
zf.writestr(
    "students.json",
    json.dumps(
        students_payload,
        indent=2
    )
)
```

---

### Write manifest.json

```python
zf.writestr(
    "manifest.json",
    json.dumps(
        manifest,
        indent=2
    )
)
```

---

### ZIP Structure

```text
students-export.zip

├── students.json
├── manifest.json
└── photos
    ├── S101
    │   ├── angle_0.jpg
    │   └── angle_1.jpg
    │
    ├── S102
    │   ├── angle_0.jpg
    │   └── angle_1.jpg
    │
    └── S103
        └── angle_0.jpg
```

---

### Reset Memory Pointer

```python
mem.seek(0)
```

Move ZIP cursor back to beginning.

---

### Select Output Filename

#### Multiple Students

```python
filename =
    "students-export-selected.zip"
```

---

#### Single Student

```python
filename =
    f"students-export-{student_id}.zip"
```

Example:

```text
students-export-S101.zip
```

---

#### All Students

```python
filename =
    "students-export.zip"
```

---

### Return ZIP Download

```python
return StreamingResponse(
    mem,
    media_type="application/zip",
    headers={
        "Content-Disposition":
        f'attachment; filename="{filename}"'
    },
)
```

Response:

```http
Content-Type: application/zip
```

Browser downloads:

```text
students-export.zip
```

---
<details>
<summary><b>view Flow Diagram</b></summary>

### Flow Diagram

```text
GET /export/students
        │
        ▼
Fetch Students
        │
        ▼
Collect Photos
        │
        ▼
Download Images
        │
        ▼
Create students.json
        │
        ▼
Create manifest.json
        │
        ▼
Build ZIP
        │
        ▼
Return ZIP Download
```
</details>
</details>

<details>
<summary><b>API: POST /import/students</b></summary>


## Operation Type

```text
CRUD Operation: CREATE / UPDATE
HTTP Method: POST

Purpose:
Import students and photos from a ZIP file,
restore them into the system,
and queue them for re-enrollment.
```

### Authentication

```python
_user = RequireAdmin
```

Only Admin users can access this API.

---

### Request

```text
multipart/form-data
```

Fields:

```text
file        -> students-export.zip
overwrite   -> true | false
```

Example:

```text
file = students-export.zip
overwrite = true
```

---

<details>
<summary><strong>Complete API Execution Flow</strong></summary>

## Step 1: Read Uploaded ZIP

```python
raw = await file.read()
```

Reads uploaded ZIP file into memory.

---

## Step 2: Initialize Services

```python
storage_svc = get_storage_service()
vector_svc = get_vector_db_service()
```

Purpose:

```text
storage_svc -> MinIO/S3 operations
vector_svc  -> Milvus operations
```

---

## Step 3: Open ZIP

```python
with zipfile.ZipFile(
    io.BytesIO(raw),
    "r"
) as zf:
```

Example:

```text
students-export.zip

├── students.json
├── manifest.json
└── photos/
```

---

## Step 4: Validate students.json

```python
if "students.json" not in zf.namelist():
```

Error:

```json
{
  "detail": "students.json missing in import file"
}
```

---

## Step 5: Read Student Records

```python
records = json.loads(
    zf.read("students.json")
      .decode("utf-8")
)
```

Example:

```json
[
  {
    "student_id": "S101",
    "name": "John"
  }
]
```

---

## Step 6: Process Each Student

```python
for rec in records:
```

Extract:

```python
sid = str(
    rec.get("student_id", "")
).strip()
```

Find existing student:

```python
existing = (
    db.query(Student)
    .filter(
        Student.student_id == sid
    )
    .first()
)
```

---

<details>
<summary><strong>Student Existence Decision Tree</strong></summary>

# Condition 1

## Student Exists AND overwrite=False

```python
if existing and not overwrite:
    skipped += 1
    continue
```

### Effect

```text
Student skipped
No update
No photo upload
No MinIO changes
No Milvus changes
```

---

# Condition 2

## Student Exists AND overwrite=True

```python
if existing and overwrite:
```

### Delete Old Milvus Embedding

```python
vector_svc.delete_embedding(
    existing.class_section,
    sid
)
```

### Delete Old MinIO Photos

```python
storage_svc.delete_image(...)
```

### Delete Old StudentFaceImage Rows

```python
db.query(StudentFaceImage)
.filter(...)
.delete()
```

### Update Existing Student

```python
student = existing

student.name = name
student.student_class = student_class
student.section = section
```

### Effect

```text
Student row retained
Old photos removed
Old embeddings removed
Old StudentFaceImage rows removed
New photos imported
New StudentFaceImage rows created
```

---

# Condition 3

## Student Does Not Exist

```python
else:
```

### Create Student

```python
student = Student(
    student_id=sid,
    name=name,
    student_class=student_class,
    section=section,
    minio_bucket=storage_svc.bucket,
    minio_object_key=None,
)
```

### Save

```python
db.add(student)
```

### Effect

```text
New Student row created
Photos uploaded
StudentFaceImage rows created
```

---

## Decision Flow

```text
Student Exists?
        │
   ┌────┴────┐
   │         │
  YES       NO
   │         │
   ▼         ▼
Overwrite? Create Student
   │
 ┌─┴─────┐
 │       │
YES      NO
 │       │
 ▼       ▼
Replace Skip
```

</details>

---

## Step 7: Ensure Primary Assignment

```python
_ensure_primary_assignment(
    db,
    sid,
    student_class,
    section
)
```

Ensures student-class mapping exists.

---

## Step 8: Import Photos

```python
for p in photos:
```

Read image:

```python
data = zf.read(src)
```

Build path:

```python
object_key =
f"{class_section}/{sid}/faces/{angle}.jpg"
```

Example:

```text
10-A/S101/faces/0.jpg
```

Upload image:

```python
storage_svc.upload_image(
    object_key,
    data,
    content_type="image/jpeg"
)
```

Create metadata:

```python
db.add(
    StudentFaceImage(...)
)
```

---

## Step 9: Set Primary Photo

```python
student.minio_object_key =
primary_object_key
```

Example:

```text
10-A/S101/faces/0.jpg
```

---

## Step 10: Track Imported Student

```python
imported_ids.append(sid)
```

Example:

```python
["S101", "S102"]
```

---

## Step 11: Save Database Changes

```python
db.commit()
```

Stores:

```text
Student rows
StudentFaceImage rows
Updates
```

---

## Step 12: Load Imported Students

```python
students = (
    db.query(Student)
    .filter(
        Student.student_id.in_(
            imported_ids
        )
    )
    .all()
)
```

---

## Step 13: Queue Re-enrollment

```python
reenroll_result =
_queue_reenroll_students(
    db,
    students
)
```

Purpose:

```text
Generate face embeddings
Store vectors in Milvus
```

---

## Step 14: Build Import Message

Skipped students:

```python
if skipped > 0:
```

Example:

```text
5 students skipped
```

---

## Step 15: Return Response

```python
return StudentImportResponse(...)
```

Example:

```json
{
  "total_students": 100,
  "imported_students": 95,
  "skipped_students": 5,
  "reenroll": {...},
  "message": "5 row(s) skipped"
}
```

</details>

---

## Complete System Flow

```text
Upload ZIP
      │
      ▼
Read students.json
      │
      ▼
For Each Student
      │
      ├── Exists + overwrite=False
      │         │
      │         ▼
      │       Skip
      │
      ├── Exists + overwrite=True
      │         │
      │         ▼
      │       Replace Existing Data
      │
      └── New Student
                │
                ▼
            Create Student
      │
      ▼
Upload Photos To MinIO
      │
      ▼
Create StudentFaceImage Rows
      │
      ▼
Commit PostgreSQL
      │
      ▼
Queue Re-enrollment
      │
      ▼
Generate Face Embeddings
      │
      ▼
Store Embeddings In Milvus
      │
      ▼
Return Import Summary
```
</details>

<details>
<summary><b>API: POST /cleanup</b></summary>


## Operation Type

```text
CRUD Operation: DELETE
HTTP Method: POST

Purpose:
Remove all data from PostgreSQL,
Milvus, and MinIO.

This operation permanently deletes
all student, attendance, vector,
and image data.
```

### Authentication

```python
_user = RequireSuperAdmin
```

Only Super Admin users can access this API.

### Request

```http
POST /cleanup?confirm=true
```

Example:

```text
/cleanup?confirm=true
```

---

<details>
<summary><strong>Complete API Execution Flow</strong></summary>

## Step 1: Validate Confirmation

```python
if not confirm:
    raise HTTPException(
        status_code=400,
        detail="Set confirm=true to perform cleanup"
    )
```

### Example

```text
confirm=false
```

Response:

```json
{
  "detail": "Set confirm=true to perform cleanup"
}
```

---

## Step 2: Initialize Result Object

```python
result = {
    "postgres": {},
    "milvus": {},
    "minio": {}
}
```

Example:

```json
{
  "postgres": {},
  "milvus": {},
  "minio": {}
}
```

---


## Delete Attendance Records

```python
deleted_attendance =
db.query(
    AttendanceRecord
).delete()
```

Equivalent SQL:

```sql
DELETE FROM attendance_records;
```

---

## Delete Attendance Sessions

```python
deleted_sessions =
db.query(
    AttendanceSession
).delete()
```

Equivalent SQL:

```sql
DELETE FROM attendance_sessions;
```

---

## Delete Student Transfers

```python
deleted_transfers =
db.query(
    StudentTransfer
).delete()
```

Equivalent SQL:

```sql
DELETE FROM student_transfers;
```

---

## Delete Students

```python
deleted_students =
db.query(
    Student
).delete()
```

Equivalent SQL:

```sql
DELETE FROM students;
```

---

## Commit Changes

```python
db.commit()
```

---

## Result

```python
result["postgres"] = {
    "attendance_records":
        deleted_attendance,

    "attendance_sessions":
        deleted_sessions,

    "student_transfers":
        deleted_transfers,

    "students":
        deleted_students
}
```

Example:

```json
{
  "attendance_records": 500,
  "attendance_sessions": 20,
  "student_transfers": 30,
  "students": 100
}
```

---

## Failure Scenario

```python
except Exception as e:
```

Rollback:

```python
db.rollback()
```

Response:

```json
{
  "detail":
  "Postgres cleanup failed"
}
```

</details>

---

<details>
<summary><strong>Milvus Cleanup</strong></summary>

## Drop All Collections

```python
dropped =
get_vector_db_service()
.drop_all_collections()
```

Example:

```python
[
  "10A",
  "10B",
  "10C"
]
```

---

## Store Result

```python
result["milvus"] = {
    "collections_dropped":
        len(dropped),

    "names":
        dropped
}
```

Example:

```json
{
  "collections_dropped": 3,
  "names": [
    "10A",
    "10B",
    "10C"
  ]
}
```

---

## Failure Scenario

```python
except Exception as e:
```

Response:

```json
{
  "detail":
  "Milvus cleanup failed"
}
```

</details>

---

<details>
<summary><strong>MinIO Cleanup</strong></summary>

## Delete All Objects

```python
count =
get_storage_service()
.delete_all_objects()
```

Example:

```text
250 images deleted
```

---

## Store Result

```python
result["minio"] = {
    "objects_deleted": count
}
```

Example:

```json
{
  "objects_deleted": 250
}
```

---

## Failure Scenario

```python
except Exception as e:
```

Response:

```json
{
  "detail":
  "MinIO cleanup failed"
}
```

</details>

---

## Step 3: Return Response

```python
return {
    "detail":
        "All data cleaned up",

    "result":
        result
}
```

Example Response:

```json
{
  "detail": "All data cleaned up",
  "result": {
    "postgres": {
      "attendance_records": 500,
      "attendance_sessions": 20,
      "student_transfers": 30,
      "students": 100
    },
    "milvus": {
      "collections_dropped": 3,
      "names": [
        "10A",
        "10B",
        "10C"
      ]
    },
    "minio": {
      "objects_deleted": 250
    }
  }
}
```


## Complete System Flow

```text
POST /cleanup?confirm=true
            │
            ▼
Validate confirm
            │
            ▼
Delete Attendance Records
            │
            ▼
Delete Attendance Sessions
            │
            ▼
Delete Student Transfers
            │
            ▼
Delete Students
            │
            ▼
Commit PostgreSQL
            │
            ▼
Drop Milvus Collections
            │
            ▼
Delete MinIO Objects
            │
            ▼
Build Result
            │
            ▼
Return Cleanup Summary
```
</details>



<details>
<summary><b>API: GET /abis-integration/b></summary>

### Operation Type

```text
CRUD Operation: READ
HTTP Method: GET

Purpose:
Returns the current ABIS integration configuration,
API key status, tenant information,
collection configuration and warnings.
```

### Authentication

```python
_user = RequireAdmin
```

Only Admin users can access this API.

### Route

```python
@router.get(
    "/abis-integration",
    response_model=AbisIntegrationStatusResponse
)
def get_abis_integration(
    db: Session = Depends(get_db),
    _user=RequireAdmin
):
    return get_abis_integration_status(db)
```

### Flow

```text
GET /abis-integration
        │
        ▼
get_abis_integration()
        │
        ▼
get_abis_integration_status(db)
        │
        ▼
_get_settings_row(db)
        │
        ▼
Build Status Response
        │
        ▼
Return JSON
```



---

# Function: _get_settings_row(db)

<details>
<summary><strong>_get_settings_row(db)</strong></summary>

### Purpose

```text
Ensures the settings table always contains
one settings row with id = 1.
```

### Query Settings Table

```python
row = (
    db.query(AbisIntegrationSettings)
    .filter(
        AbisIntegrationSettings.id == 1
    )
    .first()
)
```

Equivalent SQL:

```sql
SELECT *
FROM abis_integration_settings
WHERE id = 1
LIMIT 1;
```

---

### Row Found?

#### YES

```python
return row
```

Example:

```text
id = 1 already exists
```

Return existing row.

---

#### NO

Create Default Row

```python
row = AbisIntegrationSettings(id=1)
```

Add Row

```python
db.add(row)
```

Commit

```python
db.commit()
```

Refresh

```python
db.refresh(row)
```

Return

```python
return row
```

Equivalent SQL:

```sql
INSERT INTO abis_integration_settings(id)
VALUES (1);
```

### Result

```text
Guarantees a single settings row always exists.
```

</details>

---

# Model: AbisIntegrationSettings

<details>
<summary><strong>AbisIntegrationSettings Table Structure</strong></summary>

### Purpose

```text
Stores ABIS integration settings.

Single-row table.
Only one row exists with id=1.
```

### Table Name

```python
__tablename__ = "abis_integration_settings"
```

---

### Columns

#### Primary Key

```python
id = Column(
    Integer,
    primary_key=True,
    default=1
)
```

Example:

```text
1
```

---

#### Encrypted API Key

```python
abis_api_key_encrypted = Column(
    String(1024),
    nullable=True
)
```

Stores encrypted ABIS API key.

Example:

```text
encrypted_string_here
```

---

#### Tenant ID

```python
abis_tenant_id = Column(
    String(64),
    nullable=True
)
```

Example:

```text
tenant_001
```

---

#### Collection Name

```python
abis_vector_collection_name = Column(
    String(128),
    nullable=True
)
```

Example:

```text
school_faces_collection
```

---

#### Expiry Time

```python
abis_key_expires_at = Column(
    DateTime(timezone=True),
    nullable=True
)
```

Example:

```text
2026-12-31T00:00:00Z
```

---

#### Updated Timestamp

```python
updated_at = Column(
    DateTime(timezone=True),
    server_default=func.now(),
    onupdate=func.now()
)
```

Automatically updates whenever row changes.

</details>

---

# Function: get_abis_integration_status(db)

<details>
<summary><strong>get_abis_integration_status(db)</strong></summary>

### Purpose

```text
Builds the ABIS integration status response.
```

---

### Step 1

Get Settings Row

```python
row = _get_settings_row(db)
```

Possible Result:

```text
id = 1
tenant_id = tenant_001
collection = school_faces
```

---

### Step 2

Read Environment API Key

```python
env_key = (
    ATTENDANCE_ABIS_API_KEY or ""
).strip()
```

Examples:

```text
"abc123" -> "abc123"
None     -> ""
```

---

### Step 3

Check DB Key

```python
db_key_set = bool(
    row.abis_api_key_encrypted
)
```

Examples:

```text
Encrypted Key Exists -> True
No Key              -> False
```

---

### Step 4

Resolve Collection

```python
env_collection =
resolve_attendance_abis_vector_collection()
```

Possible Result:

```text
school_faces
```

or

```text
None
```

---

### Step 5

Determine Source

```python
source = (
    "database"
    if db_key_set
    else (
        "environment"
        if env_key
        else "none"
    )
)
```

Possible Results:

```text
database
environment
none
```

---

### Step 6

Determine API Key Active

```python
api_key_active =
db_key_set or bool(env_key)
```

Examples:

```text
DB Key Exists      -> True
ENV Key Exists     -> True
No Keys            -> False
```

---

### Step 7

Check Collection Configured

```python
env_collection_configured =
bool(env_collection)
```

Examples:

```text
Collection Exists -> True
No Collection     -> False
```

---

### Step 8

Determine Collection Mode

```python
effective_collection_mode = (
    "tenant_bound_via_api_key"
    if api_key_active
    else (
        "env_vector_collection"
        if env_collection_configured
        else "legacy_default"
    )
)
```

Possible Results:

#### API Key Active

```text
tenant_bound_via_api_key
```

---

#### No API Key but Collection Exists

```text
env_vector_collection
```

---

#### Neither Exists

```text
legacy_default
```

---

### Step 9

Initialize Warning

```python
warning = None
```

---

### Step 10

Both DB Key And ENV Key Exist?

```python
if db_key_set and env_key:
```

Warning:

```text
Both DB-stored key and ATTENDANCE_ABIS_API_KEY
are configured; database key is active.
```

---

### Step 11

API Key Active + Collection Exists?

```python
elif (
    api_key_active
    and env_collection_configured
):
```

Warning:

```text
API key mode is active,
environment collection is ignored.
```

---

### Step 12

Build Response

```python
return {
    ...
}
```

Returned Fields:

#### API Key Configured

```python
"api_key_configured":
api_key_active
```

Example:

```text
true
```

---

#### API Key Source

```python
"api_key_source":
source
```

Example:

```text
database
```

---

#### ENV Key Configured

```python
"env_api_key_configured":
bool(env_key)
```

Example:

```text
true
```

---

#### Collection Configured

```python
"env_collection_configured":
env_collection_configured
```

Example:

```text
true
```

---

#### Effective Mode

```python
"effective_collection_mode":
effective_collection_mode
```

Example:

```text
tenant_bound_via_api_key
```

---

#### Warning

```python
"warning":
warning
```

Example:

```text
Database key overrides environment key
```

---

#### Tenant ID

```python
"tenant_id":
row.abis_tenant_id
```

Example:

```text
tenant_001
```

---

#### Collection Name

```python
"vector_collection_name":
row.abis_vector_collection_name
or env_collection
or None
```

Example:

```text
school_faces_collection
```

---

#### Key Expiry

```python
"key_expires_at":
row.abis_key_expires_at.isoformat()
```

Example:

```text
2026-12-31T00:00:00Z
```

---

#### Updated Time

```python
"updated_at":
row.updated_at.isoformat()
```

Example:

```text
2026-06-21T10:30:00Z
```

</details>

---

# Final Flow

```text
GET /abis-integration
        │
        ▼
get_abis_integration()
        │
        ▼
get_abis_integration_status()
        │
        ▼
_get_settings_row()
        │
        ├── Row Exists
        │       │
        │       ▼
        │   Return Row
        │
        └── Row Missing
                │
                ▼
           Create Row(id=1)
                │
                ▼
           Commit
                │
                ▼
           Return Row
        │
        ▼
Check DB API Key
        │
        ▼
Check ENV API Key
        │
        ▼
Check Collection
        │
        ▼
Determine Mode
        │
        ▼
Generate Warning
        │
        ▼
Build Response
        │
        ▼
Return JSON
```
</details>


<details>
<summary><b>API: PUT /abis-integration</b></summary>

### Operation Type

```text
CRUD Operation: UPDATE
HTTP Method: PUT

Purpose:
Update ABIS integration settings.
```

### Authentication

```python
_user = RequireAdmin
```

### Route

```python
@router.put("/abis-integration")
def update_abis_integration(...):
```

### Validation

```python
if body.api_key is not None and not body.api_key.strip() and not body.clear_api_key:
```

Return:

```json
{
  "detail": "api_key cannot be empty; use clear_api_key=true to remove"
}
```

### Function Call

```python
return save_abis_integration(...)
```



---

<details>
<summary><strong>Function: save_abis_integration()</strong></summary>

### Get Settings Row

```python
row = _get_settings_row(db)
```

#### Internal Function Call

<details>
<summary><strong>Function: _get_settings_row()</strong></summary>

```python
row = db.query(
    AbisIntegrationSettings
).filter(
    AbisIntegrationSettings.id == 1
).first()
```

Row Exists?

```text
YES → Return Row
```

Row Missing?

```python
row = AbisIntegrationSettings(id=1)
db.add(row)
db.commit()
db.refresh(row)
```

Return:

```python
return row
```

</details>

---

### Clear API Key?

```python
if clear_api_key:
```

```python
row.abis_api_key_encrypted = None
```

---

### New API Key?

```python
elif api_key is not None and api_key.strip():
```

```python
row.abis_api_key_encrypted =
encrypt_api_key(api_key.strip())
```

---

### Update Tenant

```python
if tenant_id is not None:
```

```python
row.abis_tenant_id =
tenant_id.strip() or None
```

---

### Update Collection

```python
if vector_collection_name is not None:
```

```python
row.abis_vector_collection_name =
vector_collection_name.strip() or None
```

---

### Update Expiry

```python
if key_expires_at is not None:
```

```python
row.abis_key_expires_at =
key_expires_at
```

---

### Save

```python
db.commit()
```

```python
db.refresh(row)
```

---

### Return Updated Status

```python
return get_abis_integration_status(db)
```

#### Internal Function Call

<details>
<summary><strong>Function: get_abis_integration_status()</strong></summary>

Builds final response:

```python
{
    "api_key_configured": ...,
    "api_key_source": ...,
    "tenant_id": ...,
    "vector_collection_name": ...,
    "key_expires_at": ...
}
```
</details>
</details>

</details>

<details>
<summary><strong>API: POST /sessions</strong></summary>

# API: POST /sessions

## Operation Type

```text
CRUD Operation: CREATE
HTTP Method: POST

Purpose:
Creates a new attendance session for a specific
class and section.
```

### Authentication

```python
_user = RequireOperator
```

Only Operator users can access this API.

---

### Request Example

```json
{
  "name": "Morning Attendance",
  "session_type": "class",
  "class_section": "III-F"
}
```

---

### Step 1: Read Session Name

```python
name = (body.name or "").strip()
```

Remove leading/trailing spaces.

Example:

```text
" Morning Attendance "
        ↓
"Morning Attendance"
```

### Name Empty?

```python
if not name:
```

Return:

```json
{
  "detail": "name is required"
}
```

HTTP Status:

```text
400 Bad Request
```

---

### Step 2: Read Session Type

```python
st = (body.session_type or "class").strip().lower()
```

Examples:

```text
"CLASS"  -> "class"
"Exam"   -> "exam"
None     -> "class"
```

### Validate Session Type

```python
if st not in SESSION_TYPES:
```

Example:

```text
Allowed:
class
exam
event
```

Invalid:

```text
meeting
sports
```

Return:

```json
{
  "detail": "session_type must be one of ..."
}
```

---

<details>
<summary><strong>Internal Function: parse_class_section()</strong></summary>

### Step 3: Parse Class Section

```python
sc, sec = parse_class_section(body.class_section)
```

Function:

```python
def parse_class_section(class_section: str):
```

#### Input

```text
III-F
```

#### Processing

```python
parts = class_section.split("-", 1)
```

Result:

```python
["III", "F"]
```

#### Return

```python
("III", "F")
```

Example:

```text
III-F → Class=III, Section=F
III   → Class=III, Section=""
```

### Class Missing?

```python
if not sc:
```

Return:

```json
{
  "detail": "class_section must include a class"
}
```

</details>

---

<details>
<summary><strong>Internal Function: _has_active_session()</strong></summary>

### Step 4: Check Active Session

```python
_has_active_session(
    db,
    sc,
    sec or ""
)
```

Function:

```python
def _has_active_session(
    db,
    student_class,
    section
)
```

### Query

```python
db.query(AttendanceSession)
.filter(
    AttendanceSession.student_class == student_class,
    AttendanceSession.section == section,
    AttendanceSession.status == SESSION_ACTIVE,
)
.first()
```

Equivalent SQL:

```sql
SELECT *
FROM attendance_session
WHERE student_class='III'
AND section='F'
AND status='ACTIVE'
LIMIT 1;
```

### Active Session Found?

#### YES

Return:

```json
{
  "detail": "An active session already exists for this class and section. Complete or cancel it first."
}
```

HTTP:

```text
409 Conflict
```

#### NO

Continue.

</details>

---

<details>
<summary><strong>Internal Function: _find_duplicate_session_today()</strong></summary>

### Step 5: Check Duplicate Session

```python
duplicate = _find_duplicate_session_today(
    db,
    sc,
    sec or "",
    name,
    st
)
```

Function:

```python
def _find_duplicate_session_today(
    db,
    student_class,
    section,
    name,
    session_type
)
```

### Get Today's UTC Date

```python
today = utc_calendar_day(
    datetime.now(timezone.utc)
)
```

Example:

```text
2026-06-21
```

### Normalize Name

```python
norm_name = name.strip().lower()
```

Example:

```text
"Morning Attendance"
        ↓
"morning attendance"
```

### Query Matching Sessions

```python
rows = (
    db.query(AttendanceSession)
    .filter(
        AttendanceSession.student_class == student_class,
        AttendanceSession.section == section,
        AttendanceSession.session_type == session_type,
        func.lower(
            AttendanceSession.name
        ) == norm_name,
    )
    .all()
)
```

Equivalent SQL:

```sql
SELECT *
FROM attendance_session
WHERE student_class='III'
AND section='F'
AND session_type='class'
AND LOWER(name)='morning attendance';
```

### Check Same Day

```python
for row in rows:
```

```python
if row.started_at
and utc_calendar_day(
    row.started_at
) == today:
```

#### Duplicate Found

Return Session Object.

#### No Duplicate

```python
return None
```

### Duplicate Exists?

#### YES

Return:

```json
{
  "detail": "A session named 'Morning Attendance' already exists today..."
}
```

HTTP:

```text
409 Conflict
```

#### NO

Continue.

</details>

---

### Step 6: Generate Session ID

```python
sid = str(uuid.uuid4())
```

Example:

```text
a3d76e78-7ef9-4c13-8d9f-75fdf2bdf533
```

---

### Step 7: Create AttendanceSession Object

```python
row = AttendanceSession(
    id=sid,
    name=name,
    session_type=st,
    student_class=sc,
    section=sec or "",
    status=SESSION_ACTIVE,
    started_at=datetime.now(timezone.utc),
    ended_at=None,
)
```

Example:

```python
AttendanceSession(
    id="123",
    name="Morning Attendance",
    session_type="class",
    student_class="III",
    section="F",
    status="ACTIVE"
)
```

---

### Step 8: Save To Database

```python
db.add(row)
```

Add object to SQLAlchemy session.

```python
db.commit()
```

Save row in PostgreSQL.

```python
db.refresh(row)
```

Reload saved values from database.

---

### Step 9: Return Response

```python
return _session_to_response(row)
```

Example Response:

```json
{
  "id": "a3d76e78-7ef9-4c13-8d9f-75fdf2bdf533",
  "name": "Morning Attendance",
  "session_type": "class",
  "student_class": "III",
  "section": "F",
  "status": "ACTIVE"
}
```

---

### Flow

```text
POST /sessions
      │
      ▼
Read Name
      │
      ▼
Validate Name
      │
      ▼
Read Session Type
      │
      ▼
Validate Session Type
      │
      ▼
parse_class_section()
      │
      ▼
_has_active_session()
      │
      ├── YES → 409 Error
      │
      ▼
_find_duplicate_session_today()
      │
      ├── YES → 409 Error
      │
      ▼
Generate UUID
      │
      ▼
Create AttendanceSession
      │
      ▼
db.add()
      │
      ▼
db.commit()
      │
      ▼
db.refresh()
      │
      ▼
Return Response
```

</details>


<details>
<summary><strong>API: GET /sessions</strong></summary>

## Operation Type

```text
CRUD Operation: READ
HTTP Method: GET

Purpose:
Returns attendance sessions with optional
class-section and status filtering.
Supports pagination.
```

### Authentication

```python
_user = RequireOperator
```

Only Operator users can access this API.

---

### Query Parameters

```text
class_section (optional)
status        (optional)
skip          (optional)
limit         (optional)
```

Example:

```http
GET /sessions?class_section=III-F&status=ACTIVE&skip=0&limit=50
```

---

### Step 1: Create Base Query

```python
q = db.query(AttendanceSession)
```

Equivalent SQL:

```sql
SELECT *
FROM attendance_session;
```

---

### Class Section Provided?

```python
if class_section:
```

<details>
<summary><strong>Internal Function: parse_class_section()</strong></summary>

### Parse Class Section

```python
sc, sec = parse_class_section(
    class_section
)
```

Function:

```python
def parse_class_section(
    class_section: str
)
```

Examples:

```text
III-F
```

Returns:

```python
("III", "F")
```

Example:

```text
III
```

Returns:

```python
("III", "")
```

</details>

### Apply Class Filter

```python
q = q.filter(
    AttendanceSession.student_class == sc,
    AttendanceSession.section == (
        sec or ""
    )
)
```

Equivalent SQL:

```sql
SELECT *
FROM attendance_session
WHERE student_class='III'
AND section='F';
```

---

### Status Provided?

```python
if status:
```

### Apply Status Filter

```python
q = q.filter(
    AttendanceSession.status
    == status.strip()
)
```

Example:

```text
ACTIVE
```

Equivalent SQL:

```sql
SELECT *
FROM attendance_session
WHERE status='ACTIVE';
```

---

### Step 2: Count Total Records

```python
total = q.count()
```

Equivalent SQL:

```sql
SELECT COUNT(*)
FROM attendance_session;
```

Example:

```text
125
```

This count is calculated before pagination.

---

### Step 3: Apply Sorting

```python
q.order_by(
    AttendanceSession.started_at.desc()
)
```

Sort sessions by newest first.

Example:

```text
2026-06-21 10:00
2026-06-21 09:00
2026-06-20 15:00
```

---

### Step 4: Apply Pagination

#### Skip Records

```python
.offset(skip)
```

Example:

```python
skip = 50
```

Skip first 50 records.

---

#### Limit Records

```python
.limit(limit)
```

Example:

```python
limit = 50
```

Return maximum 50 records.

---

### Execute Query

```python
rows = (
    q.order_by(
        AttendanceSession.started_at.desc()
    )
    .offset(skip)
    .limit(limit)
    .all()
)
```

Equivalent SQL:

```sql
SELECT *
FROM attendance_session
ORDER BY started_at DESC
LIMIT 50
OFFSET 0;
```

---

### Step 5: Convert Database Objects To Response Objects

```python
[
    _session_to_response(s)
    for s in rows
]
```

Example:

```python
AttendanceSession
```

↓

```json
{
  "id": "123",
  "name": "Morning Attendance",
  "status": "ACTIVE"
}
```

---

### Step 6: Return Response

```python
return AttendanceSessionListResponse(
    sessions=[
        _session_to_response(s)
        for s in rows
    ],
    total=total
)
```

Example Response:

```json
{
  "sessions": [
    {
      "id": "123",
      "name": "Morning Attendance",
      "session_type": "class",
      "student_class": "III",
      "section": "F",
      "status": "ACTIVE"
    }
  ],
  "total": 125
}
```

---

### Flow

```text
GET /sessions
      │
      ▼
Create Base Query
      │
      ▼
class_section Provided?
      │
      ├── YES
      │      │
      │      ▼
      │ parse_class_section()
      │      │
      │      ▼
      │ Apply Class Filter
      │
      ▼
status Provided?
      │
      ├── YES
      │      │
      │      ▼
      │ Apply Status Filter
      │
      ▼
Count Total Records
      │
      ▼
Sort By started_at DESC
      │
      ▼
Apply Offset(skip)
      │
      ▼
Apply Limit(limit)
      │
      ▼
Execute Query
      │
      ▼
Convert To Response Objects
      │
      ▼
Return Response
```

</details>

 <details>
<summary><b>API: GET /sessions/suggested-names</b></summary>

### Operation Type

```text
CRUD Operation: READ
HTTP Method: GET

Purpose:
Returns recently used session names for a specific
class-section.
```

### Authentication

```python
_user = RequireOperator
```

### Request Example

```http
GET /sessions/suggested-names?class_section=10-A&limit=12
```

---

### Step 1: Parse Class Section

```python
sc, sec = parse_class_section(class_section)
```

<details>
<summary><strong>Function: parse_class_section()</strong></summary>

```python
def parse_class_section(class_section: str):
```

Input:

```text
10-A
```

Output:

```python
("10", "A")
```

Input:

```text
10
```

Output:

```python
("10", "")
```

</details>

---

### Step 2: Validate Class

```python
if not sc:
    return AttendanceSessionNamesResponse(names=[])
```

Example Response:

```json
{
  "names": []
}
```

---

### Step 3: Query Recent Session Names

```python
rows = (
    db.query(AttendanceSession.name)
    .filter(
        AttendanceSession.student_class == sc,
        AttendanceSession.section == (sec or ""),
    )
    .order_by(AttendanceSession.started_at.desc())
    .limit(limit * 3)
    .all()
)
```

Equivalent SQL:

```sql
SELECT name
FROM attendance_session
WHERE student_class='10'
AND section='A'
ORDER BY started_at DESC
LIMIT 36;
```

Example Result:

```python
[
    ("Math Test",),
    ("Math Test",),
    ("Morning Attendance",),
    ("Science Quiz",)
]
```

---

### Step 4: Initialize Collections

```python
seen = set()
out = []
```

Purpose:

```text
seen -> Track duplicates
out  -> Final response list
```

---

### Step 5: Process Names

```python
for (n,) in rows:
```

#### First Occurrence

```python
if n and n not in seen:
```

```python
seen.add(n)
out.append(n)
```

Example:

```python
seen = {"Math Test"}
out = ["Math Test"]
```

#### Duplicate Occurrence

```python
Skip
```

Example:

```python
"Math Test"
```

Already exists in:

```python
seen
```

So it is ignored.

---

### Step 6: Apply Limit

```python
if len(out) >= limit:
    break
```

Example:

```python
limit = 12
```

Once:

```python
len(out) == 12
```

Stop processing.

---

### Step 7: Return Response

```python
return AttendanceSessionNamesResponse(
    names=out
)
```

Example Response:

```json
{
  "names": [
    "Math Test",
    "Morning Attendance",
    "Science Quiz",
    "Weekly Assessment"
  ]
}
```

---

```text
GET /sessions/suggested-names
            │
            ▼
Receive class_section
            │
            ▼
parse_class_section()
            │
            ▼
Class Valid?
      │
 ┌────┴────┐
 │         │
NO        YES
 │         │
 ▼         ▼
Return [] Query Sessions
               │
               ▼
 Filter By Class & Section
               │
               ▼
 Order By Latest First
               │
               ▼
 Remove Duplicates
               │
               ▼
 Apply Limit
               │
               ▼
 Return Names
```

</details>

<details>
<summary><strong>GET /sessions/{session_id}</strong></summary>

### Operation Type

```text
CRUD Operation: READ
HTTP Method: GET

Purpose:
Fetch a single attendance session using its session_id.
```

### Authentication

```python
_user = RequireOperator
```

Only Operator users can access this API.

### Request Example

```http
GET /sessions/550e8400-e29b-41d4-a716-446655440000
```

### Path Parameter

```python
session_id: str
```

Example:

```text
550e8400-e29b-41d4-a716-446655440000
```

---

### Step 1: Call Internal Function

```python
return _session_to_response(
    _get_session_or_404(
        db,
        session_id
    )
)
```

The API executes two internal functions:

```text
1. _get_session_or_404()
2. _session_to_response()
```

---

<details>
<summary><strong>Function: _get_session_or_404()</strong></summary>

### Purpose

```text
Fetch attendance session from database.

If session does not exist,
return HTTP 404.
```

Typical Logic:

```python
session = (
    db.query(AttendanceSession)
    .filter(
        AttendanceSession.id == session_id
    )
    .first()
)
```

#### Session Found

Example:

```python
AttendanceSession(
    id="123",
    name="Morning Attendance"
)
```

Return:

```python
session
```

#### Session Not Found

Raise:

```python
HTTPException(
    status_code=404,
    detail="Session not found"
)
```

</details>

---

<details>
<summary><strong>Function: _session_to_response()</strong></summary>

### Purpose

```text
Convert AttendanceSession database object
into AttendanceSessionResponse.
```

Function:

```python
def _session_to_response(
    s: AttendanceSession
) -> AttendanceSessionResponse:
```

Return:

```python
AttendanceSessionResponse(
    id=s.id,
    name=s.name,
    session_type=s.session_type,
    class_section=s.class_section,
    student_class=s.student_class,
    section=s.section,
    status=s.status,
    started_at=s.started_at,
    ended_at=s.ended_at,
)
```

---

### Example Input

```python
AttendanceSession(
    id="123",
    name="Morning Attendance",
    session_type="class",
    student_class="10",
    section="A",
    status="ACTIVE",
    started_at="2026-06-21T09:00:00Z",
    ended_at=None
)
```

### Example Output

```json
{
  "id": "123",
  "name": "Morning Attendance",
  "session_type": "class",
  "class_section": "10-A",
  "student_class": "10",
  "section": "A",
  "status": "ACTIVE",
  "started_at": "2026-06-21T09:00:00Z",
  "ended_at": null
}
```

</details>

---

### Final Response

```json
{
  "id": "123",
  "name": "Morning Attendance",
  "session_type": "class",
  "class_section": "10-A",
  "student_class": "10",
  "section": "A",
  "status": "ACTIVE",
  "started_at": "2026-06-21T09:00:00Z",
  "ended_at": null
}
```

---

```text
GET /sessions/{session_id}
            │
            ▼
_get_session_or_404()
            │
            ▼
Session Found?
      │
 ┌────┴────┐
 │         │
NO        YES
 │         │
 ▼         ▼
404     _session_to_response()
               │
               ▼
Convert DB Object
               │
               ▼
Return Response
```

</details>

<details>
<summary><strong>API: GET /sessions/{session_id}/unknowns</strong></summary>

### Operation Type

```text
CRUD Operation: READ
HTTP Method: GET

Purpose:
Returns all pending unknown faces detected
for a specific attendance session.
```

### Authentication

```python
_user = RequireOperator
```

Only Operators can access this API.

### Route

```http
GET /sessions/{session_id}/unknowns
```

### Step 1: Get Session

```python
sess = _get_session_or_404(
    db,
    session_id
)
```

<details>
<summary><strong>Function: _get_session_or_404()</strong></summary>

### Query Session Table

```python
s = (
    db.query(AttendanceSession)
    .filter(
        AttendanceSession.id == session_id
    )
    .first()
)
```

### Session Found?

#### YES

```python
return s
```

#### NO

```python
raise HTTPException(
    status_code=404,
    detail="Session not found"
)
```

Response:

```json
{
  "detail": "Session not found"
}
```

</details>

---

### Step 2: Get Pending Unknown Faces

```python
rows = _list_pending_session_unknowns(
    db,
    sess.id
)
```

<details>
<summary><strong>Function: _list_pending_session_unknowns()</strong></summary>

### Query Unknown Faces Table

```python
return (
    db.query(AttendanceSessionUnknownFace)
    .filter(
        AttendanceSessionUnknownFace.session_id == session_id,
        AttendanceSessionUnknownFace.status == UNKNOWN_STATUS_PENDING,
    )
    .order_by(
        AttendanceSessionUnknownFace.last_seen_at.desc()
    )
    .all()
)
```

### Filters

```python
AttendanceSessionUnknownFace.session_id == session_id
```

Only records belonging to this session.

---

```python
AttendanceSessionUnknownFace.status == UNKNOWN_STATUS_PENDING
```

Only pending unknown faces.

Example:

```text
PENDING   -> Included
RESOLVED  -> Excluded
REJECTED  -> Excluded
```

### Sorting

```python
.order_by(
    AttendanceSessionUnknownFace.last_seen_at.desc()
)
```

Newest faces first.

### Return

```python
[
    AttendanceSessionUnknownFace(...),
    AttendanceSessionUnknownFace(...)
]
```

</details>

---

### Step 3: Convert Rows To Response Items

```python
unknowns = [
    _session_unknown_to_item(row)
    for row in rows
]
```

Convert database objects into API response objects.

---

### Step 4: Return Response

```python
return SessionUnknownFacesResponse(
    session_id=sess.id,
    unknowns=[
        _session_unknown_to_item(row)
        for row in rows
    ],
)
```

Example Response:

```json
{
  "session_id": "123",
  "unknowns": [
    {
      "id": 1,
      "status": "PENDING"
    },
    {
      "id": 2,
      "status": "PENDING"
    }
  ]
}
```

### Flow

```text
GET /sessions/{session_id}/unknowns
                │
                ▼
      _get_session_or_404()
                │
        Session Exists?
          │         │
         YES        NO
          │         │
          │      HTTP 404
          ▼
_list_pending_session_unknowns()
          │
          ▼
Filter Session ID
          │
          ▼
Filter Status=PENDING
          │
          ▼
Sort By last_seen_at DESC
          │
          ▼
Convert To Response Items
          │
          ▼
Return SessionUnknownFacesResponse
```

</details>

<details>
<summary><strong>API: POST /sessions/{session_id}/complete</strong></summary>

### Operation Type

```text
CRUD Operation: UPDATE
HTTP Method: POST

Purpose:
Completes an active attendance session,
sets its end time, and schedules cleanup
of session unknown faces.
```

### Authentication

```python
_user = RequireOperator
```

Only Operators can access this API.

### Route

```http
POST /sessions/{session_id}/complete
```

### Step 1: Get Session

```python
s = _get_session_or_404(
    db,
    session_id
)
```

<details>
<summary><strong>Function: _get_session_or_404()</strong></summary>

### Query Session Table

```python
s = (
    db.query(AttendanceSession)
    .filter(
        AttendanceSession.id == session_id
    )
    .first()
)
```

### Session Found?

#### YES

```python
return s
```

#### NO

```python
raise HTTPException(
    status_code=404,
    detail="Session not found"
)
```

</details>

---

### Step 2: Validate Session Status

```python
if s.status != SESSION_ACTIVE:
    raise HTTPException(
        status_code=400,
        detail="Only an active session can be completed"
    )
```

### Valid?

#### YES

Continue.

#### NO

Response:

```json
{
  "detail": "Only an active session can be completed"
}
```

Example:

```text
ACTIVE       -> Allowed
COMPLETED    -> Rejected
CANCELLED    -> Rejected
```

---

### Step 3: Mark Session Completed

```python
s.status = SESSION_COMPLETED
```

Example:

```text
Before: ACTIVE
After : COMPLETED
```

---

### Step 4: Set End Time

```python
s.ended_at = datetime.now(
    timezone.utc
)
```

Example:

```text
2026-06-22 14:30:15 UTC
```

---

### Step 5: Save Changes

```python
db.commit()
```

Persist changes to database.

---

### Step 6: Refresh Session Object

```python
db.refresh(s)
```

Reload latest values from database.

---

### Step 7: Schedule Background Cleanup

```python
background_tasks.add_task(
    _cleanup_session_unknowns_background,
    s.id
)
```

Schedules cleanup of session unknown faces.

---

```python
background_tasks.add_task(
    _cleanup_session_unknowns_retry_background,
    s.id
)
```

Schedules retry cleanup process.

These tasks run after the API response is returned.

---

### Step 8: Convert To Response Object

```python
return _session_to_response(s)
```

<details>
<summary><strong>Function: _session_to_response()</strong></summary>

### Convert Database Model

```python
AttendanceSessionResponse(
    id=s.id,
    name=s.name,
    session_type=s.session_type,
    class_section=s.class_section,
    student_class=s.student_class,
    section=s.section,
    status=s.status,
    started_at=s.started_at,
    ended_at=s.ended_at,
)
```

### Example Response Object

```python
{
    "id": "123",
    "name": "Morning Attendance",
    "session_type": "class",
    "class_section": "10-A",
    "student_class": "10",
    "section": "A",
    "status": "COMPLETED",
    "started_at": "...",
    "ended_at": "..."
}
```

</details>

---

### Final Response

```json
{
  "id": "123",
  "name": "Morning Attendance",
  "session_type": "class",
  "class_section": "10-A",
  "student_class": "10",
  "section": "A",
  "status": "COMPLETED",
  "started_at": "2026-06-22T09:00:00Z",
  "ended_at": "2026-06-22T10:15:00Z"
}
```

### Flow

```text
POST /sessions/{session_id}/complete
                    │
                    ▼
      _get_session_or_404()
                    │
            Session Found?
              │         │
             YES        NO
              │         │
              │      HTTP 404
              ▼
      Status == ACTIVE ?
              │
       ┌──────┴──────┐
       │             │
      YES            NO
       │             │
       │        HTTP 400
       ▼
Set Status = COMPLETED
       │
       ▼
Set ended_at
       │
       ▼
db.commit()
       │
       ▼
db.refresh()
       │
       ▼
Schedule Cleanup Tasks
       │
       ▼
_session_to_response()
       │
       ▼
Return AttendanceSessionResponse
```

</details>

<details>
<summary><strong>API: POST /sessions/{session_id}/cancel</strong></summary>

### Operation Type

```text
CRUD Operation: UPDATE
HTTP Method: POST

Purpose:
Cancels an active attendance session,
sets its end time, and schedules cleanup
of session unknown faces.
```

### Authentication

```python
_user = RequireOperator
```

Only Operators can access this API.

### Route

```http
POST /sessions/{session_id}/cancel
```

### Step 1: Get Session

```python
s = _get_session_or_404(
    db,
    session_id
)
```

<details>
<summary><strong>Function: _get_session_or_404()</strong></summary>

### Query Session Table

```python
s = (
    db.query(AttendanceSession)
    .filter(
        AttendanceSession.id == session_id
    )
    .first()
)
```

### Session Found?

#### YES

```python
return s
```

#### NO

```python
raise HTTPException(
    status_code=404,
    detail="Session not found"
)
```

Response:

```json
{
  "detail": "Session not found"
}
```

</details>

---

### Step 2: Validate Session Status

```python
if s.status != SESSION_ACTIVE:
    raise HTTPException(
        status_code=400,
        detail="Only an active session can be cancelled"
    )
```

### Valid?

#### YES

Continue.

#### NO

Response:

```json
{
  "detail": "Only an active session can be cancelled"
}
```

Example:

```text
ACTIVE       -> Allowed
COMPLETED    -> Rejected
CANCELLED    -> Rejected
```

---

### Step 3: Mark Session Cancelled

```python
s.status = SESSION_CANCELLED
```

Example:

```text
Before: ACTIVE
After : CANCELLED
```

---

### Step 4: Set End Time

```python
s.ended_at = datetime.now(
    timezone.utc
)
```

Example:

```text
2026-06-22 14:30:15 UTC
```

---

### Step 5: Save Changes

```python
db.commit()
```

Persist changes to database.

---

### Step 6: Refresh Session Object

```python
db.refresh(s)
```

Reload latest values from database.

---

### Step 7: Schedule Background Cleanup

```python
background_tasks.add_task(
    _cleanup_session_unknowns_background,
    s.id
)
```

Schedules cleanup of session unknown faces.

---

```python
background_tasks.add_task(
    _cleanup_session_unknowns_retry_background,
    s.id
)
```

Schedules retry cleanup process.

These tasks run after the API response is returned.

---

### Step 8: Convert To Response Object

```python
return _session_to_response(s)
```

<details>
<summary><strong>Function: _session_to_response()</strong></summary>

### Convert Database Model

```python
AttendanceSessionResponse(
    id=s.id,
    name=s.name,
    session_type=s.session_type,
    class_section=s.class_section,
    student_class=s.student_class,
    section=s.section,
    status=s.status,
    started_at=s.started_at,
    ended_at=s.ended_at,
)
```

### Example Response Object

```python
{
    "id": "123",
    "name": "Morning Attendance",
    "session_type": "class",
    "class_section": "10-A",
    "student_class": "10",
    "section": "A",
    "status": "CANCELLED",
    "started_at": "...",
    "ended_at": "..."
}
```

</details>

---

### Final Response

```json
{
  "id": "123",
  "name": "Morning Attendance",
  "session_type": "class",
  "class_section": "10-A",
  "student_class": "10",
  "section": "A",
  "status": "CANCELLED",
  "started_at": "2026-06-22T09:00:00Z",
  "ended_at": "2026-06-22T09:30:00Z"
}
```

### Flow

```text
POST /sessions/{session_id}/cancel
                  │
                  ▼
    _get_session_or_404()
                  │
          Session Found?
            │         │
           YES        NO
            │         │
            │      HTTP 404
            ▼
    Status == ACTIVE ?
            │
     ┌──────┴──────┐
     │             │
    YES            NO
     │             │
     │        HTTP 400
     ▼
Set Status = CANCELLED
     │
     ▼
Set ended_at
     │
     ▼
db.commit()
     │
     ▼
db.refresh()
     │
     ▼
Schedule Cleanup Tasks
     │
     ▼
_session_to_response()
     │
     ▼
Return AttendanceSessionResponse
```

</details>


<details>
<summary><b>API: POST /recognize</b></summary>

```text
1. Operator uploads attendance image
2. Validate session and class-section
3. Read image bytes
4. Call _recognize_and_mark_attendance()
5. Detect faces
6. Search matching students in ABIS/Milvus
7. Mark attendance for recognized students
8. Store unknown faces if not recognized
9. Save frame and thumbnails (optional)
10. Return recognition result
```

---

## API Route

```python
@router.post("/recognize", response_model=AttendanceRecognizeResponse)
```

Creates attendance from a captured image.

---

### Input Parameters

```python
frame: UploadFile = File(...)
class_section: str = Form(...)
session_id: str = Form(...)
threshold: Optional[float] = Form(None)
search_mode: Optional[str] = Form(None)
threshold_mode: Optional[str] = Form(None)
capture_face_thumbnail: Optional[bool] = Form(None)
capture_frame_image: Optional[bool] = Form(None)
```

Example:

```text
frame = class_photo.jpg
class_section = III-A
session_id = 12345
threshold = 0.8
search_mode = abis_full_frame
```

---

### Authentication

```python
_user = RequireOperator
```

Only Operators can use this API.

---

### Validate Session

<details>
<summary><strong>_validate_session_scope()</strong></summary>

```python
sess = _validate_session_scope(
    db,
    session_id,
    class_section
)
```

Purpose:

```text
Checks:
- Session exists
- Session belongs to class-section
- Session is valid
```

Returns:

```python
AttendanceSession
```

</details>

---

### Read Uploaded Image

```python
image_bytes = frame.file.read()
```

Example:

```text
JPEG file
      ↓
Raw bytes
```

Stored in:

```python
image_bytes
```

---

### Convert Thumbnail Settings

```python
capture_face_thumbnail_enabled =
    _coerce_bool(capture_face_thumbnail, True)

capture_frame_image_enabled =
    _coerce_bool(capture_frame_image, True)
```

Examples:

```text
None  -> True
True  -> True
False -> False
```

---

### Main Recognition Function

<details>
<summary><strong>_recognize_and_mark_attendance()</strong></summary>

```python
out = _recognize_and_mark_attendance(
    db,
    sess,
    image_bytes,
    threshold=threshold,
    search_mode=search_mode,
    threshold_mode=threshold_mode,
    frame_id=None,
    capture_face_thumbnail_enabled=
        capture_face_thumbnail_enabled,
    capture_frame_image_enabled=
        capture_frame_image_enabled,
)
```

Purpose:

```text
Core attendance recognition engine.

Responsibilities:

1. Detect faces
2. Search ABIS/Milvus
3. Match students
4. Mark attendance
5. Save thumbnails
6. Handle unknown faces
7. Return results
```

### High Level Internal Flow

```text
Image
  ↓
Face Detection
  ↓
Face Search
  ↓
Student Match
  ↓
Attendance Record
  ↓
Save Images
  ↓
Return Result
```

</details>

---

## Build Response

```python
return AttendanceRecognizeResponse(
```

Creates final API response.

---

### Recognized Faces

```python
recognized=[
    RecognizedFace(**r)
    for r in out["recognized"]
]
```

Example:

```json
[
  {
    "student_id": "S001",
    "name": "John",
    "distance": 0.92
  }
]
```

---

### Unknown Faces

```python
unrecognized_faces=[
    UnknownFaceBox(**b)
    for b in out["unrecognized_faces"]
]
```

Example:

```json
[
  {
    "unknown_id": "abc-123",
    "x": 100,
    "y": 50,
    "w": 80,
    "h": 80
  }
]
```

---

### Remaining Response Fields

```python
class_section=out["class_section"]
unrecognized_count=out["unrecognized_count"]
result_id=out.get("result_id")
frame_photo_url=out.get("frame_photo_url")
runtime_detector_backend=out.get("runtime_detector_backend")
runtime_recognition_model=out.get("runtime_recognition_model")
```

Example:

```json
{
  "class_section": "III-A",
  "unrecognized_count": 1,
  "result_id": "uuid",
  "frame_photo_url": "/api/attendance/images/frame.jpg",
  "runtime_detector_backend": "abis",
  "runtime_recognition_model": "ABIS"
}
```

---

## Final Response Example

```json
{
  "class_section": "III-A",
  "recognized": [
    {
      "student_id": "S001",
      "name": "John",
      "distance": 0.91
    }
  ],
  "unrecognized_count": 1,
  "unrecognized_faces": [
    {
      "unknown_id": "u123",
      "x": 120,
      "y": 60,
      "w": 80,
      "h": 80
    }
  ],
  "result_id": "uuid",
  "frame_photo_url": "/api/attendance/images/frame.jpg",
  "runtime_detector_backend": "abis",
  "runtime_recognition_model": "ABIS"
}
```

---

## Complete Flow

```text
POST /recognize
      ↓
Validate Session
      ↓
Read Uploaded Image
      ↓
Convert Settings
      ↓
Call _recognize_and_mark_attendance()
      ↓
Detect Faces
      ↓
Search Matches
      ↓
Mark Attendance
      ↓
Store Unknown Faces
      ↓
Build Response
      ↓
Return AttendanceRecognizeResponse
```



# Complete Attendance Session API

## Endpoint
`POST /sessions/{session_id}/complete`

## Purpose
Marks an active attendance session as completed.

Once a session is completed:
- No more attendance can be marked in that session.
- Session status changes from `ACTIVE` → `COMPLETED`.
- End time is recorded.
- Background cleanup of unknown faces is scheduled.
- Updated session details are returned.

---

## Main Function

```python
@router.post("/sessions/{session_id}/complete", response_model=AttendanceSessionResponse)
def complete_attendance_session(
    session_id: str,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    _user=RequireOperator,
):
```

### Parameters

| Parameter | Purpose |
|------------|----------|
| session_id | Session to complete |
| background_tasks | Used to run cleanup jobs after response |
| db | Database session |
| _user | Ensures authenticated operator |

---

### Step 1: Load Session

```python
s = _get_session_or_404(db, session_id)
```

Fetches the session from database.

Internal Function:

```python
def _get_session_or_404(db: Session, session_id: str) -> AttendanceSession:
    s = db.query(AttendanceSession)\
          .filter(AttendanceSession.id == session_id)\
          .first()

    if not s:
        raise HTTPException(
            status_code=404,
            detail="Session not found"
        )

    return s
```

#### Example

Database:

| id | status |
|-----|---------|
| S1 | ACTIVE |

Request:

```http
POST /sessions/S1/complete
```

Returns session object.

---

### Step 2: Verify Session Is Active

```python
if s.status != SESSION_ACTIVE:
```

Checks current status.

---

```python
raise HTTPException(
    status_code=400,
    detail="Only an active session can be completed"
)
```

Prevents completion of:

- Completed sessions
- Cancelled sessions

#### Example

Current Status:

```text
COMPLETED
```

Result:

```json
{
  "detail": "Only an active session can be completed"
}
```

---

### Step 3: Change Status

```python
s.status = SESSION_COMPLETED
```

Updates status.

Before:

```text
ACTIVE
```

After:

```text
COMPLETED
```

---

### Step 4: Store End Time

```python
s.ended_at = datetime.now(timezone.utc)
```

Records when session ended.

Example:

```text
2026-06-21 11:45:20 UTC
```

---

### Step 5: Save Changes

```python
db.commit()
```

Writes changes permanently to database.

---

### Step 6: Refresh Object

```python
db.refresh(s)
```

Reloads latest values from database.

Now `s` contains updated status and end time.

---

### Step 7: Schedule Unknown Face Cleanup

```python
background_tasks.add_task(
    _cleanup_session_unknowns_background,
    s.id
)
```

Schedules cleanup of unknown-face records associated with this session.

Runs after API response is sent.

---

### Step 8: Schedule Retry Cleanup

```python
background_tasks.add_task(
    _cleanup_session_unknowns_retry_background,
    s.id
)
```

Schedules retry cleanup process.

Used if some unknown-face cleanup operations previously failed.

---

### Why Unknown Face Cleanup?

During attendance recognition:

```text
Face Found
   ↓
No Student Match
   ↓
Stored as Unknown Face
```

Unknown faces are temporarily stored while session is active.

When session ends:

```text
Session Completed
      ↓
Remove temporary unknown-face data
      ↓
Free storage and clean records
```

---

### Step 9: Return Updated Session

```python
return _session_to_response(s)
```

Converts database model into API response.

---

## Internal Function

```python
def _session_to_response(
    s: AttendanceSession
) -> AttendanceSessionResponse:
```

Purpose:

Converts database object into response schema.

---

```python
return AttendanceSessionResponse(
    id=s.id,
    name=s.name,
    session_type=s.session_type,
    class_section=s.class_section,
    student_class=s.student_class,
    section=s.section,
    status=s.status,
    started_at=s.started_at,
    ended_at=s.ended_at,
)
```

Returned fields:

| Field | Value |
|---------|---------|
| id | Session ID |
| name | Session name |
| session_type | Manual / Live |
| class_section | Combined class-section |
| student_class | Class |
| section | Section |
| status | COMPLETED |
| started_at | Start time |
| ended_at | End time |

---

## Example Flow

```text
Client
   |
   | POST /sessions/S1/complete
   |
   v
Load Session
   |
Verify ACTIVE
   |
Mark COMPLETED
   |
Set ended_at
   |
Commit DB
   |
Schedule unknown-face cleanup
   |
Schedule retry cleanup
   |
Return updated session
```

---

## Example Response

```json
{
  "id": "S1",
  "name": "Morning Attendance",
  "session_type": "LIVE",
  "class_section": "10-A",
  "student_class": "10",
  "section": "A",
  "status": "COMPLETED",
  "started_at": "2026-06-21T09:00:00Z",
  "ended_at": "2026-06-21T09:15:30Z"
}
```
<details>
