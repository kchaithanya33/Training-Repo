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

