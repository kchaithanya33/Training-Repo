# Post-Attendance Report
 
## Overview
Once attendance is completed, the system should display a concise report with the following details:
 
- **Total Enrolled Students**: The total number of students registered in the class or section.
- **Number of Students Present**: The count of students who were present in that session.
- **Number of Students Absent**: The count of students who were absent in that session.
- **List of Absent Students**: Names of all students who were absent in that session.
 
## Example Report
 
- **Total Enrolled**: 30
- **Present**: 27
- **Absent**: 3
- **Absent Students**:
  - Alice Johnson
  - Mark Smith
  - Priya Kumar
## Workflow Diagram
![Attendance Report](Attendance%20Report-2026-06-08-033415.png)

# Student Attendance Report

## Overview

This report focuses on a specific student. After selecting a Student ID, the system allows the user to generate attendance reports for a selected time period (**Day**, **Week**, **Month**, or **Semester**).

The report can optionally be filtered by subject.

---

## Steps

### 1. Select Student ID

The user selects a student using their unique **Student ID**.

### 2. Select Report Type

Choose one of the following:

- Day
- Week
- Month
- Semester

### 3. Optional Subject Selection

- If a subject is selected, the report displays attendance only for that subject.
- If no subject is selected, the report displays attendance across all enrolled subjects.

---

## Output Details

### Student Information

- Student ID
- Student Name
- Class
- Section

### Attendance Information

For each subject (or selected subject):

- Total Classes Conducted
- Classes Attended
- Classes Absent
- Attendance Percentage

### Overall Summary

- Overall Attendance Percentage
- Total Classes Conducted
- Total Classes Attended
- Total Classes Absent

---

## Example Report

### Filters

- **Student ID:** 12345
- **Report Type:** Semester
- **Subject:** All Subjects

### Student Details

- **Student ID:** 12345
- **Name:** John Doe
- **Class:** 10
- **Section:** A

### Subject-wise Attendance

| Subject | Total Classes | Classes Attended | Classes Absent | Attendance % |
|----------|--------------|------------------|----------------|--------------|
| Maths | 40 | 36 | 4 | 90.0% |
| Science | 38 | 35 | 3 | 92.1% |
| English | 42 | 39 | 3 | 92.9% |

### Overall Attendance

- **Total Classes Conducted:** 120
- **Total Classes Attended:** 110
- **Total Classes Absent:** 10
- **Overall Attendance Percentage:** 91.67%

