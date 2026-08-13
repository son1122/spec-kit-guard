# Feature Specification: Demo

## User Scenarios & Testing

### User Story 1 - Sign in (Priority: P1)

**Acceptance Scenarios**:

1. **Given** a registered user, **When** they submit valid credentials, **Then** a session starts.
2. **Given** a wrong password, **When** they submit, **Then** the attempt is refused.

### User Story 2 - Sign out (Priority: P2)

**Acceptance Scenarios**:

1. **Given** an active session, **When** they sign out, **Then** the session ends.

## Requirements

### Functional Requirements

- **FR-001**: System MUST authenticate users.
- **FR-002**: System MUST refuse invalid credentials.
- **FR-002a**: System MUST rate-limit repeated failures.
- **FR-003**: System MUST end sessions on sign out.
