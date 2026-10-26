class Components::Feedback < Components::Base
  def initialize(message:, reference: nil, outcome: nil, check_url: nil, operation_id: nil, sign_in: false)
    @message, @reference, @outcome, @check_url, @operation_id, @sign_in = message, reference, outcome, check_url, operation_id, sign_in
  end

  def view_template
    div(role: "status", class: "mb-6 break-words rounded-xl border border-amber-200 bg-amber-50 p-4 text-stone-900", data: { operation_id: @operation_id, outcome: @outcome, check_url: @check_url }) do
      p { @message }
      p(class: "mt-2 break-all font-mono text-xs") { "Reference: #{@reference}" } if @reference
      a(href: @check_url, class: "mt-3 inline-block font-semibold underline", data: { turbo_stream: true }) { "Check completion" } if @check_url
      a(href: new_session_path, class: "mt-3 inline-block font-semibold underline") { "Sign in again" } if @sign_in
    end
  end
end
