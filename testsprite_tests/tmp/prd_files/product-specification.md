# Product Specification Document

## 1) Product Overview

**Product Name:** Goldenmole Construction Management App  
**Product Type:** Web application (desktop + mobile field mode)  
**Primary Goal:** Centralize daily construction operations, workforce tracking, finance records, maintenance logs, and land project tracking into one operational system.

This product is designed for construction/land development teams that currently rely on manual notes, spreadsheets, and scattered communication. The system provides a single source of truth for operational, payroll, and expense/income decisions.

## 2) Purpose and Problem Statement

### Current Problems
- Daily labor attendance and assignments are hard to track consistently.
- Income/expense records are fragmented and difficult to reconcile.
- Field activities (machine work, sand production, events) are not captured in a structured format.
- Payroll preparation is time-consuming and prone to mistakes.
- Land purchase project status and cost visibility are not always up to date.

### Intended Outcomes
- Faster and more accurate daily data entry.
- Clear operational visibility through dashboard and record lists.
- Reliable payroll and period lock controls.
- Better accountability through admin access control and audit logs.

## 3) Users and Roles

### Super Admin
- Manage admin accounts and permissions.
- Configure global settings and system defaults.
- View full operational and financial records.

### Admin
- Record transactions and daily operations.
- Manage employees, labor records, payroll, and planning tasks.
- Use desktop and mobile field entry modes.

### Field User (Mobile Workflow via Admin session)
- Quickly log operational activities from phone-optimized interface.
- Submit structured daily work inputs with minimal friction.

## 4) Scope

### In Scope (MVP + Current Core)
1. Authentication and role-based admin access.
2. Dashboard with operational and financial visibility.
3. Transaction management (income, expense, leave-linked records).
4. Employee and labor management.
5. Payroll generation and payroll period lock/unlock controls.
6. Daily logs (machine work, sand production, general events).
7. Vehicle and maintenance expense workflows.
8. Land project tracking (purchase/deposit/transfer status).
9. Work planning module (daily/weekly/monthly tasks).
10. Data list/record management for review and corrections.
11. Application settings and master data configuration.

### Out of Scope (for this phase)
- External accounting software integration.
- Public customer/contractor portal.
- Multi-company tenancy in one deployment.

## 5) Functional Requirements

### FR-01: Authentication and Session
- Users must log in with admin credentials.
- First-login password change must be supported when flagged.
- System must support logout and session restore behavior.

### FR-02: Dashboard and Analytics
- Show key summary cards for operations and finance.
- Provide calendar/period-based views for transaction and activity trends.
- Support quick navigation to related modules.

### FR-03: Transaction Capture
- Users must be able to create/update/delete financial transactions.
- Transaction types: `Income`, `Expense`, and leave-related records.
- Records can include category, sub-category, amount, description, linked employee(s), and optional project.

### FR-04: Employee Management
- Maintain employee profile, wage type (daily/monthly), and status.
- Support multi-position assignment and salary history tracking.
- Preserve KPI evaluation history when used.

### FR-05: Labor Operations
- Record attendance with full-day/half-day option.
- Capture overtime, advances, special adjustments, and leave reasons.
- Support assignment grouping for work crews.

### FR-06: Payroll
- Generate payroll snapshots per period.
- Store base pay, OT, allowances, adjustments, deductions, and net pay.
- Implement payroll period lock to prevent accidental edits.
- Allow controlled unlock/relock action with admin trace.

### FR-07: Daily Logs
- Machine work log: machine, hours, work type, and trip data.
- Sand production log: morning/afternoon quantities and totals.
- General event log: event category/priority/time with notes.

### FR-08: Vehicle and Maintenance
- Record vehicle-related expenses and operation details.
- Capture maintenance entries by maintenance type.
- Link costs to date and descriptive context for auditability.

### FR-09: Land Project Management
- Manage land projects with seller, deed, area, payment values, and status.
- Track lifecycle status: `Deposit`, `PaidFull`, `Transferred`.
- Allow notes/details per project for due diligence and handover context.

### FR-10: Planning
- Create plans by scope (`Daily`, `Weekly`, `Monthly`).
- Track status (`Todo`, `Done`) and lane/work type.
- Keep carry-over history for incomplete plans.

### FR-11: Settings and Master Data
- Configure organization profile, app branding, and operational defaults.
- Manage configurable lists (cars, job descriptions, categories, locations, etc.).
- Manage fuel opening stock defaults and other app defaults.

### FR-12: Administration and Audit
- Super Admin can manage admin users.
- System logs key admin actions for accountability.
- Role-based access should restrict sensitive operations.

## 6) Non-Functional Requirements

- **Usability:** Data entry should be possible within 2-3 taps/clicks for common field operations.
- **Performance:** Standard module navigation and record load should feel near-instant for normal dataset sizes.
- **Reliability:** Saved records must persist and remain recoverable after refresh.
- **Security:** Admin credentials and role checks required for all protected actions.
- **Responsiveness:** UI must support both desktop operation and mobile field workflow.
- **Maintainability:** Modular code structure so each domain (payroll, labor, land, logs) can evolve independently.

## 7) End-to-End Workflow (How It Should Work)

1. Admin logs in and selects desktop or mobile working surface.
2. During operations, user records:
   - labor attendance and work details,
   - machine/sand/event logs,
   - expenses/income.
3. Dashboard updates to reflect the latest entries.
4. Back-office admin reviews records in list/manager screens.
5. Payroll is computed at period end and locked after approval.
6. Managers use planning and land modules for forward planning and project status tracking.
7. Super Admin monitors settings, user access, and admin logs.

## 8) Success Metrics

- 100% of daily labor attendance captured in-app.
- Payroll preparation time reduced by at least 50%.
- Month-end financial reconciliation completed from system records without spreadsheet backfill.
- Reduced data correction incidents after payroll lock.

## 9) Risks and Mitigations

- **Risk:** Incomplete field data entry.  
  **Mitigation:** Mobile-first quick entry flows and required key fields.

- **Risk:** Incorrect payroll edits after approval.  
  **Mitigation:** Payroll period lock with controlled unlock trail.

- **Risk:** Inconsistent master data (categories, job labels).  
  **Mitigation:** Centralized settings and limited edit permissions.

## 10) Acceptance Criteria

1. Admin can log in, create records across all core modules, and retrieve them after refresh.
2. Dashboard reflects newly created operational and financial data.
3. Payroll can be generated for a period and locked from modification.
4. Land project records can be created and moved through defined statuses.
5. Super Admin can manage admin accounts and view admin logs.
6. Mobile workflow allows practical daily usage in field conditions.

## 11) Future Enhancements (Post-MVP)

- Export packs for accounting and management reporting.
- Notification/reminder system for payroll and planning deadlines.
- Media/file attachments for evidence records.
- Integration with external finance/ERP systems.

