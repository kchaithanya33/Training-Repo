<details>
<summary><b>POST /enroll - Student Face Enrollment API Summary</b></summary>

## Endpoint

```http
POST /enroll
```

## Purpose

Enroll a new student by uploading face images and student details.

This API:

- Creates student record in database
- Generates/validates student ID
- Uploads face images to storage (MinIO/local)
- Creates StudentFaceImage records
- Creates student assignment
- Sets enrollment status as NEW

Note:
This API does **not** create face embeddings or insert data into Milvus.

The later enrollment process handles:

- Face detection
- Face embedding generation
- Milvus vector insertion
- Enrollment completion update

## Request Type

```text
multipart/form-data
```

## Parameters

### Images

```text
image / images
```

Upload student face images.

Allowed:

```text
1 - 10 images
```

Supports:

```text
image = single file

images = multiple files
```

### Primary Image

```text
primary_index
```

Index of the image to mark as primary.

Default:

```text
0
```

Example:

```text
primary_index=1
```

Second uploaded image becomes primary.

### Student Name

```text
name
```

Required.

Example:

```text
name=Rahul
```

### Class Section

```text
class_section
```

Required.

Example:

```text
III-F
```

Stored as:

```text
student_class = III
section = F
```

### Student ID

```text
student_id
```

Optional.

If provided:

- Must be unique
- Must match allowed format

Example:

```text
S001
```

If not provided:

Server generates:

```text
S0001
S0002
...
```

### Crop Enrollment Face

```text
crop_enrollment_face
```

Controls face cropping.

If enabled:

```text
Original Image
       |
       v
Detect Face
       |
       v
Store Cropped Face
```

## Internal Flow

```text
Client
  |
  v
POST /enroll
  |
  v
Validate Images
  |
  v
Create Student ID
  |
  v
Insert Student Record
  |
  v
Upload Images
  |
  v
Create Face Image Records
  |
  v
Set Status = NEW
  |
  v
Return Response
```

## Database Changes

### Student Table

```json
{
 "student_id": "S0001",
 "name": "Rahul",
 "student_class": "III",
 "section": "F",
 "enrollment_status": "NEW"
}
```

### StudentAssignment Table

```json
{
 "student_id": "S0001",
 "student_class": "III",
 "section": "F",
 "active": true
}
```

### StudentFaceImage Table

```json
{
 "student_id": "S0001",
 "minio_object_key": "staging/S0001/faces/0.jpg",
 "is_primary": true
}
```

## Success Response

```json
{
 "student_id": "S0001",
 "name": "Rahul",
 "enrollment_status": "NEW"
}
```

## Error Cases

No image:

```json
{
 "detail": "At least one image is required"
}
```

More than 10 images:

```json
{
 "detail": "You can upload 1..10 images per student"
}
```

Duplicate student ID:

```json
{
 "detail": "This student ID is already in use"
}
```

## Authentication

Required Role:

```text
Operator
```
</details>

<details>
<summary><b>GET /students - Student Listing API</b></summary>


## Purpose

Retrieve students from the database with optional filtering, searching, and pagination.

This API supports:

- Student ID filtering
- Name search
- Class filtering
- Section filtering
- Enrollment status filtering
- Pagination
- Assignment-based class scope filtering

---

## Authentication

Required Role:

```text
Viewer
```

```python
_user = RequireViewer
```

---

## Query Parameters

### student_id

```text
student_id=S001
```

Returns only the specified student.

Example:

```http
GET /students?student_id=S001
```

---

### search

Partial case-insensitive search on:

- Student ID
- Student Name

Example:

```http
GET /students?search=rah
```

Matches:

```text
Rahul
rahul
RAHUL
S001_RAH
```

---

### enrollment_status

Allowed values:

```text
NEW
PROCESSING
STORED
ERROR
```

Example:

```http
GET /students?enrollment_status=STORED
```

Returns only students whose enrollment status is STORED.

Invalid values return:

```json
{
  "detail": "enrollment_status must be one of: ERROR, NEW, PROCESSING, STORED"
}
```

---

### class_section

Combined class-section filter.

Example:

```http
GET /students?class_section=III-F
```

Internally parsed as:

```text
student_class = III
section = F
```

Returns students having an active assignment in III-F.

---

### student_class

Filter by class only.

Example:

```http
GET /students?student_class=III
```

---

### section

Filter by section only.

Example:

```http
GET /students?section=F
```

---

### Pagination

#### skip

Number of rows to skip.

Example:

```http
GET /students?skip=20
```

---

#### limit

Maximum records to return.

Example:

```http
GET /students?limit=10
```

Maximum:

```text
200
```

---

## Internal Flow

```text
GET /students
      |
      v
Create Student Query
      |
      v
Filter by student_id
      |
      v
Filter by search
      |
      v
Filter by enrollment status
      |
      v
Filter by class/section
      |
      v
Count matching records
      |
      v
Sort by student_id
      |
      v
Apply pagination
      |
      v
Fetch students
      |
      v
Load assignments
      |
      v
Build response
      |
      v
Return StudentListResponse
```

---

## Query Building

Initial query:

```python
query = db.query(Student)
```

Equivalent SQL:

```sql
SELECT *
FROM student
```

---

## Student ID Filter

```python
query.filter(
    Student.student_id == student_id
)
```

Equivalent SQL:

```sql
WHERE student_id='S001'
```

---

## Search Filter

```python
Student.student_id.ilike(term)
Student.name.ilike(term)
```

Equivalent SQL:

```sql
WHERE
student_id ILIKE '%rah%'
OR
name ILIKE '%rah%'
```

---

## Enrollment Status Filter

```python
query.filter(
    Student.enrollment_status == status_val
)
```

Example:

```sql
WHERE enrollment_status='STORED'
```

---

## Class/Section Filtering

Uses StudentAssignment table.

Example:

Student:

```text
S001
S002
```

Assignments:

```text
S001 -> III-F
S002 -> III-A
```

Request:

```http
GET /students?class_section=III-F
```

Result:

```text
S001
```

Only students with matching active assignments are returned.

---

## Total Count

```python
total = query.count()
```

Calculates total matching rows before pagination.

Example:

```text
500
```

---

## Sorting

```python
query.order_by(Student.student_id)
```

Result:

```text
S001
S002
S003
...
```

---

## Pagination

```python
q.offset(skip).limit(limit)
```

Example:

```http
GET /students?skip=20&limit=10
```

Returns:

```text
Records 21-30
```

---

## Response Construction

For every student:

```python
_load_assignments(
    db,
    s.student_id
)
```

Loads active assignments.

Then:

```python
_student_response(...)
```

Builds response object.

---

## Success Response

```json
{
  "students": [
    {
      "student_id": "S001",
      "name": "Rahul",
      "class_section": "III-F",
      "enrollment_status": "STORED"
    },
    {
      "student_id": "S002",
      "name": "Amit",
      "class_section": "III-A",
      "enrollment_status": "NEW"
    }
  ],
  "total": 125
}
```

---

## Runtime Models Included

The API fetches currently configured face recognition algorithms:

```python
runtime_detector_backend,
runtime_recognition_model
= face_svc.get_runtime_algorithms()
```

Example:

```text
Detector: RetinaFace
Recognition: ArcFace
```

These values are included when building each student response.

---

## Summary

This API is the main student search endpoint.

It allows:

- Searching students
- Filtering students
- Viewing enrollment status
- Filtering by class and section
- Paginating results
- Returning assignment-aware student information
</details>
