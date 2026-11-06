class Views::Recruitment::Received < Views::Base
  def initialize(**options)
    super(public_page: true, **options)
  end
  def view_template
    h1(class: "text-4xl font-semibold tracking-tight") { "Application received" }
    p(class: "mt-6 max-w-2xl leading-relaxed text-stone-600") { "Your application is pending review. No membership or role assignment has been granted. The recruitment team must review it and complete the relevant vouching and safeguarding steps." }
  end
end
