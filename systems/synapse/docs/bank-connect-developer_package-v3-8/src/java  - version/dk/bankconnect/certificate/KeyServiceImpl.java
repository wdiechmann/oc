package dk.bankconnect.certificate;

import java.io.IOException;
import java.security.KeyFactory;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.spec.InvalidKeySpecException;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;

import javax.jws.WebMethod;
import javax.jws.WebService;
import javax.jws.soap.SOAPBinding;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import dk.bankconnect.security.BCKeyPair;
import dk.bankconnect.security.SecurityException;
import dk.bankconnect.security.SecurityService;
import dk.bankconnect.security.SecurityServiceImpl;
import dk.bankconnect.server.config.Constants;

/**
 * The class KeyServiceImpl.
 * 
 */
@WebService(serviceName = "KeyService", targetNamespace = "http://service.bankconnect.dk", portName = "KeyServicePort", name = "BankConnect")
@SOAPBinding(style = SOAPBinding.Style.RPC, parameterStyle = SOAPBinding.ParameterStyle.WRAPPED)
public class KeyServiceImpl implements KeyService {
    private Log logger = LogFactory.getFactory().getInstance(KeyServiceImpl.class);

    /**
     * Gets the publickey as a proper RSA key
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
    @Override
    @WebMethod(exclude = true)
    public PublicKey getPublic(byte[] publicKey) throws NoSuchAlgorithmException, InvalidKeySpecException, IOException {
        PublicKey generatedPublicKey = null;
        if (publicKey != null) {
            KeyFactory kf=KeyFactory.getInstance(Constants.KEY_ALGORITHM);
            X509EncodedKeySpec keySpec=new X509EncodedKeySpec(publicKey);
            generatedPublicKey = kf.generatePublic(keySpec);
        }
        return generatedPublicKey;
    }

    /**
     * Gets the private key as a proper RSA key
     * 
     * @param privateKey
     * 
     * @return a privatekey - {@link java.security.PrivateKey}
     * 
     * @throws IOException
     *             I/O exception
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws InvalidKeySpecException
     *             The provided keypair has invalid specifications
     */
    @Override
    @WebMethod(exclude = true)
    public PrivateKey getPrivate(byte[] privateKey) throws IOException, NoSuchAlgorithmException,
            InvalidKeySpecException {
        PrivateKey generatedPrivateKey = null;
        if (privateKey != null) {
            PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(privateKey);
            KeyFactory kf = KeyFactory.getInstance(Constants.KEY_ALGORITHM);
            generatedPrivateKey = kf.generatePrivate(keySpec);
            
        }
        return generatedPrivateKey;
    }

    /**
     * Retrieves the keypair.
     * 
     * @return The keypair
     * 
     * @throws SecurityException
     *             Security exception
     */
    @Override
    @WebMethod
    public BCKeyPair getKeypair() throws SecurityException {
        SecurityService se = new SecurityServiceImpl();
        return se.getKeypair();
    }
}
