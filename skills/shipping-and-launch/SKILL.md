---
name: shipping-and-launch
description: Prepares production launches. Use when preparing to deploy to production. Use when you need a pre-launch checklist, when setting up monitoring, when planning a staged rollout, or when you need a rollback strategy.
license: MIT
metadata:
  author: https://github.com/mindsandco
  version: "1.0.0"
  domain: process
  triggers: ship, launch, deploy, deployment, release, rollback, feature flag, canary, staged rollout, production, go-live, pre-launch checklist
  role: specialist
  scope: deployment
  output-format: report
  related-skills: incremental-implementation, debugging-and-error-recovery, code-reviewer, git-workflow-and-versioning
---

# Shipping and Launch

## Overview

Ship with confidence. The goal is not just to deploy — it's to deploy safely, with monitoring in place, a rollback plan ready, and a clear understanding of what success looks like. Every launch should be reversible, observable, and incremental.

## When to Use

- Deploying a feature to production for the first time
- Releasing a significant change to users
- Migrating data or infrastructure
- Opening a beta or early access program
- Any deployment that carries risk (all of them)

## The Pre-Launch Checklist

### Code Quality

- [ ] All tests pass (unit, integration, e2e)
- [ ] Build succeeds with no warnings
- [ ] Lint and type checking pass
- [ ] Code reviewed and approved
- [ ] No TODO comments that should be resolved before launch
- [ ] No `console.log` debugging statements in production code
- [ ] Error handling covers expected failure modes

### Security

- [ ] No secrets in code or version control
- [ ] `npm audit` shows no critical or high vulnerabilities
- [ ] Input validation on all user-facing endpoints
- [ ] Authentication and authorization checks in place
- [ ] Security headers configured (CSP, HSTS, etc.)
- [ ] Rate limiting on authentication endpoints
- [ ] CORS configured to specific origins (not wildcard)

### Performance

- [ ] Core Web Vitals within "Good" thresholds
- [ ] No N+1 queries in critical paths
- [ ] Images optimized (compression, responsive sizes, lazy loading)
- [ ] Bundle size within budget
- [ ] Database queries have appropriate indexes
- [ ] Caching configured for static assets and repeated queries

### Accessibility

- [ ] Keyboard navigation works for all interactive elements
- [ ] Screen reader can convey page content and structure
- [ ] Color contrast meets WCAG 2.1 AA (4.5:1 for text)
- [ ] Focus management correct for modals and dynamic content
- [ ] Error messages are descriptive and associated with form fields
- [ ] No accessibility warnings in axe-core or Lighthouse

### Infrastructure

- [ ] Environment variables set in production
- [ ] Database migrations applied (or ready to apply)
- [ ] DNS and SSL configured
- [ ] CDN configured for static assets
- [ ] Logging and error reporting configured
- [ ] Health check endpoint exists and responds

### Documentation

- [ ] README updated with any new setup requirements
- [ ] API documentation current
- [ ] ADRs written for any architectural decisions
- [ ] Changelog updated
- [ ] User-facing documentation updated (if applicable)

## Feature Flag Strategy

Ship behind feature flags to decouple deployment from release:

```typescript
// Feature flag check
const flags = await getFeatureFlags(userId);

if (flags.taskSharing) {
  // New feature: task sharing
  return <TaskSharingPanel task={task} />;
}

// Default: existing behavior
return null;
```

**Feature flag lifecycle:**

```
1. DEPLOY with flag OFF     → Code is in production but inactive
2. ENABLE for team/beta     → Internal testing in production environment
3. GRADUAL ROLLOUT          → 5% → 25% → 50% → 100% of users
4. MONITOR at each stage    → Watch error rates, performance, user feedback
5. CLEAN UP                 → Remove flag and dead code path after full rollout
```

**Rules:**
- Every feature flag has an owner and an expiration date
- Clean up flags within 2 weeks of full rollout
- Don't nest feature flags (creates exponential combinations)
- Test both flag states (on and off) in CI

## Staged Rollout

### The Rollout Sequence

```
1. DEPLOY to staging
   └── Full test suite in staging environment
   └── Manual smoke test of critical flows

2. DEPLOY to production (feature flag OFF)
   └── Verify deployment succeeded (health check)
   └── Check error monitoring (no new errors)

3. ENABLE for team (flag ON for internal users)
   └── Team uses the feature in production
   └── 24-hour monitoring window

4. CANARY rollout (flag ON for 5% of users)
   └── Monitor error rates, latency, user behavior
   └── Compare metrics: canary vs. baseline
   └── 24-48 hour monitoring window
   └── Advance only if all thresholds pass (see table below)

5. GRADUAL increase (25% -> 50% -> 100%)
   └── Same monitoring at each step
   └── Ability to roll back to previous percentage at any point

6. FULL rollout (flag ON for all users)
   └── Monitor for 1 week
   └── Clean up feature flag
```

### Rollout Decision Thresholds

Use these thresholds to decide whether to advance, hold, or roll back at each stage:

| Metric | Advance (green) | Hold and investigate (yellow) | Roll back (red) |
|--------|-----------------|-------------------------------|-----------------|
| Error rate | Within 10% of baseline | 10-100% above baseline | >2x baseline |
| P95 latency | Within 20% of baseline | 20-50% above baseline | >50% above baseline |
| Client JS errors | No new error types | New errors at <0.1% of sessions | New errors at >0.1% of sessions |
| Business metrics | Neutral or positive | Decline <5% (may be noise) | Decline >5% |

### When to Roll Back

Roll back immediately if:
- Error rate increases by more than 2x baseline
- P95 latency increases by more than 50%
- User-reported issues spike
- Data integrity issues detected
- Security vulnerability discovered

## Monitoring and Observability

### What to Monitor

```
Application metrics:
├── Error rate (total and by endpoint)
├── Response time (p50, p95, p99)
├── Request volume
├── Active users
└── Key business metrics (conversion, engagement)

Infrastructure metrics:
├── CPU and memory utilization
├── Database connection pool usage
├── Disk space
├── Network latency
└── Queue depth (if applicable)

Client metrics:
├── Core Web Vitals (LCP, INP, CLS)
├── JavaScript errors
├── API error rates from client perspective
└── Page load time
```

### Error Reporting

```typescript
// Set up error boundary with reporting
class ErrorBoundary extends React.Component {
  componentDidCatch(error: Error, info: React.ErrorInfo) {
    // Report to error tracking service
    reportError(error, {
      componentStack: info.componentStack,
      userId: getCurrentUser()?.id,
      page: window.location.pathname,
    });
  }

  render() {
    if (this.state.hasError) {
      return <ErrorFallback onRetry={() => this.setState({ hasError: false })} />;
    }
    return this.props.children;
  }
}

// Server-side error reporting
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  reportError(err, {
    method: req.method,
    url: req.url,
    userId: req.user?.id,
  });

  // Don't expose internals to users
  res.status(500).json({
    error: { code: 'INTERNAL_ERROR', message: 'Something went wrong' },
  });
});
```

### Post-Launch Verification

In the first hour after launch:

```
1. Check health endpoint returns 200
2. Check error monitoring dashboard (no new error types)
3. Check latency dashboard (no regression)
4. Test the critical user flow manually
5. Verify logs are flowing and readable
6. Confirm rollback mechanism works (dry run if possible)
```

## Rollback Strategy

Every deployment needs a rollback plan before it happens:

```markdown
## Rollback Plan for [Feature/Release]

### Trigger Conditions
- Error rate > 2x baseline
- P95 latency > [X]ms
- User reports of [specific issue]

### Rollback Steps
1. Disable feature flag (if applicable)
   OR
1. Deploy previous version: `git revert <commit> && git push`
2. Verify rollback: health check, error monitoring
3. Communicate: notify team of rollback

### Database Considerations
- Migration [X] has a rollback: `npx prisma migrate rollback`
- Data inserted by new feature: [preserved / cleaned up]

### Time to Rollback
- Feature flag: < 1 minute
- Redeploy previous version: < 5 minutes
- Database rollback: < 15 minutes
```
## See Also

- For security pre-launch checks, see `references/security-checklist.md`
- For performance pre-launch checklist, see `references/performance-checklist.md`
- For accessibility verification before launch, see `references/accessibility-checklist.md`

## Stack-specific notes (.NET Core + React)

The pre-launch checklist is stack-agnostic. Here are the concrete commands, signals, and risk areas for each side of a full-stack release.

### .NET Core (backend services)

**Pre-launch:**

- `dotnet build -c Release` must be clean. `TreatWarningsAsErrors=true` means every analyzer hit blocks the build.
- `dotnet test` (xUnit v3 + MTP) — unit + integration. Integration tests must run against a real PostgreSQL container (see `testcontainers-dotnet`).
- `dotnet list package --vulnerable --include-transitive` — fail the launch on any **high** / **critical** CVE. NuGet audit is enabled in `Directory.Build.props` via `<NuGetAudit>true</NuGetAudit>` so the build also flags vulnerable packages.
- DbUp migrations: confirm the latest numbered `.sql` in the `Db` project is idempotent and has been smoke-tested on a copy of production data. There is no rollback button — write a follow-up SQL migration if you need to undo.
- Container image: rebuild from `mcr.microsoft.com/dotnet/aspnet:10.0` and push to ACR (`aipsim.azurecr.io` or equivalent). Verify the image runs locally before deploying.
- Health checks: `/health/live` and `/health/ready` return 200 (Dapr sidecar + Npgsql probes).
- Configuration: confirm Dapr secret store keys exist in the target environment; UserSecrets do not deploy.

**Rollback:**

- Container image: redeploy the previous tag.
- Database: write a new numbered `.sql` that reverses the change. **Do not edit committed migrations.** If the new column is `NOT NULL` and the rollback drops it, write `038 - Revert add of Foo.sql`.
- Feature flag: prefer a Dapr-config-store-backed flag so toggling is sub-minute.

**Post-launch monitoring:**

- Structured logs from `Asset.Insights.Portal.AspNetCore.Logging` (or your equivalent) — watch for `LogLevel.Error` spikes.
- Dapr sidecar logs — pub/sub backlog, secret-store failures.
- Npgsql connection pool saturation (`pg_stat_activity`, `pg_stat_database`).
- HotChocolate diagnostics — slow queries, validation errors.

Pair with: `dotnet-core-expert`, `dotnet-code-analyzer`, `testcontainers-dotnet`.

### React + Vite (frontend SPA)

**Pre-launch:**

- `pnpm lint && pnpm test && pnpm build` — all clean. Vite production build emits a `dist/` you ship.
- `pnpm audit --audit-level=high` — no high or critical advisories. `npm audit` works the same way if you use npm.
- Bundle analysis: `pnpm vite build --mode production && pnpm dlx vite-bundle-visualizer` — verify chunk sizes against the budget (don't ship a regression you didn't review).
- Core Web Vitals: run Lighthouse against the staging URL; LCP / INP / CLS in the "Good" band.
- Accessibility: `pnpm dlx axe-core` or Lighthouse a11y; keyboard nav verified manually on the primary flow.
- Smoke test in the real browser via Chrome DevTools MCP — console clean, no failed network calls.

**Rollback:**

- Static asset hosts (Cloudfront / Azure Static Web Apps / S3 + CDN) — redeploy the previous build artifact. Keep at least the last 3 builds retained.
- Feature flag for the new route or component — fastest path to disable a single feature without redeploying.

**Post-launch monitoring:**

- Client error reporting (Sentry, Rollbar, App Insights JS SDK) — watch for new error fingerprints.
- Real User Monitoring (RUM) — LCP / INP / CLS at the p75.
- API error rate from the client's perspective (4xx / 5xx via `fetch` interceptor).
- Vite's source maps must be deployed alongside the bundle so stack traces resolve.

Pair with: `react-vite-guide`, `antd`.

### Full-stack release coordination

- Ship backend **before** frontend when the frontend depends on a new API field. Backwards-compatible additions only.
- Add the new GraphQL field / REST endpoint behind an `@deprecated` annotation on the **old** field; remove only after the frontend has rolled out to 100%.
- Run the canary on both tiers simultaneously — staged rollout makes no sense if the backend is at 100% but the frontend isn't yet seeing the new shape.
- Database migrations apply before code rollout: zero-downtime requires the old code to keep working against the new schema.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "It works in staging, it'll work in production" | Production has different data, traffic patterns, and edge cases. Monitor after deploy. |
| "We don't need feature flags for this" | Every feature benefits from a kill switch. Even "simple" changes can break things. |
| "Monitoring is overhead" | Not having monitoring means you discover problems from user complaints instead of dashboards. |
| "We'll add monitoring later" | Add it before launch. You can't debug what you can't see. |
| "Rolling back is admitting failure" | Rolling back is responsible engineering. Shipping a broken feature is the failure. |

## Red Flags

- Deploying without a rollback plan
- No monitoring or error reporting in production
- Big-bang releases (everything at once, no staging)
- Feature flags with no expiration or owner
- No one monitoring the deploy for the first hour
- Production environment configuration done by memory, not code
- "It's Friday afternoon, let's ship it"

## Verification

Before deploying:

- [ ] Pre-launch checklist completed (all sections green)
- [ ] Feature flag configured (if applicable)
- [ ] Rollback plan documented
- [ ] Monitoring dashboards set up
- [ ] Team notified of deployment

After deploying:

- [ ] Health check returns 200
- [ ] Error rate is normal
- [ ] Latency is normal
- [ ] Critical user flow works
- [ ] Logs are flowing
- [ ] Rollback tested or verified ready