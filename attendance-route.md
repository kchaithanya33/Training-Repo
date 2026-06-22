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
