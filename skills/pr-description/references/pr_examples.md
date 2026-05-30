# PR Description Examples and Best Practices

This document provides examples and guidelines for generating effective pull request descriptions.

## Key Principles

1. **Clarity**: Make it easy for reviewers to understand what changed and why
2. **Context**: Provide enough background for reviewers unfamiliar with the task
3. **Completeness**: Cover what was done, why it was done, and potential risks
4. **Reviewability**: Help reviewers know what to focus on

## Structure Template

### Why I'm Doing This
- Business context or user problem being solved
- Technical motivation (performance, maintainability, security, etc.)
- Related issues, tickets, or discussions
- Background that helps reviewers understand the necessity

### What I'm Doing
- High-level summary of the changes
- Key technical decisions and trade-offs
- Major components or files modified
- New features, optimizations, or fixes implemented
- Breaking changes or deprecations (if any)
- Risks, limitations, or follow-up work needed

## Example 1: Feature Implementation

### Why I'm Doing This
Users have been requesting the ability to export their data in CSV format. Currently, we only support JSON export, which is not convenient for non-technical users who want to analyze data in Excel. This feature was prioritized in Q4 planning and has 150+ upvotes in our feedback portal.

### What I'm Doing
- Added CSV export functionality to the data export service
- Implemented streaming export for large datasets to prevent memory issues
- Added format selection dropdown in the export UI
- Updated export API to accept `format` parameter (json/csv)

**Technical Details:**
- Used `csv-stringify` library for CSV generation
- Implemented chunked streaming for datasets >10k rows
- Added comprehensive test coverage for both small and large exports

**Risks:**
- CSV format loses some nested data structure (documented in user-facing help text)
- Large exports may take longer due to streaming approach (acceptable trade-off for memory safety)

## Example 2: Performance Optimization

### Why I'm Doing This
The dashboard page has been loading slowly for users with large datasets (>50k records). Monitoring shows the main bottleneck is the inefficient database query that loads all records before filtering. This affects ~15% of our enterprise customers.

### What I'm Doing
- Optimized the dashboard query to use database-level filtering and pagination
- Added database index on `user_id` and `created_at` columns
- Implemented result caching with 5-minute TTL for frequently accessed data

**Performance Impact:**
- Load time reduced from 8.5s to 1.2s for large datasets
- Database query time reduced from 6s to 0.3s
- Memory usage reduced by 70% for large result sets

**Risks:**
- Cache invalidation may cause stale data for up to 5 minutes (acceptable per product requirements)
- New database migration required for index creation

## Example 3: Bug Fix

### Why I'm Doing This
Users reported that the login form crashes when entering certain special characters in the password field. This is a regression introduced in v2.3.0 when we updated the validation library. Affects users with passwords containing non-ASCII characters.

### What I'm Doing
- Fixed input sanitization to properly handle Unicode characters
- Reverted to previous validation approach for password fields
- Added regression tests for Unicode and special character inputs
- Updated validation library to v3.2.1 which includes the fix upstream

**Root Cause:**
The validation library v3.0.0 introduced stricter regex that incorrectly rejected valid Unicode characters.

**Testing:**
- Verified fix with test cases covering emoji, CJK characters, and various special characters
- Confirmed no other input fields are affected

## Example 4: Refactoring

### Why I'm Doing This
The authentication module has grown to 1500+ lines with multiple responsibilities, making it hard to test and maintain. Recent bugs and feature requests have been slowed down by this complexity. This refactoring sets the foundation for upcoming SSO integration work.

### What I'm Doing
- Split `auth.ts` into separate modules: `login.ts`, `session.ts`, `permissions.ts`
- Extracted shared utilities to `auth-utils.ts`
- Improved type safety with stricter TypeScript types
- Added unit tests for previously untested edge cases

**No Functional Changes:**
This is a pure refactoring with no behavior changes. All existing tests pass unchanged.

**Review Focus:**
- Logic correctness in the module splitting
- Test coverage for edge cases

## Things to Avoid

- ❌ Vague descriptions: "Fixed bug" or "Updated code"
- ❌ Only describing implementation without context
- ❌ Missing risk assessment
- ❌ Assuming reviewers have full context
- ❌ Wall of text without structure
- ❌ Skipping "why" and only covering "what"