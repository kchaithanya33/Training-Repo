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

