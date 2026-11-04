# Danish VAT preset catalogue

Version 2026-11-04.1; sources reviewed 2026-11-04. Templates require explicit selection, eligible use and effective dates. Reporting boxes are book-local shorthand; there is no automatic VAT return or EU sales-list submission. Imported code aliases describe matching only, never legal eligibility.

## U25 — Dansk salgsmoms

Treatment: output; rate 25%; deductible VAT share 0%; assessment net.

Ordinary Danish taxable supplies at the standard rate. Confirm place of supply and any exemption.

- https://skat.dk/erhverv/moms/i-gang-med-moms

## I25 — Dansk købsmoms — fuldt fradrag

Treatment: input; rate 25%; deductible VAT share 100%; assessment net.

Full deduction assumes exclusively deductible business use; adjust the share for mixed, exempt or private use.

- https://skat.dk/erhverv/moms/i-gang-med-moms
- https://skat.dk/erhverv/moms/fradrag-for-moms/saadan-faar-du-momsfradrag

## REP — Restaurant — kvart momsfradrag

Treatment: input; rate 25%; deductible VAT share 25%; assessment net.

Eligible business restaurant expenditure only. This is a quarter of VAT, not a general deduction for representation or gifts.

- https://skat.dk/erhverv/moms/fradrag-for-moms/udgifter-du-kan-faa-momsfradrag-for/momsfradrag-for-forplejning-og-hotel

## IEUV — EU-varekøb

Treatment: reverse_charge; rate 25%; deductible VAT share 100%; assessment net.

EU acquisition subject to Danish assessment; verify invoice and VAT registrations. Full deduction assumes exclusively deductible business use; adjust the share for mixed, exempt or private use.

- https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/moms-ved-handel-med-virksomheder/moms-ved-handel-med-lande-i-eu/moms-ved-koeb-af-varer-og-ydelser-i-eu
- https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/indberet-din-handel-med-udlandet

## IEUY — EU-ydelseskøb

Treatment: reverse_charge; rate 25%; deductible VAT share 100%; assessment net.

General-rule EU business services taxable in Denmark. Check place-of-supply exceptions. Full deduction assumes exclusively deductible business use; adjust the share for mixed, exempt or private use.

- https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/moms-ved-handel-med-virksomheder/moms-ved-handel-med-lande-i-eu/moms-ved-koeb-af-varer-og-ydelser-i-eu
- https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/indberet-din-handel-med-udlandet

## IVV — Vareimport — moms fra importspecifikation

Treatment: reverse_charge; rate 25%; deductible VAT share 100%; assessment import_statement.

Use the assessed import VAT from the import specification, including applicable customs adjustments. Supplier net alone is not the import VAT basis. No EU acquisition base is added. Full deduction assumes exclusively deductible business use; adjust the share for mixed, exempt or private use.

- https://toldst.dk/erhverv/import/forstaa-din-importspecifikation
- https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/moms-ved-handel-med-virksomheder/moms-ved-handel-med-lande-uden-for-eu/moms-ved-koeb-af-varer-og-ydelser-i-lande-uden-for-eu

## IVY — Ydelseskøb uden for EU

Treatment: reverse_charge; rate 25%; deductible VAT share 100%; assessment net.

General-rule services taxable in Denmark; exceptions exist. No EU-only acquisition base. Full deduction assumes exclusively deductible business use; adjust the share for mixed, exempt or private use.

- https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/moms-ved-handel-med-virksomheder/moms-ved-handel-med-lande-uden-for-eu/moms-ved-koeb-af-varer-og-ydelser-i-lande-uden-for-eu
- https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/indberet-din-handel-med-udlandet

## OBPK — Dansk køb med omvendt betalingspligt

Treatment: reverse_charge; rate 25%; deductible VAT share 100%; assessment net.

Only qualifying domestic reverse-charge purchases; verify the goods, supplier and invoice. No foreign-purchase box. Full deduction assumes exclusively deductible business use; adjust the share for mixed, exempt or private use.

- https://info.skat.dk/data.aspx?oid=2133870
- https://info.skat.dk/data.aspx?oid=2107416

## UEUV — EU-varesalg — EU-liste

Treatment: output; rate 0%; deductible VAT share 0%; assessment net.

Qualifying goods supplied to a VAT-registered EU customer with transport evidence. EU sales-list reporting remains separately required.

- https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/indberet-din-handel-med-udlandet

## UEUV2 — EU-varesalg — uden EU-liste

Treatment: output; rate 0%; deductible VAT share 0%; assessment net.

Only transactions specifically belonging in the non-EU-list goods box, such as qualifying installation or assembly. Not a universal preset for consumer or OSS sales.

- https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/indberet-din-handel-med-udlandet

## UEUY — EU-ydelsessalg

Treatment: output; rate 0%; deductible VAT share 0%; assessment net.

Qualifying general-rule EU business services. Verify customer status and place of supply; other services can belong in Rubrik C. EU sales-list reporting remains separate.

- https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/indberet-din-handel-med-udlandet

## UVV — Vareeksport uden for EU

Treatment: output; rate 0%; deductible VAT share 0%; assessment net.

Qualifying export supplies without Danish VAT; retain export evidence and verify conditions.

- https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/indberet-din-handel-med-udlandet

## UVY — Ydelsessalg uden dansk moms

Treatment: output; rate 0%; deductible VAT share 0%; assessment net.

Only services whose place-of-supply treatment excludes Danish VAT and belongs in Rubrik C. Not every foreign customer qualifies.

- https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/indberet-din-handel-med-udlandet

## HOTEL — Hotelovernatning — fuldt momsfradrag

Treatment: input; rate 25%; deductible VAT share 100%; assessment net.

Eligible business accommodation only. Separate breakfast/restaurant charges; social/private portions do not get this full deduction. Do not reuse legacy 75% hotel coding.

- https://skat.dk/erhverv/moms/fradrag-for-moms/udgifter-du-kan-faa-momsfradrag-for/momsfradrag-for-forplejning-og-hotel

## OBPS — Dansk salg med omvendt betalingspligt

Treatment: output; rate 0%; deductible VAT share 0%; assessment net.

Only qualifying domestic reverse-charge supplies. Check supplier/recipient and product exceptions, invoice requirements and the applicable regime.

- https://info.skat.dk/data.aspx?oid=2133870

## NONE — Ingen momsberegning

Treatment: none; rate 0%; deductible VAT share 0%; assessment net.

Use only when no VAT assessment is applicable. A label or zero amount does not establish an exemption or reporting treatment.

- https://skat.dk/erhverv/moms/i-gang-med-moms

Alias interpretation only: https://dinero.dk/support/hvilke-momskoder-har-vi-dinero/ . Official SKAT/Toldstyrelsen sources govern the template conditions. Obsolete hotel 75% coding is deliberately excluded. The check date does not establish a transaction effective date.
