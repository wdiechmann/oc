# UI

The public home page introduces VERA and links to **Sign in** at /session/new. Use the same email as the existing identity managed in TOM; there is no VERA signup, invitation or recovery UI. **Open TOM** links to the configured TOM origin for those tasks.

Request a link, open its VERA URL and press **Continue to VERA**. In development the link is in VERA's private tmp/outbox file. GET alone does not redeem it. A generic notice covers unknown/throttled addresses. EP/delivery failures render inline, preserving the email form; tokens never appear in the rendered page.

After sign-in, the home page lists only the current tenants/occasions returned by EP, or explains that no authorized workspaces are available. These are navigation contexts; no financial authority or book functionality is implied yet. **Sign out** clears VERA and revokes its EP session independently from TOM. If EP cannot confirm revocation, show that fact rather than claim global logout.

Desktop/mobile pages use Phlex/Tailwind, local Turbo, keyboard/touch form controls and status text. Tenant-book UI follows the next package in ../../system_2_plan.md.
