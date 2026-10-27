class Views::Base < Components::Base
  def around_template(&block)
    render Components::Layout.new, &block
  end
end
