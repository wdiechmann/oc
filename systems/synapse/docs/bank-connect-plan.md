# Bank Connect implementation plan

Prepared 2026-11-10 from the local `bank-connect-developer_package-v3-8` package.

## Scope and evidence

Implement Bank Connect in Synapse as an agreement-scoped SOAP integration with certificate activation and renewal, payment submission, asynchronous payment status collection, and account reporting. Build certificate handling and authenticated retrieval first, then enable outbound payments after duplicate prevention and recovery have been demonstrated.

This plan is an extraction of the supplied package, not a statement that its service addresses, bank capabilities, certificates, or operational limits have been verified against the live service. No bank was contacted and no payment was submitted. Requirements below cite the source register by document ID. Proposed architecture, delivery order, retry safeguards, and operational defaults are implementation decisions rather than promises made by Bank Connect.

All 25 DOCX documents and the differences PDF were reviewed individually. Word tables were extracted with their row/cell relationships, since cardinalities, alternatives, and bank-specific remarks carry requirements. WSDL, schemas, example XML, archive contents, and selected sample source were checked for implementation implications. This is not an exhaustive audit of the sample code or every archived fixture. Synapse currently contains this documentation package; no application stack or existing integration framework is assumed here.


## 1. Findings from each document

Paths in this register are relative to [the developer package](bank-connect-developer_package-v3-8/). Each entry records the information to carry into implementation, rather than reproducing the complete field catalogue.

| ID | Document | Extracted requirements and planning consequences |
| --- | --- | --- |
| D01 | `ContentDeveloperPackage.docx` | Package navigation: documentation, Java/.NET examples, security resources, WSDL/XSD, XML fixtures, and XSL viewers. Use the contract and examples as interoperability evidence; the examples are not a maintained application foundation. |
| D02 | `docs/Bank Connect Term description.docx` | Agreement ID, Bank Connect ID, and Function ID identify the same technical `functionIdentification`. An Exchange Agreement is a different business entity. Model company → bank/customer → Exchange Agreement → Agreement IDs/mailboxes and certificate association. Different ERP installations can require separate Exchange Agreements. Preserve identifiers as strings with leading zeroes; typical lengths vary by centre (Bankdata 13, BEC 11, SDC 26), so do not enforce one universal length. Activation and renewal are minimum ERP capabilities. |
| D03 | `docs/Bankconnect-API.docx` | Defines nine operations, header/body structures, certificate flows, security matrix, queue retrieval, technical receipts, SOAP faults, limits, and reordering. `transferPayments` produces a technical receipt; `getStatus` supplies later pain.002 business reports. Empty retrieval is normal. Drain using `severalMessages`. Persist request IDs for reordering. Main requirements appear in sections 2–8 below. |
| D04 | `docs/Certificate-policy.docx` | X.509 v3, RSA-2048 customer/bank keys, RSA/SHA-256 certificate signatures, password-protected customer keystore. Customer certificates are specific to a financial institution; bank certificates may cover a whole centre. Separate test and production trust chains. Customer validity is up to three years; read actual dates because centres may shorten it. Bank validity is three or five years. Trust all participating Bank Connect CAs within the correct environment, validate chains and critical extensions. There is no public CRL; revocation/reissue is coordinated through the bank/RA. |
| D05 | `docs/Programming-Guide.docx` | SOAP with camelCase names, UTF-8, documented TLS 1.2, 180-second server timeout, gzip and size constraints. Fetch/cache bank certificates automatically, e.g. once daily per primary registration number. Start with `getBankCertificate`, then obtain a system-test customer and activation code from support. Use XSL viewers only as development aids. End-to-end technical IDs must be at most 35 characters; UUIDs without dashes are suggested. |
| D06 | `docs/Step by step guides/Customer certificate - ActivateServiceAgreement.docx` | Generate keypair locally; CSR CN is `functionIdentification@activationCode`. Remove activation-code dashes before use; base64-encode the code and DER CSR, without PEM framing or line breaks. Encrypt the SOAP body with the bank certificate. Parse all certificates returned, find the customer leaf matching the generated public key, and attach it to the stored private key. Test uses DK/8079 and Bankdata/Sydbank; its Function ID includes bank/customer/user components, not merely the customer number from SMS. Verify the response signature in code. |
| D07 | `docs/Step by step guides/RenewCertificate.docx` | Generate a new keypair and CSR; CN has no activation-code suffix. Business-sign the certificate request and sign header/body with the old customer key; encrypt using the bank certificate. BEC signs the plaintext body before encryption, whereas Bankdata/NBS encrypt before the outer signature. Install the returned certificate against the new keypair. |
| D08 | `docs/Step by step guides/Signature and get operations.docx` | Every business GET must sign both `serviceHeader` and SOAP `Body`, including an empty request body. Decrypt replies with the customer private key. Treat the SoapUI dependency downgrade workaround as historical troubleshooting, not a dependency recommendation. |
| D09 | `docs/Step by step guides/TransferPayment.docx` | Encode the payment XML as base64 in `paymentMessage`; the business signature is a sibling referencing that message, not an arbitrary signature inserted in ISO XML. Bankdata/NBS: business-sign → encrypt body → sign header/body. BEC: business-sign → sign plaintext header/body → encrypt body. Bank certificate refresh must be automatic. |
| D10 | `docs/ISO20022 - Differences in the interpretation.pdf` | Centre-specific policy is necessary. BEC associates certificates with users and has a different security order. NBS may omit account-servicer references, locate OCR references differently, use the first unstructured remittance line as recipient text, and omit pain.002 after a user rejection. BEC may return CPR for NemKonto, aggregate debits, reject non-banking-day execution, and require BIC for foreign payments. Bankdata/NBS may shift execution dates. Error codes/languages and transaction-code detail vary. These are package claims to confirm per target centre, not universal current capabilities. |
| D11 | `docs/Guidelines to payment types.docx` | Provides discriminator combinations for domestic, salary, inpayment forms, SEPA, foreign, and MT101 payments. Payment type is a combination of method, service level, local instrument, category purpose, account scheme, and remittance fields. Bankdata foreign transfer codes are bank-dependent. The document still describes foreign cheques, superseded by the October 2026 guides. See section 5. |
| D12 | `docs/Pain 001, 002 Camt 052, 053, 054/ISO Pain 001.001.03 version 1.3.docx` | Outbound namespace/version is pain.001.001.03. Group, payment-group, and transaction identifiers have distinct roles and uniqueness periods. Enforce schema plus Bank Connect usage rules. Revision 1.3 dated 04.10.2026 requires structured debtor addresses, structured or hybrid creditor addresses, one `Ustrd` of at most 140 characters, and discontinues foreign cheques. See shared validation below. |
| D13 | `docs/Rules for Pain 001 & 002/ISO 20022 rules Pain 001.docx` | R1 forbids simultaneous group/transaction `PmtTpInf`; R5 makes group/transaction `ChrgBr` mutually exclusive; R6 does the same for `UltmtDbtr`; R10 requires creditor account when method is TRF and creditor is absent. Charge-account/intermediary-agent rules refer to unused features and contain copied/inconsistent examples; do not translate those examples literally into validator logic. |
| D14 | `docs/Payment types in ISO format/Danish Account Transfer.docx` | Domestic TRF: normal ONCL, same-day SDCL, urgent service URNS; category SUPP. Danish BBAN representation is registration number plus account number, 14 characters (4+10). Initiating-party identification includes customer ID, with CUST scheme shown. October 2026 address/remittance rules apply. |
| D15 | `docs/Payment types in ISO format/Danish Salary.docx` | Salary uses SALA category; detailed guide documents ONCL, while the discriminator guide also describes same-day/express variants. Employee reference EPNU is shown, but the general pain.001 guide limits EPNU to Bankdata. Enable variants and employee references by confirmed centre capability. Apply the shared October 2026 rules. |
| D16 | `docs/Payment types in ISO format/Foreign Account Transfer.docx` | Ordinary/express/Nationalbank use IN; express and Nationalbank use URGP. Nationalbank transfer code is 99; other foreign codes are bank-specific. Handle SHAR/DEBT/CRED charge choices and instructed/equivalent amounts. Foreign cheques are discontinued in the 04.10.2026 revision. |
| D17 | `docs/Payment types in ISO format/Giro-01 04 15 FI-71 73 75  Bank Connect ISO 20022 format.docx` | Inpayment forms use OCR account scheme, SCOR reference type and form-specific `Ref`: `01/`, `04/<id>`, `15/<id>`, `71/<id>`, `73/`, `75/<id>`. Keep creditor/Giro number separate from payment reference. Transaction-level ultimate debtor is documented only for Giro 01 and FI-73. FI-71 reference length conflicts with D11; resolve before enabling it. |
| D18 | `docs/Payment types in ISO format/NemKonto.docx` | Account scheme distinguishes NKC (CPR, 10 digits), NKV (CVR, 8), NKP (CVR/P, 8/10), NKR (CVR/SE, 8/8), NKS (SE, 8). Compound identifiers use `/`. Treat these as identifier-based destinations, not bank account numbers; protect CPR data. Support varies by centre and needs confirmation. |
| D19 | `docs/Payment types in ISO format/SEPA Credit Transfer.docx` | TRF, service SEPA, local instrument IN, category SUPP; SLEV charges and transfer code 97 are shown. D11 says Bankdata's SEPA code is usually 97 but must be agreed with the bank. Validate destination/account choices and currency against the confirmed SEPA profile; generic BBAN text in the table is insufficient to establish those restrictions. |
| D20 | `docs/Payment types in ISO format/Transfer from account abroad ICM MT-101.docx` | IN for regular/own-account transfers; own-account category INTC. D11 also describes urgent and group variants and requires foreign debtor-agent BIC. The location of INTC conflicts across documents. Support through a separate, bank-approved profile rather than reusing domestic defaults. |
| D21 | `docs/Pain 001, 002 Camt 052, 053, 054/ISO  Pain 002.001.03 version 1.1.docx` | Parse group, payment-group, and transaction statuses and reason information; preserve original message/group/payment identifiers. Support ACTC, ACCP, ACSP, ACSC, ACWC, PART, PDNG, RCVD, RJCT when present. Keep ISO reason codes and narrative text. The table maps `OrgnlEndToEndId` to outgoing `InstrId`, contradicting the field semantics: test real reports and retain both IDs. |
| D22 | `docs/Rules for Pain 001 & 002/ISO 20022 rules Pain 002.docx` | R1–R10 describe parent/child status consistency, RCVD prohibiting child statuses, and NARR requiring additional information. R8/R9 repeat rejected-status behavior despite different titles. Later rules refer to settlement/amendment features outside this integration. Preserve inconsistent incoming reports for diagnosis rather than silently losing status data. |
| D23 | `docs/Pain 001, 002 Camt 052, 053, 054/Pain 002 pending orders.docx` | ACSP with AM14 at payment-group/bulk level can mean insufficient liquidity and automatic execution when funds become available. This is not a terminal rejection or a reason to submit another payment. Morning or post-submission notifications depend on when the order was sent. One account's bulk can wait while another executes. |
| D24 | `docs/Pain 001, 002 Camt 052, 053, 054/ISO  Camt 052 001 02 v 1 1.docx` | camt.052.001.02 account reports can contain multiple reports/accounts, balances, entries and transaction breakdowns. Preserve report identity/sequence, account, period, OPBD/CLBD/OPAV/CLAV balances, DBIT/CRDT direction, dates, reversals, bank codes, references and remittance. API calls this future/intraday data while this guide describes BOOK entries; do not infer accounting finality solely from the operation. |
| D25 | `docs/Pain 001, 002 Camt 052, 053, 054/ISO  Camt 053 001 02  v1 2.docx` | camt.053.001.02 statements provide booked transactions and balances, including multiple accounts, batched entries and underlying transaction details. References can occur at batch or transaction level. Amount detail repeats entry amounts: avoid double counting. `NtryRef` is locally numbered from 1 and is not a global transaction key. Preserve structured DEBI/CRED/PRIM and OCR/RF remittance references. |
| D26 | `docs/Pain 001, 002 Camt 052, 053, 054/ISO  Camt 054 001 02 v 1 2.docx` | camt.054.001.02 debit/credit notifications can contain multiple notifications, entries and batch details. `/OCRN/` identifies OCR credit notifications; preserve SCOR/OCR/RF references and acceptance date/time. The API says this operation is Bankdata-only; enable it by confirmed capability. Do not assume these notifications replace end-of-day statements. |

### Supporting artifacts checked

| Artifact | Consequence |
| --- | --- |
| [CorporateService WSDL](bank-connect-developer_package-v3-8/resources/wsdl/bankconnect.wsdl) | Contains inline schemas and SOAPAction values. Operation is `transferPayments`, body element `transferPayment`, SOAPAction `urn:CorporateService:transferPayment`. Its service address is localhost and must be overridden. Its four retrieval bodies support `reorderEndToEndMessageId`. |
| [Standalone Bank Connect XSD](bank-connect-developer_package-v3-8/resources/wsdl/xsd/bankconnect.xsd) | Older than the inline WSDL for reordering: retrieval requests have empty sequences. Do not generate from one definition and validate against the other. Some XSD signatures are optional even where the security policy requires them. |
| [ISO schemas](bank-connect-developer_package-v3-8/resources/xsd/) | Schemas for pain.001/.002 .001.03 and camt.052/.053/.054 .001.02. These validate syntax, not all Bank Connect business restrictions or the 2026 changes. |
| [Payment XML examples](bank-connect-developer_package-v3-8/docs/XML%20example%20files/) and [resource XML](bank-connect-developer_package-v3-8/resources/xml/) | Examples cover domestic, foreign, SEPA, FI forms, status, pending orders, reporting, and security. Some resource CAMT samples are .001.03, outside the documented .001.02 profile; classify fixtures by actual namespace. |
| `docs/Paytypes XML.zip` | 313 archive members, including workbook, templates, generated scenario XML, and historical change notes. Use selected scenarios as fixture seeds after updating/validating them; do not assume old fixtures comply with 2026 address/remittance rules. |
| [Sample-code notice](bank-connect-developer_package-v3-8/src/hvadErDette.txt) | Explicitly describes legacy Java 1.6/C# examples and the cost of keeping them secure. Use samples for protocol understanding, not dependency or security defaults. |
| `src/dotnet- version/BankConnectClient/SecuredClient/XmlSecurity/OperationPolicy.cs` | Illustrates per-operation security policies, but does not remove the need to enforce response business signatures required by the documentation. |
| [Security resources](bank-connect-developer_package-v3-8/resources/security/) | Includes test material and certificates with historical expiry dates in filenames. Obtain and authenticate deployment trust anchors separately; never ship demo private keys/keystores as customer credentials. |

## 2. Integration boundary and durable data

Proposed components, independent of the eventual Synapse runtime:

- **Agreement configuration:** company/tenant, financial institution, centre, environment, endpoint/contract version, primary registration number, country, Function ID, ERP identity/version, mailbox association, enabled operations/payment profiles, certificate reference and lifecycle state. Use the customer-facing terms from D02. Do not turn typical ID lengths or the test bank's composition into universal rules.
- **Certificate service:** authenticated trust-anchor installation; bank-certificate retrieval/cache; local key generation; activation; renewal; expiry monitoring; protected key access. Certificate association must accommodate BEC user scope as well as other centres' customer scope.
- **SOAP/security adapter:** contract serialization, operation-specific WS-Security/XMLDSIG/XML Encryption, authenticated response handling, faults, timeouts and size accounting.
- **Payment service and durable outbox:** validated immutable payment batches, approval reference, stable business IDs, exact payload/hash, transmission attempts, technical receipts, ambiguous outcomes and reconciliation state.
- **Mailbox poller and durable inbox:** separate polling per agreement and operation; raw protected response/payload storage; signature results; deduplication; `severalMessages` draining; restart/reorder recovery; independent parsing and projection.
- **ISO codecs and reconciliation:** explicit versioned pain.001 builder, pain.002 parser/status reducer, and CAMT parsers mapping references and transactions to Synapse records.

Persist the identifiers separately: SOAP request `endToEndMessageId`, returned corporate-message ID, pain.001 `GrpHdr/MsgId`, `PmtInfId`, transaction `InstrId`/`EndToEndId`, bank correlation ID, statement/report/notification ID, sequence number, and bank transaction references. They have different scopes and must not be collapsed into one generic message ID. Store amounts as decimals with currency, identifiers as strings, and timestamps with sufficient timezone information.

Use transactional outbox/inbox transitions and database uniqueness constraints. Serialize consumers for a given agreement/mailbox operation until bank queue/concurrency semantics are confirmed. Make downstream application of a received document idempotent. Retain raw evidence under restricted access and retention policy; operational logs should contain IDs, hashes, timings and status, with payment/CPR data and activation codes redacted. These are proposed reliability and privacy controls.

## 3. SOAP contract, transport and security

### Contract and headers

Use SOAP 1.1, document/literal XML, UTF-8, Bank Connect namespace `http://bankconnect.dk/schema/2014`, and HTTP content type `text/xml`. Generate or implement serialization from one pinned, confirmed WSDL, including its inline schema. Preserve schema element order and exact case; do not derive wire names from prose headings. [D03, D05]

`activationHeader` is used for bank-certificate retrieval and activation. `serviceHeader` is used for authenticated business operations and renewal. Both carry `organisationIdentification` (`mainRegistrationNumber`, `isoCountryCode`), `functionIdentification`, `erpInformation`, `endToEndMessageId` and `createDateTime`; service header additionally carries `format=ISO20022`. The ERP container exists even when its system/version children are omitted. `technicalAddress` contains optional IP/port/applied-time information and is unsigned because routing may change it. [D03, WSDL]

Technical IDs must be unique in their customer scope and no longer than 35 characters; generate 32-character UUID hex strings and persist before sending. Generate Danish local timestamps using `Europe/Copenhagen` and the actual daylight-saving offset, with synchronized system clocks; do not hardcode GMT+1/+2. [D03, D05]

The package documents these service URLs, which must be confirmed before connecting:

| Environment | Documented service URL |
| --- | --- |
| System test | `https://stest.bankconnect.dk/2019/04/04/services/CorporateService` |
| Production | `https://www.bankconnectservices.dk/2019/04/04/services/CorporateService` |

`?wsdl` retrieves the contract. The bundled WSDL's localhost endpoint is for sample use. TLS 1.2 and a server timeout of 180 seconds are documented; confirm supported transport settings, then configure HTTP client, job leases, proxy timeouts and retry timing coherently. Avoid a shorter hidden gateway timeout. Endpoint version is configuration: the package describes three concurrent versions with retirement periods, which must be checked before implementation. [D03, D05]

### Security policy

Use a maintained XML security implementation. Prove its support for RSA-SHA256 signatures, SHA-256 digests, exclusive XML canonicalization without comments, AES-256-CBC body encryption and RSA-OAEP-MGF1P key transport as shown by the package. Confirm exact algorithm parameters with system-test fixtures. Never substitute algorithms or operation ordering merely because a SOAP library has different defaults. [D03, D06, D08, D09]

| Operation | Request protection | Response protection required by API |
| --- | --- | --- |
| `getBankCertificate` | Unsigned activation header; no encrypted body | Business signature and authenticated bank certificate chain; no body encryption |
| `activateServiceAgreement` | Encrypted body; CSR proof-of-possession signature; unsigned activation header | Business signature; certificate content is not body-encrypted |
| `renewCustomerCertificate` | Business signature, body encryption, signed service header and body with current customer key | Encrypted reply, outer signature, business signature; decrypt with current/old customer key |
| `transferPayments` | Business signature over `paymentMessage`, body encryption, signed service header and body | Encrypted technical receipt, outer signature, business signature |
| Business GETs | Signed service header and body, including empty bodies | Encrypted reply, outer signature, business signature; handle genuine empty replies according to confirmed profile |

The API's general statement that CorporateMessage is always encrypted has explicit certificate-operation exceptions in its security matrix. Enforce operation policy rather than that generalization. The matrix and the step-by-step guides also take precedence over prose suggesting only the header is signed for GETs. [D03, D06, D08]

For Bankdata/NBS outbound payment and renewal requests: construct content → business-sign → encrypt SOAP body → sign service header and encrypted body. For BEC: construct content → business-sign → sign service header and plaintext body → encrypt SOAP body. Keep the sequence explicit in centre policy. Implement inbound verification/decryption against centre-specific evidence; if the outer signature covers plaintext, decryption must precede that verification. No business effects occur before all required signatures and certificate checks succeed. [D07, D09, D10]

Business signatures reference `paymentMessage`, `certificateRequestMessage`, or the returned business object as specified, with a sibling `ds:Signature`. Base64/gzip payload handling must not change signed bytes. Construct final payload encoding/compression metadata before signing its enclosing message. The API's shorthand about signing ISO content and gzip is less precise than D09's wire example; use that example and interoperability tests to settle the actual signed node. [D03, D09]

As implementation safeguards, disable DTD/external entity resolution and external signature references, reject duplicate XML IDs/signature wrapping, enforce required signed-node coverage and expected algorithms, and validate that the consumed nodes are exactly the verified nodes. Validate chains to independently configured environment-specific roots, validity periods and critical extensions; neither a certificate in `KeyInfo` nor a matching issuer string is sufficient trust. Preserve canonicalization namespace handling; test reserialization and whitespace effects.

### Encoding and limits

- ISO XML is UTF-8. Base64 is encoding, not encryption. Certificate CSR is DER bytes represented as base64; certificate response content is base64 of a PEM bundle. Avoid double encoding generated `base64Binary` fields. [D03, D06]
- `compressed=0` means no compression; `1` means gzip. Content above 5 MB must be compressed. Reject unsupported flags and corrupt gzip; impose a configurable decompressed-size bound as well as a wire-size bound. [D03]
- The programming guide says 30 MB compressed content, while the API also caps the complete SOAP payload at 30 MB. Until clarified, satisfy both with headroom for base64 expansion, security elements and encryption. Measure final serialized bytes and split before submission; confirm decimal/binary MB interpretation. [D03, D05]
- Recommend no more than 20,000 payments per transfer, independently of byte limits. Split only at valid payment-group boundaries or rebuild groups/counts consistently. Recompute `NbOfTxs` and any control sums; XML schema-required values remain required even where usage tables label them optional. [D03, D12]

## 4. Certificate lifecycle

### Activation

1. Obtain the signed Exchange Agreement, bank primary registration number/country, Function ID, mailbox/report setup, and activation code. For system testing obtain a support-issued customer; D05's printed contact address contains a comma typo and should be verified before use. The package's DK/8079 and Sydbank numbering examples are test-only. [D02, D05, D06]
2. Install authenticated test trust anchors. Call `getBankCertificate`, verify its business signature/chain, parse the entire returned PEM bundle and identify the correct bank leaf/intermediates. Cache per environment and bank routing identity, retaining fingerprints and validity metadata. Refresh automatically, e.g. daily on first use, and stage any trust-anchor changes independently. [D03–D06]
3. Generate RSA-2048 keypair locally and persist its protected private key before the network call. Generate a valid signed PKCS#10 CSR with CN `<functionIdentification>@<normalizedActivationCode>`; CSR attributes must be an empty set if unused, not null. Strip code dashes; base64-encode the code bytes and DER CSR. [D03, D04, D06]
4. Build the activation header and encrypted activation body, send and validate the response business signature. Parse all certificates, validate the chain/environment/validity and verify that the issued leaf's public key matches the pending keypair. Atomically install the certificate/key association and mark the agreement active. Retain failed/uncertain activation state for recovery without losing the keypair. [D03, D06]
5. Demonstrate one signed GET and validated/decrypted response before declaring setup complete. Do not retain the activation code in routine logs or long-term configuration.

### Renewal and revocation

Schedule renewal from actual `notAfter`, with an initial proposed lead time of 30 days, alerts and retry backoff; the exact lead time is configurable, not a Bank Connect requirement. Generate a new keypair and a CSR with Function ID CN and no activation-code suffix. Sign the inner request and outer message with the old key, using centre-specific order; decrypt the response using that old key. Validate the new leaf/keypair match and switch atomically only after successful installation. [D03, D04, D07]

The API allows only two active customer certificates and says older certificates are revoked 48 hours after renewal. Do not perform repeated renewals as generic retries. Track pending/active/retiring generations and uncertain renewal responses; test coexistence and crash recovery. Retain old keys long enough to finish legitimate in-flight response handling under a defined retention policy; expired/revoked certificates must not be used for new requests. Confirm the exact overlap behavior with each centre. [D03]

The certificate policy requires password-protected keystores and limits Bank Connect keys to Bank Connect use; do not reuse them as TLS client certificates or for unrelated signing. Design controlled keystore password access, encrypted backup/restore, role restrictions and access auditing. Expiry, revocation or lost keys require bank/RA-assisted recovery and possibly reactivation. There is no public CRL API to invent; document the bank's revocation/support procedure and stop new submissions when an agreement is blocked. [D04]

## 5. Payment construction and submission

### Shared pain.001 rules

Build namespace `urn:iso:std:iso:20022:tech:xsd:pain.001.001.03`; validate both against its XSD and the selected Bank Connect/centre/payment-type profile. At minimum map initiating-party customer identification, unique group message ID, creation time/count, one or more payment-information groups (ID, method, type, execution date, debtor/account/agent), and transactions (payment IDs, amount/currency, beneficiary/account and remittance). Use actual XSD spellings such as `CdtTrfTxInf`, despite the occasional prose/table typo. [D12, WSDL/ISO XSD]

Use non-reused generated IDs as a stronger local policy than minimum windows. The guide says `MsgId` is duplicate-checked for three months; `PmtInfId` must be unique for 90 days (60 days for Bankdata); transaction `EndToEndId` must be unique for 90 days even where the bank does not validate it. Do not equate transaction `EndToEndId` with the SOAP technical ID. [D03, D12]

Put `PmtTpInf` at payment-group level by default and group compatible transactions together; do not populate it again at transaction level. Enforce group/transaction exclusivity for charge bearer and ultimate debtor. Account ID choices, instructed versus equivalent amount, purpose code versus proprietary purpose, and other `{Or}` choices must respect the actual XSD and profile. Danish BBAN is a string comprising 4 registration digits plus 10 account digits, zero-padded as needed. [D12–D14]

Apply 04.10.2026 restrictions across all payment profiles, including ultimate parties where their tables specify them:

- Debtor addresses, when supplied, are structured with at least `TwnNm` and `Ctry`.
- Creditor addresses, when supplied, are structured or hybrid with `TwnNm` and `Ctry`; hybrid addresses additionally contain one or two `AdrLine` elements. Fully unstructured addresses are unsupported.
- `RmtInf/Ustrd` is at most one element of at most 140 characters. Do not silently truncate invoice/reference information; reject or ask the upstream caller to correct it.
- Foreign cheque submission is disabled, even though older guidelines and schemas still describe CHK.

These are package revision requirements, not conclusions inferred from the older XML fixtures. [D12, D14–D20]

### Payment profiles

| Profile | Core discriminator/mapping | Enablement conditions |
| --- | --- | --- |
| Domestic normal | TRF, ONCL, SUPP; NURG/default service | First outbound profile; confirm permitted accounts, currencies, cutoff and approval workflow. |
| Domestic same-day | TRF, SDCL, SUPP | Confirm cutoff, date handling and bank limits. |
| Domestic urgent | TRF, service URNS, SUPP; omit local instrument per discriminator guide | Distinguish from foreign URGP; confirm bank support. |
| Salary | TRF, SALA; ONCL initially | Same-day/urgent salary variants need confirmation because guides differ. EPNU only where confirmed, general guide says Bankdata-only. |
| Giro/FI | TRF, OCR account scheme, SCOR reference; separate creditor/Giro number and `type/payment-id` | Types 01/04/15/71/73/75; 01/73 have trailing slash with no payment ID. Confirm exact lengths/check digits; D11 says FI-71 max 15 while D17 says max 16. |
| NemKonto | TRF, ONCL, SUPP; account `Othr/Id` plus NKC/NKV/NKP/NKR/NKS proprietary scheme | Validate identifier structure, centre support and sensitive-data handling; do not treat CPR as an ordinary account number. |
| SEPA | TRF, SEPA, IN, SUPP; SLEV charges | Confirm account/currency rules and bank-specific code; D11's usual Bankdata code 97 is not universal. |
| Foreign ordinary/express/group | TRF, IN; NURG/URGP as appropriate; INTC category for group transfer | Bank-specific code (examples 53/57/61), beneficiary/agent/BIC, charge and FX rules need confirmation. |
| Nationalbank transfer | TRF, IN, URGP, transfer code 99 in detailed guide | Separate bank capability and currency validation. |
| MT101/account abroad | TRF, IN, foreign debtor-agent BIC; own/group purpose depends on confirmed profile | D11 gives example codes 83/84/85/86; reconcile INTC field-location conflict with D20 before enabling. |

Do not infer availability merely from a documented payment type. Maintain capability profiles keyed by centre/bank/agreement; unknown profiles remain disabled. Do not hardcode Bankdata example transfer codes into all banks. [D10–D20]

### Submission and duplicate prevention

1. Validate the upstream business payment and authorization/approval reference, build an immutable batch and persist it in the outbox before calling the bank. Bank Connect certificate signing does not establish what additional bank-side approval mandates apply; confirm them per agreement.
2. Persist SOAP ID, `MsgId`, group/transaction IDs, payload hash, certificate generation and attempt metadata. Apply business signature/encryption/outer signature according to centre policy and verify final wire size.
3. Send `transferPayments` with singular `transferPayment` body/SOAPAction. Authenticate and decode the returned `paymentResponse`; persist response code, sender, original technical ID, correlation ID and message. Codes 200 and 202 mean technical delivery/processing, not completed payment. [D03, D09]
4. Poll `getStatus` and correlate pain.002 back to original group/transaction records. Keep technical delivery, bank validation/processing, waiting-for-funds, rejection and accounting settlement as separate facts.
5. A timeout, connection loss, 504, or duplicate fault after uncertain delivery produces an **unknown submission outcome**. D03 labels 504 retryable and suggests a new ID for 705; do not automatically follow that advice for payments, as a fresh ID can bypass duplicate detection. Reconcile mailbox status and bank evidence first, then retry only under an agreed policy that preserves business identity. No resubmission merely because a positive status was not received.

## 6. Status, reporting and reconciliation

### Mailbox retrieval

| Operation | Expected content | Processing purpose |
| --- | --- | --- |
| `getStatus` | pain.002.001.03 | Business validation/status and pending orders |
| `getCustomerStatement` | camt.053.001.02 | End-of-day booked entries/balances |
| `getCustomerAccountReport` | camt.052.001.02 | Intraday/ad-hoc/future information; interpret actual contents and bank semantics |
| `getDebitCreditNotification` | camt.054.001.02 | Intraday debit/credit notifications, enabled for confirmed centres |
| `getAlternate` | Unspecified/non-ISO content | Optional; retain safely by format/MIME type and dispatch only to registered handlers |

Statements/extracts are ordered for the mailbox through the bank/online banking; the package does not define account enumeration, arbitrary date-range query, webhook, or cancellation APIs. Capture the bank-side report-ordering/setup procedure during onboarding. [D02, D03]

Each poll gets a fresh technical request ID, persisted before calling. Authenticate/decrypt the reply, validate its business signature, decode base64 and honor gzip; dispatch by actual namespace and documented format/MIME metadata. Empty responses, absent `corporateMessage` and absent content are normal no-data cases subject to the operation profile. A certificate response is a specific unencrypted exception. [D03, D06, D08]

Persist each received item and its original request ID before advancing to the next retrieval. Continue while `severalMessages=true`, with bounded work per job and rescheduling to avoid starvation. Use backoff/jitter when empty or temporarily unavailable; obtain permitted polling frequency from support. Quarantine malformed/unknown content with protected evidence, then allow other durably recorded items to be processed. Do not assume receiving a message can be rolled back at the bank.

For supported centres, recovery uses a **new** retrieval request with the original call's `ServiceHeader/endToEndMessageId` in body `reorderEndToEndMessageId`. Persist this original request ID even if the reply was lost. Inline WSDL supports reorder for status, statement, account report and debit/credit notification; `getAlternate` does not contain it. Confirm centre support, retention window and lost-response behavior before relying on this as recovery. [D03, WSDL]

### pain.002 state handling

Parse original message ID, payment-information ID, original transaction identifiers, statuses, reason codes and all narrative lines at their original hierarchy. Retain raw events and derive current state without letting late/replayed events erase newer evidence. Allow partial batches: a group-level status must not indiscriminately overwrite every transaction's more specific outcome. [D21, D22]

ACTC/ACCP are validation/acceptance progress, ACSP is processing, PDNG is pending, ACWC includes changes, PART means mixed outcomes, RJCT means rejection at the reported level. Preserve ACSC/RCVD and unknown future values without treating every non-rejection as settled. Validate the R1–R10 hierarchy rules diagnostically; NARR requires narrative details. Real reports that conflict with the rules must remain recoverable for investigation. [D21, D22]

Handle **ACSP + AM14 at bulk level** as waiting for liquidity; payments may execute automatically once funded. Do not reject or resubmit these orders. Preserve the general AM14 reason description as well as the pending-orders interpretation. NBS may omit reports after a user rejection, so absence of a report cannot prove success or failure. Escalate overdue/unknown states for reconciliation rather than inventing a terminal status. [D10, D23]

Test correlation using both `InstrId` and `EndToEndId`: D21's mapping text is ambiguous. Do not assume equal values in fixtures prove the mapping. Use distinct values in bank acceptance tests and implement explicit centre mapping only after evidence.

### CAMT ingestion

Parse the actual .001.02 namespaces and container shapes: `BkToCstmrAcctRpt/Rpt`, `BkToCstmrStmt/Stmt`, and `BkToCstmrDbtCdtNtfctn/Ntfctn`. Support multiple accounts/containers and entries with zero or many transaction details. [D24–D26]

Normalize while retaining source hierarchy:

- Account identification/scheme/currency; report ID, sequence and period; opening/closing booked/available balance types and signs.
- Entry amount/currency, DBIT/CRDT direction, status, reversal, booking/value dates, bank domain/family/subfamily and proprietary transaction codes.
- Batch total/count and transaction details; original message/group/instruction/end-to-end IDs, bank references, parties, amounts/FX and remittance.
- Structured SCOR/OCR/RF references and DEBI/CRED/PRIM document references; separate creditor number from `71/<payment-id>` etc. Preserve raw centre-specific layout before normalization.

Do not add entry totals and their repeated transaction amounts together. Reconcile BEC aggregated debits against detailed payments and preserve unmatched differences. Account-servicer reference may be absent at NBS; `NtryRef` is only locally numbered. Define document replay identity separately from economic-transaction matching, and deduplicate overlapping CAMT notifications/reports/statements using available bank identity, account, references and evidence. A content hash alone cannot identify the same transaction appearing in different document types. Do not automatically collapse legitimate identical payments. [D10, D24–D26]

Use camt.053 as the initial booked-ledger ingestion path; introduce camt.052/.054 as additional views with tested reconciliation rules. D24 describes BOOK entries while D03 describes future entries, so confirm semantics before posting camt.052 directly into the ledger. Preserve balance/transaction discrepancies for review.

## 7. Fault handling and operations

Parse SOAP 1.1 `faultcode` and `faultstring`, whose Bank Connect shape is `errorcode#correlation-id#message`; correlation ID may be empty. Split on the first two separators and preserve the remaining message. Keep HTTP failure, SOAP fault, technical `paymentResponse` and pain.002 reason code as distinct error types. [D03]

| Code | Meaning/action |
| --- | --- |
| 400 | Invalid request: fix/validate locally; no blind retries. |
| 413 | Too large: reduce/rebuild batch while preserving submission evidence. |
| 426 | Contract/service version unsupported: operational alert and controlled upgrade. |
| 500/501 | Server/invocation failure: bounded retry or support investigation, with mutation outcome reconciliation. |
| 504 | Timeout: GET recovery/reorder as supported; payment/renewal outcome may be uncertain. |
| 631 | Signature invalid: inspect canonicalization, key and signed-node coverage. |
| 633 | Decryption failed: inspect bank-certificate freshness, algorithm parameters and encryption structure. |
| 634 | Certificate invalid: check chain/environment/expiry/revocation; renew or recover through bank. |
| 701 | Identification failed: verify bank/country/Function ID/request ID/activation code. |
| 705 | Duplicate request: reconcile original outcome; changing a payment ID is not a safe generic retry. |
| 710/711/712 | Invalid schema/content, format, or gzip: correct locally and retain diagnostic evidence. |

Track last successful retrieval per agreement/operation, queue drain lag, rejected/quarantined messages, pending/unknown payment age, technical versus business rejection rate, certificate expiry/refresh failures, latency and timeouts. Include error code and bank correlation ID in support diagnostics. Use `getBankCertificate` as a limited connectivity check because the API defines no ping operation; it does not prove payment mandates or mailbox setup. [D03]

Prepare runbooks for activation failure, failed/ambiguous renewal, bank-certificate rollover, revoked/lost keys, uncertain payment submission, inbox crash/reorder, incorrect bank configuration, version retirement, and bank-side approval/rejection. Record report ordering and account access/mandates per agreement.

## 8. Delivery sequence and acceptance gates

Estimates should follow the XML-security feasibility spike and confirmation of the first bank. Each phase below produces a reviewable implementation increment; later payment profiles are independent enablement work, not presumed available at first release.

| Phase | Work and dependencies | Exit criteria |
| --- | --- | --- |
| P0 — Confirm contract and pilot | Choose pilot bank/centre, initial operations and runtime integration location; obtain system-test agreement/activation code, trusted CA fingerprints, mailbox subscriptions and sample bank responses. Resolve the release-blocking questions in section 9 for the pilot. | Versioned contract/capability record; test access available; selected stack can implement required XML security. |
| P1 — Transport/security feasibility | Pin WSDL/ISO schemas; implement headers, SOAPAction, faults, IDs and TLS configuration; get/validate bank certificate. Prove canonicalization, signature, encryption and centre ordering with isolated fixtures. | Authenticated `getBankCertificate`; no localhost or demo credential defaults; tampering/incorrect chain/incorrect signed-node coverage rejected. |
| P2 — Agreement and certificates | Durable configuration/key storage; activation; signed GET; renewal with old/new generations, scheduling, backup/restore and alerts. Depends on P1. | Test activation and renewal succeed; new keypair matches certificate; crash/timeout does not lose pending keys; both signature orders covered locally, and target centre flow tested against its service. |
| P3 — Durable inbound reporting | Inbox, per-operation pollers, draining/replay/reorder, pain.002 and camt.053 parsers, account/reference mapping and reconciliation. Depends on P2. | Empty and multi-message retrieval work; restart does not duplicate postings; bank samples map correctly; unrecoverable queue gaps are surfaced; pending AM14 and partial status fixtures behave correctly. |
| P4 — First outbound payments | Domestic normal pain.001 builder/validator, upstream approval boundary, immutable outbox, technical receipts, uncertain outcomes and status correlation. Depends on P2/P3. | Controlled system-test transfer; 200/202 never shown as settled; invalid payments blocked locally; replay/timeout/705/504 scenarios cannot automatically create a fresh duplicate payment. |
| P5 — Additional capabilities | FI/Giro, same-day/urgent, salary, SEPA, foreign, NemKonto and MT101 profiles; camt.052/.054 and alternate handlers. Prioritize actual business need and agreed bank capabilities. | Each enabled profile has positive/negative fixtures and bank acceptance evidence; unsupported combinations blocked. BEC/NBS differences covered where those centres are enabled. |
| P6 — Production pilot and operation | Separate production trust/keys/configuration, support runbooks, metrics, recovery rehearsal, restricted pilot and reconciliation review. Depends on all enabled capability gates. | Bank-required acceptance completed, production activation validated, operators can restore keys/inbox/outbox, pilot payments reconcile, certificate renewal and version-upgrade ownership assigned. |

### Required validation scenarios

- Contract: correct singular/plural operation mapping, namespace/case/order, header fields, maximum technical ID length, DST timestamps, and inline-WSDL reorder body.
- Security: valid/invalid chain, environment mismatch, expired leaf, multiple PEM certificates, wrong keypair, missing/tampered inner/outer signature, duplicate IDs, unsigned consumed node, namespace/canonicalization changes, both centre sequences, corrupt ciphertext and unsupported algorithms.
- Lifecycle: normalized activation code, proper DER CSR/empty attributes, interrupted activation, renewal with fresh keypair/old signing key, response loss, concurrent workers, atomic switch, expiry and overlap boundary.
- Payload: uncompressed/gzip, above-5-MB compression, final wire-size cap including base64/security overhead, decompression bound, invalid encoding/format and 20,000-payment batching policy.
- Payment validation: required identifiers/accounts, group counts/sums, exclusive fields, correct discriminator combinations, structured/hybrid address limits, single 140-character Ustrd, forbidden cheques, scheme-specific NemKonto and OCR/FI rules.
- Delivery: crash before send/after send/before receipt persistence, 200/202/504, duplicate 705, repeated job execution and unchanged business identity across recovery.
- Status/reporting: differing InstrId/EndToEndId, group/transaction partial rejection, ACSP/AM14, narrative/unknown codes, missing reports, empty queues, multiple messages, lost-response reorder, overlapping CAMT documents, batched debits, repeated amounts, reversal and absent bank reference.

Validate sample fixtures before adopting them: historical examples and .001.03 CAMT files are not automatic positive tests for the .001.02/2026 profiles. Maintain a small suite of known-good wire captures generated with test-only keys; perform real system-test acceptance for each centre enabled. Local mock success alone is insufficient evidence of interoperability.

## 9. Questions and conflicts to resolve

These are concrete discovery tasks for P0 or capability enablement. They do not prevent building isolated codecs or a security spike.

| Question/conflict | Evidence | Planned resolution and gate |
| --- | --- | --- |
| What contract endpoint/version, TLS settings, CA fingerprints and support contacts are currently supported? | D03/D05 use dated URLs; bundled WSDL points to localhost; security resources include historical certificates. | Confirm with Bank Connect/pilot bank before any live connectivity or production trust installation. |
| Which operations, payment types, mandates, approvals and mailbox subscriptions does the target agreement permit? | D02/D03/D10 show permissions, report ordering and centre differences; camt.054 is described as Bankdata-only. | Record a tested capability matrix before enabling each operation/profile. Confirm whether NBS/SDC naming denotes the same target service context. |
| Which certificate identity scope, response signing order and renewal overlap behavior applies? | BEC user scope and alternate order in D07/D09/D10; D03 says two active certificates and 48-hour retirement. | Obtain distinct centre fixtures and acceptance results; block unsupported centre configuration. |
| Is the 30 MB limit raw/compressed content or entire serialized SOAP, and how are MB units interpreted? | D03 and D05 describe different layers. | Enforce conservative bounds on both initially; verify actual service limit before large batches. |
| Is reordering available, for how long, and what happens after a response is lost? | API/inline WSDL supports reorder; standalone XSD does not; centre support is external to package. | Pin consistent schemas; verify per-centre recovery and queue delivery/acknowledgment semantics before relying on automatic recovery. |
| How should ambiguous payment/activation/renewal timeouts be recovered? | D03 suggests retryable 504/new ID for 705 without establishing idempotent mutation semantics. | Agree recovery with bank; keep unknown state and do not automatically repeat mutations with fresh IDs. |
| Does a returned original transaction ID contain InstrId or EndToEndId? | D21 semantics and mapping remarks disagree. | Test with deliberately distinct identifiers and document centre-specific behavior before payment-status matching is accepted. |
| What is FI-71 payment-ID length and validation? | D11 says max 15; D17 says max 16. | Obtain a confirmed profile including check-digit rules and positive/negative samples before enabling FI-71. |
| Which salary variants, NemKonto schemes, EPNU references and foreign/SEPA transfer codes are supported? | Detailed/generic guides differ; example Bankdata codes explicitly require bank confirmation. | Confirm per-bank rules; unknown combinations disabled. Confirm SEPA currency/account requirements rather than infer from generic table rows. |
| Where does MT101 INTC belong, and what foreign-account format is required? | D11 uses service-level INTC for some variants; D20 uses category-purpose INTC and retains generic Danish account text. | Agree exact XML with bank and add fixtures before MT101 enablement. |
| Are camt.052 entries future/intraday projections or booked ledger data, and how should aggregate/overlapping reporting reconcile? | D03 versus D24; BEC debit aggregation in D10. | Collect real samples and define posting policy before feeding camt.052/.054 into booked accounting. |
| How should validation conflicts and old fixtures be ranked? | Usage tables contain optional/required ambiguity and copied rule examples; old guidelines still describe cheques. | Use the pinned XSD for syntax, newer October 2026 guides for explicit payment restrictions, step-by-step guides for demonstrated security placement/order, and bank acceptance to settle remaining conflicts. Record exceptions instead of silently guessing. |

Production readiness requires completed activation/renewal, authenticated message handling, demonstrated duplicate prevention and uncertain-outcome recovery, durable inbox recovery, and reconciliation for every enabled payment/reporting profile. Bank-specific features remain gated until their open questions have evidence-backed answers.
