Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.style_src :self
  policy.img_src :self, :data
  policy.script_src :none
  policy.connect_src :self
  policy.form_action :self
  policy.frame_ancestors :none
  policy.base_uri :self
end
