defmodule Ep.Finance.DanishVatPresets do
  @moduledoc "Versioned, sourced Danish VAT draft templates. Selecting a template never accepts a rule."
  @version "2026-11-04.1"
  @checked "2026-11-04"
  @basic "https://skat.dk/erhverv/moms/i-gang-med-moms"
  @deduction "https://skat.dk/erhverv/moms/fradrag-for-moms/saadan-faar-du-momsfradrag"
  @restaurant "https://skat.dk/erhverv/moms/fradrag-for-moms/udgifter-du-kan-faa-momsfradrag-for/momsfradrag-for-forplejning-og-hotel"
  @eu "https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/moms-ved-handel-med-virksomheder/moms-ved-handel-med-lande-i-eu/moms-ved-koeb-af-varer-og-ydelser-i-eu"
  @abroad "https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/indberet-din-handel-med-udlandet"
  @non_eu "https://skat.dk/erhverv/moms/moms-ved-handel-med-udlandet/moms-ved-handel-med-virksomheder/moms-ved-handel-med-lande-uden-for-eu/moms-ved-koeb-af-varer-og-ydelser-i-lande-uden-for-eu"
  @customs "https://toldst.dk/erhverv/import/forstaa-din-importspecifikation"
  @domestic "https://info.skat.dk/data.aspx?oid=2133870"
  @domestic_boxes "https://info.skat.dk/data.aspx?oid=2107416"
  @full "Full deduction assumes exclusively deductible business use; adjust the share for mixed, exempt or private use."
  @baseline ~w(direction rate_bps deductible_bps mappings assessment_basis)

  def all do
    [
      preset(
        "U25",
        "Dansk salgsmoms",
        ~w(U25 output),
        "output",
        2500,
        0,
        [line("Salgsmoms", "vat")],
        "Ordinary Danish taxable supplies at the standard rate. Confirm place of supply and any exemption.",
        [@basic]
      ),
      preset(
        "I25",
        "Dansk købsmoms — fuldt fradrag",
        ~w(I25 input),
        "input",
        2500,
        10000,
        [line("Købsmoms", "deductible_vat")],
        @full,
        [@basic, @deduction]
      ),
      preset(
        "REP",
        "Restaurant — kvart momsfradrag",
        ["REP"],
        "input",
        2500,
        2500,
        [line("Købsmoms", "deductible_vat")],
        "Eligible business restaurant expenditure only. This is a quarter of VAT, not a general deduction for representation or gifts.",
        [@restaurant]
      ),
      preset(
        "IEUV",
        "EU-varekøb",
        ["IEUV"],
        "reverse_charge",
        2500,
        10000,
        [
          line("Udlandsvaremoms", "vat"),
          line("Købsmoms", "deductible_vat"),
          line("Rubrik A varer", "net")
        ],
        "EU acquisition subject to Danish assessment; verify invoice and VAT registrations. " <>
          @full,
        [@eu, @abroad]
      ),
      preset(
        "IEUY",
        "EU-ydelseskøb",
        ["IEUY"],
        "reverse_charge",
        2500,
        10000,
        [
          line("Udlandsydelsesmoms", "vat"),
          line("Købsmoms", "deductible_vat"),
          line("Rubrik A ydelser", "net")
        ],
        "General-rule EU business services taxable in Denmark. Check place-of-supply exceptions. " <>
          @full,
        [@eu, @abroad]
      ),
      preset(
        "IVV",
        "Vareimport — moms fra importspecifikation",
        ["IVV"],
        "reverse_charge",
        2500,
        10000,
        [line("Udlandsvaremoms", "vat"), line("Købsmoms", "deductible_vat")],
        "Use the assessed import VAT from the import specification, including applicable customs adjustments. Supplier net alone is not the import VAT basis. No EU acquisition base is added. " <>
          @full,
        [@customs, @non_eu],
        "import_statement"
      ),
      preset(
        "IVY",
        "Ydelseskøb uden for EU",
        ["IVY"],
        "reverse_charge",
        2500,
        10000,
        [line("Udlandsydelsesmoms", "vat"), line("Købsmoms", "deductible_vat")],
        "General-rule services taxable in Denmark; exceptions exist. No EU-only acquisition base. " <>
          @full,
        [@non_eu, @abroad]
      ),
      preset(
        "OBPK",
        "Dansk køb med omvendt betalingspligt",
        ["OBPK"],
        "reverse_charge",
        2500,
        10000,
        [line("Salgsmoms", "vat"), line("Købsmoms", "deductible_vat")],
        "Only qualifying domestic reverse-charge purchases; verify the goods, supplier and invoice. No foreign-purchase box. " <>
          @full,
        [@domestic, @domestic_boxes]
      ),
      preset(
        "UEUV",
        "EU-varesalg — EU-liste",
        ["UEUV"],
        "output",
        0,
        0,
        [line("Rubrik B varer (EU-liste)", "net")],
        "Qualifying goods supplied to a VAT-registered EU customer with transport evidence. EU sales-list reporting remains separately required.",
        [@abroad]
      ),
      preset(
        "UEUV2",
        "EU-varesalg — uden EU-liste",
        ["UEUV2"],
        "output",
        0,
        0,
        [line("Rubrik B varer (uden EU-liste)", "net")],
        "Only transactions specifically belonging in the non-EU-list goods box, such as qualifying installation or assembly. Not a universal preset for consumer or OSS sales.",
        [@abroad]
      ),
      preset(
        "UEUY",
        "EU-ydelsessalg",
        ["UEUY"],
        "output",
        0,
        0,
        [line("Rubrik B ydelser", "net")],
        "Qualifying general-rule EU business services. Verify customer status and place of supply; other services can belong in Rubrik C. EU sales-list reporting remains separate.",
        [@abroad]
      ),
      preset(
        "UVV",
        "Vareeksport uden for EU",
        ["UVV"],
        "output",
        0,
        0,
        [line("Rubrik C", "net")],
        "Qualifying export supplies without Danish VAT; retain export evidence and verify conditions.",
        [@abroad]
      ),
      preset(
        "UVY",
        "Ydelsessalg uden dansk moms",
        ["UVY"],
        "output",
        0,
        0,
        [line("Rubrik C", "net")],
        "Only services whose place-of-supply treatment excludes Danish VAT and belongs in Rubrik C. Not every foreign customer qualifies.",
        [@abroad]
      ),
      preset(
        "HOTEL",
        "Hotelovernatning — fuldt momsfradrag",
        ["HOTEL"],
        "input",
        2500,
        10000,
        [line("Købsmoms", "deductible_vat")],
        "Eligible business accommodation only. Separate breakfast/restaurant charges; social/private portions do not get this full deduction. Do not reuse legacy 75% hotel coding.",
        [@restaurant]
      ),
      preset(
        "OBPS",
        "Dansk salg med omvendt betalingspligt",
        ["OBPS"],
        "output",
        0,
        0,
        [line("Rubrik C", "net")],
        "Only qualifying domestic reverse-charge supplies. Check supplier/recipient and product exceptions, invoice requirements and the applicable regime.",
        [@domestic]
      ),
      preset(
        "NONE",
        "Ingen momsberegning",
        ["none"],
        "none",
        0,
        0,
        [],
        "Use only when no VAT assessment is applicable. A label or zero amount does not establish an exemption or reporting treatment.",
        [@basic]
      )
    ]
  end

  def find(id, version), do: if(version == @version, do: Enum.find(all(), &(&1["id"] == id)))

  def provenance(id, version, old, attrs) do
    source =
      cond do
        id in [nil, ""] && version in [nil, ""] ->
          nil

        old && old["id"] == id && old["version"] == version ->
          old

        true ->
          p = find(id, version) || Ep.Repo.rollback(:invalid_vat_preset)

          Map.take(p, ~w(id version checked_on title conditions sources))
          |> Map.put("baseline", Map.take(p, @baseline))
      end

    if source do
      values =
        Map.new(@baseline, fn key -> {key, Map.fetch!(attrs, String.to_existing_atom(key))} end)
        |> Map.update!("mappings", & &1["lines"])

      Map.put(source, "customized", values != source["baseline"])
    end
  end

  def suggested_entries(preset, entries),
    do:
      Enum.filter(entries, fn entry ->
        token =
          entry["code"]
          |> String.split(~r/\s+[-–]\s+/, parts: 2)
          |> hd()
          |> String.trim()
          |> String.downcase()

        entry["active"] && token in Enum.map(preset["aliases"], &String.downcase/1)
      end)

  defp line(box, component), do: %{"box" => box, "component" => component, "sign" => 1}

  defp preset(
         id,
         title,
         aliases,
         direction,
         rate,
         deductible,
         mappings,
         conditions,
         sources,
         basis \\ "net"
       ) do
    %{
      "id" => id,
      "version" => @version,
      "checked_on" => @checked,
      "title" => title,
      "aliases" => aliases,
      "direction" => direction,
      "rate_bps" => rate,
      "deductible_bps" => deductible,
      "mappings" => mappings,
      "assessment_basis" => basis,
      "conditions" => conditions,
      "sources" => sources
    }
  end
end
