package dk.bankconnect.certificate;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.io.StringReader;
import java.io.StringWriter;
import java.math.BigInteger;
import java.security.InvalidAlgorithmParameterException;
import java.security.InvalidKeyException;
import java.security.Key;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.NoSuchProviderException;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.Security;
import java.security.SignatureException;
import java.security.UnrecoverableKeyException;
import java.security.cert.CertPathBuilder;
import java.security.cert.CertPathBuilderException;
import java.security.cert.CertPathValidatorException;
import java.security.cert.CertStore;
import java.security.cert.CertificateEncodingException;
import java.security.cert.CertificateException;
import java.security.cert.CertificateFactory;
import java.security.cert.CollectionCertStoreParameters;
import java.security.cert.PKIXBuilderParameters;
import java.security.cert.PKIXCertPathBuilderResult;
import java.security.cert.PKIXCertPathChecker;
import java.security.cert.PKIXParameters;
import java.security.cert.TrustAnchor;
import java.security.cert.X509CertSelector;
import java.security.cert.X509Certificate;
import java.security.interfaces.RSAPrivateCrtKey;
import java.security.spec.InvalidKeySpecException;
import java.util.ArrayList;
import java.util.Date;
import java.util.Enumeration;
import java.util.GregorianCalendar;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;

import javax.jws.WebMethod;
import javax.jws.WebService;
import javax.jws.soap.SOAPBinding;
import javax.security.auth.x500.X500Principal;
import javax.xml.bind.DatatypeConverter;

import org.apache.commons.lang.StringUtils;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.bouncycastle.asn1.ASN1Sequence;
import org.bouncycastle.asn1.x509.BasicConstraints;
import org.bouncycastle.asn1.x509.Extension;
import org.bouncycastle.asn1.x509.KeyUsage;
import org.bouncycastle.asn1.x509.SubjectPublicKeyInfo;
import org.bouncycastle.cert.CertIOException;
import org.bouncycastle.cert.X509CertificateHolder;
import org.bouncycastle.cert.X509v3CertificateBuilder;
import org.bouncycastle.cert.crmf.CRMFException;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509ExtensionUtils;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.OperatorCreationException;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;
import org.bouncycastle.pkcs.PKCS10CertificationRequest;
import org.bouncycastle.util.io.pem.PemObject;
import org.bouncycastle.util.io.pem.PemReader;
import org.bouncycastle.util.io.pem.PemWriter;

import dk.bankconnect.BankConnectConstants;
import dk.bankconnect.security.BCKeyPair;
import dk.bankconnect.security.SecurityException;
import dk.bankconnect.security.SecurityService;
import dk.bankconnect.security.SecurityServiceImpl;
import dk.bankconnect.server.config.Constants;

/**
 * Implementation of the Bank Connect certificate functionality. The majority of
 * operations are available as a webservice - <a
 * href="http://localhost:8080/bankconnect/services"
 * target="_blank">http://localhost:8080/bankconnect/services</a>
 * 
 * This includes
 * <ul>
 * <li>Creating a proper PKCS10 request</li>
 * <li>Generation of CA, IA and entitycertificates</li>
 * <li>Validation of certificates</li>
 * <li>Getting certificates and keys from keystore</li>
 * <li>Converting to/from PEM</li>
 * </ul>
 * 
 * @author bdyaag
 */
@WebService(serviceName = "CertificateService", targetNamespace = "http://service.bankconnect.dk", portName = "CertificateServicePort", name = "BankConnect")
@SOAPBinding(style = SOAPBinding.Style.RPC, parameterStyle = SOAPBinding.ParameterStyle.WRAPPED)
public class CertificateServiceImpl implements CertificateService {

    /** The logger. */
    private Log logger = LogFactory.getFactory().getInstance(CertificateServiceImpl.class);

    /** Alias for Bank Connect intermidiate certificate */
    private final String BANK_IA_CERT = "bank connect ia-test";

    /** The key service. */
    private KeyService keyService;

    /**
     * Instantiates a new certificate service - initializing BouncyCastle as
     * security provider.
     */
    public CertificateServiceImpl() {
        Security.addProvider(new BouncyCastleProvider());
        keyService = new KeyServiceImpl();
    }

    /**
     * Wraps a PKCS10 DEC encoded bytearray to PEM format.
     * 
     * @param pkcs10
     *            - DER encoded bytearray
     * @return String - PEM encoded string
     */
    @WebMethod
    public String getCertificateRequestAsPEM(byte[] pkcs10) throws IOException, InvalidKeySpecException,
            NoSuchAlgorithmException, CRMFException {
        PKCS10CertificationRequest p = new PKCS10CertificationRequest(pkcs10);
        String pstring = getPEMString(new PemObject("CERTIFICATE REQUEST", p.getEncoded()));
        return pstring;
    }

    /**
     * Generates a valid CA Bank Connect certificate.
     * 
     * @param bcKeyPair
     *            - public and private keys wrapped in keypair
     * @param x500Name
     *            - X500Name string - like
     *            "CN=Bank Connect CA-test,OU=Bank Connect,O=Bank Connect,C=DK"
     * 
     * @return DER encoded X.509 certificate
     * 
     * @see dk.bankconnect.certificate.CertificateService#generateCACertificate(dk.bankconnect.security.BCKeyPair, String)
     */
    @WebMethod
    public byte[] generateCACertificate(BCKeyPair bcKeyPair, String x500Name) throws OperatorCreationException,
            CertificateException, CertIOException, NoSuchAlgorithmException, InvalidKeySpecException, IOException {
        X500Principal issuer = new X500Principal(x500Name);
        X500Principal subject = new X500Principal(x500Name);

        Date startDate = new Date(System.currentTimeMillis());
        GregorianCalendar gc = new GregorianCalendar();
        gc.setGregorianChange(startDate);
        gc.add(GregorianCalendar.YEAR, 30);
        Date endDate = gc.getTime();

        X509v3CertificateBuilder certBldr = new JcaX509v3CertificateBuilder(issuer, BigInteger.valueOf(0), startDate,
                endDate, subject, bcKeyPair.getPublic());
        JcaX509ExtensionUtils extUtils = new JcaX509ExtensionUtils();

        certBldr.addExtension(Extension.subjectKeyIdentifier, false,
                extUtils.createSubjectKeyIdentifier(bcKeyPair.getPublic()))
                .addExtension(Extension.basicConstraints, true, new BasicConstraints(true))
                .addExtension(Extension.keyUsage, true, new KeyUsage(KeyUsage.keyCertSign));

        ContentSigner signer = new JcaContentSignerBuilder("SHA256WITHRSA").setProvider(Constants.JCE_PROVIDER).build(
                bcKeyPair.getPrivate());
        X509Certificate x509Certificate = new JcaX509CertificateConverter().setProvider(Constants.JCE_PROVIDER)
                .getCertificate(certBldr.build(signer));

        return x509Certificate.getEncoded();

    }

    /**
     * Gets the CA Bank Connect certificate either from keystore or generated.
     * 
     * @param alias
     *            - the alias used to lookup in keystore or applied to CN
     * @param caKeyPair
     *            - a keypair - if null load the certificate from default
     *            keystore
     * @return the CA certificate - DER encoded
     * 
     * @throws CertificateEncodingException
     *             the certificate encoding exception
     * @throws KeyStoreException
     *             the key store exception
     * @throws NoSuchAlgorithmException
     *             the no such algorithm exception
     * @throws CertificateException
     *             the certificate exception
     * @throws IOException
     *             Signals that an I/O exception has occurred.
     * @throws OperatorCreationException
     *             the operator creation exception
     * @throws InvalidKeySpecException
     *             the invalid key spec exception
     */
    @WebMethod
    public byte[] getCACertificate(String alias, BCKeyPair caKeyPair) throws CertificateEncodingException,
            KeyStoreException, NoSuchAlgorithmException, CertificateException, IOException, OperatorCreationException,
            InvalidKeySpecException {

        byte[] certificate = null;
        if (caKeyPair == null) {
            certificate = getCertificateFromKeystore(null, alias).getEncoded();
        } else {
            certificate = generateCACertificate(caKeyPair, "CN=" + alias);
        }
        return certificate;

    }

    /**
     * Generates a valid intermidiate Bank Connect certificate.
     * 
     * @param publicKey
     *            - the publickey part of the generated keypair
     * @param privateSigningKey
     *            - the key used to create the certificate signature
     * @param caCertificate
     *            - the CA certificate used as authority
     * @param x500Name
     *            - X500Name string - like
     *            "CN=Bank Connect IA-test,OU=Bank Connect,O=Bank Connect,C=DK"
     * 
     * @return DER encoded X.509 certificate
     * 
     */
    @WebMethod
    public byte[] generateIACertificate(byte[] publicKey, byte[] privateSigningKey, byte[] caCertificate,
            String x500Name) throws InvalidKeyException, NoSuchProviderException, SignatureException, IOException,
            OperatorCreationException, CertificateException, NoSuchAlgorithmException, InvalidKeySpecException {
        X509Certificate caCert = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(
                new ByteArrayInputStream(caCertificate));
        PublicKey key = keyService.getPublic(publicKey);
        SubjectPublicKeyInfo spki = SubjectPublicKeyInfo.getInstance(ASN1Sequence.getInstance(key.getEncoded()));

        Date startDate = new Date();
        GregorianCalendar gc = new GregorianCalendar();
        gc.setGregorianChange(startDate);
        gc.add(GregorianCalendar.YEAR, 10);
        Date endDate = gc.getTime();

        X500Principal iaPrincipal = new X500Principal(x500Name);
        X509v3CertificateBuilder certBuilder = new JcaX509v3CertificateBuilder(caCert.getSubjectX500Principal(),
                BigInteger.valueOf(new Date().getTime()), startDate, endDate, iaPrincipal, key);

        JcaX509ExtensionUtils extUtils = new JcaX509ExtensionUtils();
        certBuilder
                .addExtension(Extension.authorityKeyIdentifier, false,
                        extUtils.createAuthorityKeyIdentifier(caCert.getPublicKey()))
                .addExtension(Extension.basicConstraints, true, new BasicConstraints(true))
                .addExtension(Extension.subjectKeyIdentifier, false, extUtils.createSubjectKeyIdentifier(spki))
                .addExtension(Extension.keyUsage, true, new KeyUsage(KeyUsage.digitalSignature | KeyUsage.keyCertSign));
        PrivateKey privKey = keyService.getPrivate(privateSigningKey);
        ContentSigner signer = new JcaContentSignerBuilder("SHA256WITHRSA").setProvider(Constants.JCE_PROVIDER).build(
                privKey);
        X509CertificateHolder cert = certBuilder.build(signer);
        return cert.getEncoded();
    }

    /**
     * Generates a valid entity Bank Connect certificate - e.g a customer
     * certificate.
     * 
     * @param publicKey
     *            - the publickey part of the generated keypair
     * @param privateSigningKey
     *            - the key used to create the certificate signature
     * @param intermidiateCertificate
     *            - the IA certificate used as authority
     * @param customerIdentification
     *            - String used for commonname - like "CN=erp-xyz" - "CN=" will
     *            be prefixed
     * 
     * @return DER encoded X.509 certificate
     * 
     * @see dk.bankconnect.certificate.CertificateService#generateCertificate(String, byte[], byte[], byte[])
     */
    @Override
    @WebMethod
    public byte[] generateCertificate(String customerIdentification, byte[] publicKey, byte[] privateSigningKey,
            byte[] intermidiateCertificate) throws InvalidKeyException, NoSuchProviderException, SignatureException,
            OperatorCreationException, CertificateException, IOException, NoSuchAlgorithmException,
            InvalidKeySpecException {

        X509Certificate iaCertificate = null;
        if (intermidiateCertificate == null) {
            try {
                iaCertificate = getCertificateFromKeystore(null, BANK_IA_CERT);
            } catch (KeyStoreException e) {
                logger.error("No intermediate certificate supplied or found in keystore");
                return null;
            }
        } else {
            iaCertificate = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(
                    new ByteArrayInputStream(intermidiateCertificate));
        }
        PublicKey pubKey = keyService.getPublic(publicKey);
        if (publicKey == null) {
            logger.error("No valid publickey supplied");
            return null;
        }

        PrivateKey privKey = keyService.getPrivate(privateSigningKey);
        Date startDate = new Date();
        GregorianCalendar gc = new GregorianCalendar();
        gc.setGregorianChange(startDate);
        gc.add(GregorianCalendar.YEAR, 3);
        Date endDate = gc.getTime();
        SubjectPublicKeyInfo spki = SubjectPublicKeyInfo.getInstance(ASN1Sequence.getInstance(pubKey.getEncoded()));
        X500Principal ePrincipal = new X500Principal("CN=" + customerIdentification);
        X509v3CertificateBuilder certBldr = new JcaX509v3CertificateBuilder(iaCertificate.getSubjectX500Principal(),
                BigInteger.valueOf(startDate.getTime()), startDate, endDate, ePrincipal, pubKey);

        JcaX509ExtensionUtils extUtils = new JcaX509ExtensionUtils();
        certBldr.addExtension(Extension.authorityKeyIdentifier, false,
                extUtils.createAuthorityKeyIdentifier(iaCertificate.getPublicKey())).addExtension(
                Extension.subjectKeyIdentifier, false, extUtils.createSubjectKeyIdentifier(spki));

        ContentSigner signer = new JcaContentSignerBuilder("SHA256WITHRSA").setProvider(Constants.JCE_PROVIDER).build(
                privKey);
        X509CertificateHolder x509CertificateHolder = certBldr.build(signer);
        return x509CertificateHolder.getEncoded();
    }

    /**
     * Fetches and returns a X509 certificate from keystore. "bankconnect.jks"
     * is default. Password to keystore must be "bankconnect". This method is
     * not available in the webservice.
     * 
     * @param keystoreStream
     *            inputstream to keystore - if null default is used
     * @param alias
     *            certificate alias
     * 
     * @return {@link X509Certificate}
     * 
     * @see dk.bankconnect.certificate.CertificateService#getCertificateFromKeystore(java.io.InputStream,
     *      java.lang.String)
     */
    @WebMethod(exclude = true)
    public X509Certificate getCertificateFromKeystore(InputStream keystoreStream, String alias)
            throws KeyStoreException, NoSuchAlgorithmException, CertificateException, IOException {

        if (keystoreStream == null) {
            logger.debug("Fetching alias " + alias + " from bankconnect.jks");
            keystoreStream = this.getClass().getClassLoader().getResourceAsStream("bankconnect.jks");
        }

        KeyStore keystore = KeyStore.getInstance(KeyStore.getDefaultType());
        String password = "bankconnect";
        keystore.load(keystoreStream, password.toCharArray());
        X509Certificate certificate = (X509Certificate) keystore.getCertificate(alias);
        if (certificate == null) {
            Enumeration<String> aliases = keystore.aliases();
            while (aliases.hasMoreElements()) {
                String a = (String) aliases.nextElement();
                logger.debug("Certificate found: " + a);
            }
            throw new NullPointerException("Certificate alias " + alias + " not found");
        }
        return certificate;
    }

    /**
     * Fetches and returns a private key from keystore. "bankconnect.jks" is
     * default. Password to keystore must be "bankconnect". This method is not
     * available in the webservice.
     * 
     * @param keystoreStream
     *            inputstream to keystore - if null default is used
     * @param alias
     *            key alias
     * 
     * @return {@link Key}
     * 
     * @see dk.bankconnect.certificate.CertificateService#getKeyFromKeystore(java.io.InputStream,
     *      java.lang.String)
     */
    @WebMethod(exclude = true)
    public Key getKeyFromKeystore(InputStream keystoreStream, String alias) throws KeyStoreException,
            NoSuchAlgorithmException, CertificateException, IOException, UnrecoverableKeyException {

        if (keystoreStream == null) {
            logger.debug("Fetching alias " + alias + " from bankconnect.jks");
            keystoreStream = this.getClass().getClassLoader().getResourceAsStream("bankconnect.jks");
        }

        KeyStore keystore = KeyStore.getInstance(KeyStore.getDefaultType());
        String password = "bankconnect";
        keystore.load(keystoreStream, password.toCharArray());
        RSAPrivateCrtKey key = (RSAPrivateCrtKey) keystore.getKey(alias, password.toCharArray());

        if (key == null) {
            Enumeration<String> aliases = keystore.aliases();
            while (aliases.hasMoreElements()) {
                String a = (String) aliases.nextElement();
                logger.debug("Aliases found: " + a);
            }
            throw new NullPointerException("Key alias " + alias + " not found");
        }
        return key;
    }

    /**
     * Gets a certificate from default keystore
     * 
     * @see dk.bankconnect.certificate.CertificateService#getCertificate(java.lang.String)
     */
    @WebMethod
    public byte[] getCertificate(String alias) throws KeyStoreException, NoSuchAlgorithmException,
            CertificateException, IOException {
        return getCertificateFromKeystore(null, alias).getEncoded();
    }

    /**
     * Generate and return a valid keypair for use to generate CA certificates
     * 
     * @return private and public keys wrapped in keypair
     * 
     * @see dk.bankconnect.certificate.CertificateService#getCAKeyPair()
     */
    @Override
    public BCKeyPair getCAKeyPair() throws SecurityException {

        KeyPair generateKeyPair = null;
        try {
            KeyPairGenerator kpGen = KeyPairGenerator.getInstance(Constants.KEY_ALGORITHM, Constants.JCE_PROVIDER);
            kpGen.initialize(4096, new SecureRandom());
            generateKeyPair = kpGen.generateKeyPair();
        } catch (Exception e) {
            SecurityException se = new SecurityException(e);
            se.setErrorcode(BankConnectConstants.INTERNAL_SERVER);
            throw se;
        }
        BCKeyPair kp = new BCKeyPair(generateKeyPair.getPublic(), generateKeyPair.getPrivate());
        return kp;

    }

    /**
     * Instantiate and returns X.509 certificate
     * 
     * @param certificate
     *            a DER encoded certificate
     * 
     * @see dk.bankconnect.certificate.CertificateService#getCertificate(byte[])
     */
    @Override
    @WebMethod(exclude = true)
    public X509Certificate getCertificate(byte[] certificate) throws CertificateException {
        if (certificate != null) {
            CertificateFactory cf = CertificateFactory.getInstance("x.509");
            InputStream inStream = new ByteArrayInputStream(certificate);
            return (X509Certificate) cf.generateCertificate(inStream);
        }
        return null;
    }

    /**
     * Gets a PEM string. Encoding is based on OpenSSL, available at openssl.org
     * – see <a href="https://www.openssl.org/docs/crypto/pem.html"
     * target="_blank">https://www.openssl.org/docs/crypto/pem.html</a>.
     * 
     * @param pemObject
     *            a PEM object
     * @return the PEM string
     * @throws IOException
     *             Signals that an I/O exception has occurred.
     */
    private String getPEMString(PemObject pemObject) throws IOException {
        StringWriter stringWriter = new StringWriter();
        PemWriter pemWriter = new PemWriter(stringWriter);
        pemWriter.writeObject(pemObject);
        pemWriter.close();
        return stringWriter.toString();
    }

    /**
     * Create and return a Bank Connect DER encoded PKCS10 CSR. Commonname has a
     * pattern like -
     * "CN=functionIdentification@activationCode,OU=Bank Connect,O=Bank Connect,L=DK,ST=DK,C=DK"
     * ;
     * 
     * @param functionIdentification
     *            functionIdentification first part of commonname
     * @param activationCode
     *            the activationcode second part of commonname
     * @param publicKey
     *            publickey to be embedded in the final customer certificate
     * @param privateKey
     *            privatekey for signing purpose
     * 
     * {@link CertificateService CertificateService}
     */
    @WebMethod
    public byte[] createPKCS10Request(String functionIdentification, String activationCode, String publicKey,
            String privateKey) throws SecurityException {

        SecurityService securityService = new SecurityServiceImpl();
        return securityService.createPKCS10Request(functionIdentification, activationCode, publicKey, privateKey);
    }

    /**
     * Validates a X.509 certificate using the rules from certificate policy.
     * 
     * @param certificate
     *            X.509 certificate to be checked
     * 
     * @return true if certificate is valid
     * 
     * {@link BankConnectCertPathChecker BankConnectCertPathChecker} 
     * {@link CertificateService CertificateService}
     */
    @WebMethod
    public boolean validateEntityCertificate(byte[] certificate) throws CertificateException {
        InputStream inStream = new ByteArrayInputStream(certificate);
        X509Certificate currentCertificate = (X509Certificate) CertificateFactory.getInstance("X.509")
                .generateCertificate(inStream);
        logger.debug("Certificate read from byte array");
        BankConnectCertPathChecker checker = new BankConnectCertPathChecker();
        try {
            logger.debug("Certificate check started");
            checker.check(currentCertificate, null);
        } catch (CertPathValidatorException e) {
            return false;
        }
        return true;
    }

    /**
     * Validate an entity certificate.
     * 
     * @param entityCertificate
     *            the X.509 certificate to be checked
     * @param chainCertificates
     *            a list of X.509 certificates to be a part of a
     *            certificatechain
     * @param trustedCertificates
     *            trusted certificates - if null cacerts is loaded
     * @return true, if successful
     */
    @Override
    @WebMethod(exclude = true)
    public boolean validateEntityCertificate(X509Certificate entityCertificate,
            List<X509Certificate> chainCertificates, List<TrustAnchor> trustedCertificates) throws SecurityException {
        boolean certificateOk = false;
        try {
            if (trustedCertificates == null) {
                trustedCertificates = new ArrayList<TrustAnchor>();
                String filename = System.getProperty("java.home")
                        + "/lib/security/cacerts".replace('/', File.separatorChar);
                logger.debug("Loading trusted certificates from file: " + filename);
                FileInputStream is;

                is = new FileInputStream(filename);
                KeyStore keystore = KeyStore.getInstance(KeyStore.getDefaultType());
                String password = "changeit";
                keystore.load(is, password.toCharArray());

                // This class retrieves the most-trusted CAs from the keystore
                PKIXParameters params = new PKIXParameters(keystore);
                Iterator it = params.getTrustAnchors().iterator();
                while (it.hasNext()) {
                    TrustAnchor ta = (TrustAnchor) it.next();
                    logger.debug("Loading CA: " + ta.getTrustedCert().getSubjectX500Principal());
                    trustedCertificates.add(ta);
                }
            }
            logger.debug("Validating entitycertificate " + entityCertificate.getSubjectX500Principal());
            X509CertSelector xcs = new X509CertSelector();
            xcs.setCertificate(entityCertificate);
            
            PKIXBuilderParameters params = new PKIXBuilderParameters(new HashSet<TrustAnchor>(trustedCertificates), xcs);
            params.setRevocationEnabled(false);
            PKIXCertPathChecker checker = new BankConnectCertPathChecker();
            params.addCertPathChecker(checker);
            CertStore intermediateCertStore = CertStore.getInstance("Collection", new CollectionCertStoreParameters(
                    chainCertificates));
            params.addCertStore(intermediateCertStore);

            // Build and verify the certification chain
            CertPathBuilder builder = CertPathBuilder.getInstance("PKIX");
            PKIXCertPathBuilderResult result = (PKIXCertPathBuilderResult) builder.build(params);
            certificateOk = (result.getCertPath() != null);
        } catch (FileNotFoundException e) {
            SecurityException se = new SecurityException(e);
            se.setErrorcode(BankConnectConstants.INTERNAL_SERVER);
            logger.error(se);
            throw se;
        } catch (KeyStoreException e) {
            SecurityException se = new SecurityException(e);
            se.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            logger.error(se);
            throw se;
        } catch (NoSuchAlgorithmException e) {
            SecurityException se = new SecurityException(e);
            se.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            logger.error(se);
            throw se;
        } catch (CertificateException e) {
            SecurityException se = new SecurityException(e);
            se.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            logger.error(se);
            throw se;
        } catch (IOException e) {
            SecurityException se = new SecurityException(e);
            se.setErrorcode(BankConnectConstants.INTERNAL_SERVER);
            logger.error(se);
            throw se;
        } catch (InvalidAlgorithmParameterException e) {
            SecurityException se = new SecurityException(e);
            se.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            logger.error(se);
            throw se;
        } catch (CertPathBuilderException e) {
            SecurityException se = new SecurityException(e);
            se.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            logger.error(se);
            throw se;
        }
        return true;
    }

    /**
     * Validates PEM encoded certificate using the rules from certificate
     * policy.
     * 
     * @param certificateAsPEM
     *            PEM string containing certificate
     * 
     * @return true if certificate is valid
     * 
     * {@link BankConnectCertPathChecker} , {@link CertificateService}
     */
    @WebMethod
    public boolean validateEntityCertficate(String certificateAsPEM) throws IOException, CertificateException {
        PemReader pubPemReader = new PemReader(new StringReader(certificateAsPEM));
        PemObject pubPemObject = pubPemReader.readPemObject();
        return validateEntityCertificate(pubPemObject.getContent());
    }

    /**
     * 
     * Returns the certificate without basic constraints from the list.
     * 
     * @param certificates
     *            list of X.509 certificates
     * @return X509Certificate the first certificate without basic contraints
     * 
     * @throws CertificateException
     *             not a valid X.509 certificate
     * @throws NoSuchProviderException
     *             no security provider
     * 
     * 
     * @see dk.bankconnect.certificate.CertificateService#getEntityCertificate(java.util.List)
     * @see X509CertSelector#getBasicConstraints() the valid return values to
     *      identify an entity certificate
     */
    @WebMethod
    public X509Certificate getEntityCertificate(List<X509Certificate> certificates) throws CertificateException,
            NoSuchProviderException {

        for (Iterator<X509Certificate> iterator = certificates.iterator(); iterator.hasNext();) {
            X509Certificate x509Certificate = (X509Certificate) iterator.next();
            if (x509Certificate.getBasicConstraints() < 0) {
                return x509Certificate;
            }
        }
        return null;
    }

    /**
     * 
     * Returns a list of certificates with basic constraints and and issuer from
     * the list.
     * 
     * @param certificates
     *            list of X.509 certificates
     * @return X509Certificate list of certificates with basic contraints
     * 
     * @throws CertificateException
     *             not a valid X.509 certificate
     * @throws NoSuchProviderException
     *             no security provider
     * 
     * 
     * @see dk.bankconnect.certificate.CertificateService#getEntityCertificate(java.util.List)
     * @see X509CertSelector#getBasicConstraints() the valid return values to
     *      identify an entity certificate
     */
    @Override
    @WebMethod
    public List<X509Certificate> getIACertificates(List<X509Certificate> certificates) throws CertificateException,
            NoSuchProviderException {
        List<X509Certificate> iaCerts = new ArrayList<X509Certificate>();
        try {
            for (Iterator<X509Certificate> iterator = certificates.iterator(); iterator.hasNext();) {
                X509Certificate x509Certificate = (X509Certificate) iterator.next();
                X509CertificateHolder x509CertificateHolder = new X509CertificateHolder(x509Certificate.getEncoded());
                if ((x509Certificate.getBasicConstraints() != -1)
                        && (x509CertificateHolder.getExtension(Extension.authorityKeyIdentifier) != null)) {
                    logger.debug("Adding IA certificate " + x509Certificate.getSubjectX500Principal());
                    iaCerts.add(x509Certificate);
                }
            }
        } catch (IOException e) {
            throw new CertificateException(e);
        }
        return iaCerts;
    }

    /**
     * 
     * Returns a list of certificates with basic constraints and and NO issuer
     * from the list.
     * 
     * @param certificates
     *            list of X.509 certificates
     * @return X509Certificate list of certificates with basic contraints and no
     *         issuer
     * 
     * @throws CertificateException
     *             not a valid X.509 certificate
     * @throws NoSuchProviderException
     *             no security provider
     * 
     * 
     * @see dk.bankconnect.certificate.CertificateService#getEntityCertificate(java.util.List)
     * @see X509CertSelector#getBasicConstraints() the valid return values to
     *      identify an entity certificate
     */
    @Override
    @WebMethod
    public List<X509Certificate> getCACertificates(List<X509Certificate> certificates) throws CertificateException,
            NoSuchProviderException {
        List<X509Certificate> caCerts = new ArrayList<X509Certificate>();
        try {
            for (Iterator<X509Certificate> iterator = certificates.iterator(); iterator.hasNext();) {
                X509Certificate x509Certificate = (X509Certificate) iterator.next();
                X509CertificateHolder x509CertificateHolder = new X509CertificateHolder(x509Certificate.getEncoded());

                if ((x509Certificate.getBasicConstraints() != -1)
                        && (x509CertificateHolder.getExtension(Extension.authorityKeyIdentifier) == null)) {
                    logger.debug("Adding CA certificate " + x509Certificate.getIssuerX500Principal());
                    caCerts.add(x509Certificate);
                }
            }
        } catch (IOException e) {
            throw new CertificateException(e);
        }

        return caCerts;
    }

    /**
     * Creates a PEM encode string containing a certificate
     * 
     * @param certificate
     *            a DER encoded certificate
     * 
     * @return PEM string containing the certificate
     * 
     * @see dk.bankconnect.certificate.CertificateService#getCertificateInPEMFormat(byte[])
     */
    @WebMethod
    public String getCertificateInPEMFormat(byte[] certificate) throws IOException {
        PemObject pemObject = new PemObject("CERTIFICATE", certificate);
        return getPEMString(pemObject);
    }

    /**
     * Creating a list of certificates based on a single PEM encoded string.
     * Please note that a set of PEM formatted certificates, larger than one, that are collected in a single base64 encoded string, will be parsed without exceptions to a single certificate.
     * 
     * @param pemString
     *            containing one or more certificates
     * @return a list of X509Certificates
     * @throws CertificateException 
     *              if the input isn't PEM encoded certificates
     * 
     * @see dk.bankconnect.certificate.CertificateService#getCertificatesFromPEMString(java.lang.String)
     */
    @WebMethod
    public List<X509Certificate> getCertificatesFromPEMString(String pemString) throws CertificateException {
        List<X509Certificate> certificates = new ArrayList<X509Certificate>();
        try {
            if (pemString!=null && StringUtils.isNotEmpty(pemString)) {
                String[] splitString1 = pemString.split("-----BEGIN CERTIFICATE-----");
                for (int i = 0; i < splitString1.length; i++) {
                    String[] splitString2 = splitString1[i].split("-----END CERTIFICATE-----");
                    for (int j = 0; j < splitString2.length; j++) {
                        String string = splitString2[j].trim();
                        if (StringUtils.isNotEmpty(string)) {
                            InputStream inStream = new ByteArrayInputStream(DatatypeConverter.parseBase64Binary(string));
                            X509Certificate currentCertificate = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(inStream);
                            certificates.add(currentCertificate);
                        }
                    }
                }
            } 
            else{
                throw new CertificateException("Input was empty");
            }
        } catch (Exception e){
            logger.error(e);
            throw new CertificateException(e);
        }
        return certificates;
    }

    /**
     * Generates a certificate from the provided file.
     * 
     * @param file
     *            certificate file
     * 
     * @return a X509Certificate
     * 
     * @throws CertificateException
     *             Certificate exception
     * @throws FileNotFoundException
     *             The provided file was not found
     */
    @WebMethod(exclude = true)
    public X509Certificate getCertificate(File file) throws CertificateException, FileNotFoundException {
        CertificateFactory certFactory = CertificateFactory.getInstance("X.509");
        return (X509Certificate) certFactory.generateCertificate(new FileInputStream(file));
    }

}
