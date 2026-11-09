package dk.bankconnect.security;

import java.io.IOException;
import java.io.StringWriter;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.spec.InvalidKeySpecException;

import javax.xml.bind.annotation.XmlAccessType;
import javax.xml.bind.annotation.XmlAccessorType;
import javax.xml.bind.annotation.XmlTransient;

import org.bouncycastle.util.io.pem.PemObject;
import org.bouncycastle.util.io.pem.PemWriter;

import dk.bankconnect.certificate.KeyServiceImpl;

/**
 * BCKeyPair holds a private and publickey for Bank Connect. Contains methods for the different formats used throughout Bank Connect.
 * The class is jaxb'le.
 * 
 */
@XmlAccessorType(XmlAccessType.FIELD)
public class BCKeyPair {

     @XmlTransient
     private KeyServiceImpl keyService=new KeyServiceImpl();
    /**
     * Default constructor.
     * 
     * @param pubKey
     *            the public key
     * @param privKey
     *            the private key
     */
    public BCKeyPair(PublicKey pubKey, PrivateKey privKey) {
        publicKey = pubKey.getEncoded();
        privateKey = privKey.getEncoded();
    }

    private byte[] publicKey;
    private byte[] privateKey;

    /**
     * Gets the publickey
     * 
     * @return the publickey in standard DER format
     * 
     */
    public byte[] getPublicKey() {
        return publicKey;
    }
    
    /**
     * Sets the publickey (DER format)
     * 
     * @param publicKey
     */
    public void setPublicKey(byte[] publicKey) {
        this.publicKey = publicKey;
    }

    /**
     * Gets the privatekey
     * 
     * @return the privatekey in standard DER format
     */
    public byte[] getPrivateKey() {
        return privateKey;
    }

    /**
     * Set the privatekey
     * 
     * @param privateKey
     */
    public void setPrivateKey(byte[] privateKey) {
        this.privateKey = privateKey;
    }

    /**
     * Gets the privatekey as a proper RSA key
     * 
     * @return a private key - {@link java.security.PrivateKey}
     * 
     * @throws IOException
     *          I/O exception
     * @throws NoSuchAlgorithmException
     *          The encryption algorithm does not exist
     * @throws InvalidKeySpecException
     *          The provided keypair has invalid specifications
     */
    public PrivateKey getPrivate() throws IOException, NoSuchAlgorithmException, InvalidKeySpecException {
        return keyService.getPrivate(privateKey);
    }

    /**
     * Gets the publickey as a proper RSA key
     * 
     * @return a publickey - {@link java.security.PublicKey}
     * 
     * @throws NoSuchAlgorithmException
     *          The encryption algorithm does not exist
     * @throws InvalidKeySpecException
     *          The provided keypair has invalid specifications
     * @throws IOException
     *          I/O exception
     */
    public PublicKey getPublic() throws NoSuchAlgorithmException, InvalidKeySpecException, IOException {
        return keyService.getPublic(publicKey);
    }

    /**
     * Gets the private key in PKCS8 format in PEM format. Like: </br>
     * 
     * <pre>
     *  -----BEGIN RSA PRIVATE KEY-----
     *  MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCjklabPdWOoQX9
     *  ....yQIsfw5YyPwrbBoJuE0tJ1wT/bLNuJEOBK6yBsQLO6YK6o/Cza53GzN7TNfQHo1Q
     *  u+nF7ohtZyeJEgL03+rnaudP
     *  -----END RSA PRIVATE KEY-----
     * </pre>
     * 
     * @return The PKCS8 formated private key
     * @throws IOException
     *          I/O exception
     */
    public String getPrivateKeyAsPKCS8() throws IOException {
        PemObject pemObject=new PemObject( "RSA PRIVATE KEY",getPrivateKey());
        return getPEMString(pemObject);
    }
    
    /**
     * Gets the private key in PKCS1 format in PEM format. Like: </br>
     * 
     * <pre>
     *   -----BEGIN PUBLIC KEY-----
     *   MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAo5JWmz3VjqEF/dbY71A7
     *   .......
     *   lNB3zPC8rwmL/6CKrQcrnZcuUIPbXGVlio64uOtdQCuXu4WsYj7K11G2GvZ17vwv
     *   7QIDAQAB
     *   -----END PUBLIC KEY-----
     * </pre>
     * 
     * @return
     *          The PKCS1 formated public key
     *          
     * @throws NoSuchAlgorithmException
     *          The encryption algorithm does not exist
     * @throws InvalidKeySpecException
     *          The provided keypair has invalid specifications
     * @throws IOException
     *          I/O exception
     */
    public String getPublicKeyAsPKCS1() throws NoSuchAlgorithmException, InvalidKeySpecException, IOException {
        PemObject pemObject=new PemObject( "PUBLIC KEY",getPublicKey());
        return getPEMString(pemObject);
    }

    /**
     * Get string from PemObject.
     * 
     * @param pemObject
     *          The pem object
     *          
     * @return
     *          The string
     * @throws IOException
     *          I/O exception
     */
    private String getPEMString(PemObject pemObject) throws IOException {
        StringWriter stringWriter = new StringWriter();
        PemWriter pemWriter = new PemWriter(stringWriter);
        pemWriter.writeObject(pemObject);
        pemWriter.close();
        return stringWriter.toString();
    }
}
