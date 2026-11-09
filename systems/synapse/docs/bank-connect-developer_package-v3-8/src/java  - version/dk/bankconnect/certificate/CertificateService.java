package dk.bankconnect.certificate;

import java.io.IOException;
import java.io.InputStream;
import java.security.InvalidKeyException;
import java.security.Key;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.NoSuchProviderException;
import java.security.SignatureException;
import java.security.UnrecoverableKeyException;
import java.security.cert.CertificateEncodingException;
import java.security.cert.CertificateException;
import java.security.cert.TrustAnchor;
import java.security.cert.X509Certificate;
import java.security.spec.InvalidKeySpecException;
import java.util.List;

import javax.jws.WebMethod;
import javax.jws.WebParam;
import javax.jws.WebService;

import org.bouncycastle.cert.CertIOException;
import org.bouncycastle.cert.crmf.CRMFException;
import org.bouncycastle.operator.OperatorCreationException;

import dk.bankconnect.security.BCKeyPair;
import dk.bankconnect.security.SecurityException;

/**
 * The Interface for the Bank Connect certificate functionality.
 * 
 */
@WebService(targetNamespace = "http://service.bankconnect.dk")
public interface CertificateService {

    public abstract byte[] createPKCS10Request(
            @WebParam(name = "functionIdentification") String functionIdentification,
            @WebParam(name = "activationCode") String activationCode, @WebParam(name = "publickey") String publicKey,
            @WebParam(name = "privatekey") String privateKey) throws SecurityException;

    public abstract byte[] getCertificate(String alias) throws KeyStoreException, NoSuchAlgorithmException,
            CertificateException, IOException;

    public abstract X509Certificate getCertificate(byte[] certificate) throws CertificateException;

    public abstract X509Certificate getCertificateFromKeystore(InputStream keystoreStream, String alias)
            throws KeyStoreException, NoSuchAlgorithmException, CertificateException, IOException;

    public abstract Key getKeyFromKeystore(InputStream keystoreStream, String alias) throws KeyStoreException,
            NoSuchAlgorithmException, CertificateException, IOException, UnrecoverableKeyException;

    public abstract String getCertificateRequestAsPEM(byte[] pkcs10) throws IOException, InvalidKeySpecException,
            NoSuchAlgorithmException, CRMFException;

    public abstract boolean validateEntityCertificate(byte[] certficate) throws CertificateException;

    @WebMethod(operationName = "validateCertificate")
    public abstract boolean validateEntityCertficate(String certificateAsPEM) throws CertificateEncodingException,
            IOException, CertificateException;

    public abstract List<X509Certificate> getCertificatesFromPEMString(String pemString) throws CertificateException;

    public abstract X509Certificate getEntityCertificate(List<X509Certificate> certificates)
            throws CertificateEncodingException, CertificateException, NoSuchProviderException;

    public abstract byte[] generateCACertificate(BCKeyPair bcKeyPair, String x500Name)
            throws OperatorCreationException, CertificateException, CertIOException, NoSuchAlgorithmException,
            InvalidKeySpecException, IOException;

    public abstract byte[] generateIACertificate(byte[] publicKey, byte[] privateSigningKey, byte[] caCertificate,
            String x500Name) throws InvalidKeyException, NoSuchProviderException, SignatureException, IOException,
            OperatorCreationException, CertificateException, NoSuchAlgorithmException, InvalidKeySpecException;

    public abstract String getCertificateInPEMFormat(byte[] certificate) throws IOException;

    public abstract BCKeyPair getCAKeyPair() throws SecurityException;

    public abstract byte[] generateCertificate(String customerIdentification, byte[] publicKey,
            byte[] privateSigningKey, byte[] intermidiateCertificate) throws InvalidKeyException,
            NoSuchProviderException, SignatureException, OperatorCreationException, CertificateException, IOException,
            NoSuchAlgorithmException, InvalidKeySpecException;

    public abstract boolean validateEntityCertificate(X509Certificate entityCertificate,
            List<X509Certificate> chainCertificates, List<TrustAnchor> trustedCertificates) throws SecurityException;

    public abstract List<X509Certificate> getIACertificates(List<X509Certificate> certificates)
            throws CertificateException, NoSuchProviderException;

    public abstract List<X509Certificate> getCACertificates(List<X509Certificate> certificates)
            throws CertificateException, NoSuchProviderException;

}