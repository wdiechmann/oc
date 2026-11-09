package dk.bankconnect.certificate;

import java.io.IOException;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.spec.InvalidKeySpecException;

import javax.jws.WebService;

import dk.bankconnect.security.BCKeyPair;
import dk.bankconnect.security.SecurityException;

/**
 * The interface KeyService.
 * 
 */
@WebService(targetNamespace = "http://service.bankconnect.dk")
public interface KeyService {

    /**
     * This method retrieves and returns a keypair.
     * 
     * @return The keypair
     * 
     * @throws SecurityException
     *             Security exception
     */
    public BCKeyPair getKeypair() throws SecurityException;

    /**
     * Gets the private key as a proper RSA key
     * 
     * @param privateKey
     *            as byte array
     * 
     * @return a privatekey - {@link java.security.PrivateKey}
     * 
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws InvalidKeySpecException
     *             The provided keypair has invalid specifications
     * @throws IOException
     *             I/O exception
     */
    public PrivateKey getPrivate(byte[] privateKey) throws IOException, NoSuchAlgorithmException,
            InvalidKeySpecException;

    /**
     * Gets the publickey as a proper RSA key
     * 
     * @param publicKey
     *            as byte array
     * 
     * @return a publickey - {@link java.security.PublicKey}
     * 
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws InvalidKeySpecException
     *             The provided keypair has invalid specifications
     * @throws IOException
     *             I/O exception
     */
    public PublicKey getPublic(byte[] publicKey) throws NoSuchAlgorithmException, InvalidKeySpecException, IOException;

}
