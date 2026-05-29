# MultiLingo Project Context & Business Logic Specification

## 1. Product Identity and Core Concept
MultiLingo is a cross-platform mobile application that presents itself as a fully functional, genuine language-learning utility ("Multi Lingo — Learn a new language today"). Beneath this decoy layer is an isolated secure communications vault providing E2EE messaging, a shared notebook, location pings, and duress PIN safeguards.

### The Decoy & Cover Duality
- **The Decoy:** The decoy app is a legitimate language-learning application featuring real-time translation (via a free API), a "Word of the Day", streak tracking, and daily tasks. If a user never sets up the vault, the app remains a pure utility.
- **The Vault:** A highly secure, coercion-resistant messaging vault. It is accessed only via hidden-in-plain-sight triggers inside the decoy app:
  1. **Report Issue Form:** Typing the Vault PIN into the numeric "Error Code" or "Reference Number" field and hitting submit.
  2. **Long Press:** Pressing the cover app's logo/designated element for 3 seconds.
  3. **Enable Premium Features:** Button in cover onboarding/settings used to execute the initial vault setup.

If the vault has not been configured:
- The Report Issue form operates like a standard decoy bug submission.
- The Long Press trigger is disabled.
- No vault indicators, options, or assets are visible in code compilation/rendering that would leak vault existence to casual inspectors.

---

## 2. The 8 Production Security Principles
Every module must strictly respect these 8 fundamental security invariants. No compromise is permitted:

1. **Zero Server Plaintext:** The server stores only ciphertext. No encryption keys are ever written to database logs, environment files, or server records in production.
2. **No Exceptional Access:** There are absolutely no backdoors, recovery mechanisms, or developer master keys in production. If keys are lost, data is lost permanently.
3. **Metadata Minimization:** Timestamps, sender identifiers, and message status tags are nested inside encrypted blocks. The server cannot query who sent what message at what exact second.
4. **PIN-Only Coercion Model:** Biometric authentication is banned. PINs are fast to clear and cannot be forced legally or physically in the same manner. A 3-wrong-attempt policy wipes local vault keys immediately.
5. **Single Device Session:** Accounts are active on only one device at a time. Authenticating a new device immediately terminates and wipes session states on the previous device.
6. **Immutable Message Record:** Message edits and global deletes are banned. Hiding a message is strictly local-only and does not affect the partner's device or server storage.
7. **Admin Governance:** All structural shifts (key rotations, member revocations, restorations) require explicit approval from the conversation creator (Admin), or must pass through the inactivity escape valve.
8. **Cover App Integrity:** The decoy app must remain fully operational, updated, and legitimate.

---

## 3. The 16 Critical Edge Cases (E1–E16)
These scenarios dictate critical paths in code execution:

| ID | Scenario | Architecture Resolution |
|---|---|---|
| **E1** | Invitation not accepted | Pending status expires in 24 hours. Creator can cancel pending invites, which purges all server database tracks. |
| ****E2**** | Creator cancels invite | Server immediately purges the Conversation ID from database history. |
| **E3** | Both users lose vault | The conversation admin must execute restoration first. The non-admin is blocked until admin restores. |
| **E4** | Recovery phrase login | Server returns decrypted Conversation ID lists, allowing the client to execute restoration requests individually. |
| **E5** | Admin permanently unavailable | Inactivity escape valve triggers. If the admin's last-seen threshold exceeds configured days (30–365, default 90), request is auto-approved. |
| **E6** | Key rotation | Admin triggers rotation → room state locks as ROTATING. Re-encryption executes, admin gets the new key, and the partner is prompted on open. |
| **E7** | Duress PIN = Vault PIN | Blocked during the 8-screen onboarding. Hash comparison enforces distinct values. |
| **E8** | Duress event | Empty shell opens. Disguised push notification is broadcast to all active conversation partners, logging the event in notification tabs. |
| **E9** | Phone call interruption | Triggers background cycle. Grace period applies immediately, regardless of user settings. |
| **E10** | Admin self-restoration | Auto-approved immediately. The admin must still input correct Vault PIN and Conversation Key on client. |
| **E11** | Wrong key 3x after rotation | Conversation is locally wiped on the partner's device. Standard restoration request flow must be followed. |
| **E12** | Simultaneous loss | Admin restores first (auto-approved), then admin approves partner's request. |
| **E13** | Session hijack attempt | New session handshake immediately revokes old session, logging device details. Old device resets to decoy layout on next interaction. |
| **E14** | Location ping permission denied | Graceful error handling. Target client responds with error status; failure logs inside the conversation's notification tab. |
| **E15** | Note edit lock timeout | System autosaves changes, releases lock, and exits edit mode on inactivity (default 30s). |
| **E16** | Restore during edit | Restoration of note version blocked while another user holds the active edit lock. |

---

## 4. Super Key Dev Workflow
To facilitate debugging during active development, a "Developer Super Key" workflow is established:
- **Feature Flag:** Exists behind the `SUPER_KEY_ENABLED` flag. Evaluates strictly to `false` in production.
- **Shadow Records:** When enabled, the server performs a shadow-write of all generated credentials (e.g. PIN hashes, recovery phrases, conversation keys) to a dedicated `dev_shadow` collection, encrypted with an AES-256-GCM key derived from the developer environment.
- **Removal Audit:** The CI pipeline runs a strict regex/grep scan. If any traces of `dev_shadow`, `superKey`, or shadow endpoints are found in the final production branch code, compilation FAILS. Code must be physically deleted, not just deactivated.

---

## 5. Admin Governance Model
The conversation creator holds permanent Admin status.
- Admin controls: Key changes, member revocation, see-deleted mode, version restores, and time parameters.
- If admin has not logged into MultiLingo for a set duration, the "Admin Inactivity Escape Valve" automatically bypasses approval barriers to prevent permanent lockouts.
