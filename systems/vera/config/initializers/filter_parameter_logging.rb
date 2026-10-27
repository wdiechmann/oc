# Never log arbitrary financial forms, tokens, identity data or provider payloads.
Rails.application.config.filter_parameters << /.*/
