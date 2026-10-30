# UI

The public home page introduces VERA and links to **Sign in** at /session/new. Use the same email as the existing identity managed in TOM; there is no VERA signup, invitation or recovery UI. **Open TOM** links to the configured TOM origin for those tasks.

Request a link, open its VERA URL and press **Continue to VERA**. In development the link is in VERA's private tmp/outbox file. GET alone does not redeem it. A generic notice covers unknown/throttled addresses. EP/delivery failures render inline, preserving the email form; tokens never appear in the rendered page.

After sign-in, the home page lists only the current tenants/occasions returned by EP, or explains that no authorized workspaces are available. These are navigation contexts; financial commands still require current explicit authority. **Sign out** clears VERA and revokes its EP session independently from TOM. If EP cannot confirm revocation, show that fact rather than claim global logout.

Desktop/mobile pages use Phlex/Tailwind, local Turbo, keyboard/touch form controls and status text. Book setup follows the current package in ../../system_2_plan.md.

A newly issued VERA challenge invalidates earlier VERA links; TOM links are backend-bound and cannot confirm a VERA session. Open the complete URL from the newest VERA message. Challenge rejection now explains replacement/use/expiry separately from an expired authenticated session and clears the rejected pending challenge. Requesting a replacement clears old confirmation state.

## Tenant books

After sign-in, **Open books** appears on each tenant-administrator card. The book registry identifies the tenant, displays roots/children with their parent and depth, and reports source/latest accepted revisions. **Create book** opens name/code, initial supported currency, accounting authority, timezone, financial-year start and optional parent fields. All books start Draft. Neither selecting External nor creating a parent starts an adapter or consolidation calculation.

Open a book to view its fixed initial setup and edit its name/parent. Codes and currency/authority/calendar are fixed in this slice. EP rejects unavailable/foreign parents, cycles and stale revisions. Inline feedback preserves the submitted form; a known conflict requires review/refresh. If a save response is lost, use **Check completion** before another submission. If the projection is pending, refresh and wait for the accepted revision before editing. If serving is stopped or access revoked, the protected view is unavailable rather than stale-successful.

Book hierarchy is context nesting. Accounting periods, extended CoA rules/imports, full finance-role delegation, live cross-user subscriptions and monetary functionality follow later; a book named SL2030 is not automatically associated with the SL2030 occasion.

## Roles, occasions and accounts

Open a tenant book and choose **Roles, occasions and accounts**. Tenant administrators can inspect its chart and explicitly assign/revoke configuration stewards, including themselves. The initial identity selector lists active existing tenant/occasion administrators and current stewards; the API also accepts a known existing verified identity UUID. No identity/invitation workflow is added. A steward sees a direct **Configure book** workspace card without gaining tenant-wide book administration.

Within that book, stewards link/unlink occasions and add/edit account number, name, posting/heading/total kind and active status. Account rows show accepted values and actor/application/revision underneath the form. Standard Tab/Enter controls, Cancel and account search are available. Totals are labels only; no accounting period, formula or journal is activated. A book name does not establish an occasion association.

Pending views disable editing until refresh catches up. Conflicts preserve the submitted draft above the newer accepted row and offer **Reapply draft** with current versions. A lost response offers **Check completion**, blocks new changes and never infers failure from a missing receipt. After an unknown receipt, **Retry original request** explicitly sends the unchanged original body/key, safely deduplicated by EP. Stopped views/revoked access replace the protected region. Drafts are not autosaved across navigation.
