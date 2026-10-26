require "openssl"
require "base64"
require "securerandom"
module EpMonitor
  class Vault
    MAGIC = "EPMONB1\n".b
    def initialize(key)
      @key = Base64.strict_decode64(key)
      raise ArgumentError,"Invalid vault key" unless @key.bytesize == 32
    end
    def encrypt(input,output)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = @key
      nonce = SecureRandom.random_bytes(12); cipher.iv = nonce; cipher.auth_data = MAGIC
      write_private(output) do |file|
        file.write(MAGIC+nonce)
        File.open(input,"rb") do |source|
          while chunk = source.read(65_536)
            file.write(cipher.update(chunk))
          end
        end
        file.write(cipher.final); file.write(cipher.auth_tag)
      end
    end
    def decrypt(input,output)
      File.open(input,"rb") do |source|
        raise ArgumentError,"Invalid backup" unless source.read(MAGIC.bytesize) == MAGIC && source.size >= MAGIC.bytesize+28
        nonce = source.read(12)
        length = source.size-MAGIC.bytesize-28
        source.seek(-16,IO::SEEK_END); tag = source.read(16); source.seek(MAGIC.bytesize+12)
        cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
        cipher.key = @key; cipher.iv = nonce; cipher.auth_tag = tag; cipher.auth_data = MAGIC
        write_private(output) do |file|
          while length > 0
            chunk = source.read([length,65_536].min)
            raise ArgumentError,"Truncated backup" unless chunk
            file.write(cipher.update(chunk)); length -= chunk.bytesize
          end
          file.write(cipher.final)
        end
      end
    end
    private
    def write_private(output)
      raise ArgumentError,"Refusing to overwrite an existing artifact" if File.exist?(output)
      temp = output+".#{SecureRandom.uuid}.tmp"
      File.open(temp,File::WRONLY|File::CREAT|File::EXCL,0o600) { |f| f.binmode; yield f; f.flush; f.fsync }
      File.rename(temp,output)
    ensure
      File.unlink(temp) if temp && File.exist?(temp)
    end
  end
end
