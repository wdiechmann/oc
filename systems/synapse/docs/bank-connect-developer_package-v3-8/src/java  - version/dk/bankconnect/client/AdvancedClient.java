package dk.bankconnect.client;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
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
import org.apache.cxf.jaxws.JaxWsProxyFactoryBean;
import org.apache.cxf.transport.http.HTTPConduit;
import org.apache.cxf.transports.http.configuration.HTTPClientPolicy;

import dk.bankconnect.certificate.CertificateService;
import dk.bankconnect.certificate.CertificateServiceImpl;
import dk.bankconnect.common.util.zip.GZIPCompressionUtility;
import dk.bankconnect.schema._2014.ActivationHeader;
import dk.bankconnect.schema._2014.CorporateService;
import dk.bankconnect.schema._2014.Duration;
import dk.bankconnect.schema._2014.GetBankCertificateResponse;
import dk.bankconnect.schema._2014.PaymentMessage;
import dk.bankconnect.schema._2014.ServiceHeader;
import dk.bankconnect.schema._2014.TechnicalAddress;
import dk.bankconnect.schema._2014.TransferPayment;
import dk.bankconnect.schema._2014.TransferPaymentResponse;
import dk.bankconnect.security.SecurityException;
import dk.bankconnect.server.util.AddDuration;

/**
 * This is a webserviceclient for Bank Connect. The simple client implements the
 * most basic functions. As such, it can be used as a quick introduction in
 * using the functions of the API.
 * 
 * @author bdumof
 * 
 */
public class AdvancedClient extends BankConnectClient {

    private static boolean enableDurationPoint = false;
    private static boolean enableSecurity = true;
    private static boolean logBeforeSecurity = false;

    /**
     * Instantiates a new advanced bank connect client. The constructor of the
     * AdvancedClient sets up the global variables and properties.
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
    public AdvancedClient(String url) throws IOException, UnrecoverableKeyException, KeyStoreException,
            NoSuchAlgorithmException, CertificateException {
        super();

        logger = LogFactory.getFactory().getInstance(AdvancedClient.class);
        logger.info("Calling service endpoint at url: " + url);

        factory.setAddress(url);
        factory.setServiceClass(CorporateService.class);

        if (logBeforeSecurity) {
            if (logger.isDebugEnabled())
                enableDebugLogging(factory);
            if (enableSecurity)
                enableSecurity(factory);
        } else {
            if (enableSecurity)
                enableSecurity(factory);
            if (logger.isDebugEnabled())
                enableDebugLogging(factory);
        }

        client = (CorporateService) factory.create();

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

        // Setup cxf client
        Client cxfClient = ClientProxy.getClient(client);
        HTTPConduit http = (HTTPConduit) cxfClient.getConduit();
        HTTPClientPolicy httpClientPolicy = new HTTPClientPolicy();
        httpClientPolicy.setConnectionTimeout(36000);
        httpClientPolicy.setAllowChunking(false);
        httpClientPolicy.setReceiveTimeout(240000); // BankConnectHub has 3
                                                    // minutes as timeout

        http.setClient(httpClientPolicy);

        // Store certificates and private key
        cxfClient.getRequestContext().put("dk.bankconnect.security.bankconnectcrypto.signing.certificate", signCert);
        cxfClient.getRequestContext().put("dk.bankconnect.security.bankconnectcrypto.private.key", privKey);
        cxfClient.getRequestContext().put("dk.bankconnect.security.bankconnectcrypto.encryption.certificate", encCert);
        cxfClient.getResponseContext().put("dk.bankconnect.security.bankconnectcrypto.private.key", privKey);
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
    private void getBankCertificate() throws DatatypeConfigurationException,
            CertificateException, UnsupportedEncodingException, NoSuchProviderException {

        logger.info("Calling service: GetBankCertificate");

        Holder<ActivationHeader> activationHeader = new Holder<ActivationHeader>(getActivationHeader());
        Holder<TechnicalAddress> technicalAddress = new Holder<TechnicalAddress>(getTechnicalAddress());

        if (enableDurationPoint)
            AddDuration.ForceAdd(technicalAddress, "AdvancedClient - calling getBankCertificate");

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

        if (enableDurationPoint) {
            AddDuration.ForceAdd(technicalAddress, "AdvancedClient - received response");
            logDurationPoints(technicalAddress);
        }

        logger.info("Bank certificate received:\n "
                + new String(bankCertificateResponse.getCorporateMessage().getContent(), "UTF-8"));
    }

    private void enableSecurity(JaxWsProxyFactoryBean factory) {
        factory.getInInterceptors().add(new ClientSecurityInterceptorIn());
        factory.getOutInterceptors().add(new ClientSecurityInterceptorOut());
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
    private void callTransferPayments(String file) throws DatatypeConfigurationException,
            IOException, KeyStoreException, NoSuchAlgorithmException, CertificateException {

        logger.info("Calling service: TransferPayments");

        Holder<ServiceHeader> serviceHeader = new Holder<ServiceHeader>(getServiceHeader());
        Holder<TechnicalAddress> technicalAddress = new Holder<TechnicalAddress>(getTechnicalAddress());

        // Setup payment message
        PaymentMessage mp = bankConnectFactory.createPaymentMessage();
        mp.setCompressed(new BigInteger("1"));
        mp.setMimeType("text/xml");
        mp.setFormat("ISO20022");

        InputStream xmlFile = new FileInputStream(new File(file));

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

    private void logDurationPoints(Holder<TechnicalAddress> technicalAddress) {
        for (Duration duration : technicalAddress.value.getDuration()) {
            logger.info("\n");
            logger.info("Duration point");
            logger.info("Point:" + duration.getPoint());
            logger.info("Time:" + duration.getTime() + "ms");
        }

        if (technicalAddress.value.getDuration().size() == 8) {
            long timestampClient1 = technicalAddress.value.getDuration().get(0).getTime();
            long timestampHub1 = technicalAddress.value.getDuration().get(1).getTime();
            long timestampHub2 = technicalAddress.value.getDuration().get(2).getTime();
            long timestampMock1 = technicalAddress.value.getDuration().get(3).getTime();
            long timestampMock2 = technicalAddress.value.getDuration().get(4).getTime();
            long timestampHub3 = technicalAddress.value.getDuration().get(5).getTime();
            long timestampHub4 = technicalAddress.value.getDuration().get(6).getTime();
            long timestampClient2 = technicalAddress.value.getDuration().get(7).getTime();

            long value1 = timestampHub1 - timestampClient1;
            long value2 = timestampHub2 - timestampHub1;
            long value3 = timestampMock1 - timestampHub2;
            long value4 = timestampMock2 - timestampMock1;
            long value5 = timestampHub3 - timestampMock2;
            long value6 = timestampHub4 - timestampHub3;
            long value7 = timestampClient2 - timestampHub4;
            long value8 = timestampClient2 - timestampClient1;

            logger.info("\n");
            logger.info("Time elapsed sending request from Client to HUB = " + value1 + "ms");
            logger.info("Time elapsed processing request in HUB = " + value2 + "ms");
            logger.info("Time elapsed sending request from HUB to MOCK = " + value3 + "ms");
            logger.info("Time elapsed processing request in MOCK = " + value4 + "ms");
            logger.info("Time elapsed returning response from MOCK to HUB = " + value5 + "ms");
            logger.info("Time elapsed processing response in HUB = " + value6 + "ms");
            logger.info("Time elapsed returning response from HUB to CLIENT = " + value7 + "ms");
            logger.info("Total time elapsed from request to response = " + value8 + "ms");
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
            
            String file = "test/soapui/Basic-Project/input/FI-71-1.xml";
            if (args.length > 1) {
                file = args[1];
            }

            enableSecurity = true;
            enableDurationPoint = true;

            AdvancedClient bcc = new AdvancedClient(url);

            bcc.getBankCertificate();
            bcc.callTransferPayments(file);
    }
}