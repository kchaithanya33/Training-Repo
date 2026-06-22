
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



<details> <summary><b>API: GET /records/tree</b></summary>


**Description:**  
Get hierarchical attendance records tree with counts for navigation.  
Supports filtering by date range, class/section, and session. Returns grouped data by date → class/section → session with attendance counts.

#### Endpoint
```http
GET /records/tree
```

#### Query Parameters

| Parameter       | Type     | Required | Description |
|-----------------|----------|----------|-------------|
| `date`          | string   | No       | Specific date (YYYY-MM-DD) |
| `start_date`    | string   | No       | Start date for range (YYYY-MM-DD) |
| `end_date`      | string   | No       | End date for range (YYYY-MM-DD) |
| `class_section` | string   | No       | Full class section (e.g., "10-A") |
| `student_class` | string   | No       | Class only (e.g., "10") |
| `section`       | string   | No       | Section only (e.g., "A") |
| `session_id`    | string   | No       | Session ID. Use `__none__` for records without session |

#### Response Model
`AttendanceRecordsTreeResponse`

**Example Response:**
```json
{
  "success": true,
  "tree": [
    {
      "date": "2026-06-20",
      "total": 47,
      "children": [
        {
          "class": "10",
          "section": "A",
          "class_section": "10-A",
          "total": 47,
          "children": [
            {
              "session_id": "session_123",
              "session_name": "Morning Session",
              "session_type": "regular",
              "count": 42
            },
            {
              "session_id": null,
              "session_name": null,
              "session_type": null,
              "count": 5
            }
          ]
        }
      ]
    }
  ]
}
```

---

#### Internal Implementation

```python
@router.get("/records/tree", response_model=AttendanceRecordsTreeResponse)
def get_attendance_records_tree(
    date: Optional[str] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    class_section: Optional[str] = None,
    student_class: Optional[str] = None,
    section: Optional[str] = None,
    session_id: Optional[str] = None,
    db: Session = Depends(get_db),
    _user=RequireViewer,
):
    """Hierarchy with counts for Attendance History tree navigation."""
    q = (
        db.query(
            AttendanceRecord.date,
            AttendanceRecord.student_class,
            AttendanceRecord.section,
            AttendanceRecord.session_id,
            AttendanceSession.name,
            AttendanceSession.session_type,
            func.count(AttendanceRecord.id),
        )
        .outerjoin(AttendanceSession, AttendanceRecord.session_id == AttendanceSession.id)
    )
    q = _apply_attendance_records_filters(
        q, date, start_date, end_date, class_section,
        student_class, section, session_id
    )
    q = q.group_by(
        AttendanceRecord.date,
        AttendanceRecord.student_class,
        AttendanceRecord.section,
        AttendanceRecord.session_id,
        AttendanceSession.name,
        AttendanceSession.session_type,
    ).order_by(
        AttendanceRecord.date.desc(),
        AttendanceRecord.student_class.asc(),
        AttendanceRecord.section.asc(),
        AttendanceSession.name.asc().nulls_last(),
    )
    rows = q.all()
    return build_attendance_records_tree(rows)
```

#### Helper Function
```python
def _apply_attendance_records_filters(
    query,
    date: Optional[str],
    start_date: Optional[str],
    end_date: Optional[str],
    class_section: Optional[str],
    student_class: Optional[str],
    section: Optional[str],
    session_id: Optional[str],
):
    # Date filtering
    if date:
        query = query.filter(AttendanceRecord.date == date)
    else:
        if start_date:
            query = query.filter(AttendanceRecord.date >= start_date)
        if end_date:
            query = query.filter(AttendanceRecord.date <= end_date)
    
    query = _apply_class_filters(query, class_section, student_class, section)
    
    # Session filtering
    if session_id:
        sid = session_id.strip()
        if sid == "__none__":
            query = query.filter(AttendanceRecord.session_id.is_(None))
        else:
            query = query.filter(AttendanceRecord.session_id == sid)
    return query
```

#### Flow
```text
GET /records/tree
      |
Apply Filters (Date → Class/Section → Session)
      |
Query + Outer Join AttendanceSession
      |
Group By (date, class, section, session)
      |
Order By (date DESC, class ASC, ...)
      |
Build Tree Hierarchy
      |
Return Response
```
</details>
</details>
</details>
<details>
<summary><b>GET /summary</b></summary>Purpose
 
Returns attendance summary for a given date range.
 
Summary is returned in two categories:
 
- By Date
- By Class/Section
 
---
 
Endpoint
 
GET /summary
 
---
 
Query Parameters
 
Parameter| Required| Description
start_date| Yes| Start date (YYYY-MM-DD)
end_date| Yes| End date (YYYY-MM-DD)
class_section| No| Combined class + section
student_class| No| Student class
section| No| Student section
session_id| No| Attendance session ID
 
---
 
Example Request
 
/summary?start_date=2026-06-01&end_date=2026-06-10&student_class=10&section=A
 
---
 
Step 1: Validate Dates
 
Check if start_date is less than or equal to end_date.
 
if start_date > end_date:
    raise HTTPException(status_code=400)
 
If invalid, return error.
 
---
 
Step 2: Query Attendance Records by Date Range
 
Create base query with date filter.
 
base = db.query(AttendanceRecord).filter(
    AttendanceRecord.date >= start_date,
    AttendanceRecord.date <= end_date,
)
 
At this stage records are filtered only by:
 
- start_date
- end_date
 
---
 
Step 3: Apply Session Filter (Optional)
 
If session_id is provided:
 
if session_id:
    base = base.filter(
        AttendanceRecord.session_id == session_id.strip()
    )
 
Example:
 
- Morning session
- Evening session
 
---
 
Step 4: Apply Class Filters (Optional)
 
Apply:
 
- class_section
- student_class
- section
 
base = _apply_class_filters(
    base,
    class_section,
    student_class,
    section
)
 
Example:
 
- Class = 10
- Section = A
 
Now base contains only filtered records.
 
---
 
Step 5: Group Filtered Records by Date
 
At this point base already contains all filtered attendance records.
 
Now group by date:
 
by_date_rows = (
    base.with_entities(
        AttendanceRecord.date,
        func.count(AttendanceRecord.id)
    )
    .group_by(AttendanceRecord.date)
    .order_by(AttendanceRecord.date)
    .all()
)
 
Important:
 
- No new filter is added here
- group_by() works on already filtered base query
 
Example Output:
 
Date| Count
2026-06-01| 45
2026-06-02| 42
 
Convert to response:
 
by_date = [
    AttendanceDayCount(date=r[0], count=r[1])
    for r in by_date_rows
]
 
---
 
Step 6: Create Query for Class Summary
 
Separate query is created for class summary.
 
by_class_base = db.query(AttendanceRecord).filter(
    AttendanceRecord.date >= start_date,
    AttendanceRecord.date <= end_date,
)
 
---
 
Step 7: Apply Filters Again
 
Apply same filters again.
 
if session_id:
    by_class_base = by_class_base.filter(
        AttendanceRecord.session_id == session_id.strip()
    )
 
by_class_base = _apply_class_filters(
    by_class_base,
    class_section,
    student_class,
    section
)
 
---
 
Step 8: Group by Class and Section
 
Group filtered records by:
 
- student_class
- section
 
by_class_rows = (
    by_class_base.with_entities(
        AttendanceRecord.student_class,
        AttendanceRecord.section,
        func.count(AttendanceRecord.id),
    )
    .group_by(
        AttendanceRecord.student_class,
        AttendanceRecord.section
    )
    .order_by(
        AttendanceRecord.student_class,
        AttendanceRecord.section
    )
    .all()
)
 
Example Output:
 
Class| Section| Count
10| A| 200
10| B| 180
 
Convert to response:
 
by_class = [
    AttendanceClassCount(
        student_class=r[0],
        section=r[1] or "",
        class_section=_class_section_combined(r[0], r[1] or ""),
        count=r[2],
    )
    for r in by_class_rows
]
 
---
 
Step 9: Return Final Response
 
Return summary response.
 
return AttendanceSummaryResponse(
    start_date=start_date,
    end_date=end_date,
    by_date=by_date,
    by_class=by_class,
)
 
Example Response:
 
{
  "start_date": "2026-06-01",
  "end_date": "2026-06-10",
  "by_date": [...],
  "by_class": [...]
}
 
---
 
Final Flow
 
1. Validate dates
2. Filter attendance records by date
3. Apply session filter
4. Apply class filters
5. Group filtered records by date
6. Create second query
7. Apply filters again
8. Group by class and section
9. Return response
 
</details>
 
Attendance Image API Documentation
 
<details>
<summary><b>GET /images/{object_key}</b></summary>Purpose
 
Returns attendance-related images from storage.
 
Used for:
 
- Recognized face image
- Frame image
 
---
 
Endpoint
 
GET /images/{object_key}
 
---
 
Example Request
 
/images/attendance/student_101_face.jpg
 
---
 
Step 1: Receive Object Key
 
Route receives object_key as path parameter.
 
@router.get("/images/{object_key:path}")
def get_attendance_image(object_key: str, _user=RequireViewer):
 
Example:
 
attendance/student_101_face.jpg
 
---
 
Step 2: Validate Object Key
 
Check if object key is valid.
 
if not object_key or object_key.startswith("/") or ".." in object_key:
    raise HTTPException(status_code=404, detail="Image not found")
 
This prevents invalid paths.
 
Examples blocked:
 
- Empty path
- Absolute path
- Path traversal
 
Example:
 
../../etc/passwd
 
---
 
Step 3: Get Storage Service
 
Initialize storage service.
 
storage_svc = get_storage_service()
 
Storage may be:
 
- Local storage
- AWS S3
- Azure Blob
 
---
 
Step 4: Download Image
 
Try downloading image using object key.
 
try:
    data = storage_svc.download_image(object_key)
except Exception:
    raise HTTPException(status_code=404, detail="Image not found")
 
If image exists:
 
- Returns image bytes
 
If image not found:
 
- Returns 404 error
 
---
 
Step 5: Return Image Response
 
Return image as HTTP response.
 
return Response(content=data, media_type="image/jpeg")
 
Response:
 
- content = image bytes
- media_type = image/jpeg
 
Frontend can directly render image.
 
---
 
Final Flow
 
1. Receive object_key
2. Validate object_key
3. Get storage service
4. Download image
5. Return image response
 
</details>
 
