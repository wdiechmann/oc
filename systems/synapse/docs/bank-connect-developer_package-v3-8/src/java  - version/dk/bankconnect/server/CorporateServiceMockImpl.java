package dk.bankconnect.server;

import dk.bankconnect.BankConnectConstants;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.math.BigInteger;
import java.net.URL;
import java.security.Key;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.cert.X509Certificate;
import java.security.spec.X509EncodedKeySpec;
import java.util.GregorianCalendar;
import java.util.UUID;

import javax.annotation.Resource;
import javax.servlet.ServletContext;
import javax.xml.bind.JAXBContext;
import javax.xml.bind.JAXBElement;
import javax.xml.bind.JAXBException;
import javax.xml.bind.Unmarshaller;
import javax.xml.datatype.DatatypeConfigurationException;
import javax.xml.datatype.DatatypeFactory;
import javax.xml.datatype.XMLGregorianCalendar;
import javax.xml.namespace.QName;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;
import javax.xml.transform.stream.StreamSource;
import javax.xml.ws.Holder;
import javax.xml.ws.WebServiceContext;
import javax.xml.ws.handler.MessageContext;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.cxf.binding.soap.SoapFault;
import org.bouncycastle.pkcs.PKCS10CertificationRequest;
import org.springframework.core.io.support.PropertiesLoaderUtils;
import org.w3c.dom.Document;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.SAXException;

import dk.bankconnect.certificate.CertificateService;
import dk.bankconnect.certificate.CertificateServiceImpl;
import dk.bankconnect.common.w3c.dom.DocumentSource;
import dk.bankconnect.schema._2014.ActivateServiceAgreement;
import dk.bankconnect.schema._2014.ActivateServiceAgreementResponse;
import dk.bankconnect.schema._2014.ActivationHeader;
import dk.bankconnect.schema._2014.CorporateMessage;
import dk.bankconnect.schema._2014.CorporateService;
import dk.bankconnect.schema._2014.GetAlternate;
import dk.bankconnect.schema._2014.GetAlternateResponse;
import dk.bankconnect.schema._2014.GetBankCertificate;
import dk.bankconnect.schema._2014.GetBankCertificateResponse;
import dk.bankconnect.schema._2014.GetCustomerAccountReport;
import dk.bankconnect.schema._2014.GetCustomerAccountReportResponse;
import dk.bankconnect.schema._2014.GetCustomerStatement;
import dk.bankconnect.schema._2014.GetCustomerStatementResponse;
import dk.bankconnect.schema._2014.GetDebitCreditNotification;
import dk.bankconnect.schema._2014.GetDebitCreditNotificationResponse;
import dk.bankconnect.schema._2014.GetStatus;
import dk.bankconnect.schema._2014.GetStatusResponse;
import dk.bankconnect.schema._2014.ObjectFactory;
import dk.bankconnect.schema._2014.PaymentMessage;
import dk.bankconnect.schema._2014.PaymentResponse;
import dk.bankconnect.schema._2014.RenewCustomerCertificate;
import dk.bankconnect.schema._2014.RenewCustomerCertificateResponse;
import dk.bankconnect.schema._2014.ServiceHeader;
import dk.bankconnect.schema._2014.TechnicalAddress;
import dk.bankconnect.schema._2014.TransferPayment;
import dk.bankconnect.schema._2014.TransferPaymentResponse;
import dk.bankconnect.security.ActivationIdentification;
import dk.bankconnect.security.SecurityException;
import dk.bankconnect.security.SecurityService;
import dk.bankconnect.security.SecurityServiceImpl;
import dk.bankconnect.server.config.Constants;
import dk.bankconnect.server.util.AddDuration;
import dk.bankconnect.server.util.MIMEType;
import dk.bankconnect.server.util.ValidateContent;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.cxf.binding.soap.SoapFault;
import org.bouncycastle.operator.OperatorCreationException;
import org.bouncycastle.pkcs.PKCS10CertificationRequest;
import org.springframework.core.io.support.PropertiesLoaderUtils;
import org.w3c.dom.Document;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.SAXException;

import javax.annotation.Resource;
import javax.servlet.ServletContext;
import javax.xml.bind.JAXBContext;
import javax.xml.bind.JAXBElement;
import javax.xml.bind.JAXBException;
import javax.xml.bind.Unmarshaller;
import javax.xml.datatype.DatatypeConfigurationException;
import javax.xml.datatype.DatatypeFactory;
import javax.xml.datatype.XMLGregorianCalendar;
import javax.xml.namespace.QName;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;
import javax.xml.transform.stream.StreamSource;
import javax.xml.ws.Holder;
import javax.xml.ws.WebServiceContext;
import javax.xml.ws.handler.MessageContext;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.math.BigInteger;
import java.net.URL;
import java.security.InvalidKeyException;
import java.security.Key;
import java.security.KeyFactory;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.NoSuchProviderException;
import java.security.PublicKey;
import java.security.SignatureException;
import java.security.UnrecoverableKeyException;
import java.security.cert.CertificateEncodingException;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.security.spec.InvalidKeySpecException;
import java.security.spec.X509EncodedKeySpec;
import java.util.GregorianCalendar;
import java.util.UUID;

/**
 * The CorporateServiceMockImpl implements the CorporateService class.
 */
@org.apache.cxf.interceptor.OutInterceptors(interceptors = { "org.apache.cxf.interceptor.LoggingOutInterceptor",
        "dk.bankconnect.server.WebserviceInterceptorOut", "dk.bankconnect.server.WebserviceSecurityInterceptorOut" })
@org.apache.cxf.interceptor.InInterceptors(interceptors = { "org.apache.cxf.interceptor.LoggingInInterceptor",
        "dk.bankconnect.server.WebserviceInterceptorIn", "dk.bankconnect.server.WebserviceSecurityInterceptorIn" })
public class CorporateServiceMockImpl implements CorporateService {

    @Resource
    WebServiceContext webServiceContext;

    private String mockPathToFiles = null;
    final String BANK_IA_CERT = "bank connect ia-test";
    private Log logger = LogFactory.getFactory().getInstance(CorporateServiceMockImpl.class);
    CertificateService certificateService;

    /**
     * Constructor.
     * 
     * @param certificateService
     */
    public CorporateServiceMockImpl(CertificateService certificateService) {
        this.certificateService = certificateService;
    }

    /**
     * Constructor.
     */
    public CorporateServiceMockImpl() {
        certificateService = new CertificateServiceImpl();

    }

    /**
     * Get the mock path to files.
     * 
     * @return the mock path to files
     */
    private String getMockServerPath() {
        if (mockPathToFiles == null) {
            if (webServiceContext != null) {
                ServletContext servletContext = (ServletContext) webServiceContext.getMessageContext().get(
                        MessageContext.SERVLET_CONTEXT);
                mockPathToFiles = servletContext.getInitParameter("MockPathToFiles");
            }
            if (mockPathToFiles == null) {
                mockPathToFiles = Constants.MOCKSERVERPATH;
            }
        }
        return mockPathToFiles;
    }

    /**
     * Get the bank certificate response.
     * 
     * @param parameters
     *            GetBankCertificate parameters
     * @param technicalAddress
     *            IpAddress and ipPort
     * @param activationHeader
     *            Header information
     * @return The bank certificate response object
     */
    @Override
    public GetBankCertificateResponse getBankCertificate(GetBankCertificate parameters,
            Holder<TechnicalAddress> technicalAddress, Holder<ActivationHeader> activationHeader) {
        logIncoming(activationHeader.value);
        AddDuration.Add(technicalAddress, "MockServer - getBankCertificate request received");
        GetBankCertificateResponse bankCertificateResponse = new GetBankCertificateResponse();
        String bankCertificateAlias;
        try {
            bankCertificateAlias = PropertiesLoaderUtils.loadAllProperties(Constants.PROPERTY_FILE).getProperty(
                    "dk.bankconnect.security.bankconnectcrypto.private.key");


            ObjectFactory of = new ObjectFactory();
            CorporateMessage corporateMessage = of.createCorporateMessage();
            X509Certificate bankCertificate = certificateService.getCertificateFromKeystore(null, bankCertificateAlias);
            X509Certificate intermediateCertificate = getIntermediateCACertificate();
            corporateMessage.setContent(buildCertificateChain(intermediateCertificate, bankCertificate).getBytes());
            corporateMessage.setCompressed(BigInteger.ZERO);
            corporateMessage.setDescription(bankCertificateAlias);
            corporateMessage.setSender("MOCK");
            corporateMessage.setMimeType(MIMEType.TextXML.getName());
            corporateMessage.setEndToEndMessageId(activationHeader.value.getEndToEndMessageId());
            corporateMessage.setSeveralMessages(false);
            corporateMessage.setMessageDate(getNow());
            corporateMessage.setFormat("text");
            bankCertificateResponse.setCorporateMessage(corporateMessage);
        } catch (IOException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (KeyStoreException e) {
            logger.error(e.getMessage());
            throw buildFault(e);
        } catch (NoSuchAlgorithmException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (CertificateException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (DatatypeConfigurationException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        }

        AddDuration.Add(technicalAddress, "MockServer - getBankCertificate response sent");

        return bankCertificateResponse;
    }

    private X509Certificate getIntermediateCACertificate() throws KeyStoreException, NoSuchAlgorithmException, CertificateException, IOException {
        return certificateService.getCertificateFromKeystore(null, BANK_IA_CERT);
    }

    private SoapFault buildFault(KeyStoreException e) {
        return new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
    }

    private String buildCertificateChain(X509Certificate... certificates) throws CertificateEncodingException, IOException {
        StringBuilder builder = new StringBuilder();
        for (X509Certificate certificate : certificates) {
            builder.append(certificateService.getCertificateInPEMFormat(certificate.getEncoded()));
        }
        return builder.toString();
    }

    /**
     * Get the status response.
     * 
     * @param parameters
     *            GetStatus parameters
     * @param technicalAddress
     *            IpAddress and ipPort
     * @param serviceHeader
     *            Header information
     * @return The status response object
     */
    @Override
    public GetStatusResponse getStatus(GetStatus parameters, Holder<TechnicalAddress> technicalAddress,
            Holder<ServiceHeader> serviceHeader) {
        GetStatusResponse statusResponse = new GetStatusResponse();
        try {
            AddDuration.Add(technicalAddress, "MockServer - getStatus request received");

            logger.debug("Status has been invoked");
            logIncoming(serviceHeader.value);

            statusResponse.setCorporateMessage(getCorporateMessageFromFile(getMockServerPath()
                    + "output/default-getStatus.xml"));

            AddDuration.Add(technicalAddress, "MockServer - getStatus response sent");
        } catch (SoapFault sf) {
            throw sf;
        } catch (Exception e) {
            SecurityException se = new SecurityException(e);
            throw se.getAsSoapFault();
        }
        return statusResponse;
    }

    /**
     * Get the debit credit notification response.
     * 
     * @param parameters
     *            GetDebitCreditNotification parameters
     * @param technicalAddress
     *            IpAddress and ipPort
     * @param serviceHeader
     *            Header information
     * @return The debit credit notification response object
     */
    @Override
    public GetDebitCreditNotificationResponse getDebitCreditNotification(GetDebitCreditNotification parameters,
            Holder<TechnicalAddress> technicalAddress, Holder<ServiceHeader> serviceHeader) {
        GetDebitCreditNotificationResponse debitCreditNotificationResponse = new GetDebitCreditNotificationResponse();
        try {
            AddDuration.Add(technicalAddress, "MockServer - getDebitCreditNotification request received");

            logIncoming(serviceHeader.value);
            debitCreditNotificationResponse.setCorporateMessage(getCorporateMessageFromFile(getMockServerPath()
                    + "output/default-getDebitCreditNotification.xml"));

            AddDuration.Add(technicalAddress, "MockServer - getDebitCreditNotification response sent");
        } catch (SoapFault sf) {
            throw sf;
        } catch (Exception e) {
            SecurityException se = new SecurityException(e);
            throw se.getAsSoapFault();
        }

        return debitCreditNotificationResponse;
    }

    /**
     * Get alternate response.
     * 
     * @param parameters
     *            GetAlternate parameters
     * @param technicalAddress
     *            IpAddress and ipPort
     * @param serviceHeader
     *            Header information
     * @return The alternate response object
     */
    @Override
    public GetAlternateResponse getAlternate(GetAlternate parameters, Holder<TechnicalAddress> technicalAddress,
            Holder<ServiceHeader> serviceHeader) {

        GetAlternateResponse alternateResponse = new GetAlternateResponse();
        try {
            AddDuration.Add(technicalAddress, "MockServer - getAlternate request received");

            logger.debug("Alternate has been invoked");
            logIncoming(serviceHeader.value);
            alternateResponse.setCorporateMessage(getCorporateMessageFromFile(getMockServerPath()
                    + "output/default-getAlternate.xml"));

            AddDuration.Add(technicalAddress, "MockServer - getAlternate response sent");
        } catch (SoapFault sf) {
            throw sf;
        } catch (Exception e) {
            SecurityException se = new SecurityException(e);
            throw se.getAsSoapFault();
        }

        return alternateResponse;
    }

    /**
     * Get the customer statement response.
     * 
     * @param parameters
     *            GetCustomerStatement parameters
     * @param technicalAddress
     *            IpAddress and ipPort
     * @param serviceHeader
     *            Header information
     * @return The customer statement response object
     */
    @Override
    public GetCustomerStatementResponse getCustomerStatement(GetCustomerStatement parameters,
            Holder<TechnicalAddress> technicalAddress, Holder<ServiceHeader> serviceHeader) {

        GetCustomerStatementResponse customerStatementResponse = new GetCustomerStatementResponse();
        try {
            AddDuration.Add(technicalAddress, "MockServer - getCustomerStatement request received");

            logger.debug("CustomerStatement has been invoked");
            logIncoming(serviceHeader.value);
            if (serviceHeader.value.getFunctionIdentification().equalsIgnoreCase("largeReply")) {
                customerStatementResponse.setCorporateMessage(getCorporateMessageFromFile(getMockServerPath()
                        + "output/largeReply.xml"));
            } else {
                customerStatementResponse.setCorporateMessage(getCorporateMessageFromFile(getMockServerPath()
                        + "output/default-getCustomerStatement.xml"));
            }

            AddDuration.Add(technicalAddress, "MockServer - getCustomerStatement response sent");
        } catch (SoapFault sf) {
            throw sf;
        } catch (Exception e) {
            SecurityException se = new SecurityException(e);
            throw se.getAsSoapFault();
        }

        return customerStatementResponse;
    }

    /**
     * Get the transfer payments response.
     * 
     * @param parameters
     *            TransferPayment parameters
     * @param technicalAddress
     *            IpAddress and ipPort
     * @param serviceHeader
     *            Header information
     * @return The transfer payments response object
     */
    @Override
    public TransferPaymentResponse transferPayments(TransferPayment parameters,
            Holder<TechnicalAddress> technicalAddress, Holder<ServiceHeader> serviceHeader) {
        TransferPaymentResponse paymentResponse = null;
        try {
            AddDuration.Add(technicalAddress, "MockServer - TransferPayments request received");

            logger.debug("TransferPayments has been invoked");

            validateContent(parameters.getPaymentMessage());

            getSoapFaultAndThrowSoapFault(serviceHeader.value);

            logIncoming(serviceHeader.value, parameters.getPaymentMessage());
            if (parameters != null) {
                if (logger.isDebugEnabled()) {
                    saveContent(parameters.getPaymentMessage(),
                            getMockServerPath() + "content/" + serviceHeader.value.getEndToEndMessageId() + ".xml");
                }
                paymentResponse = readPaymentResponseMessageFromFile(serviceHeader.value);
            } else {
                logger.error("No payment recieved!");
            }

            paymentResponse.getPaymentResponse().setEndToEndMessageId(serviceHeader.value.getEndToEndMessageId());

            AddDuration.Add(technicalAddress, "MockServer - TransferPayments response sent");
        } catch (SoapFault sf) {
            throw sf;
        } catch (Exception e) {
            SecurityException se = new SecurityException(e);
            throw se.getAsSoapFault();
        }

        return paymentResponse;
    }

    /**
     * Save the content of the payment into a file.
     * 
     * @param paymentMessage
     * @param filename
     */
    private void saveContent(PaymentMessage paymentMessage, String filename) {
        FileOutputStream stream = null;
        try {
            File doooFile = new File(new URL(filename).getFile());
            logger.debug("Debug is enabled - saving content: " + doooFile.getAbsoluteFile());
            stream = new FileOutputStream(doooFile);
            stream.write(paymentMessage.getContent());
        } catch (FileNotFoundException e) {
            logger.error(e.getMessage());
        } catch (IOException e) {
            logger.error(e.getMessage());
        } finally {
            try {
                if (stream != null) {
                    stream.close();
                }
            } catch (IOException e) {
                logger.error(e.getMessage());
            }
        }
    }

    /**
     * Log incoming payment messages.
     * 
     * @param serviceHeader
     *            Header information
     * @param parameters
     *            PaymentMessage
     */
    private void logIncoming(ServiceHeader serviceHeader, PaymentMessage... parameters) {
        logger.debug("Incoming with end2endmsgid: " + serviceHeader.getEndToEndMessageId());
        logger.debug("- functionidentification: " + serviceHeader.getFunctionIdentification());

        if (parameters.length > 0) {
            if (parameters[0] == null) {
                logger.debug("- no content !");
            } else {
                logger.debug("- content size: " + parameters[0].getContent().length);
            }
        }
    }

    /**
     * Get a buggy corporate message.
     * 
     * @param serviceHeader
     *            Header information
     * @return Buggy corporate message
     */
    private CorporateMessage getFailed(ServiceHeader serviceHeader) {
        CorporateMessage cm = new CorporateMessage();
        cm.setCompressed(BigInteger.ONE);
        cm.setEndToEndMessageId(UUID.randomUUID().toString());
        cm.setSeveralMessages(false);
        return cm;
    }

    /**
     * Simulator a soap fault.
     * 
     * @param serviceHeader
     *            Header information
     * @throws ParserConfigurationException
     * @throws IOException
     * @throws SAXException
     */
    private void getSoapFaultAndThrowSoapFault(ServiceHeader serviceHeader) throws ParserConfigurationException,
            SAXException, IOException {
        logger.debug("getSoapFaultAndThrowSoapFault has been invoked");
        String fileName = getMockServerPath() + "output/" + serviceHeader.getFunctionIdentification() + ".xml";
        StreamSource fileInput = null;
        InputStream inputStream = this.getClass().getClassLoader().getResourceAsStream(fileName);
        if (inputStream != null) {
            logger.debug("File found: " + fileName);
            fileInput = new StreamSource(inputStream);
            DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
            dbf.setValidating(false);
            dbf.setIgnoringComments(false);
            dbf.setIgnoringElementContentWhitespace(true);
            dbf.setNamespaceAware(true);

            Document doc = dbf.newDocumentBuilder().parse(inputStream);

            NodeList faultstring = doc.getElementsByTagName("faultstring");
            Node itemFaultstring = faultstring.item(0);
            
         // There is no fault in the xml.
            if (itemFaultstring == null) {
                return;
            }
            
            logger.debug("itemFaultstring: " + itemFaultstring.getTextContent());

            QName faultCode = SoapFault.FAULT_CODE_SERVER;
            NodeList faultcode = doc.getElementsByTagName("faultcode");
            Node itemFaultcode = faultcode.item(0);
            logger.debug("Faultcode: " + itemFaultcode.getTextContent());
            if (itemFaultcode.getTextContent().toLowerCase().contains("server")) {
                faultCode = SoapFault.FAULT_CODE_SERVER;
            } else {
                faultCode = SoapFault.FAULT_CODE_CLIENT;
            }
            SoapFault sf = new SoapFault(itemFaultstring.getTextContent(), faultCode);

            throw sf;
        } else {
            logger.debug("File NOT found: " + fileName);
            fileName = getMockServerPath() + "output/default.xml";
            fileInput = new StreamSource(this.getClass().getClassLoader().getResourceAsStream(fileName));
            logger.debug("Setting to default file : " + fileName);
        }
    }

    /* *
     * 
     * @deprecated
     */
    /*private CorporateMessage getSuccess(ServiceHeader serviceHeader) {
        String fileName = getMockServerPath() + "output/" + serviceHeader.getFunctionIdentification() + ".xml";
        CorporateMessage cm = getCorporateMessageFromFile(fileName);
        return cm;
    }*/

    /**
     * 
     * @deprecated
     */
    private CorporateMessage getCorporateMessageFromFile(String fileName) {
        CorporateMessage cm = null;
        StreamSource fileInput = null;
        InputStream inputStream = null;
        try {
            inputStream = new FileInputStream(new File(fileName));
        } catch (FileNotFoundException e1) {
        }
        if (inputStream == null) {
            inputStream = this.getClass().getResourceAsStream(fileName);
        }
        if (inputStream != null) {
            logger.debug("File found: " + fileName);
            fileInput = new StreamSource(inputStream);
        } else {
            logger.debug("File NOT found: " + fileName);
            fileName = Constants.MOCKSERVERPATH + "output/default.xml";
            fileInput = new StreamSource(this.getClass().getResourceAsStream(fileName));
            logger.debug("Setting to default file : " + fileName);
        }
        try {
            JAXBContext jaxbContext = JAXBContext.newInstance(CorporateMessage.class);
            JAXBElement<CorporateMessage> element = new JAXBElement<CorporateMessage>(new QName("corporateMessage"),
                    CorporateMessage.class, cm);
            Unmarshaller jaxbUnmarshaller = jaxbContext.createUnmarshaller();
            element = jaxbUnmarshaller.unmarshal(fileInput, CorporateMessage.class);
            cm = element.getValue();
        } catch (JAXBException e) {
            logger.error(e);
        }
        return cm;
    }

    /**
     * 
     * @deprecated
     */
    private TransferPaymentResponse readPaymentResponseMessageFromFile(ServiceHeader serviceHeader) {
        TransferPaymentResponse res = null;

        if (serviceHeader != null) {
            String functionIdentification = serviceHeader.getFunctionIdentification();
            String fileName = getMockServerPath() + "output/" + functionIdentification + ".xml";
            res = readPaymentResponseMessageFromFile(fileName);
        }

        return res;
    }

    /**
     * Read a payment response message from a file.
     * 
     * @param fileName
     * @return Transfer Payment Response object
     */
    private TransferPaymentResponse readPaymentResponseMessageFromFile(String fileName) {
        TransferPaymentResponse transferPaymentResponse = new TransferPaymentResponse();
        StreamSource fileInput = null;
        InputStream inputStream = null;
        try {
            inputStream = new FileInputStream(new File(fileName));
        } catch (FileNotFoundException e1) {
        }
        if (inputStream == null) {
            inputStream = this.getClass().getResourceAsStream(fileName);
        }
        if (inputStream != null) {
            logger.debug("File found: " + fileName);
            fileInput = new StreamSource(inputStream);
        } else {
            logger.debug("File NOT found: " + fileName);
            fileName = Constants.MOCKSERVERPATH + "output/default.xml";
            fileInput = new StreamSource(this.getClass().getClassLoader().getResourceAsStream(fileName));
            logger.debug("Setting to default file : " + fileName);
        }
        try {
            PaymentResponse paymentResponse = null;
            JAXBContext jaxbContext = JAXBContext.newInstance(PaymentResponse.class);
            JAXBElement<PaymentResponse> element = new JAXBElement<PaymentResponse>(new QName("PaymentResponse"),
                    PaymentResponse.class, paymentResponse);
            Unmarshaller jaxbUnmarshaller = jaxbContext.createUnmarshaller();
            element = jaxbUnmarshaller.unmarshal(fileInput, PaymentResponse.class);
            // paymentResponse = ;
            transferPaymentResponse.setPaymentResponse(element.getValue());
        } catch (JAXBException e) {
            logger.error(e);
        }

        return transferPaymentResponse;
    }

    /**
     * Get the customer certificate renewed.
     * 
     * @param parameters
     *            RenewCustomerCertificate
     * @param technicalAddress
     *            IpAddress and ipPort
     * @param serviceHeader
     *            Header information
     * @return The customer certificate response object
     */
    @Override
    public RenewCustomerCertificateResponse renewCustomerCertificate(RenewCustomerCertificate parameters,
            Holder<TechnicalAddress> technicalAddress, Holder<ServiceHeader> serviceHeader) {

        logger.debug("RenewCustomerCertificate has been invoked");

        RenewCustomerCertificateResponse customerCertificateResponse = new RenewCustomerCertificateResponse();

        try {
            AddDuration.Add(technicalAddress, "MockServer - renewCustomerCertificate request received");
            SecurityService se = new SecurityServiceImpl();
            final byte[] certificateRequest = parameters.getCertificateRequestMessage().getCertificateRequest();
            se.validatePKCS10Request(certificateRequest);
            final String functionIdentification = serviceHeader.value.getFunctionIdentification();
            byte[] generateCertificate = null;
            se.validatePKCS10Request(parameters.getCertificateRequestMessage().getCertificateRequest());
            PKCS10CertificationRequest pkcs10 = new PKCS10CertificationRequest(parameters.getCertificateRequestMessage().getCertificateRequest());
            PublicKey publicKey = KeyFactory.getInstance(Constants.KEY_ALGORITHM).generatePublic(
                    new X509EncodedKeySpec(pkcs10.getSubjectPublicKeyInfo().getEncoded()));

            final X509Certificate customerCertificate = issueCertificate(certificateRequest, functionIdentification);

            CorporateMessage cm = new CorporateMessage();
            cm.setContent(buildCertificateChain(getIntermediateCACertificate(), customerCertificate).getBytes());
            cm.setCompressed(BigInteger.ZERO);
            cm.setMimeType(MIMEType.PEM.getName());
            cm.setFormat("text");
            cm.setSender("MOCK");
            cm.setSeveralMessages(false);
            cm.setEndToEndMessageId(serviceHeader.value.getEndToEndMessageId());
            customerCertificateResponse.setCorporateMessage(cm);
            AddDuration.Add(technicalAddress, "MockServer - renewCustomerCertificate response sent");
        } catch (InvalidKeyException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (SoapFault sf) {
            throw sf;
        } catch (NoSuchProviderException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (SignatureException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (OperatorCreationException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (CertificateException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (NoSuchAlgorithmException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (IOException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (InvalidKeySpecException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (SecurityException e) {
            logger.error(e.getErrorMessage());
            throw new SoapFault(e.getErrorMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (UnrecoverableKeyException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (KeyStoreException e) {
            logger.error(e.getMessage());
            throw new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
        } catch (Exception e) {
            SecurityException se = new SecurityException(e);
            throw se.getAsSoapFault();
        }

        return customerCertificateResponse;
    }

    private X509Certificate issueCertificate(byte[] certificateRequest, String functionIdentification) throws IOException, InvalidKeySpecException, NoSuchAlgorithmException, KeyStoreException, CertificateException, UnrecoverableKeyException, InvalidKeyException, NoSuchProviderException, SignatureException, OperatorCreationException {
        PKCS10CertificationRequest pkcs10 = new PKCS10CertificationRequest(certificateRequest);
        PublicKey publicKey = KeyFactory.getInstance(Constants.KEY_ALGORITHM).generatePublic(
                new X509EncodedKeySpec(pkcs10.getSubjectPublicKeyInfo().getEncoded()));

        Key privateSigningKey = certificateService.getKeyFromKeystore(null, BANK_IA_CERT);
        X509Certificate iaCertificate = getIntermediateCACertificate();
        byte[] generatedCertificate = certificateService.generateCertificate(
                functionIdentification, publicKey.getEncoded(),
                privateSigningKey.getEncoded(), iaCertificate.getEncoded());
        return certificateService.getCertificate(generatedCertificate);
    }

    /**
     * Activate the service agreement.
     * 
     * @param request
     *            ActivateServiceAgreement
     * @param technicalAddress
     *            IpAddress and ipPort
     * @param activationHeader
     *            Header information
     * @return The activate service agreement response object
     */

    @Override
    public ActivateServiceAgreementResponse activateServiceAgreement(ActivateServiceAgreement request,
            Holder<TechnicalAddress> technicalAddress, Holder<ActivationHeader> activationHeader) {

        logger.debug("ActivateServiceAgreement has been invoked");
        ActivateServiceAgreementResponse activateServiceAgreementResponse = new ActivateServiceAgreementResponse();
        try {
            //validateContent(request, activationHeader);
            AddDuration.Add(technicalAddress, "MockServer - activateServiceAgreement request received");
            logIncoming(activationHeader.value);
            try {
                validateContent(request, activationHeader);
            } catch (Exception e) {
                logger.error(e.getMessage());
                SoapFault sf = new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
                throw sf;
            }
            CertificateService csi = new CertificateServiceImpl();
            activateServiceAgreementResponse.setCorporateMessage(getCorporateMessageFromFile(getMockServerPath()
                    + "output/default-activateServiceAgreement.xml"));

            AddDuration.Add(technicalAddress, "MockServer - activateServiceAgreement response sent");
        } catch (SoapFault sf) {
            throw sf;
        } catch (Exception e) {
            SecurityException se = new SecurityException(e);
            throw se.getAsSoapFault();
        }

        try {
            final byte[] certificateRequest = request.getActivationAgreement().getCertificateRequest();
            final String functionIdentification = activationHeader.value.getFunctionIdentification();
            final X509Certificate customerCertificate = issueCertificate(certificateRequest, functionIdentification);

            CorporateMessage cm = new CorporateMessage();
            cm.setContent(buildCertificateChain(getIntermediateCACertificate(), customerCertificate).getBytes());
            cm.setCompressed(BigInteger.ZERO);
            cm.setMimeType(MIMEType.PEM.getName());
            cm.setFormat("text");
            cm.setSender("MOCK");
            cm.setSeveralMessages(false);
            cm.setEndToEndMessageId(activationHeader.value.getEndToEndMessageId());
            cm.setDescription("Returning client certificate");

            activateServiceAgreementResponse.setCorporateMessage(cm);

            AddDuration.Add(technicalAddress, "MockServer - activateServiceAgreement response sent");

            return activateServiceAgreementResponse;
        } catch (IOException e) {
            throw logAndBuildFault(e);
        } catch (InvalidKeySpecException e) {
            throw logAndBuildFault(e);
        } catch (NoSuchAlgorithmException e) {
            throw logAndBuildFault(e);
        } catch (KeyStoreException e) {
            throw logAndBuildFault(e);
        } catch (CertificateException e) {
            throw logAndBuildFault(e);
        } catch (UnrecoverableKeyException e) {
            throw logAndBuildFault(e);
        } catch (InvalidKeyException e) {
            throw logAndBuildFault(e);
        } catch (NoSuchProviderException e) {
            throw logAndBuildFault(e);
        } catch (SignatureException e) {
            throw logAndBuildFault(e);
        } catch (OperatorCreationException e) {
            throw logAndBuildFault(e);
        }
    }

    private SoapFault logAndBuildFault(Exception exception) {
        logger.error(exception);
        return new SoapFault(exception.getMessage(), SoapFault.FAULT_CODE_SERVER);
    }

    /**
     * Log the incoming header information from the activationHeader.
     * 
     * @param activationHeader
     *            Header information
     */
    private void logIncoming(ActivationHeader activationHeader) {
        if (activationHeader == null) {
            String eMsg = "Missing ActivationHeader !";
            logger.error(eMsg);
            throw new SoapFault(eMsg, SoapFault.FAULT_CODE_SERVER);

        } else {
            logger.debug("Incoming with end2endmsgid: " + activationHeader.getEndToEndMessageId());
        }
    }

    /**
     * Validate the content.
     * 
     * @param parameters
     *            ActivateServiceAgreement parameters
     * @param activationHeader
     *            Header information
     * @throws IOException
     * @see IOException
     * @throws SecurityException
     * @see SecurityException
     */
    private void validateContent(ActivateServiceAgreement parameters, Holder<ActivationHeader> activationHeader)
            throws IOException, SecurityException {
        String activationCode = PropertiesLoaderUtils.loadAllProperties(Constants.PROPERTY_FILE).getProperty(
                "dk.bankconnect.server.valid.activationcode");
        byte[] activationcodeBytes = parameters.getActivationAgreement().getActivationCode();
        String ac = new String(activationcodeBytes);
        if (ac.matches(activationCode)) {
            logger.debug("Activationcode has been validated");
        } else {
            Exception e = new Exception("Activationcode not correct");
            SecurityException se = new SecurityException(e);
            se.setErrorcode(BankConnectConstants.IDENTIFICATION_ERROR);
            throw se.getAsSoapFault();
        }
        byte[] certificateRequest = parameters.getActivationAgreement().getCertificateRequest();
        SecurityService ssi = new SecurityServiceImpl();
        ssi.validatePKCS10Request(certificateRequest);
        ActivationIdentification ai = new ActivationIdentification(new PKCS10CertificationRequest(certificateRequest));
        if (((!ai.getActivationCode().equals(ac)) || (!ai.getFunctionIdentification().equals(
                activationHeader.value.getFunctionIdentification())))) {
            Exception e = new Exception(
                    "Activationcode or functionidentification does not correspond to value in PKCS10Request");
            SecurityException se = new SecurityException(e);
            se.setErrorcode(BankConnectConstants.IDENTIFICATION_ERROR);
            throw se.getAsSoapFault();
        }
    }

    /**
     * Get customer account report.
     * 
     * @param parameters
     *            GetCustomerAccountReport parameters
     * @param technicalAddress
     *            IpAddress and ipPort
     * @param serviceHeader
     *            Header information
     * @return the customer account report response object
     */
    @Override
    public GetCustomerAccountReportResponse getCustomerAccountReport(GetCustomerAccountReport parameters,
            Holder<TechnicalAddress> technicalAddress, Holder<ServiceHeader> serviceHeader) {
        logger.debug("GetCustomerAccountReportResponse has been invoked");
        GetCustomerAccountReportResponse customerAccountReportResponse = new GetCustomerAccountReportResponse();
        AddDuration.Add(technicalAddress, "MockServer - getCustomerAccountReport request received");
        try {
            logIncoming(serviceHeader.value);
            customerAccountReportResponse.setCorporateMessage(getCorporateMessageFromFile(getMockServerPath()
                    + "output/default-getCustomerAccountReport.xml"));

            AddDuration.Add(technicalAddress, "MockServer - getCustomerAccountReport response sent");
        } catch (SoapFault sf) {
            throw sf;
        } catch (Exception e) {
            SecurityException se = new SecurityException(e);
            throw se.getAsSoapFault();
        }

        return customerAccountReportResponse;
    }

    /**
     * Validate the content of the payment Message.
     * 
     * @param paymentMessage
     */
    private void validateContent(PaymentMessage paymentMessage) {
        String formatName = paymentMessage.getFormat();
        String mimeType = paymentMessage.getMimeType();
        String characterEncoding = null;
        String compressionName = paymentMessage.getCompressed().toString();
        byte[] content = paymentMessage.getContent();
        if (content.length < 1) {
            logger.error("No Content");
        }

        try {
            DocumentSource documentSource = ValidateContent.createContentDocumentSource(formatName, mimeType,
                    characterEncoding, compressionName, content, Constants.contentDecompressionLimit);

            if (documentSource != null) {
                validateContent(documentSource);
            }
        } catch (IOException ex) {
            SecurityException se = new SecurityException(ex);
            throw se.getAsSoapFault();
        }
    }

    /**
     * Validate the content of the documentSource.
     * 
     * @param documentSource
     * @throws IOException
     */
    private void validateContent(DocumentSource documentSource) throws IOException {
        if (Constants.validateContentByXMLSchema) {
            ValidateContent
                    .validateContentByXMLSchema(documentSource, Constants.validateContentByXMLSchema_FailOnError);
        }

        if (Constants.validateContentByCGIRules) {
            ValidateContent.validateContentByCGIRules(documentSource, Constants.validateContentByCGIRules_FailOnError);
        }
    }

    /**
     * Returns "now" - an XML formated gregorian calendar date
     * 
     * @return date of "now"
     * @throws DatatypeConfigurationException
     */
    private XMLGregorianCalendar getNow() throws DatatypeConfigurationException {
        GregorianCalendar gregorianCalendar = new GregorianCalendar();
        XMLGregorianCalendar now = DatatypeFactory.newInstance().newXMLGregorianCalendar(gregorianCalendar);
        return now;
    }

}
