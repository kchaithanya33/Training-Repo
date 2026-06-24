# MOSIP and ABIS

## What is MOSIP?

MOSIP is an open-source **identity management platform** used to build large-scale digital identity systems.

### MOSIP manages:

* Enrollment workflows
* Identity records
* Authentication requests
* Identity lifecycle (create, update, delete)
* Integration with biometric systems

> **Note:** MOSIP does not perform biometric matching itself.

---

## How is MOSIP used with ABIS?

```text
MOSIP
   ↓
ABIS
```

MOSIP manages the identity process, while ABIS performs biometric operations such as:

* Face matching
* Fingerprint matching
* Iris matching
* Duplicate detection
* Identification


* **MOSIP** = Identity Management Platform
* **ABIS** = Biometric Matching Engine

MOSIP manages identities and workflows, while ABIS performs fingerprint, face, and iris matching.


# MOSIP Wrapper Explanation

The **MOSIP Wrapper** is needed because MOSIP and our ABIS service speak different APIs/formats.

## Architecture Flow

```
MOSIP
  ↓
MOSIP Wrapper
  ↓
ABIS Service
```

## Without MOSIP Wrapper

MOSIP sends requests in the **MOSIP ABIS standard format**:

- Insert
- Identify
- Delete
- Status

However, our **BioChq ABIS service** expects its own proprietary API format. Therefore, MOSIP cannot directly communicate with the ABIS service.

## What the Wrapper Does

The MOSIP Wrapper acts as a translator/bridge between MOSIP and the BioChq ABIS service.

### Step-by-step Process:

1. **Receives MOSIP requests**
   ```
   MOSIP → Enroll person
   ```

2. **Converts MOSIP data to BioChq format**
   ```
   MOSIP JSON
         ↓
   Wrapper Mapping
         ↓
   BioChq JSON
   ```

3. **Calls ABIS Service**
   ```
   Wrapper
      ↓
   ABIS Service
   ```

4. **Gets ABIS response**
   ```
   ABIS Service
         ↓
      Wrapper
   ```

5. **Converts response back to MOSIP format**
   ```
   BioChq Response
          ↓
   Wrapper Mapping
          ↓
   MOSIP Response
   ```

<details><summary><b>Mapper classes<b></summary>

<details><summary>BiometricTypeMapper Class</summary>

## Overview

**Class:** `BiometricTypeMapper`

**What it does:**  
This class is responsible for converting biometric-related information between **MOSIP** and **BioChq** formats.

It handles:

- Biometric Type Mapping (Face, Finger, Iris)
- Biometric Subtype Mapping (Right Thumb, Left Iris, etc.)
- Image Format Mapping (PNG, JPG, JP2, WSQ)

---

## Functions

### 1. `cbeff_to_biochq_type()`

**Purpose:**  
Converts MOSIP/CBEFF biometric type → BioChq biometric type.

```plaintext
Face    → FID
Finger  → FIR
Iris    → IIR
```

---

### 2. `biochq_to_mosip_type()`

**Purpose:**  
Converts BioChq biometric type → MOSIP biometric type.

```plaintext
FID → Face
FIR → Finger
IIR → Iris
```

---

### 3. `map_subtype()`

**Purpose:**  
Converts biometric subtypes.

```plaintext
Right IndexFinger → Right_Index
Left Thumb        → Left_Thumb
Right Iris        → Right_Iris
```

---

### 4. `get_image_type()`

**Purpose:**  
Converts image format codes into BioChq image types.

```plaintext
7  → JPG
10 → JP2
14 → PNG
4  → WSQ
```

---

### 5. `get_biochq_type()`

**Purpose:**  
Helper function that calls `cbeff_to_biochq_type()` and returns a valid BioChq type.

```plaintext
Face   → FID
Finger → FIR
```

---

### 6. `get_mosip_type()`

**Purpose:**  
Helper function that calls `biochq_to_mosip_type()` and returns a valid MOSIP type.

```plaintext
FID → Face
FIR → Finger
```

---

### 7. `get_biochq_subtype()`

**Purpose:**  
Legacy helper function for subtype conversion.

```plaintext
Right IndexFinger → Right_Index
```

---
</details>
<details><summary><b>MOSIPToBioChqMapper Class</b></summary>

**Class:** `MOSIPToBioChqMapper`

**Purpose:**  
Converts MOSIP requests into the format expected by BioChq ABIS.

This class contains all mappings from **MOSIP → BioChq** for the three main operations:

- Insert
- Identify
- Delete

And one helper function for FPIR → Threshold conversion.

---

## Functions

### 1. `_fpir_to_threshold()`

**What it does:**  
Converts MOSIP's `targetFPIR` value into a BioChq similarity threshold.

**Input:** `targetFPIR`  
**Output:** `threshold`

**Example:**

```text
MOSIP:
targetFPIR = 50
      ↓
_fpir_to_threshold()
      ↓
BioChq:
threshold = 0.999...
```

**Used by:** `map_identify_request()`

---

### 2. `map_insert_request()`

**What it does:**  
Converts a MOSIP Insert/Enrollment request into a BioChq Insert payload.

**Flow:**

```text
MOSIP Insert Request
      ↓
Read biometric type
      ↓
Map type (Face/Finger/Iris → FID/FIR/IIR)
      ↓
Map subtype
      ↓
Check image format
      ↓
If ISO (FAC/FIR/IIR)
    Extract image
    Convert to PNG
      ↓
Base64 encode image
      ↓
Create BioChq payload
      ↓
Return payload
```

**Output Payload Example:**

```json
{
    "uId": "...",
    "bioType": "FID",
    "imageType": "PNG",
    "encodedImage": "...",
    "bioSubType": "Face",
    "captureMode": "CONTACT"
}
```

---

### 3. `map_identify_request()`

**What it does:**  
Converts a MOSIP Identify request into a BioChq Search/Identify request.

**Flow:**

```text
MOSIP Identify Request
      ↓
Read targetFPIR
      ↓
Convert to threshold
      ↓
Read maxResults
      ↓
Map biometric type
      ↓
Base64 encode image
      ↓
Add gallery filters (if any)
      ↓
Create BioChq search payload
      ↓
Return payload
```

**Output Payload Example:**

```json
{
    "threshold": 0.99,
    "limit": 100,
    "bioType": "FID",
    "encodedImage": "...",
    "imageType": "PNG"
}
```

**Special Handling:**
- Converts FPIR → threshold
- Supports gallery filtering
- Supports identify-by-image
- Supports identify-by-reference-id

---

### 4. `map_delete_request()`

**What it does:**  
Converts a MOSIP Delete request into a BioChq Delete request.

**Flow:**

```text
MOSIP referenceId
      ↓
galleryId
      ↓
BioChq Delete Payload
```

**Input:**

```python
reference_id = "123"
```

**Output:**

```json
{
    "galleryId": "123"
}
```

---

## Summary Table

| Function                    | Purpose                              | Input                  | Output              |
|-----------------------------|--------------------------------------|------------------------|---------------------|
| `_fpir_to_threshold()`     | Convert FPIR to BioChq threshold    | targetFPIR            | threshold          |
| `map_insert_request()`     | MOSIP Enrollment → BioChq Enrollment| biometric data        | Insert payload     |
| `map_identify_request()`   | MOSIP Identify → BioChq Search      | image/referenceId     | Identify payload   |
| `map_delete_request()`     | MOSIP Delete → BioChq Delete        | referenceId           | Delete payload     |

---

This class serves as the core request mapper from MOSIP to BioChq ABIS.
</details>
<details><summary><b>BioChqToMOSIPMapper Class</b></summary>

**Class:** `BioChqToMOSIPMapper`

**Purpose:**  
Converts BioChq responses into the format expected by MOSIP.

This is the **reverse mapper** of `MOSIPToBioChqMapper`.

```
BioChq Response
    ↓
BioChqToMOSIPMapper
    ↓
MOSIP Response
```

Handles:
- Insert Response
- Identify Response
- Delete Response
- Error Codes
- Candidate Results

---

## Main Functions

### 1. `map_insert_response()`

Converts BioChq enrollment response to MOSIP Insert response.

- Reads `status`, `galleryId`, `errorCode`
- Sets `returnValue` → `"1"` (Success) or `"2"` (Failure)
- Maps errors using `_map_error_code()`

**MOSIP Output:**
```json
{
  "id": "mosip.abis.insert",
  "requestId": "...",
  "responsetime": "2025-...",
  "returnValue": "1"
}
```

---

### 2. `map_identify_response()`

Converts BioChq search results to MOSIP Identify response.

- Extracts `searchResults`
- Converts each result using `_map_candidate()`
- Builds `candidateList` with count and candidates

**MOSIP Output:**
```json
{
  "id": "mosip.abis.identify",
  "requestId": "...",
  "returnValue": "1",
  "candidateList": { ... }
}
```

---

### 3. `map_delete_response()`

Converts BioChq delete response to MOSIP Delete response.

- Sets `returnValue` → `"1"` (Success) or `"2"` (Failure)

---

## Helper Functions

- **`_map_candidate()`** — Converts one BioChq match to MOSIP candidate (referenceId, analytics, modalities)
- **`_map_error_code()`** — Maps BioChq errors to MOSIP error codes (e.g. `INVALID_IMAGE` → `7`)
- **`_map_bio_type()`** — FID → Face, FIR → Finger, IIR → Iris
- **`_normalize_reference_id()`** — Cleans BioChq reference IDs
- **`_map_failure_reason()`** — Maps failure reasons for Identify

---

This class ensures full compatibility when sending responses back to MOSIP.

</details>
</details>
<details><summary><b>Client</b></summary>
BioChqClient Class

## Overview

This class is the **BioChq API Client**.  
Its job is to send HTTP requests to BioChq ABIS and return responses.

It acts as the **communication layer** between the MOSIP Wrapper and BioChq ABIS.

---

## Constructor & Setup

### `__init__()`

```python
client = BioChqClient(
    base_url="http://localhost:8000",
    api_key="abc123"
)
```

Stores: `base_url`, `api_key`, `timeout`, `max_retries` and creates an HTTP session.

---

### Key Helper Methods

- **`_create_session()`** — Creates reusable session with automatic retries (429, 500, 502, 503, 504)
- **`_get_headers()`** — Returns headers with `Content-Type` and `X-ABIS-Api-Key`
- **`_response_snippet()`** — Helper for logging error messages

---

## BioChq Operations

### 1. `insert()`
- **Method:** `POST /api/metadata/insert/`
- Enrolls biometric data
- Input: `uId`, `bioType`, `image` (base64)
- Output: `galleryId`, `status`

### 2. `search()`
- **Method:** `POST /api/metadata/search/`
- Performs 1:N biometric search

### 3. `identify()`
- **Method:** `POST /api/metadata/identify/`
- Identify using `uId`

### 4. `status()`
- **Method:** `POST /api/metadata/status/`
- Check enrollment status

### 5. `delete()`
- **Method:** `DELETE /api/metadata/{galleryId}/`
- Deletes enrolled record

---

## Admin Operations

- **`health_check()`** — `GET /api/metadata/admin/health/`
- **`processing_status()`** — Get pending jobs
- **`stats()`** — Get database statistics

---

## Session Management

- **`close()`** — Closes HTTP session
- Supports Context Manager (`with` statement)

---

## Architecture Position

```text
MOSIP Request
      ↓
MOSIPToBioChqMapper
      ↓
BioChqClient
      ↓
BioChq ABIS API
      ↓
BioChqToMOSIPMapper
      ↓
MOSIP Response
```

**Role:** Handles all actual HTTP communication with BioChq.

</details>

</details>


<details><summary>View</summary>

<details>
<summary><strong>insert()</strong></summary>

### Purpose

Acts as the API entry point for MOSIP Insert requests.

### Code

```python
@api_view(["POST"])
@require_mosip_auth
def insert(request):
    response_payload, status_code = _handle_insert_payload(
        request.data,
        getattr(request, "mosip_token", None)
    )
    return Response(response_payload, status=status_code)
```

### Flow

```text
MOSIP Request
      ↓
Authentication Check
      ↓
Read request.data
      ↓
Read mosip_token
      ↓
Call _handle_insert_payload()
      ↓
Receive:
    response_payload
    status_code
      ↓
Return HTTP Response
```

### Responsibility

- Receive request from MOSIP
- Verify authentication
- Pass payload to business logic layer
- Return final response

---

<details>
<summary><strong>_handle_insert_payload() Function Flow</strong></summary>

### 1. Read Request Data

Extract:

- requestId
- referenceId
- referenceURL
- requesttime
- id
- version

---

### 2. Validate Request

Checks:

- Validate operation id (`mosip.abis.insert`)
- Validate requesttime
- Validate referenceId
- Validate referenceURL
- Validate version
- Reject unknown fields

---

### 3. Create Request Record

```python
_create_request_record("insert", payload)
```

Stores request metadata in the database.

---

### 4. Check Duplicate ReferenceId

```text
referenceId already exists?
        │
   Yes ─┴─→ failureReason = 10
        │
       No
```

---

### 5. Download and Extract Biometrics

```python
_extract_biometrics(payload, token)
```

Responsibilities:

- Download CBEFF XML
- Decrypt data
- Parse XML
- Extract biometric records

---

### 6. Handle Extraction Errors

| Scenario | failureReason |
|-----------|--------------|
| Download failure | 7 |
| Decryption failure | 11 |
| Expired URL | 17 |
| Invalid XML/CBEFF | 16 |
| No biometric data | 11 |

---

### 7. Validate Biometric Data

Checks:

- Data exists
- Valid biometric type
- Valid format
- Base64 decoding
- Data integrity
- Not corrupted

---

### 8. Face / Iris Validation

#### Face

```python
DeepFace
```

Validate face image.

#### Iris

```python
OpenIris
```

Validate iris image.

---

### 9. MOSIP → BioChq Mapping

```python
MOSIPToBioChqMapper.map_insert_request()
```

Converts MOSIP biometric format into BioChq enrollment format.

---

### 10. Call BioChq Insert API

```python
biochq_client.insert()
```

Returns:

- galleryId
- status
- qualityScore

---

### 11. Wait Until STORED

```python
biochq_client.status()
```

Poll until:

```text
STORED
```

or

```text
COMPLETED
```

---

### 12. Save Mapping

```python
_record_mapping()
```

Stores:

```text
referenceId
      ↕
   galleryId
```

Used later by:

- Delete API
- Identify API
- Status API

---

### 13. Mark Request Completed

```python
mosip_request.mark_completed()
```

---

### 14. BioChq → MOSIP Mapping

```python
BioChqToMOSIPMapper.map_insert_response()
```

Converts BioChq response into MOSIP response.

---

### 15. Return Success Response

```json
{
  "id": "mosip.abis.insert",
  "requestId": "...",
  "returnValue": "1"
}
```

</details>

</details>
   
   <details><summary>identify()</summary>
   # Identify API (`mosip.abis.identify`)

## Purpose

The Identify API performs biometric identification.

It receives biometric data from MOSIP, sends it to BioChq ABIS for matching, and returns matching candidates in MOSIP format.

## Entry Point

```python
@api_view(["POST"])
@require_mosip_auth
def identify(request):

    response_payload, status_code = _handle_identify_payload(
        request.data,
        getattr(request, "mosip_token", None)
    )

    return Response(
        response_payload,
        status=status_code
    )
```

The main processing is handled by `_handle_identify_payload()`.

## Identify Processing Flow

MOSIP Identify Request  
→ Identify API  
→ Validate MOSIP Authentication  
→ Extract Request Data  
→ Validate Request Fields  
→ Create Request Record  
→ Process Gallery Filter  
→ Extract Biometric Data  
→ Check Reference Mapping  
→ Convert MOSIP Data to BioChq Format  
→ Call BioChq ABIS (Search / Identify)  
→ Process Matching Results  
→ Convert BioChq Response to MOSIP Format  
→ Return Candidate List

## Main Business Logic Function: `_handle_identify_payload(payload, token)`

### 1. Extract Request Information
- `requestId`, `referenceId`, `requesttime`, `version`, `flags`, `gallery`, `biometricData`

### 2. Validate Request
- API ID must be `mosip.abis.identify`
- Validates `requesttime` format
- Checks required fields
- Rejects unknown fields

### 3. Create Request Record
- `_create_request_record("identify", payload)`

### 4. Process Gallery Filter
- Validates reference IDs using database mapping
- Returns `ABIS3028` if no valid gallery

### 5. Extract Biometrics
- `_extract_biometrics(payload, token)`
- Decodes CBEFF and extracts biometric records

### 6. Reference Mapping
- Maps `referenceId` → `galleryId` using `ReferenceMapping` table

### 7. Determine Matching Threshold
- Uses `targetFPIR` or default

### 8. MOSIP → BioChq Mapping
- `MOSIPToBioChqMapper.map_identify_request()`

### 9. Call BioChq API
- `biochq_client.search()` if biometric data present
- `biochq_client.identify()` if only referenceId

### 10. Process BioChq Response
- Convert IDs back
- Remove self-match
- Apply filters & threshold
- Remove duplicates
- Sort by similarity

### 11. BioChq → MOSIP Mapping
- `BioChqToMOSIPMapper.map_identify_response()`

### 12. Update Request Status
- Mark as completed or failed

## Final Response Example

```json
{
  "id": "mosip.abis.identify",
  "requestId": "12345",
  "returnValue": "1",
  "candidateList": [
    {
      "referenceId": "USER002",
      "analytics": { ... }
    }
  ]
}
```

This API is the core of 1:N biometric identification in the MOSIP Wrapper.
</details>
</details>
