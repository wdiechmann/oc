require "test_helper"

class ClientFoundationTest < ActionDispatch::IntegrationTest
  test "finance shell works independently of EP and loads local assets" do
    get "/"
    assert_response :success
    assert_select "title", "VERA · Financial Control"
    assert_select "h1", "A clear view of every book."
    assert_select "link[rel=stylesheet]"
    assert_not defined?(ActiveRecord::Base)
    assert_not_requested :get, "http://localhost:4000/health/ready"
  end

  test "EP dependency readiness is separate from application liveness" do
    get "/up"
    assert_response :success
    stub_request(:get, "http://localhost:4000/health/ready").to_return(status: 200, body: { status: "ready" }.to_json)
    get "/up/ep"
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    stub_request(:get, "http://localhost:4000/health/ready").to_timeout
    get "/up/ep"
    assert_response :service_unavailable
    assert_equal({ "status"=>"unavailable" }, response.parsed_body)
    get "/"
    assert_response :success
  end

  test "EP redirects are not followed" do
    stub_request(:get, "http://localhost:4000/health/ready").to_return(status: 302, headers: { "Location"=>"http://foreign.example.test/" })
    get "/up/ep"
    assert_response :service_unavailable
    assert_not_requested :get, "http://foreign.example.test/"
  end
  test "a malformed EP readiness body is unavailable, not an application exception" do
    stub_request(:get, "http://localhost:4000/health/ready").to_return(status: 200, body: "[]")
    get "/up/ep"
    assert_response :service_unavailable
  end

  test "EP origin cannot contain credentials or target an insecure remote server" do
    assert_raises(ArgumentError) { Ep::Client.new(origin: "http://user:secret@localhost:4000") }
    assert_raises(ArgumentError) { Ep::Client.new(origin: "http://remote.example.test") }
    assert_raises(ArgumentError) { Ep::Client.new(origin: "http://localhost:4000?token=secret") }
  end
end
