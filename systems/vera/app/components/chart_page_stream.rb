class Components::ChartPageStream < Components::Base
  register_element :turbo_stream
  def initialize(**options) = @options = options
  def view_template
    turbo_stream(action: "append", target: "coa-rows") do
      template do
        @options.fetch(:collection).each do |account|
          render Components::ChartRow.new(data: @options.fetch(:data), account: account, token: @options.fetch(:token), locked: !!@options[:check_url])
        end
      end
    end
    turbo_stream(action: "replace", target: "coa-pagination") do
      template { render Components::ChartPagination.new(data: @options.fetch(:data), collection: @options.fetch(:collection), query: @options.fetch(:query)) }
    end
  end
end
