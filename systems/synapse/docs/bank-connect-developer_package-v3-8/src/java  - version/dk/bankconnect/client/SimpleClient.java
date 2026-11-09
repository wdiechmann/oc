package dk.bankconnect.client;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UnsupportedEncodingException;
import java.math.BigInteger;
import java.security.Key;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.NoSuchProviderException;
import java.security.UnrecoverableKeyException;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.security.spec.InvalidKeySpecException;
import java.util.List;

import javax.xml.datatype.DatatypeConfigurationException;
import javax.xml.ws.Holder;

import org.apache.commons.logging.LogFactory;
import org.apache.cxf.endpoint.Client;
import org.apache.cxf.frontend.ClientProxy;
import org.apache.cxf.transport.http.HTTPConduit;
import org.apache.cxf.transports.http.configuration.HTTPClientPolicy;

import dk.bankconnect.certificate.CertificateService;
import dk.bankconnect.certificate.CertificateServiceImpl;
import dk.bankconnect.certificate.KeyService;
import dk.bankconnect.certificate.KeyServiceImpl;
import dk.bankconnect.common.util.zip.GZIPCompressionUtility;
import dk.bankconnect.schema._2014.ActivateServiceAgreement;
import dk.bankconnect.schema._2014.ActivateServiceAgreementResponse;
import dk.bankconnect.schema._2014.ActivationAgreement;
import dk.bankconnect.schema._2014.ActivationHeader;
import dk.bankconnect.schema._2014.CertificateRequestMessage;
import dk.bankconnect.schema._2014.CorporateService;
import dk.bankconnect.schema._2014.GetAlternateResponse;
import dk.bankconnect.schema._2014.GetBankCertificateResponse;
import dk.bankconnect.schema._2014.GetCustomerAccountReportResponse;
import dk.bankconnect.schema._2014.GetCustomerStatementResponse;
import dk.bankconnect.schema._2014.GetDebitCreditNotificationResponse;
import dk.bankconnect.schema._2014.GetStatus;
import dk.bankconnect.schema._2014.GetStatusResponse;
import dk.bankconnect.schema._2014.PaymentMessage;
import dk.bankconnect.schema._2014.RenewCustomerCertificate;
import dk.bankconnect.schema._2014.RenewCustomerCertificateResponse;
import dk.bankconnect.schema._2014.ServiceHeader;
import dk.bankconnect.schema._2014.TechnicalAddress;
import dk.bankconnect.schema._2014.TransferPayment;
import dk.bankconnect.schema._2014.TransferPaymentResponse;
import dk.bankconnect.security.BCKeyPair;
import dk.bankconnect.security.SecurityException;
import dk.bankconnect.security.SecurityServiceImpl;

/**
 * This is a webserviceclient for Bank Connect. The simple client implements the
 * most basic functions. As such, it can be used as a quick introduction in
 * using the functions of the API.
 * 
 * @author bdumof
 * 
 */
public class SimpleClient extends BankConnectClient {

    private final boolean useSecurity = true;
    private final boolean useLog = true;

    /**
     * Instantiates a new advanced bank connect client. The constructor of the
     * SimpleClient sets up the global variables and properties.
     * 
     * @throws IOException
     *             I/O exception
     * @throws KeyStoreException
     *             An error occurred while accessing the keystore
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws CertificateException
     *             Certificate exception
     * @throws UnrecoverableKeyException
     *             Unable to recover the key
     */
    public SimpleClient(String url) throws IOException, UnrecoverableKeyException, KeyStoreException,
            NoSuchAlgorithmException, CertificateException {
        super();

        logger = LogFactory.getFactory().getInstance(SimpleClient.class);
        logger.info("Calling service endpoint at url: " + url);

        factory.setAddress(url);
        factory.setServiceClass(CorporateService.class);
        if (useSecurity) {
            factory.getInInterceptors().add(new ClientSecurityInterceptorIn());
            factory.getOutInterceptors().add(new ClientSecurityInterceptorOut());
        }
        if (useLog)
            enableDebugLogging(factory);

        client = (CorporateService) factory.create();

        // Setup cxf client
        Client cxfClient = ClientProxy.getClient(client);
        HTTPConduit http = (HTTPConduit) cxfClient.getConduit();
        HTTPClientPolicy httpClientPolicy = new HTTPClientPolicy();
        httpClientPolicy.setConnectionTimeout(36000);
        httpClientPolicy.setAllowChunking(false);
        httpClientPolicy.setReceiveTimeout(240000); // BankConnectHub has 3
                                                    // minutes as timeout

        http.setClient(httpClientPolicy);
        if (useSecurity) {
            // Fetch certificates and private key
            CertificateService csi = new CertificateServiceImpl();
            String signingCertificate = clientProperties
                    .getProperty("dk.bankconnect.security.bankconnectcrypto.signing.certificate");
            X509Certificate signCert = csi.getCertificateFromKeystore(null, signingCertificate);
            String encryptionCertificate = clientProperties
                    .getProperty("dk.bankconnect.security.bankconnectcrypto.encryption.certificate");
            X509Certificate encCert = csi.getCertificateFromKeystore(null, encryptionCertificate);
            String privateKey = clientProperties.getProperty("dk.bankconnect.security.bankconnectcrypto.private.key");
            Key privKey = csi.getKeyFromKeystore(null, privateKey);

            // Store certificates and private key
            cxfClient.getRequestContext()
                    .put("dk.bankconnect.security.bankconnectcrypto.signing.certificate", signCert);
            cxfClient.getRequestContext().put("dk.bankconnect.security.bankconnectcrypto.private.key", privKey);
            cxfClient.getRequestContext().put("dk.bankconnect.security.bankconnectcrypto.encryption.certificate",
                    encCert);
            cxfClient.getResponseContext().put("dk.bankconnect.security.bankconnectcrypto.private.key", privKey);
        }
    }

    /**
     * Calls the GetBankCertificate service
     * 
     * @throws CorporateException_Exception
     *             Corporate exception
     * @throws DatatypeConfigurationException
     *             Data type configuration exception
     * @throws UnsupportedEncodingException
     *             The used encoding scheme is not supported
     * @throws CertificateException
     *             Certificate exception
     * @throws NoSuchProviderException
     *             The certificate provider does not exist
     */
    private void getBankCertificate() throws DatatypeConfigurationException, CertificateException,
            UnsupportedEncodingException, NoSuchProviderException {

        logger.info("Calling service: GetBankCertificate");

        Holder<ActivationHeader> activationHeader = new Holder<ActivationHeader>(getActivationHeader());
        Holder<TechnicalAddress> technicalAddress = new Holder<TechnicalAddress>(getTechnicalAddress());

        // Call web service
        GetBankCertificateResponse bankCertificateResponse = client.getBankCertificate(
                bankConnectFactory.createGetBankCertificate(), technicalAddress, activationHeader);

        // Store the received Bank certificate
        CertificateService csi = new CertificateServiceImpl();
        List<X509Certificate> certificatesFromPEMString = csi.getCertificatesFromPEMString(new String(
                bankCertificateResponse.getCorporateMessage().getContent()));
        X509Certificate bankCertificate = csi.getEntityCertificate(certificatesFromPEMString);

        if (bankCertificate != null) {
            ClientProxy.getClient(client).getRequestContext()
                    .put("dk.bankconnect.security.bankconnectcrypto.encryption.certificate", bankCertificate);
        }

        logger.info("Bank certificate received:\n "
                + new String(bankCertificateResponse.getCorporateMessage().getContent(), "UTF-8"));
    }

    /**
     * Call renew certificate with a newly generated PKCS10 request based on a
     * new keypair. Ends with printing the new certificate.
     * 
     * @throws CorporateException_Exception
     *             Corporate exception
     * @throws SecurityException
     *             Security exception
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws InvalidKeySpecException
     *             The provided key has invalid specifications
     * @throws IOException
     *             I/O exception
     * @throws DatatypeConfigurationException
     *             Data type configuration exception
     * @throws CertificateException
     *             Certificate exception
     * @throws NoSuchProviderException
     *             The certificate provider does not exist
     */
    private void callRenewCertificate() throws SecurityException, NoSuchAlgorithmException, InvalidKeySpecException,
            IOException, DatatypeConfigurationException, CertificateException, NoSuchProviderException {

        logger.info("Calling service: RenewCustomerCertificate");

        // Create renew certificate request
        RenewCustomerCertificate renewCustomerCertificate = bankConnectFactory.createRenewCustomerCertificate();
        String activationCode = "987654321QWERTYU";

        SecurityServiceImpl securityServImpl = new SecurityServiceImpl();
        BCKeyPair keyPair = securityServImpl.getKeypair();

        byte[] pkcs10Request = securityServImpl.createPKCS10Request(FUNCTION_ID, "1111111111111111",
                keyPair.getPublicKeyAsPKCS1(), keyPair.getPrivateKeyAsPKCS8());
        CertificateRequestMessage requestMessage = bankConnectFactory.createCertificateRequestMessage();
        requestMessage.setCertificateRequest(pkcs10Request);
        renewCustomerCertificate.setCertificateRequestMessage(requestMessage);

        Holder<ServiceHeader> sh = new Holder<ServiceHeader>(getServiceHeader());
        Holder<TechnicalAddress> technicalAddress = new Holder<TechnicalAddress>(getTechnicalAddress());

        // Call web service
        RenewCustomerCertificateResponse renewCustomerCertificateResponse = client.renewCustomerCertificate(
                renewCustomerCertificate, technicalAddress, sh);

        // Extract and decode the received certificate
        CertificateService certificateService = new CertificateServiceImpl();
        List<X509Certificate> certificatesFromPEMString = certificateService.getCertificatesFromPEMString(new String(
                renewCustomerCertificateResponse.getCorporateMessage().getContent()));
        X509Certificate newCertificate = certificateService.getEntityCertificate(certificatesFromPEMString);

        logger.info("New customer certificate received:\n " + newCertificate);
    }

    /**
     * Calls the TransferPayments service
     * 
     * @throws DatatypeConfigurationException
     *             Data type configuration exception
     * @throws CorporateException_Exception
     *             Corporate exception
     * @throws IOException
     *             I/O exception
     * @throws KeyStoreException
     *             An error occurred while accessing the keystore
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws CertificateException
     *             Certificate exception
     */
    private void callTransferPayments() throws DatatypeConfigurationException, IOException, KeyStoreException,
            NoSuchAlgorithmException, CertificateException {

        logger.info("Calling service: TransferPayments");

        Holder<ServiceHeader> serviceHeader = new Holder<ServiceHeader>(getServiceHeader());
        Holder<TechnicalAddress> technicalAddress = new Holder<TechnicalAddress>(getTechnicalAddress());

        // Setup payment message
        PaymentMessage mp = bankConnectFactory.createPaymentMessage();
        mp.setCompressed(new BigInteger("1"));
        mp.setMimeType("text/xml");
        mp.setFormat("ISO20022");
         
        //InputStream xmlFile = new FileInputStream(new File("payload.xml"));
        InputStream xmlFile = this.getClass().getResourceAsStream("payload.xml");
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        GZIPCompressionUtility.compress(xmlFile, bos);
        mp.setContent(bos.toByteArray());
        TransferPayment tp = bankConnectFactory.createTransferPayment();
        tp.setPaymentMessage(mp);

        // Call web service
        TransferPaymentResponse transferPaymentResponse = client.transferPayments(tp, technicalAddress, serviceHeader);

        if (transferPaymentResponse != null) {
            logger.info("Responsecode:\n " + transferPaymentResponse.getPaymentResponse().getResponseCode());
            logger.info("Responsemessage:\n " + transferPaymentResponse.getPaymentResponse().getMessage());
        }
    }

    /**
     * Calls the GetStatus service
     * 
     * @throws DatatypeConfigurationException
     *             Data type configuration exception
     * @throws CorporateException_Exception
     *             Corporate exception
     * @throws UnsupportedEncodingException
     *             The used encoding scheme is not supported
     */
    private void callGetStatus() throws DatatypeConfigurationException, UnsupportedEncodingException {
        logger.info("Calling service: GetStatus");

        Holder<ServiceHeader> sh = new Holder<ServiceHeader>(getServiceHeader());

        // Call web service
        GetStatus getStatus = bankConnectFactory.createGetStatus();
        GetStatusResponse status;
        status = client.getStatus(getStatus, null, sh);

        logger.info("Received status:\n " + new String(status.getCorporateMessage().getContent(), "UTF-8"));
    }

    /**
     * Calls the ActivateAgreement service
     * 
     * @throws DatatypeConfigurationException
     *             Data type configuration exception
     * @throws CorporateException_Exception
     *             Corporate exception
     * @throws IOException
     *             I/O exception
     * @throws SecurityException
     *             Security exception
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws InvalidKeySpecException
     *             The provided key has invalid specifications
     */
    private void callActivateAgreement() throws DatatypeConfigurationException, IOException, SecurityException,
            NoSuchAlgorithmException, InvalidKeySpecException {

        logger.info("Calling service: ActivateServiceAgreement");

        // Setup activate service agreement request
        ActivateServiceAgreement activateServiceAgreement = bankConnectFactory.createActivateServiceAgreement();
        ActivationAgreement agreement = bankConnectFactory.createActivationAgreement();

        SecurityServiceImpl securityServImpl = new SecurityServiceImpl();
        KeyService keyServImpl = new KeyServiceImpl();
        BCKeyPair keyPair = keyServImpl.getKeypair();

        String activationCode = clientProperties.getProperty("dk.bankconnect.server.valid.activationcode");
        agreement.setActivationCode(activationCode.getBytes("UTF-8"));
        byte[] pkcs10Request = securityServImpl.createPKCS10Request(FUNCTION_ID, activationCode,
                keyPair.getPublicKeyAsPKCS1(), keyPair.getPrivateKeyAsPKCS8());
        agreement.setCertificateRequest(pkcs10Request);
        activateServiceAgreement.setActivationAgreement(agreement);

        Holder<TechnicalAddress> technicalAddress = new Holder<TechnicalAddress>(getTechnicalAddress());
        Holder<ActivationHeader> activationHeader = new Holder<ActivationHeader>(getActivationHeader());

        // Call web service
        ActivateServiceAgreementResponse agreementResponse = client.activateServiceAgreement(activateServiceAgreement,
                technicalAddress, activationHeader);

        logger.info("Received new customer certificate:\n "
                + new String(agreementResponse.getCorporateMessage().getContent(), "UTF-8"));
    }

    /**
     * Calls the GetDebitCreditNotification service
     * 
     * @throws DatatypeConfigurationException
     *             Data type configuration exception
     * @throws CorporateException_Exception
     *             Corporate exception
     * @throws UnsupportedEncodingException
     *             The used encoding scheme is not supported
     */
    private void callGetDebitCreditNotification() throws DatatypeConfigurationException, UnsupportedEncodingException {
        logger.info("Calling service: GetDebitCreditNotification");

        Holder<ServiceHeader> sh = new Holder<ServiceHeader>(getServiceHeader());

        // Call web service
        GetDebitCreditNotificationResponse notificationResponse = client.getDebitCreditNotification(
                bankConnectFactory.createGetDebitCreditNotification(), null, sh);

        logger.info("Received response:\n "
                + new String(notificationResponse.getCorporateMessage().getContent(), "UTF-8"));
    }

    /**
     * Calls the GetAlternate service
     * 
     * @throws DatatypeConfigurationException
     *             Data type configuration exception
     * @throws CorporateException_Exception
     *             Corporate exception
     * @throws UnsupportedEncodingException
     *             The used encoding scheme is not supported
     */
    private void callGetAlternate() throws DatatypeConfigurationException, UnsupportedEncodingException {
        logger.info("Calling service: GetAlternate");

        Holder<ServiceHeader> sh = new Holder<ServiceHeader>(getServiceHeader());

        // Call web service
        GetAlternateResponse alternateResponse = client.getAlternate(bankConnectFactory.createGetAlternate(), null, sh);
        logger.info(alternateResponse.getCorporateMessage().getDescription());

        logger.info("Received response:\n " + new String(alternateResponse.getCorporateMessage().getContent(), "UTF-8"));
    }

    /**
     * Calls the AccountReport service
     * 
     * @throws DatatypeConfigurationException
     *             Data type configuration exception
     * @throws CorporateException_Exception
     *             Corporate exception
     * @throws UnsupportedEncodingException
     *             The used encoding scheme is not supported
     */
    private void callGetAccountReport() throws DatatypeConfigurationException, UnsupportedEncodingException,
            IOException {
        logger.info("Calling service: GetCustomerAccountReport");

        Holder<ServiceHeader> serviceHeader = new Holder<ServiceHeader>(getServiceHeader());

        // Call web service
        GetCustomerAccountReportResponse reportResponse = client.getCustomerAccountReport(
                bankConnectFactory.createGetCustomerAccountReport(), null, serviceHeader);

        // If the corporate message is compressed, we need to decompress it
        if (reportResponse.getCorporateMessage().getCompressed().intValue() == 1) {
            InputStream xmlFile = new ByteArrayInputStream(reportResponse.getCorporateMessage().getContent());
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            GZIPCompressionUtility.decompress(xmlFile, bos);
            logger.info("Received response:\n " + bos.toString("UTF-8"));
        } else {
            logger.info("Received response:\n "
                    + new String(reportResponse.getCorporateMessage().getContent(), "UTF-8"));
        }
    }

    /**
     * Calls the GetCustomerStatement service
     * 
     * @throws DatatypeConfigurationException
     *             Data type configuration exception
     * @throws CorporateException_Exception
     *             Corporate exception
     * @throws UnsupportedEncodingException
     *             The used encoding scheme is not supported
     */
    private void callGetCustomerStatement() throws DatatypeConfigurationException, UnsupportedEncodingException,
            IOException {
        logger.info("Calling service: GetCustomerStatement");

        Holder<ServiceHeader> sh = new Holder<ServiceHeader>(getServiceHeader());

        // Call web service
        GetCustomerStatementResponse statementResponse = client.getCustomerStatement(
                bankConnectFactory.createGetCustomerStatement(), null, sh);

        // If the corporate message is compressed, we need to decompress it
        if (statementResponse.getCorporateMessage().getCompressed().intValue() == 1) {
            InputStream xmlFile = new ByteArrayInputStream(statementResponse.getCorporateMessage().getContent());
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            GZIPCompressionUtility.decompress(xmlFile, bos);
            logger.info("Received response:\n " + bos.toString("UTF-8"));
        } else {
            logger.info("Received response:\n "
                    + new String(statementResponse.getCorporateMessage().getContent(), "UTF-8"));
        }
    }

    /**
     * 
     * @param args
     *            the input arguments
     * @throws DatatypeConfigurationException
     *             Data type configuration exception
     * @throws IOException
     *             I/O exception
     * @throws KeyStoreException
     *             KeyStoreException
     * @throws NoSuchAlgorithmException
     *             The encryption algorithm does not exist
     * @throws CertificateException
     *             Certificate exception
     * @throws UnrecoverableKeyException
     *             Unable to recover the key
     * @throws InvalidKeySpecException
     *             The provided key has invalid specifications
     * @throws SecurityException
     *             Security exception
     * @throws NoSuchProviderException
     *             The certificate provider does not exist
     */
    public static void main(String[] args) throws DatatypeConfigurationException, IOException, KeyStoreException,
            NoSuchAlgorithmException, CertificateException, UnrecoverableKeyException, InvalidKeySpecException,
            SecurityException, NoSuchProviderException {
        String url = "https://stest.bankconnect.dk/2019/04/04/services/CorporateService";
        if (args.length > 0) {
            url = args[0];
        }

        SimpleClient bcc = new SimpleClient(url);

        bcc.getBankCertificate();
        bcc.callActivateAgreement();
        bcc.callRenewCertificate();
        bcc.callTransferPayments();
        bcc.callGetStatus();
        bcc.callGetDebitCreditNotification();
        bcc.callGetCustomerStatement();
        bcc.callGetAccountReport();
        bcc.callGetAlternate();
    }
}