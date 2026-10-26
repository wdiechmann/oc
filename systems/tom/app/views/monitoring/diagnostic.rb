class Views::Monitoring::Diagnostic < Views::Base
  def initialize(data:, **options)
    super(**options)
    @data = data
  end
  def view_template
    h1(class: "text-3xl font-semibold") { "Restricted diagnostics" }
    p(class: "mt-3 font-mono text-sm") { @data.fetch("diagnostic").fetch("exception_class") }
    ol(class: "mt-6 space-y-3") do
      @data.fetch("diagnostic").fetch("frames").each do |frame|
        li(class: "break-words rounded-lg border border-stone-200 bg-white p-4 font-mono text-sm") { "#{frame['file']}:#{frame['line']} · #{frame['label']}" }
      end
    end
  end
end
