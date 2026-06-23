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
