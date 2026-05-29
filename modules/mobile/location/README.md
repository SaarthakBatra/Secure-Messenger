# Module: Mobile GPS Capture & Map UI

## Overview
This directory houses the isolated codebases for `Mobile GPS Capture & Map UI`, operating within `Phase 7` development.

## Getting Started
To invoke or perform updates on this module, spawn an isolated Antigravity workspace targeting this folder and load `.agent/prompts/modules/mobile-location-agent.md`.

## Key Actions & Triggers
- **Location Hub Overlay:** Renders interactive map pins and shows historical coordinates with timestamps.
- **Background Geolocator Service:** Wakes GPS components discreetly on request alerts.

## Configuration & Environment Variables
- `SUPER_KEY_ENABLED` - Dev-only shadow write authorization (evaluate strictly false in production).
- Configuration variables are declared in local env profiles.

## Developer Verification Commands
- **Backend tests:** `npm run test -- modules/mobile/location` (or targeted Jest suites)
- **Mobile tests:** `flutter test modules/mobile/location`