# WarrantyOS

Warranty governance platform for mid-sized EPC warranty operations in solar/renewables.

## Status

Prototype phase. Building foundation for end-to-end demonstration of core lifecycle workflow.

## Architecture

See `docs/architecture-reference.md` for the platform's architectural specification, including:
- Core operational principles
- The six evaluation gates of claim review
- The three escalation pathways
- The four work plan execution paths
- The platform's lifecycle stages
- Customer-facing communications inventory
- Prototype scope and out-of-scope items

## Tech Stack

- **Frontend:** Next.js 14+ with App Router
- **Styling:** Tailwind CSS with shadcn/ui components
- **Database:** PostgreSQL via Supabase with Row-Level Security
- **Authentication:** Supabase Auth
- **File Storage:** Supabase Storage
- **Email:** Resend
- **Hosting:** Vercel
- **Version Control:** Git with GitHub
- **AI Assistance:** Claude Code

## Development Approach

This project is being built solo during the prototype phase, with the intent to bring on a technical co-founder or engineering team after the prototype validates with early customers.

The prototype demonstrates the core lifecycle workflow end-to-end through Path 1 (Warrantor Self-Performs). Additional execution paths and supporting subsystems are deferred to post-prototype development.

## Repository Structure

- `/app` — Next.js application code (created during initial setup)
- `/components` — Reusable UI components
- `/lib` — Utility functions and shared logic
- `/types` — TypeScript type definitions
- `/docs` — Architectural documentation and specifications
- `/notes` — Working notes, decisions, and project history

## Getting Started

This project is in active development. Local setup requires Node.js, Git, and a Supabase account.

See `notes/` for current development context and decisions.