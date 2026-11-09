package dk.bankconnect.security;

import org.w3c.dom.Document;

/**
 * Interface for Bank Connect made easy.
 * 
 * @author bdyaag
 *
 */
//@WebService(targetNamespace = "http://security.bankconnect.dk",name="SecurityService")
public interface SecurityService {

    /**
     * 
     * Generates a proper keypair suitable for Bank Connect. This requires
     * unlimited encryption strength.
     * 
     * @return The keypair
     * 
     * @see <a
     *      href="http://www.google.com/search?q=jce%20unlimited%20strength%20jurisdiction%20policy%20download"
     *      target="_blank">Search Google for policy files</a>
     * @see dk.bankconnect.security.SecurityService#getKeypair()
     */
    public BCKeyPair getKeypair() throws SecurityException;
//    public String wrapSoapMessageAsString(String xmlDocument, byte[] certificate,  byte[] privateKey, byte[] encryptionCertificate) throws SecurityException;
    
    /**
     * Wraps the xml document. I.e. secure the soap message;
     * encryption and header signing.
     * 
     * @param xmlDocument
     *          The xml document to wrap
     * @param certificate
     *          The signing certificate to use
     * @param privateKey
     *          The private key to use
     * @param encryptionCertificate
     *          The encryption certificate to use
     *          
     * @return The wrapped document
     * 
     * @throws SecurityException
     *          Security exception
     */
    public Document wrapSoapMessage(Document xmlDocument, byte[] certificate,  byte[] privateKey, byte[] encryptionCertificate) throws SecurityException;
//    public String unwrapSOAPMessageAsString(String soapMessage, byte[] privateKey) throws SecurityException;
    
    /**
     * 
     * UnWraps and validate the secure Bank Connect soapMessage.
     * 
     * @param soapMessage
     *          The message to unwrap
     * @param privateKey
     *          The private key to use
     *          
     * @throws SecurityException
     *          Security exception
     * 
     */
    public Document unwrapSOAPMessage(Document soapMessage, byte[] privateKey) throws SecurityException;
    
    /**
     * Validates a PKCS10 formated request. I.e. validate if the public key
     * and activation code is valid.
     * 
     * @param pkcs10Request
     *          The request to validate
     *          
     * @throws SecurityException
     *          if PKCS10 is not valid
     */
    public abstract void validatePKCS10Request(byte[] pkcs10Request) throws SecurityException;
    
    /**
     * Returns a PEM encoded PKCS10 request. The Common Name (CN) is set to
     * functionid@activationcode. 
     * 
     * @param activationCode The activationcode from the bank received by the
     * customer
     * 
     * @param publicKey
     *          A valid RSA based public key in PEM format
     * 
     * @param privateKey
     *          A valid RSA private key used for signing in PEM format
     * 
     * @return PEM encode PKCS10 request
     * 
     * @throws SecurityException
     */
    public abstract byte[] createPKCS10Request(String functionIdentification, String activationCode, String publicKey, String privateKey)
            throws SecurityException;
}
