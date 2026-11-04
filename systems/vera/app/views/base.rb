class Views::Base < Components::Base
  include Phlex::Rails::Helpers::FormWith
  FIELD = "mt-2 block w-full rounded-lg border border-stone-300 bg-white px-4 py-3 text-base focus:outline-2 focus:outline-teal-800"
  BUTTON = "mt-5 cursor-pointer rounded-lg bg-teal-950 px-5 py-3 text-sm font-semibold text-white hover:bg-teal-800 focus:outline-2 focus:outline-offset-2 focus:outline-teal-800"
  def initialize(signed_in: false, notice: nil, alert: nil, full_width: false, **)
    @layout = { signed_in: signed_in, notice: notice, alert: alert, full_width: full_width }
  end
  def around_template(&block)
    render Components::Layout.new(**@layout), &block
  end
end
