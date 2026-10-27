# Requirements

VERA is a separate client for financial control, accounting and settlement. It must use EP APIs for accepted data and current authorization, with no local business database. Books and their nesting are financial contexts using the same underlying tables and associations, as specified in ../../finance.md.

The initial foundation provides a public Phlex/Tailwind shell, locally served Turbo and separate application/dependency health checks. It must start independently of EP and coexist with TOM on a different port. Financial functionality requires a subsequent authenticated, scoped EP contract.
