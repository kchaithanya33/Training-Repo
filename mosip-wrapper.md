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
