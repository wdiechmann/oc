package dk.bankconnect.security;

import java.security.Key;
import java.security.NoSuchProviderException;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.cert.CertificateException;
import java.security.cert.TrustAnchor;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Properties;

import javax.security.auth.callback.CallbackHandler;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.ws.security.WSSecurityException;
import org.apache.ws.security.components.crypto.CryptoBase;
import org.apache.ws.security.components.crypto.CryptoType;

import dk.bankconnect.certificate.CertificateService;
import dk.bankconnect.certificate.CertificateServiceImpl;

/**
 * The BankConnectCrypto class.
 * 
 */
public class BankConnectCrypto extends CryptoBase {
    private Log logger = LogFactory.getFactory().getInstance(BankConnectCrypto.class);

    protected X509Certificate x509Certificate;
    protected PrivateKey privateKey;
    protected X509Certificate[] trustedCertificates = null;

    public BankConnectCrypto() {
        super();
    }

    /**
     * Constructor.
     * 
     * @param trustedCerts
     *            A list of trusted X509 certificates
     */
    public BankConnectCrypto(X509Certificate[] trustedCerts) {
        this.setTrustedCertificates(trustedCerts);
    }

    /**
     * Constructor.
     * 
     * @param p
     *            The properties
     * @param c
     *            The classloader
     */
    public BankConnectCrypto(Properties p, ClassLoader c) {
        logger.debug("Not implemented - BankConnectCrypto(Properties p, ClassLoader c)");
    }

    /**
     * Gets the private key. At the moment this method does not use either of
     * the provided parameters - instead it calls the
     * getPrivateKey(java.lang.String,java.lang.String) method.
     * 
     * @param paramX509Certificate
     *            The X509 certificate
     * @param paramCallbackHandler
     *            The callback handler
     * 
     * @see dk.bankconnect.security.BankConnectCrypto#getPrivateKey(java.lang.String,java.lang.String)
     */
    @Override
    public PrivateKey getPrivateKey(X509Certificate paramX509Certificate, CallbackHandler paramCallbackHandler)
            throws WSSecurityException {
        logger.debug("CallbackHandler not used - just returning single key");
        String s = null;
        return getPrivateKey(s, s);
    }

    @Override
    public PrivateKey getPrivateKey(String paramString1, String paramString2) throws WSSecurityException {
        logger.debug("Returning single privatekey");
        return privateKey;
    }

    @Override
    public X509Certificate[] getX509Certificates(CryptoType paramCryptoType) throws WSSecurityException {
        logger.debug("Returning single certificate");
        X509Certificate[] certs = new X509Certificate[] { x509Certificate };
        return certs;
    }

    @Override
    public String getX509Identifier(X509Certificate paramX509Certificate) throws WSSecurityException {
        logger.debug("Not implemented - getX509Identifier(X509Certificate paramX509Certificate)");
        return null;
    }

    @Override
    public boolean verifyTrust(X509Certificate[] paramArrayOfX509Certificate) throws WSSecurityException {
        boolean trustOk = true;
        if (trustedCertificates != null) {
            logger.debug("Validating entity certificate");
            trustOk = false;
            if (paramArrayOfX509Certificate.length > 0) {
                X509Certificate entityCertificate = paramArrayOfX509Certificate[0];
                try {
                    CertificateService certService = new CertificateServiceImpl();
                    logger.debug("Build a truststore with only CA's");
                    List<TrustAnchor> trustedAnchors = new ArrayList<TrustAnchor>();
                    List<X509Certificate> onlyCACerts = certService.getCACertificates(Arrays
                            .asList(trustedCertificates));
                    for (X509Certificate x509Certificate : onlyCACerts) {
                        trustedAnchors.add(new TrustAnchor(x509Certificate, null));
                    }
                    logger.debug("Build chain of certificates");
                    List<X509Certificate> iaCertificates = new ArrayList<X509Certificate>();
                    iaCertificates.add(entityCertificate);
                    iaCertificates.addAll(certService.getIACertificates(Arrays.asList(trustedCertificates)));

                    certService.validateEntityCertificate(entityCertificate, iaCertificates, trustedAnchors);
                    trustOk = true;
                } catch (SecurityException e) {
                    throw new WSSecurityException(e.getErrorMessage());
                } catch (CertificateException e) {
                    throw new WSSecurityException(e.getMessage());
                } catch (NoSuchProviderException e) {
                    throw new WSSecurityException(e.getMessage());
                }
            }
        }

        return trustOk;
    }

    @Override
    public boolean verifyTrust(PublicKey paramPublicKey) throws WSSecurityException {
        logger.debug("Not implemented - verifyTrust(PublicKey paramPublicKey)");
        return false;
    }

    @Override
    public boolean verifyTrust(X509Certificate[] paramArrayOfX509Certificate, boolean paramBoolean)
            throws WSSecurityException {
        return verifyTrust(paramArrayOfX509Certificate);
    }

    /**
     * Set the certificate.
     * 
     * @param certificate
     *            The certificate
     */
    public void setSingleCertificate(X509Certificate certificate) {
        x509Certificate = certificate;
    }

    /**
     * Set the key.
     * 
     * @param key
     *            The key
     */
    public void setSingleKey(Key key) {
        privateKey = (PrivateKey) key;
    }

    public void setTrustedCertificates(X509Certificate[] trustedCerts) {
        logger.debug("Setting trusted certificates");
        trustedCertificates = trustedCerts;
    }

}
