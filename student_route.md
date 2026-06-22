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

<details>
<summary><b>API :GET /classes </b></summary>

At first glance, it looks like duplication because the Student table already stores:

```text
student_id
student_class
section
```

So it seems we could get class information directly from the Student table.

However, the StudentAssignment table is designed to support:

- Assignment history
- Class transfers
- Multiple assignments per student
- Subject-specific assignments
- Active/inactive assignment tracking
- Future scalability



# Student Table

The Student table stores the student's primary information.

Example:

```text
Student
--------------------------------
S001 | Rahul | III | A
S002 | Amit  | III | B
```

Purpose:

```text
Who the student is
```

Contains information such as:

- Student ID
- Student Name
- Class
- Section
- Enrollment Status

---

# Problem If Only Student Table Exists

Suppose Rahul is transferred.

Before:

```text
S001 | Rahul | III | A
```

After:

```text
S001 | Rahul | IV | B
```

The previous assignment is lost permanently.

There is no history.

---

# StudentAssignment Table

Instead of overwriting old information, assignments can be stored separately.

Example:

```text
Student
-------------------
S001 | Rahul
```

```text
StudentAssignment
------------------------------------------------
S001 | III | A | active=False
S001 | IV  | B | active=True
```

Now both current and historical assignments are preserved.

---

# Multiple Assignments

A student may belong to more than one assignment.

Example:

```text
S001 | III | A | Math
S001 | III | A | Science
S001 | III | A | English
```

One student can have multiple assignment records.

A single Student row cannot represent this efficiently.

---

# Clue From The Model

The model contains:

```python
subject = Column(String(100))
```

This indicates the table is designed for:

```text
Student
    ↓
Class
    ↓
Section
    ↓
Subject
```

and not just basic student storage.

---

# Active Assignments

The table contains:

```python
active = Column(Boolean, nullable=False, default=True)
```

This allows the system to track:

```text
Current Assignment
vs
Old Assignment
```

Example:

```text
S001 | III | A | active=False
S001 | IV  | B | active=True
```

Only active assignments are used by APIs such as:

```http
GET /classes
GET /students
```

---

# Why /classes Uses StudentAssignment

The /classes endpoint queries:

```python
StudentAssignment.student_class
StudentAssignment.section
```

because it wants:

```text
All active class-section combinations
```

rather than simply reading values from Student.

---

# Current Implementation

During enrollment:

```python
StudentAssignment(
    student_id=new_id,
    student_class=student_class,
    section=section,
    subject="",
    is_primary=True,
    active=True,
)
```

Currently each student receives only one assignment.

Because of that, StudentAssignment appears redundant right now.

---

# Future Benefits

The design supports future features such as:

- Student transfers
- Assignment history
- Subject assignments
- Multiple class mappings
- Active/inactive assignment management

without changing the database structure later.

---

# Conceptual Difference

```text
Student
    = Who the student is
```

```text
StudentAssignment
    = Where the student belongs
```

This is a common database design pattern known as:

```text
Master Table + Assignment/Relationship Table
```
</details>
<details>
<summary><b>GET /class-sections - Class & Section Matrix API</b></summary>

## Endpoint

```http
GET /class-sections
```

## Purpose

Returns all unique active class and section combinations available in the system.

This API is mainly used by the frontend to populate:

- Class dropdowns
- Section dropdowns
- Class-section selection filters

Unlike `/classes`, this API returns class and section as separate fields instead of a combined string.

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

## Request Parameters

None.

Example:

```http
GET /class-sections
```

---

## Response Example

```json
{
  "pairs": [
    {
      "student_class": "III",
      "section": "A"
    },
    {
      "student_class": "III",
      "section": "B"
    },
    {
      "student_class": "IV",
      "section": "A"
    }
  ]
}
```



# Code Explanation

## Route Definition

```python
@router.get("/class-sections", response_model=ClassSectionMatrixResponse)
```

Creates the endpoint:

```http
GET /class-sections
```

The response must match:

```python
ClassSectionMatrixResponse
```

---

## Function Definition

```python
def list_class_section_pairs(
    db: Session = Depends(get_db),
    _user=RequireViewer
):
```

### Database Session

```python
db: Session = Depends(get_db)
```

Provides a database connection.

---

### Authentication

```python
_user = RequireViewer
```

Ensures the user has Viewer access.

---

## Function Comment

```python
"""Distinct class + section pairs for separate dropdowns in the UI."""
```

Explains the purpose of the API.

The frontend can use this endpoint to build dropdowns like:

```text
Class
-----
III
IV
V
```

```text
Section
-------
A
B
C
```

---

## Query Database

```python
rows = (
    db.query(
        StudentAssignment.student_class,
        StudentAssignment.section
    )
```

Selects only:

```text
student_class
section
```

from the StudentAssignment table.

Example table:

```text
student_id | class | section
--------------------------------
S001       | III   | A
S002       | III   | A
S003       | III   | B
S004       | IV    | A
```

---

## Filter Active Assignments

```python
.filter(StudentAssignment.active.is_(True))
```

Only active assignments are included.

Equivalent SQL:

```sql
WHERE active = true
```

---

## Remove Duplicates

```python
.distinct()
```

Without DISTINCT:

```text
III A
III A
III B
IV A
```

With DISTINCT:

```text
III A
III B
IV A
```

Only unique combinations remain.

Equivalent SQL:

```sql
SELECT DISTINCT
student_class,
section
```

---

## Sort Results

```python
.order_by(
    StudentAssignment.student_class,
    StudentAssignment.section
)
```

Sorts results by:

1. Class
2. Section

Result:

```text
III A
III B
IV A
```

---

## Execute Query

```python
.all()
```

Runs the SQL query and returns:

```python
[
    ("III", "A"),
    ("III", "B"),
    ("IV", "A")
]
```

Stored in:

```python
rows
```

---

## Build Response

```python
return ClassSectionMatrixResponse(
```

Creates the response object.

---

### List Comprehension

```python
pairs=[
    ClassSectionPair(
        student_class=r[0],
        section=r[1] or ""
    )
    for r in rows
]
```

Loops through every row.

Example:

```python
("III", "A")
```

becomes:

```python
ClassSectionPair(
    student_class="III",
    section="A"
)
```

---

### Why Use `or ""`?

```python
section=r[1] or ""
```

If section is:

```python
None
```

it becomes:

```python
""
```

This avoids returning null values to the frontend.

---

## Final Response

```json
{
  "pairs": [
    {
      "student_class": "III",
      "section": "A"
    },
    {
      "student_class": "III",
      "section": "B"
    },
    {
      "student_class": "IV",
      "section": "A"
    }
  ]
}
```

---

## SQL Equivalent

```sql
SELECT DISTINCT
    student_class,
    section
FROM student_assignments
WHERE active = true
ORDER BY
    student_class,
    section;
```

---

## Complete Flow

```text
GET /class-sections
        |
        v
Check Viewer Permission
        |
        v
Query StudentAssignment Table
        |
        v
Filter Active Assignments
        |
        v
Remove Duplicate Class-Section Pairs
        |
        v
Sort Results
        |
        v
Convert Rows To ClassSectionPair Objects
        |
        v
Return Response
```

---

## Difference Between Similar APIs

### GET /classes

Response:

```json
{
  "classes": [
    "III-A",
    "III-B",
    "IV-A"
  ]
}
```

Returns combined strings.

---

### GET /class-sections

Response:

```json
{
  "pairs": [
    {
      "student_class": "III",
      "section": "A"
    }
  ]
}
```

Returns structured class and section fields separately.

This format is more useful for frontend filters and dropdowns.
</details>


<details>
<summary><b>GET /{student_id}/assignments - Student Assignments API</b></summary>

## Endpoint

```http
GET /{student_id}/assignments
```

## Purpose

Returns all active assignments associated with a specific student.

This API is used to retrieve:

- Student class assignments
- Student section assignments
- Subject assignments
- Primary assignment information

Only active assignments are returned.

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

## Path Parameters

### student_id

Student identifier.

Example:

```http
GET /S001/assignments
```

Here:

```text
student_id = S001
```

---

## Success Response

```json
[
  {
    "student_class": "III",
    "section": "A",
    "subject": "Math",
    "is_primary": true,
    "active": true
  },
  {
    "student_class": "III",
    "section": "A",
    "subject": "Science",
    "is_primary": false,
    "active": true
  }
]
```

---

## Error Response

### Student Not Found

```json
{
  "detail": "Student not found"
}
```

Status Code:

```http
404 Not Found
```

# Code Explanation

## Route Definition

```python
@router.get(
    "/{student_id}/assignments",
    response_model=List[StudentAssignmentItem]
)
```

Creates endpoint:

```http
GET /{student_id}/assignments
```

Example:

```http
GET /S001/assignments
```

Response type:

```python
List[StudentAssignmentItem]
```

which means:

```json
[
  {},
  {},
  {}
]
```

A list of assignment objects.

---

## Function Definition

```python
def list_student_assignments(
    student_id: str,
    db: Session = Depends(get_db),
    _user=RequireViewer
):
```

### student_id

Obtained from the URL.

Example:

```http
GET /S001/assignments
```

becomes:

```python
student_id = "S001"
```

---

### Database Session

```python
db: Session = Depends(get_db)
```

Provides database access.

---

### Authentication

```python
_user = RequireViewer
```

Ensures only authorized users can access the endpoint.

---

## Verify Student Exists

```python
student = (
    db.query(Student)
    .filter(Student.student_id == student_id)
    .first()
)
```

Checks whether the student exists.

Equivalent SQL:

```sql
SELECT *
FROM students
WHERE student_id = 'S001'
LIMIT 1;
```

---

## Handle Missing Student

```python
if not student:
```

If no student is found:

```python
raise HTTPException(
    status_code=404,
    detail="Student not found"
)
```

Response:

```json
{
  "detail": "Student not found"
}
```

---

## Load Student Assignments

```python
_load_assignments(
    db,
    student_id
)
```

Loads all active assignments belonging to the student.

---

# _load_assignments Helper

```python
def _load_assignments(
    db: Session,
    student_id: str
) -> list[StudentAssignment]:
```

Purpose:

```text
Retrieve all active assignments for a student
and return them in a consistent order.
```

---

## Query StudentAssignment Table

```python
db.query(StudentAssignment)
```

Equivalent SQL:

```sql
SELECT *
FROM student_assignments
```

---

## Filter By Student

```python
.filter(
    StudentAssignment.student_id == student_id,
```

Example:

```python
student_id = "S001"
```

Equivalent SQL:

```sql
WHERE student_id = 'S001'
```

---

## Filter Active Assignments

```python
StudentAssignment.active.is_(True)
```

Equivalent SQL:

```sql
AND active = TRUE
```

Only active assignments are returned.

---

## Sort Primary Assignments First

```python
StudentAssignment.is_primary.desc()
```

Sorting:

```text
True
False
False
```

Primary assignments appear before non-primary assignments.

Equivalent SQL:

```sql
ORDER BY is_primary DESC
```

---

## Sort By Class

```python
StudentAssignment.student_class.asc()
```

Example:

```text
II
III
IV
V
```

Equivalent SQL:

```sql
student_class ASC
```

---

## Sort By Section

```python
StudentAssignment.section.asc()
```

Example:

```text
A
B
C
```

Equivalent SQL:

```sql
section ASC
```

---

## Sort By Subject

```python
StudentAssignment.subject.asc()
```

Example:

```text
English
Math
Science
```

Equivalent SQL:

```sql
subject ASC
```

---

## Execute Query

```python
.all()
```

Runs the query and returns all matching assignments.

Example result:

```python
[
    StudentAssignment(...),
    StudentAssignment(...),
    StudentAssignment(...)
]
```

---

## Convert Database Rows To API Schema

```python
[
    _assignment_row_to_schema(r)
    for r in _load_assignments(db, student_id)
]
```

Converts database objects into API response objects.

Equivalent code:

```python
result = []

for r in _load_assignments(db, student_id):
    result.append(
        _assignment_row_to_schema(r)
    )

return result
```

---

## Example

Database:

```text
student_id | class | section | subject | primary | active
---------------------------------------------------------
S001       | III   | A       | Math    | True    | True
S001       | III   | A       | Science | False   | True
S001       | III   | A       | English | False   | True
S001       | II    | B       | Math    | False   | False
```

Call:

```http
GET /S001/assignments
```

Returned assignments:

```text
Math      (Primary)
English
Science
```

Inactive assignments are excluded.

---

## SQL Equivalent

```sql
SELECT *
FROM student_assignments
WHERE
    student_id = 'S001'
    AND active = TRUE
ORDER BY
    is_primary DESC,
    student_class ASC,
    section ASC,
    subject ASC;
```

---

## Complete Flow

```text
GET /{student_id}/assignments
              |
              v
Check Viewer Permission
              |
              v
Find Student
              |
        Student Exists?
           /      \
         No        Yes
         |          |
         v          v
Return 404    Load Assignments
                    |
                    v
        Filter Active Records
                    |
                    v
      Sort Primary Assignments First
                    |
                    v
 Convert To StudentAssignmentItem
                    |
                    v
             Return Response
```

</details>
