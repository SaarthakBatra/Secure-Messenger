# Module Specification: Mobile GPS Capture & Map UI

## 1. Overview
- **Path:** `modules/mobile/location/`
- **Module ID:** `mobile-location`
- **Implementation Phase:** Phase 7
- **Core Intent:** Trigger interfaces for location requests, background service listeners capturing GPS coordinates, Leaflet map overlays, and graceful denial handlers.

### Inter-Module Dependency Layer
- **Allowed Dependencies:** `modules/shared/`, `modules/mobile/vault-auth/`, `modules/mobile/conversations/`
- **Data Flow Contract:** Direct E2EE compliant integration. Ensures zero plaintext leakage.

---

## 2. API / Interface Contracts

### Endpoints / Screen Contexts
- **Location Hub Overlay:** Renders interactive map pins and shows historical coordinates with timestamps.
- **Background Geolocator Service:** Wakes GPS components discreetly on request alerts.

---

## 3. Data Architecture & Schemas

### Local Database `location_pings` (SQLite)
- `ping_id` (Text, Primary Key)
- `conversation_id` (Text)
- `requested_by` (Text)
- `encrypted_latitude` (Text)
- `encrypted_longitude` (Text)
- `timestamp` (Int)

---

## 4. Key Contracts & Validation
- **Inputs & Validation:** Enforces strict payload validation, sanitization, and signature verification.
- **Error Mapping & Logs:** Returns explicitly mapped error packets. Logs internal failures via Winston/secure trackers.

---

## 5. Security & Edge Case Handling
- **Security Considerations:** Enforces isolated boundaries, screenshot prevention where applicable, and zero server plaintext.
- **Edge Cases Handled:** - **E14:** Gracefully returns error status packets if users deny geolocator permissions, avoiding crashes.

---

## 6. Implementation Checklist & Phases

### Sub-Task Development Matrix
| Sub-Task | Description | Done |
|---|---|:---:|
| **T.1** | Scaffold schemas, interfaces, and providers. | [ ] |
| **T.2** | Write core controller/handler business logic. | [ ] |
| **T.3** | Implement edge case handlers. | [ ] |
| **T.4** | Add unit and integration test coverages. | [ ] |

### Manual Verification Checklist
- [ ] Press 'Get Location' on Device A and verify Device B wakes, captures GPS in background, and maps coordinates on Device A.
- [ ] Disable GPS permissions on Device B, request location from Device A, and confirm Device A shows a permission error logged in event log.
- [ ] Confirm no location markers or maps are active or rendering in memory when the vault grace timer expires.