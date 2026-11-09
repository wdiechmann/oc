package dk.bankconnect.security;

import dk.bankconnect.BankConnectConstants;
import dk.bankconnect.certificate.CertificateService;
import dk.bankconnect.certificate.CertificateServiceImpl;
import dk.bankconnect.certificate.KeyServiceImpl;
import dk.bankconnect.client.PasswordCallback;
import dk.bankconnect.server.config.Constants;
import org.apache.commons.lang.StringUtils;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.log4j.Level;
import org.apache.log4j.Logger;
import org.apache.ws.security.WSConstants;
import org.apache.ws.security.WSDataRef;
import org.apache.ws.security.WSEncryptionPart;
import org.apache.ws.security.WSSConfig;
import org.apache.ws.security.WSSecurityEngine;
import org.apache.ws.security.WSSecurityEngineResult;
import org.apache.ws.security.WSSecurityException;
import org.apache.ws.security.components.crypto.CryptoBase;
import org.apache.ws.security.components.crypto.CryptoFactory;
import org.apache.ws.security.message.WSSecEncrypt;
import org.apache.ws.security.message.WSSecHeader;
import org.apache.ws.security.message.WSSecSignature;
import org.apache.ws.security.util.UUIDGenerator;
import org.apache.ws.security.util.WSSecurityUtil;
import org.apache.xml.security.utils.Base64;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;
import org.bouncycastle.operator.jcajce.JcaContentVerifierProviderBuilder;
import org.bouncycastle.pkcs.PKCS10CertificationRequest;
import org.bouncycastle.pkcs.PKCS10CertificationRequestBuilder;
import org.bouncycastle.pkcs.jcajce.JcaPKCS10CertificationRequestBuilder;
import org.bouncycastle.util.io.pem.PemObject;
import org.bouncycastle.util.io.pem.PemReader;
import org.bouncycastle.util.io.pem.PemWriter;
import org.springframework.core.io.support.PropertiesLoaderUtils;
import org.w3c.dom.Attr;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;
import javax.security.auth.x500.X500Principal;
import javax.xml.crypto.AlgorithmMethod;
import javax.xml.crypto.KeySelector;
import javax.xml.crypto.KeySelectorException;
import javax.xml.crypto.KeySelectorResult;
import javax.xml.crypto.MarshalException;
import javax.xml.crypto.XMLCryptoContext;
import javax.xml.crypto.XMLStructure;
import javax.xml.crypto.dsig.CanonicalizationMethod;
import javax.xml.crypto.dsig.DigestMethod;
import javax.xml.crypto.dsig.Reference;
import javax.xml.crypto.dsig.SignedInfo;
import javax.xml.crypto.dsig.XMLSignature;
import javax.xml.crypto.dsig.XMLSignatureException;
import javax.xml.crypto.dsig.XMLSignatureFactory;
import javax.xml.crypto.dsig.dom.DOMSignContext;
import javax.xml.crypto.dsig.dom.DOMValidateContext;
import javax.xml.crypto.dsig.keyinfo.KeyInfo;
import javax.xml.crypto.dsig.keyinfo.KeyInfoFactory;
import javax.xml.crypto.dsig.keyinfo.X509Data;
import javax.xml.crypto.dsig.spec.C14NMethodParameterSpec;
import javax.xml.crypto.dsig.spec.SignatureMethodParameterSpec;
import javax.xml.crypto.dsig.spec.TransformParameterSpec;
import javax.xml.namespace.QName;
import javax.xml.transform.OutputKeys;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerException;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.TransformerFactoryConfigurationError;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;
import java.io.IOException;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.StringReader;
import java.io.StringWriter;
import java.security.InvalidAlgorithmParameterException;
import java.security.Key;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Security;
import java.security.UnrecoverableKeyException;
import java.security.cert.CertificateEncodingException;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.security.interfaces.RSAKey;
import java.security.spec.InvalidKeySpecException;
import java.security.spec.KeySpec;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import java.util.Properties;
import java.util.ResourceBundle;

/**
 * This class is the implementation of the Bank Connect made easy
 * ("cryptolibrary"). Basically it has 3 main methods </br>
 * <ol type='1'>
 * <li>getKeyPair {@link dk.bankconnect.security.SecurityService#getKeypair()}</li>
 * </ol>
 * The class can also be invoked as a webservice - used for SoapUI test suite.
 */
public class SecurityServiceImpl implements SecurityService {
    private Log logger = LogFactory.getFactory().getInstance(SecurityServiceImpl.class);

    ResourceBundle ressourceBundle = null;
    private static final int KEYSIZE = 2048;

    private CertificateService certificateService = new CertificateServiceImpl();
    private KeyServiceImpl keyService = new KeyServiceImpl();

    private Properties properties;
    private CryptoBase bankConnectCrypto;

    /**
     * Initializes BouncyCastle, Apache Santuario (for encryption), loads
     * property file and perhaps CA certificates from the JVM.
     * 
     */
    public SecurityServiceImpl() {
        logger.debug("Initializing BouncyCastle");
        Security.addProvider(new BouncyCastleProvider());
        logger.debug("Initializing Apache Santuario");
        org.apache.xml.security.Init.init();
        logger.debug("Initializing Apache WSS4J");
        WSSConfig.init();
        try {
            logger.debug("Loading properties from " + Constants.PROPERTY_FILE);
            properties = PropertiesLoaderUtils.loadAllProperties(Constants.PROPERTY_FILE);
            bankConnectCrypto = (BankConnectCrypto) CryptoFactory.getInstance(Constants.PROPERTY_FILE);
            if ("true".equalsIgnoreCase(properties.getProperty(Constants.PROP_VALIDATE_CERTIFICATE))) {
                loadCACertsIntoBankCrypto();
            }
        } catch (IOException e) {
            logger.error("Property file not found");
        } catch (WSSecurityException e) {
            logger.error("The supplied WSS4j Crypto is not Bank Connect specific");
        }
        ressourceBundle = ResourceBundle.getBundle(BankConnectConstants.RESOURCE_BUNDLE);
    }

    /**
     * Loads all trusted X.509 certificates into BankConnectCrypto. Notice that
     * the certificates are loaded from the SSL trustmanager part of the JVM.
     * Another approach is to load the trusted certificates and pass the list
     * to SecurityServiceImpl.
     * 
     */
    private void loadCACertsIntoBankCrypto() {
        logger.debug("Loading all default trusted certificates in the JVM");
        logger.debug("JVM home "+System.getProperty("java.home"));
        List<X509Certificate> certificates = new ArrayList<X509Certificate>();
        TrustManagerFactory t;
        try {
            t = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
            t.init((KeyStore) null);
            for (TrustManager tm : t.getTrustManagers()) {
                X509TrustManager trustManager = (X509TrustManager) tm;
                for (X509Certificate cert : trustManager.getAcceptedIssuers()) {
                    certificates.add((X509Certificate) cert);
                }
            }
            logger.debug("Setting trusted certificates in BankConnectCrypto");
            X509Certificate[] certArray = certificates.toArray(new X509Certificate[certificates.size()]);
            BankConnectCrypto bcc = new BankConnectCrypto();
            bcc.setTrustedCertificates(certArray);
            bankConnectCrypto = bcc;
        } catch (NoSuchAlgorithmException e) {
            logger.error("Wrong trustmanager algorithm");
            logger.error(e.getMessage());
        } catch (KeyStoreException e) {
            logger.error("Unable to initialize jvm trustmanagers");
            logger.error(e.getMessage());
        }
    }

    /**
     * Constructor with specific trust certificates. Calls the default
     * constructor and applying certificates to BankConnectCrypto.
     * 
     * @param trustedCertificates
     *            a list of trusted X.509 certificates
     * 
     * */
    public SecurityServiceImpl(List<X509Certificate> trustedCertificates ) {
        this();
        if (bankConnectCrypto instanceof BankConnectCrypto) {
            BankConnectCrypto bcc = (BankConnectCrypto) bankConnectCrypto;
            X509Certificate[] certs = new X509Certificate[trustedCertificates.size()]; 
            bcc.setTrustedCertificates(trustedCertificates.toArray(certs));
            bankConnectCrypto = bcc;
        }   
    }

    /**
     * This method is responsible for signing of the header.
     * 
     * @param doc
     *            The document on which to perform header signing
     * @param certificate
     *            The certificate to use
     * @param privateKey
     *            The associated private key
     * 
     * @throws UnrecoverableKeyException
     *             Unable to recover the key
     * @throws KeyStoreException
     *             An error occurred while accessing the keystore
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws CertificateException
     *             Certificate exception
     * @throws WSSecurityException
     *             WSSecurity exception
     * @throws IOException
     *             I/O exception
     * @throws SecurityException
     *             Security exception
     */
    private void doHeaderSigning(Document doc, X509Certificate certificate, PrivateKey privateKey)
            throws UnrecoverableKeyException, KeyStoreException, NoSuchAlgorithmException, CertificateException,
            WSSecurityException, IOException, SecurityException {
        logger.debug("Start header signing");
        String[] elementsToBeSigned = new String[] { "serviceHeader" };
        for (int i = 0; i < elementsToBeSigned.length; i++) {
            logger.debug("Selecting element:" + elementsToBeSigned[i]);
            NodeList elementList = doc.getDocumentElement().getElementsByTagNameNS(
                    Constants.CORPORATESERVICE_NAMESPACE, elementsToBeSigned[i]);
            if (elementList.getLength() == 1) {
                signElementWSS(elementList.item(0), certificate, privateKey);
            }
        }

        logger.debug("Header signing done");
    }

    /**
     * This method is responsible for encryption of the body.
     * 
     * @param doc
     *            The document of which to encrypt the body
     * @param certificate
     *            The certificate to use
     * 
     * @throws KeyStoreException
     *             An error occurred while accessing the keystore
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws CertificateException
     *             Certificate exception
     * @throws IOException
     *             I/O exception
     * @throws WSSecurityException
     *             WSSecurity exception
     * 
     */
    private void doEncryption(Document doc, X509Certificate certificate) throws KeyStoreException,
            NoSuchAlgorithmException, CertificateException, IOException, WSSecurityException, SecurityException {
        logger.debug("Encrypting document");
        String[] elementsToBeEncrypted = new String[] { "transferPayment", "transferPaymentResponse",
                "activateServiceAgreement", "renewCustomerCertificate", "getCustomerAccountReportResponse",
                "getCustomerStatementResponse", "getAlternateResponse", "getStatusResponse",
                "getDebitCreditNotificationResponse", "renewCustomerCertificateResponse" };
        for (int i = 0; i < elementsToBeEncrypted.length; i++) {
            logger.debug("Selecting element:" + elementsToBeEncrypted[i]);
            NodeList elementList = doc.getDocumentElement().getElementsByTagNameNS(
                    Constants.CORPORATESERVICE_NAMESPACE, elementsToBeEncrypted[i]);
            if (elementList.getLength() == 1) {
                Node element = doc.getDocumentElement().getElementsByTagNameNS(Constants.SOAP_NAMESPACE, "Body")
                        .item(0);
                encryptElementWSS4J(element, certificate);
            }
        }
        logger.debug("Encryption done");
    }

    /**
     * This method is responsible for business signing the provided document.
     * 
     * @param doc
     *            The document to sign
     * @param certificate
     *            The certificate to use
     * @param privateKey
     *            The private key to use
     * 
     * @throws UnrecoverableKeyException
     *             Unable to recover the key
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws InvalidAlgorithmParameterException
     *             Invalid or inappropriate algorithm parameters
     * @throws KeyStoreException
     *             An error occurred while accessing the keystore
     * @throws CertificateException
     *             Certificate exception
     * @throws InvalidKeySpecException
     *             The provided key has invalid specifications
     * @throws IOException
     *             I/O exception
     * @throws MarshalException
     *             A MarshalException is thrown if a java.io.IOException occurs
     *             while marshalling the remote call header
     * @throws XMLSignatureException
     *             An error occurred while signing the body
     * @throws WSSecurityException
     *             WSSecurity exception
     * 
     */
    private void doBusinessSigning(Document doc, X509Certificate certificate, PrivateKey privateKey)
            throws UnrecoverableKeyException, NoSuchAlgorithmException, InvalidAlgorithmParameterException,
            KeyStoreException, CertificateException, InvalidKeySpecException, IOException, MarshalException,
            XMLSignatureException, WSSecurityException, SecurityException {
        logger.debug("Start business signing");
        // String[] elementsToBeSigned = new String[] { "paymentMessage",
        // "corporateMessage", "certificateRequest" };
        //String[] elementsToBeSigned = new String[] { "paymentMessage", "corporateMessage", "paymentResponse" };
        String[] elementsToBeSigned = new String[] { "paymentMessage", "corporateMessage","certificateRequestMessage"};
        for (int i = 0; i < elementsToBeSigned.length; i++) {
            logger.debug("Selecting element: " + elementsToBeSigned[i]);
            NodeList elementList = doc.getDocumentElement().getElementsByTagNameNS(
                    Constants.CORPORATESERVICE_NAMESPACE, elementsToBeSigned[i]);
            if (elementList.getLength() == 1) {
                signElement(elementList.item(0), certificate, privateKey);
            }
        }
        logger.debug("Business signing done");
    }

    /**
     * This method is responsible for encrypting the provided node.
     * 
     * @param nodeElement
     *            The node to encrypt
     * @param certificate
     *            The certificate to use
     * 
     * @throws WSSecurityException
     *             WSSecurity exception
     */
    private void encryptElementWSS4J(Node nodeElement, X509Certificate certificate) throws WSSecurityException,
            SecurityException {
        Level currentLevel = null;
        if (properties.getProperty("dk.bankconnect.security.securityservice.trace").contains("true")) {
            logger.info("Trace is true. Changeing to debug level.");
            currentLevel = Logger.getRootLogger().getLevel();
            Logger.getRootLogger().setLevel(Level.DEBUG);
        }
        if ((nodeElement != null) && (certificate != null)) {
            logger.debug("Encrypting element: " + nodeElement.getNodeName());
            WSSecHeader secHeader = new WSSecHeader();
            secHeader.insertSecurityHeader(nodeElement.getOwnerDocument());

            WSSecEncrypt encrypt = new WSSecEncrypt();
            encrypt.setKeyIdentifierType(WSConstants.X509_KEY_IDENTIFIER);
            encrypt.setSymmetricEncAlgorithm(WSConstants.AES_256);
            encrypt.setKeyEncAlgo(WSConstants.KEYTRANSPORT_RSAOEP);
            encrypt.setEncryptSymmKey(true);

            List<WSEncryptionPart> parts = new ArrayList<WSEncryptionPart>();
            WSEncryptionPart encP = new WSEncryptionPart(nodeElement.getNodeName(), "*", "Content");
            encP.setElement((Element) nodeElement);
            parts.add(encP);
            encrypt.setParts(parts);

            if (bankConnectCrypto instanceof BankConnectCrypto) {
                BankConnectCrypto bcc = (BankConnectCrypto) bankConnectCrypto;
                bcc.setSingleCertificate(certificate);
                bankConnectCrypto = bcc;
            } else {
            }
            encrypt.build(nodeElement.getOwnerDocument(), bankConnectCrypto, secHeader);

            if (currentLevel != null) {
                Logger.getRootLogger().setLevel(currentLevel);
            }
        } else {
            logger.error("No encryption due to missing part, element or certificate");
            logger.error("Element to sign: " + nodeElement);
            logger.error("Certificate: " + certificate);
            SecurityException securityException = new SecurityException(new Exception(
                    "No encryption due to missing part, element or certificate"));
            securityException.setErrorcode(BankConnectConstants.INTERNAL_SERVER);
            throw securityException;
        }
    }

    /**
     * This method is responsible for signing the provided node.
     * 
     * @param elementToSign
     *            The node to sign
     * @param certificate
     *            The certificate to use
     * @param privateKey
     *            The private key to use
     * 
     * @throws WSSecurityException
     *             WSSecurity exception
     * @throws KeyStoreException
     *             An error occurred while accessing the keystore
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws CertificateException
     *             Certificate exception
     * @throws IOException
     *             I/O exception
     */
    public void signElementWSS(Node elementToSign, X509Certificate certificate, Key privateKey)
            throws WSSecurityException, KeyStoreException, NoSuchAlgorithmException, CertificateException, IOException,
            SecurityException {
        if (properties.getProperty("dk.bankconnect.security.securityservice.signing").contains("true")) {
            logger.info("Signing xml:");
            logger.debug("Signing element: " + elementToSign.getNodeName());

            if (properties.getProperty("dk.bankconnect.security.securityservice.signing").contains("true")) {
                WSSecSignature wsSignatur = new WSSecSignature();
                wsSignatur.setKeyIdentifierType(WSConstants.X509_KEY_IDENTIFIER);
                wsSignatur.setSignatureAlgorithm("http://www.w3.org/2001/04/xmldsig-more#rsa-sha256");
                wsSignatur.setDigestAlgo("http://www.w3.org/2001/04/xmlenc#sha256");
                List<WSEncryptionPart> parts = new ArrayList<WSEncryptionPart>();
                WSEncryptionPart encP = new WSEncryptionPart(elementToSign.getNodeName(),
                        Constants.CORPORATESERVICE_NAMESPACE, "");
                encP.setElement((Element) elementToSign);
                parts.add(encP);
                logger.debug("Signing Body element");
                parts.add(new WSEncryptionPart(WSConstants.ELEM_BODY, WSConstants.URI_SOAP11_ENV, ""));
                wsSignatur.setParts(parts);

                WSSecHeader secHeader = new WSSecHeader();
                secHeader.insertSecurityHeader(elementToSign.getOwnerDocument());

                wsSignatur.setUseSingleCertificate(true);

                if (bankConnectCrypto instanceof BankConnectCrypto) {
                    BankConnectCrypto bcc = (BankConnectCrypto) bankConnectCrypto;
                    bcc.setSingleCertificate(certificate);
                    bcc.setSingleKey(privateKey);
                    bankConnectCrypto = bcc;
                }
                wsSignatur.build(elementToSign.getOwnerDocument(), bankConnectCrypto, secHeader);

            } else {
                logger.info("No signing - enable in " + Constants.PROPERTY_FILE);
            }
        } else {
            SecurityException securityException = new SecurityException(new Exception(
                    "No signing due to missing signing part, element, certificate or privatekey"));
            securityException.getCorrelationId();
            securityException.setErrorcode(BankConnectConstants.INTERNAL_SERVER);
            logger.error(securityException.getErrorMessage());
            logger.error("Element to sign: " + elementToSign);
            logger.error("Certificate: " + certificate);
            logger.error("PrivateKey: " + privateKey);
            throw securityException;
        }
    }

    /**
     * 
     * UnWrapping/validating the secure Bank Connect soapMessage. The order is:
     * 
     * <ol>
     * <li>Validate the header signatur</li>
     * <li>Decrypt payload</li>
     * <li>Validate the payload signature</li>
     * </ol>
     * 
     * @param soapMessage
     *            The message to unwrap
     * @param privateKey
     *            The private key to use
     * 
     * @throws SecurityException
     *             Security exception
     * 
     */
    public Document unwrapSOAPMessage(Document soapMessage, byte[] privateKey) throws SecurityException {
        try {
            logger.debug("Instantiate the document");
            Document doc = soapMessage;

            if (isRequestSecure(doc)) {
                validateSecurity(doc, keyService.getPrivate(privateKey));
            } else {
                logger.debug("No security for method");
            }
            return doc;

        } catch (SecurityException se) {
            logger.error(se.getErrorMessage());
            throw se;
        } catch (IOException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.FORMAT_ERROR);
            throw sException;
        } catch (NoSuchAlgorithmException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.INVALID_DECRYPTION);
            throw sException;
        } catch (InvalidKeySpecException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.INVALID_DECRYPTION);
            throw sException;
        } catch (TransformerFactoryConfigurationError e) {
            SecurityException sException = new SecurityException(e.getException());
            sException.setErrorcode(BankConnectConstants.FORMAT_ERROR);
            throw sException;
        }
    }

    /**
     * UnWrapping/validating the secure Bank Connect server soapMessage.
     * 
     * @param soapMessage
     *            The message to unwrap
     * @param privateKey
     *            The private key to use
     * 
     * @throws SecurityException
     *             Security exception
     */
    public Document unwrapServerSOAPMessage(Document soapMessage, byte[] privateKey) throws SecurityException {
        try {
            logger.debug("Instantiate the document");
            Document doc = soapMessage;

            validateSecurity(doc, keyService.getPrivate(privateKey));
            return doc;

        } catch (SecurityException se) {
            logger.error(se);
            throw se;
        } catch (IOException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.FORMAT_ERROR);
            throw sException;
        } catch (NoSuchAlgorithmException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.INVALID_DECRYPTION);
            throw sException;
        } catch (InvalidKeySpecException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.INVALID_DECRYPTION);
            throw sException;
        } catch (TransformerFactoryConfigurationError e) {
            SecurityException sException = new SecurityException(e.getException());
            sException.setErrorcode(BankConnectConstants.FORMAT_ERROR);
            throw sException;
        }
    }

    /**
     * Validates if security is set on the request. I.e. encryption, signing and
     * certificates.
     * 
     * @param doc
     *            The request to analyze
     * 
     * @return True if security is set on the request otherwise false
     */
    private boolean isRequestSecure(Document doc) {

        boolean isNotSecure = false;
        String[] elementsWithOutSecurity = new String[] { "getBankCertificate", "getBankCertificateResponse",
                "activateServiceAgreementResponse", "renewCustomerCertificateResponse" };
        for (int i = 0; (i < elementsWithOutSecurity.length) && (!isNotSecure); i++) {
            logger.debug("Selecting element:" + elementsWithOutSecurity[i]);
            NodeList elementList = doc.getDocumentElement().getElementsByTagNameNS(
                    Constants.CORPORATESERVICE_NAMESPACE, elementsWithOutSecurity[i]);
            isNotSecure = (elementList.getLength() == 1);
        }

        if (!isNotSecure) {
            isNotSecure = (doc.getElementsByTagNameNS(Constants.SOAP_NAMESPACE, "Fault").getLength() > 0);
        }
        return !isNotSecure;
    }

    /**
     * Validates if security is set on the document. I.e. encryption, signing
     * and certificates.
     * 
     * @param doc
     *            The document to analyze
     * @param privateKey
     *            The private key
     * 
     * @throws SecurityException
     *             Security exception
     */
    public void validateSecurity(Document doc, PrivateKey privateKey) throws SecurityException {
        Level currentLevel = null;
        if (properties.getProperty("dk.bankconnect.security.securityservice.trace").contains("true")) {
            logger.info("Trace is true. Changeing to debug level.");
            currentLevel = Logger.getRootLogger().getLevel();
            Logger.getRootLogger().setLevel(Level.DEBUG);
        }
        logger.debug("Setting up security engine");
        PasswordCallback cb = new PasswordCallback();
        WSSecurityEngine secEngine = new WSSecurityEngine();

        List<WSSecurityEngineResult> results = null;
        try {
            if (bankConnectCrypto instanceof BankConnectCrypto) {
                BankConnectCrypto bcc = (BankConnectCrypto) bankConnectCrypto;
                bcc.setSingleCertificate(null);
                bcc.setSingleKey(privateKey);
                bankConnectCrypto = bcc;
            }
            results = secEngine.processSecurityHeader(doc, null, cb, bankConnectCrypto, bankConnectCrypto);

            if (results == null) {
                logger.debug("No security found in header");
                throw new SecurityException("No security found");
            }
            List<WSSecurityEngineResult> encryptionResultList = new ArrayList<WSSecurityEngineResult>();
            WSSecurityUtil.fetchAllActionResults(results, 4, encryptionResultList);
            validEncryption(encryptionResultList);

            if (doc.getElementsByTagNameNS(Constants.CORPORATESERVICE_NAMESPACE, "serviceHeader").getLength() != 0) {
                logger.debug("Validating security applied to serviceHeader");
                QName[] parts = new QName[] { new QName(Constants.CORPORATESERVICE_NAMESPACE, "serviceHeader") };
                WSSecurityUtil.checkAllElementsProtected(results, 2, parts);
                List<WSSecurityEngineResult> signatureResultList = new ArrayList<WSSecurityEngineResult>();
                WSSecurityUtil.fetchAllActionResults(results, 2, signatureResultList);
                validateSignature(signatureResultList);
            }

            logger.debug("Validating business signing");
            validateBusinessSigning(doc.getElementsByTagName("Signature"));
        } catch (WSSecurityException e) {
            logger.error("Signature is invalid. Check the JRE for JCE Unlimited Strength Jurisdiction Policy.");
            SecurityException se = new SecurityException(e);
            se.setErrorcode(BankConnectConstants.INVALID_SIGNATURE);
            logger.error(se);
            throw se;
        }

        if (currentLevel != null) {
            Logger.getRootLogger().setLevel(currentLevel);
        }
    }

    /**
     * Sets up encryption details of the provided WSSecurityEngineResult
     * objects.
     * 
     * @param encryptionResultList
     *            The WSSecurityEngineResult objects to analyze
     * 
     * @throws SecurityException
     *             Security exception
     */
    private void validEncryption(List<WSSecurityEngineResult> encryptionResultList) throws SecurityException {
        logger.debug("Validating encryption");
        boolean badEncryption = false;
        for (int i = 0; i < encryptionResultList.size(); i++) {
            X509Certificate certificate = (X509Certificate) encryptionResultList.get(i).get(
                    WSSecurityEngineResult.TAG_X509_CERTIFICATE);
            logger.debug("- Validating certificate");
            validateCertificate(certificate);

            logger.debug("- Validating part size is 1");
            List<WSDataRef> secureElementList = (List<WSDataRef>) encryptionResultList.get(i).get(
                    WSSecurityEngineResult.TAG_DATA_REF_URIS);
            if (secureElementList.size() != 1) {
                logger.error("Found other than 1 encrypted part: " + secureElementList.size());
                badEncryption = true;
            } else {
                logger.debug("- Validating algorithm");
                WSDataRef wsDataRef = secureElementList.get(0);
                if (!wsDataRef.getAlgorithm().endsWith("aes256-cbc")) {
                    logger.error("Bad algorithm: " + wsDataRef.getAlgorithm());
                    badEncryption = true;
                }
            }
        }
        if (badEncryption) {
            SecurityException se = new SecurityException("Decryption has failed");
            se.setErrorcode(BankConnectConstants.INVALID_DECRYPTION);
            logger.error(se);
            throw se;
        }
    }

    /**
     * Sets up signing details of the provided WSSecurityEngineResult objects.
     * 
     * @param signatureResultList
     *            The WSSecurityEngineResult objects to analyze
     * 
     * @throws SecurityException
     *             Security exception
     */
    private void validateSignature(List<WSSecurityEngineResult> signatureResultList) throws SecurityException {
        logger.debug("Validating signature present");
        boolean badSignature = false;
        SecurityException se = null;

        for (int i = 0; i < signatureResultList.size(); i++) {
            logger.debug("Validating certificate");
            if(signatureResultList.get(i)==null){
            	logger.debug("A certificate is missing from the signature");
            }
            X509Certificate certificate = (X509Certificate) signatureResultList.get(i).get(
                    WSSecurityEngineResult.TAG_X509_CERTIFICATE);
            validateCertificate(certificate);

            logger.debug("- Validating algorithm");
            String signatureMethod = (String) signatureResultList.get(i).get(
                    WSSecurityEngineResult.TAG_SIGNATURE_METHOD);
            if (!signatureMethod.endsWith("rsa-sha256")) {
                se = new SecurityException(new Exception("Bad algorithm: " + signatureMethod));
                se.setErrorcode(BankConnectConstants.INVALID_SIGNATURE);
                badSignature = true;
            }
            logger.debug("- Validating canoncial method");
            String canonicalMethod = (String) signatureResultList.get(i).get(
                    WSSecurityEngineResult.TAG_CANONICALIZATION_METHOD);
            if (!canonicalMethod.endsWith("xml-exc-c14n#")) {
                se = new SecurityException(new Exception("Bad canocial method:" + canonicalMethod));
                se.setErrorcode(BankConnectConstants.INVALID_SIGNATURE);
                badSignature = true;
            }
            boolean isSignatureValid = (Boolean) signatureResultList.get(i).get(
                    WSSecurityEngineResult.TAG_VALIDATED_TOKEN);
            if (!isSignatureValid) {
                se = new SecurityException();
                se.setErrorcode(BankConnectConstants.INVALID_SIGNATURE);
                badSignature = true;
            }

            logger.debug("- Validating part size is 2");
            List<WSDataRef> secureElementList = (List<WSDataRef>) signatureResultList.get(i).get(
                    WSSecurityEngineResult.TAG_DATA_REF_URIS);
            if (secureElementList.size() != 2) {
                se = new SecurityException(
                        new Exception("Found other than 2 signed parts: " + secureElementList.size()));
                se.setErrorcode(BankConnectConstants.INVALID_SIGNATURE);
                badSignature = true;
            } else {
                logger.debug("- Validating algorithm");
                WSDataRef wsDataRef = secureElementList.get(0);
                if (!wsDataRef.getDigestAlgorithm().endsWith("sha256")) {
                    se = new SecurityException(new Exception("Bad algorithm: " + wsDataRef.getDigestAlgorithm()));
                    se.setErrorcode(BankConnectConstants.INVALID_SIGNATURE);
                    badSignature = true;
                }
                logger.debug("- Validating 1 transform");
                List<String> transformAlgorithms = wsDataRef.getTransformAlgorithms();
                if (transformAlgorithms.size() != 1) {
                    se = new SecurityException(new Exception("Found other than 1 transform: "
                            + transformAlgorithms.size()));
                    se.setErrorcode(BankConnectConstants.INVALID_SIGNATURE);
                    badSignature = true;
                } else {
                    logger.debug("- Validating transform");
                    if (!transformAlgorithms.get(0).endsWith("xml-exc-c14n#")) {
                        se = new SecurityException("Bad transformation: " + transformAlgorithms.get(0));
                        se.setErrorcode(BankConnectConstants.INVALID_SIGNATURE);
                        badSignature = true;
                    }
                }

            }
        }
        if (badSignature) {
            logger.error(se);
            throw se;
        }

    }

    /**
     * Validates the provided certificate.
     * 
     * @param certificate
     *            The certificate
     * 
     * @throws SecurityException
     *             Security exception
     */
    private void validateCertificate(X509Certificate certificate) throws SecurityException {
        logger.debug("validateCertificate called");
    	if(certificate == null){
    		logger.error("Certificate in NULL");
    	}
    	else{
    		logger.debug("Certificate validation for:"+certificate.toString());
    	}
        SecurityException se = null;
        try {
            certificateService.validateEntityCertificate(certificate.getEncoded());
        } catch (CertificateEncodingException e) {
            logger.debug("Certificate EncodingException: "+e.getMessage());
            logger.error(e);
            se = new SecurityException();
            se.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            se.setMessage("Certificate is not valid");
        } catch (CertificateException e) {
            logger.debug("Certificate Exception: "+e.getMessage());
            logger.error(e);
            se = new SecurityException();
            se.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            se.setMessage("Certificate is not valid");
        }
        if (se != null){
            logger.debug("Post certificate validation errorcode: "+se.getErrorcode());
            throw se;
        }
        logger.debug("validateCertificate ended");
    }

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
    @Override
    public BCKeyPair getKeypair() throws SecurityException {

        KeyPair generateKeyPair = null;
        try {
            KeyPairGenerator kpGen = KeyPairGenerator.getInstance(Constants.KEY_ALGORITHM);
            kpGen.initialize(KEYSIZE);
            generateKeyPair = kpGen.generateKeyPair();
            logger.debug("Keypair has been generated");
            logger.debug("Privatekey is: " + generateKeyPair.getPrivate().getClass().getName());
            logger.debug("Publickey is: " + generateKeyPair.getPublic().getClass().getName());
        } catch (NoSuchAlgorithmException e) {
            logger.error(
                    "This might be a missing JCE Unlimited strength jurisdiction policy issue. Check your jdk for the correct policy.",
                    e);
            throw new SecurityException(e);
        }
        BCKeyPair kp = new BCKeyPair(generateKeyPair.getPublic(), generateKeyPair.getPrivate());
        return kp;
    }

    /**
     * Wraps the server soap message. I.e. is responsible for securing the soap
     * message; business signing, encryption and header signing.
     * 
     * @param soapMessage
     *            The soap message to wrap
     * @param signingCertificate
     *            The signing certificate to use
     * @param signingPrivateKey
     *            The private key to use for signing
     * @param encryptionCertificate
     *            The encryption certificate to use
     * 
     * @return The wrapped message
     * @throws SecurityException
     *             Security exception
     */
    public Document wrapServerSoapMessage(Document soapMessage, byte[] signingCertificate, byte[] signingPrivateKey,
            byte[] encryptionCertificate) throws SecurityException {
        logger.debug("Instantiate the document");
        Document doc = soapMessage;
        try {
            doBusinessSigning(doc, certificateService.getCertificate(signingCertificate),
                    keyService.getPrivate(signingPrivateKey));
            doEncryption(doc, certificateService.getCertificate(encryptionCertificate));
            doHeaderSigning(doc, certificateService.getCertificate(signingCertificate),
                    keyService.getPrivate(signingPrivateKey));
            return doc;
        } catch (Exception e) {
            SecurityException se = new SecurityException(e);
            se.setErrorcode(BankConnectConstants.INTERNAL_SERVER);
            logger.error(se);
            throw se;
        }
    }

    /**
     * Applies signature to the W3C node element with a private key from the
     * keystore. The public certificate (the public key) is applied to the node.
     * Dumps the signature details to the logger if the trace property is set in
     * the server.property file.
     * 
     * @param elementToSign
     *            The W3C node element to sign
     * 
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws InvalidAlgorithmParameterException
     *             Invalid or inappropriate algorithm parameters
     * @throws KeyStoreException
     *             An error occurred while accessing the keystore
     * @throws CertificateException
     *             Certificate exception
     * @throws IOException
     *             I/O exception
     * @throws InvalidKeySpecException
     *             The provided key has invalid specifications
     * @throws MarshalException
     *             A MarshalException is thrown if a java.io.IOException occurs
     *             while marshalling the remote call header
     * @throws XMLSignatureException
     *             An error occurred while signing
     * @throws UnrecoverableKeyException
     *             Unable to recover the key
     */
    public void signElement(Node elementToSign, X509Certificate certificate, PrivateKey privateKey)
            throws NoSuchAlgorithmException, InvalidAlgorithmParameterException, KeyStoreException,
            CertificateException, IOException, InvalidKeySpecException, MarshalException, XMLSignatureException,
            UnrecoverableKeyException, SecurityException {
        if (properties.getProperty("dk.bankconnect.security.securityservice.signing").contains("true")) {
            if ((elementToSign != null) && (certificate != null) && (privateKey != null)) {

                logger.debug("Signing element: " + elementToSign.getNodeName());

                Attr createAttribute = elementToSign.getOwnerDocument().createAttribute("id");
                String signingId = "Sign-" + UUIDGenerator.getUUID();
                createAttribute.setValue(signingId);
                elementToSign.getAttributes().setNamedItemNS(createAttribute);
                logger.debug("Applied signing id: " + signingId);

                XMLSignatureFactory signatureFactory = XMLSignatureFactory.getInstance("DOM");
                List transformList = new ArrayList();
                transformList.add(signatureFactory.newTransform(CanonicalizationMethod.EXCLUSIVE,
                        (TransformParameterSpec) null));
                Reference ref = signatureFactory.newReference("#" + signingId,
                        signatureFactory.newDigestMethod(DigestMethod.SHA256, null), transformList, null, null);

                SignedInfo signedInfo = signatureFactory.newSignedInfo(signatureFactory.newCanonicalizationMethod(
                        CanonicalizationMethod.EXCLUSIVE, (C14NMethodParameterSpec) null), signatureFactory
                        .newSignatureMethod("http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
                                (SignatureMethodParameterSpec) null), Collections.singletonList(ref));

                KeyInfoFactory kif = signatureFactory.getKeyInfoFactory();
                X509Data x509Data = kif.newX509Data(Arrays.asList(certificate));
                List<XMLStructure> keyItems = new ArrayList<XMLStructure>();
                keyItems.add(x509Data);
                KeyInfo ki = kif.newKeyInfo(keyItems);

                // Create the XMLSignature (but don't sign it yet)
                XMLSignature signature = signatureFactory.newXMLSignature(signedInfo, ki);

                DOMSignContext signedBody = new DOMSignContext(privateKey, elementToSign.getParentNode());
                signedBody.setIdAttributeNS((Element) elementToSign, null, "id");
                if (properties.getProperty("dk.bankconnect.security.securityservice.trace").contains("true")) {
                    logger.info("Signing xml:");
                    try {
                        StringWriter sw = new StringWriter();
                        TransformerFactory.newInstance().newTransformer()
                                .transform(new DOMSource(elementToSign), new StreamResult(sw));
                        logger.info(sw.toString());
                    } catch (Exception e) {
                        throw new SecurityException(e);
                    }
                }
                // Sign
                signature.sign(signedBody);
                if (properties.getProperty("dk.bankconnect.security.securityservice.trace").contains("true")) {
                    dumpSignature(signature);
                }
            } else {
                logger.info("No signing - enabled in " + Constants.PROPERTY_FILE);
            }
        } else {
            SecurityException se = new SecurityException(new Exception(
                    "No signing due to missing signing part, element, certificate or privatekey"));
            String correlationId = se.getCorrelationId();
            logger.error("Correlationid: " + correlationId);
            logger.error("Element to sign: " + elementToSign);
            logger.error("Certificate: " + certificate);
            logger.error("PrivateKey: " + privateKey);
            throw se;
        }
    }

    /**
     * Dumps the signature details to logger.info
     * 
     * @param signature
     *            The signature which details should be dumped
     * 
     * @throws IOException
     *             I/O exception
     */

    private void dumpSignature(XMLSignature signature) throws IOException {
        logger.info("Dumping signature...");
        logger.info("Listing keys used for signature");
        List keys = signature.getKeyInfo().getContent();
        for (Iterator iterator = keys.iterator(); iterator.hasNext();) {
            Object objectKeyInfo = (Object) iterator.next();
            if (objectKeyInfo instanceof X509Data) {
                X509Data x509KeyInfo = (X509Data) objectKeyInfo;
                List keyItems = x509KeyInfo.getContent();
                for (Iterator iterator2 = keyItems.iterator(); iterator2.hasNext();) {

                    logger.info("Keyitem: " + iterator2.next());
                }
            } else {
                logger.info("Unsupport keytype: " + objectKeyInfo.getClass().getName());
            }
        }
        logger.info("Listing the signature");
        logger.info("Canonical method: " + signature.getSignedInfo().getCanonicalizationMethod().getAlgorithm());
        List references = signature.getSignedInfo().getReferences();
        for (Iterator iterator = references.iterator(); iterator.hasNext();) {
            Reference ref = (Reference) iterator.next();
            logger.info("Id: " + ref.getId());
            logger.info("Type: " + ref.getType());
            logger.info("URI: " + ref.getURI());

        }
        logger.info("Canonical data:" + Base64.encode(signature.getSignatureValue().getValue()));
    }

    /**
     * Returns PEM encoded PKCS10 request. The Common Name (CN) is set to
     * functionid@activationcode or just functionid depending on the
     * activationcode.
     * 
     * @param functionIdentification
     *            The functionIdentification from the bank received by the
     *            customer
     * 
     * @param activationCode
     *            The activationcode from the bank received by the customer -
     *            use null when no activationcode
     * 
     * @param publicKey
     *            A valid RSA based public key in PEM format
     * 
     * @param privateKey
     *            A valid RSA private key used for signing in PEM format
     * 
     * @return PEM encode PKCS10 request
     * 
     * @throws SecurityException
     */
    @Override
    public byte[] createPKCS10Request(String functionIdentification, String activationCode, String publicKey,
            String privateKey) throws SecurityException {
        byte[] pkcs10Request = null;
        try {
            logger.debug("Reading and generating PKCS1 public key");
            PemReader pubPemReader = new PemReader(new StringReader(publicKey));
            PemObject pubPemObject = pubPemReader.readPemObject();
            PublicKey pubKey = KeyFactory.getInstance(Constants.KEY_ALGORITHM).generatePublic(
                    (KeySpec) new X509EncodedKeySpec(pubPemObject.getContent()));
            validateKey(pubKey);
            logger.debug("Reading and generating PKCS8 private key");
            PemReader privPemReader = new PemReader(new StringReader(privateKey));
            PemObject privPemObject = privPemReader.readPemObject();
            PrivateKey privKey = KeyFactory.getInstance(Constants.KEY_ALGORITHM).generatePrivate(
                    (KeySpec) new PKCS8EncodedKeySpec(privPemObject.getContent()));
            validateKey(privKey);
            String subject = "CN=" + functionIdentification;
            if (StringUtils.isNotEmpty(activationCode)) {
                subject += "@" + activationCode;
            }
            subject += ",OU=Bank Connect,O=Bank Connect,L=DK,ST=DK,C=DK";
            logger.debug("Subject is: " + subject);

            X500Principal subjectName = new X500Principal(subject);

            logger.debug("Creating PKCS10 requestbuilder with subject and public key");
            PKCS10CertificationRequestBuilder requestBuilder = new JcaPKCS10CertificationRequestBuilder(subjectName,
                    pubKey);
            logger.debug("Setup contentsigner with algorithm and private key");

            ContentSigner contentSigner = new JcaContentSignerBuilder("SHA256withRSA").setProvider(
                    Constants.JCE_PROVIDER).build(privKey);

            logger.debug("Build PKCS10 request");
            PKCS10CertificationRequest pkcs10CertificationRequest = requestBuilder.build(contentSigner);

            logger.debug("Wrap PKCS10 request to PEM format");
            pkcs10Request = pkcs10CertificationRequest.getEncoded();

            pubPemReader.close();
            privPemReader.close();
        } catch (Exception e) {
            SecurityException se = new SecurityException(e);
            logger.error("CorrelationId: " + se.getCorrelationId());
            logger.error("Creating PKCS10 has failed");
            logger.error("Activationcode: " + activationCode);
            logger.error("FunctionId: " + functionIdentification);
            logger.error("Privatekey: " + privateKey);
            logger.error("Publickey: " + publicKey);
            throw se;
        }
        return pkcs10Request;
    }

    /**
     * Validates a PKCS10 formated request. I.e. validates the public key and
     * activation code.
     * 
     * @param pkcs10Request
     *            The request to validate
     * 
     * @throws SecurityException
     *             if request is not valid
     */
    @Override
    public void validatePKCS10Request(byte[] pkcs10Request) throws SecurityException {
        boolean isPKCS10Valid = false;
        try {
            logger.debug("Reading and generating PKCS10 request");
            PKCS10CertificationRequest p = new PKCS10CertificationRequest(pkcs10Request);
            logger.debug("Validate public key");
            PublicKey publicKey = KeyFactory.getInstance(Constants.KEY_ALGORITHM).generatePublic(
                    new X509EncodedKeySpec(p.getSubjectPublicKeyInfo().getEncoded()));
            validateKey(publicKey);

            logger.debug("Validating signature");
            isPKCS10Valid = p.isSignatureValid(new JcaContentVerifierProviderBuilder().setProvider(
                    Constants.JCE_PROVIDER).build(publicKey));
            if (!isPKCS10Valid) {
                logger.error("PKCS10 signatur is invalid.");
                SecurityException securityException = new SecurityException();
                securityException.setErrorcode(BankConnectConstants.INVALID_SIGNATURE);
                securityException.setMessage(ressourceBundle.getString(String
                        .valueOf(BankConnectConstants.INVALID_SIGNATURE)));
                throw securityException;
            }
            logger.debug("Validating common name");
            try {
                ActivationIdentification ai = new ActivationIdentification(p);
                if ((ai.getActivationCode() != null) && (ai.getActivationCode().length() != 16)) {
                    logger.error("The length of the activationcode must be 16 characters");
                    SecurityException securityException = new SecurityException();
                    securityException.setErrorcode(BankConnectConstants.VALIDATION_ERROR);
                    securityException.setMessage(ressourceBundle.getString(String
                            .valueOf(BankConnectConstants.VALIDATION_ERROR)));
                    throw securityException;
                }
            } catch (SecurityException e) {
                throw e;
            }
        } catch (Exception e) {
            logger.error("Validating PKCS10 has failed: ", e);
            SecurityException securityException = new SecurityException(e);
            securityException.setErrorcode(BankConnectConstants.VALIDATION_ERROR);
            securityException.setMessage(ressourceBundle.getString(String
                    .valueOf(BankConnectConstants.VALIDATION_ERROR)));
            throw securityException;
        }
    }

    /**
     * Validates the provided key. I.e. validates key algorithm and length.
     * 
     * @param key
     *            The key to validate
     * 
     * @throws SecurityException
     *             Security exception
     */
    private void validateKey(Key key) throws SecurityException {
        logger.debug("Validating algorithm");
        boolean isKeyValid = key.getAlgorithm().equals(Constants.KEY_ALGORITHM);
        RSAKey rk = (RSAKey) key;
        logger.debug("Validating key size");
        isKeyValid = ((isKeyValid) && (rk.getModulus().bitLength() == KEYSIZE));
        if (!isKeyValid) {
            SecurityException securityException = new SecurityException(new Exception(
                    "The applied PKI key is not valid"));
            securityException.setErrorcode(BankConnectConstants.VALIDATION_ERROR);
            throw securityException;
        }
    }

    /**
     * PemObject to string.
     * 
     * @param pemObject
     *            The PemObject to convert
     * 
     * @return The converted PemObject
     * 
     * @throws IOException
     *             I/O exception
     */
    private String getPEMString(PemObject pemObject) throws IOException {
        StringWriter stringWriter = new StringWriter();
        PemWriter pemWriter = new PemWriter(stringWriter);
        pemWriter.writeObject(pemObject);
        pemWriter.close();
        return stringWriter.toString();
    }

    /**
     * Validates all signatures in the node list.
     * 
     * @param signaturList
     *            The signature list
     * 
     * @return true, if successful otherwise false
     * 
     * @throws SecurityException
     */
    public boolean validateBusinessSigning(NodeList signaturList) throws SecurityException {
        boolean coreValidity = true;
        try {
            XMLSignatureFactory factory = XMLSignatureFactory.getInstance("DOM");
            for (int i = 0; (i < signaturList.getLength()) && coreValidity; i++) {
                Node signatureElement = signaturList.item(i);
                DOMValidateContext headerContext = new DOMValidateContext(new X509KeySelector(), signatureElement);
                XMLSignature signature = factory.unmarshalXMLSignature(headerContext);
                Reference reference = (Reference) signature.getSignedInfo().getReferences().get(0);
                Element elementWithId = getNodeWithAttribute(signatureElement.getOwnerDocument(), "id", reference
                        .getURI().replace("#", ""));
                if (elementWithId != null) {
                    headerContext.setIdAttributeNS(elementWithId, null, "id");
                    coreValidity = signature.validate(headerContext);
                    logger.debug("Signature " + reference.getURI() + " has been found and validated: " + coreValidity);
                } else {
                    logger.error("Unable to get element with id: " + reference.getId());
                    logger.error("Signature has not been validated!");
                }
            }
        } catch (Exception e) {
            logger.error("No valid SignedInfo or Reference found. ", e);
            SecurityException securityException = new SecurityException(e);
            securityException.setErrorcode(BankConnectConstants.INVALID_SIGNATURE);
            throw securityException;
        }
        return coreValidity;
    }

    /**
     * Extracts the element matching the provided attribute name and value, from
     * the root node.
     * 
     * @param root
     *            The root node
     * @param attrName
     *            The attribute name
     * @param attrValue
     *            The attribute value
     * 
     * @return The extracted element
     */
    private Element getNodeWithAttribute(Node root, String attrName, String attrValue) {
        NodeList nl = root.getChildNodes();
        for (int i = 0; i < nl.getLength(); i++) {
            Node n = nl.item(i);
            if (n instanceof Element) {
                Element el = (Element) n;
                if (el.getAttribute(attrName).equals(attrValue)) {
                    return el;
                } else {
                    el = getNodeWithAttribute(n, attrName, attrValue); // search
                                                                       // recursively
                    if (el != null) {
                        logger.debug("And got the corresponding xml element: " + el.getNodeName());
                        return el;
                    }
                }
            }
        }
        return null;
    }

    /**
     * The X509Keyselector helper-class, is used by the validateBusinessSigning
     * method.
     * 
     */
    public static class X509KeySelector extends KeySelector {
        /**
         * This method is responsible for extracting the key from the provided
         * key info.
         * 
         * @param keyInfo
         *            The key info
         * @param purpose
         *            The purpose
         * @param method
         *            The method
         * @param context
         *            The context
         * 
         * @return The key selector result
         * 
         * @throws KeySelectorException
         *             KeySelector exception
         */
        public KeySelectorResult select(KeyInfo keyInfo, KeySelector.Purpose purpose, AlgorithmMethod method,
                XMLCryptoContext context) throws KeySelectorException {
            Iterator ki = keyInfo.getContent().iterator();
            while (ki.hasNext()) {
                XMLStructure info = (XMLStructure) ki.next();
                if (!(info instanceof X509Data))
                    continue;
                X509Data x509Data = (X509Data) info;
                Iterator xi = x509Data.getContent().iterator();
                while (xi.hasNext()) {
                    Object o = xi.next();
                    if (!(o instanceof X509Certificate))
                        continue;
                    final PublicKey key = ((X509Certificate) o).getPublicKey();

                    if (algEquals(method.getAlgorithm(), key.getAlgorithm())) {
                        return new KeySelectorResult() {
                            public Key getKey() {
                                return key;
                            }
                        };
                    }
                }
            }
            throw new KeySelectorException("No key found!");
        }

        /**
         * Checks if the provided algorithm name matches "RSA".
         * 
         * @param algURI
         *            The algorithm URI
         * @param algName
         *            The algorithm name
         * 
         * @return True if algName = "RSA" otherwise false
         */
        static boolean algEquals(String algURI, String algName) {
            if ((algName.equalsIgnoreCase("RSA"))) {
                return true;
            } else {
                return false;
            }
        }
    }

    /**
     * Wraps the xml document. I.e. is responsible for securing the soap
     * message; encryption and header signing.
     * 
     * @param xmlDocument
     *            The xml document to wrap
     * @param certificate
     *            The signing certificate to use
     * @param privateKey
     *            The private key to use
     * @param encryptionCertificate
     *            The encryption certificate to use
     * 
     * @return The wrapped document
     * 
     * @throws SecurityException
     *             Security exception
     */
    @Override
    public Document wrapSoapMessage(Document xmlDocument, byte[] certificate, byte[] privateKey,
            byte[] encryptionCertificate) throws SecurityException {
        X509Certificate cert;
        Document doc = xmlDocument;
        
        try {
            printDocument(doc, System.out);
        } catch (IOException e1) {
            // TODO Auto-generated catch block, please consider logging the exception
        } catch (TransformerException e1) {
            // TODO Auto-generated catch block, please consider logging the exception
        }
        
        try {
            cert = certificateService.getCertificate(certificate);
            PrivateKey privkey = keyService.getPrivate(privateKey);

            doBusinessSigning(doc, cert, privkey);
            if (Boolean.valueOf(properties.getProperty("dk.bankconnect.security.securityservice.encrypt"))) {
                doEncryption(doc, certificateService.getCertificate(encryptionCertificate));
            } else {
                logger.debug("No encryption!");
            }
            doHeaderSigning(doc, cert, privkey);
        } catch (CertificateException e) {
            logger.error(e);
            SecurityException securityException = new SecurityException(e);
            securityException.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            securityException.setMessage(ressourceBundle.getString(String
                    .valueOf(BankConnectConstants.VALIDATION_ERROR)));
            throw securityException;
        } catch (NoSuchAlgorithmException e) {
            logger.error(e);
            SecurityException securityException = new SecurityException(e);
            securityException.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            securityException.setMessage(ressourceBundle.getString(String
                    .valueOf(BankConnectConstants.VALIDATION_ERROR)));
            throw securityException;
        } catch (InvalidKeySpecException e) {
            logger.error(e);
            SecurityException securityException = new SecurityException(e);
            securityException.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            securityException.setMessage(ressourceBundle.getString(String
                    .valueOf(BankConnectConstants.VALIDATION_ERROR)));
            throw securityException;
        } catch (IOException e) {
            logger.error(e);
            SecurityException securityException = new SecurityException(e);
            securityException.setErrorcode(BankConnectConstants.INTERNAL_SERVER);
            securityException.setMessage(ressourceBundle.getString(String
                    .valueOf(BankConnectConstants.INTERNAL_SERVER)));
            throw securityException;
        } catch (UnrecoverableKeyException e) {
            logger.error(e);
            SecurityException securityException = new SecurityException(e);
            securityException.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            securityException.setMessage(ressourceBundle.getString(String
                    .valueOf(BankConnectConstants.VALIDATION_ERROR)));
            throw securityException;
        } catch (InvalidAlgorithmParameterException e) {
            logger.error(e);
            SecurityException securityException = new SecurityException(e);
            securityException.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            securityException.setMessage(ressourceBundle.getString(String
                    .valueOf(BankConnectConstants.VALIDATION_ERROR)));
            throw securityException;
        } catch (KeyStoreException e) {
            logger.error(e);
            SecurityException securityException = new SecurityException(e);
            securityException.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            securityException.setMessage(ressourceBundle.getString(String
                    .valueOf(BankConnectConstants.VALIDATION_ERROR)));
            throw securityException;
        } catch (MarshalException e) {
            logger.error(e);
            SecurityException securityException = new SecurityException(e);
            securityException.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            securityException.setMessage(ressourceBundle.getString(String
                    .valueOf(BankConnectConstants.VALIDATION_ERROR)));
            throw securityException;
        } catch (XMLSignatureException e) {
            logger.error(e);
            SecurityException securityException = new SecurityException(e);
            securityException.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            securityException.setMessage(ressourceBundle.getString(String
                    .valueOf(BankConnectConstants.VALIDATION_ERROR)));
            throw securityException;
        } catch (WSSecurityException e) {
            logger.error(e);
            SecurityException securityException = new SecurityException(e);
            securityException.setErrorcode(BankConnectConstants.INTERNAL_SERVER);
            securityException.setMessage(ressourceBundle.getString(String
                    .valueOf(BankConnectConstants.INTERNAL_SERVER)));
            throw securityException;
        }

        return doc;
    }
    
    public static void printDocument(Document doc, OutputStream out) throws IOException, TransformerException {
        TransformerFactory tf = TransformerFactory.newInstance();
        Transformer transformer = tf.newTransformer();
        transformer.setOutputProperty(OutputKeys.OMIT_XML_DECLARATION, "no");
        transformer.setOutputProperty(OutputKeys.METHOD, "xml");
        transformer.setOutputProperty(OutputKeys.INDENT, "yes");
        transformer.setOutputProperty(OutputKeys.ENCODING, "UTF-8");
        transformer.setOutputProperty("{http://xml.apache.org/xslt}indent-amount", "4");

        transformer.transform(new DOMSource(doc), 
             new StreamResult(new OutputStreamWriter(out, "UTF-8")));
    }
}
