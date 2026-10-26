require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/ep_monitor/vault"
class VaultTest < Minitest::Test
  def test_large_roundtrip_and_corrupt_ciphertext_never_publishes_plaintext
    Dir.mktmpdir("vault-test") do |dir|
      original = File.join(dir,"source")
      File.write(original,"private backup"*100_000)
      vault = EpMonitor::Vault.new(Base64.strict_encode64("x"*32))
      vault.encrypt(original,File.join(dir,"encrypted"))
      refute File.binread(File.join(dir,"encrypted")).include?("private backup")
      vault.decrypt(File.join(dir,"encrypted"),File.join(dir,"restored"))
      assert_equal File.binread(original),File.binread(File.join(dir,"restored"))
      File.open(File.join(dir,"encrypted"),"r+b") { |f| f.seek(-1,IO::SEEK_END); byte = f.read(1).getbyte(0); f.seek(-1,IO::SEEK_END); f.write((byte ^ 255).chr) }
      assert_raises(OpenSSL::Cipher::CipherError) { vault.decrypt(File.join(dir,"encrypted"),File.join(dir,"invalid")) }
      refute File.exist?(File.join(dir,"invalid"))
      assert File.exist?(original)
    end
  end
end
