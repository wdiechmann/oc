Rails.application.config.session_store :cookie_store,
  key: "_vera_session", httponly: true, same_site: :lax,
  secure: Rails.env.production?, expire_after: 12.hours
