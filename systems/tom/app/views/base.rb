class Views::Base < Components::Base
  include Phlex::Rails::Helpers::FormWith
  FIELD = "mt-2 block w-full rounded-lg border border-stone-300 bg-white px-4 py-3 text-base focus:border-emerald-700 focus:outline-2 focus:outline-emerald-700"
  BUTTON = "mt-5 cursor-pointer rounded-lg bg-emerald-900 px-5 py-3 text-sm font-semibold text-white transition hover:bg-emerald-800 focus:outline-2 focus:outline-offset-2 focus:outline-emerald-800"

  def initialize(signed_in: false, notice: nil, alert: nil, **)
    @layout = { signed_in: signed_in, notice: notice, alert: alert }
  end

  def around_template(&block)
    render Components::Layout.new(**@layout), &block
  end
end
