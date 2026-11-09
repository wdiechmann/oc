package dk.bankconnect.client;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.PrintWriter;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.UnrecoverableKeyException;
import java.security.cert.CertificateException;
import java.util.GregorianCalendar;
import java.util.Properties;
import java.util.UUID;

import javax.xml.datatype.DatatypeConfigurationException;
import javax.xml.datatype.DatatypeFactory;
import javax.xml.datatype.XMLGregorianCalendar;

import org.apache.commons.logging.Log;
import org.apache.cxf.interceptor.LoggingInInterceptor;
import org.apache.cxf.interceptor.LoggingOutInterceptor;
import org.apache.cxf.jaxws.JaxWsProxyFactoryBean;
import org.springframework.core.io.support.PropertiesLoaderUtils;

import dk.bankconnect.schema._2014.ActivationHeader;
import dk.bankconnect.schema._2014.CorporateService;
import dk.bankconnect.schema._2014.ErpInformation;
import dk.bankconnect.schema._2014.ObjectFactory;
import dk.bankconnect.schema._2014.OrganisationIdentification;
import dk.bankconnect.schema._2014.ServiceHeader;
import dk.bankconnect.schema._2014.TechnicalAddress;

public class BankConnectClient {

    protected static String FUNCTION_ID;
    protected Log logger;
    protected JaxWsProxyFactoryBean factory = new JaxWsProxyFactoryBean();
    protected Properties clientProperties;
    protected CorporateService client = null;
    protected ObjectFactory bankConnectFactory = new ObjectFactory();
    
    /**
     * Instantiates a new bank connect client.
     * The constructor of the BankConnectClient sets up the global variables and properties. 
     * 
     * @throws IOException
     *              I/O exception
     * @throws KeyStoreException
     *              An error occurred while accessing the keystore
     * @throws NoSuchAlgorithmException
     *              The encryption algorithm does not exist
     * @throws CertificateException
     *              Certificate exception
     * @throws UnrecoverableKeyException
     *              Unable to recover the key
     */
    public BankConnectClient() throws IOException, KeyStoreException, NoSuchAlgorithmException, CertificateException, UnrecoverableKeyException {
        clientProperties = PropertiesLoaderUtils.loadAllProperties("client.properties");
        FUNCTION_ID = clientProperties.getProperty("dk.bankconnect.server.valid.functionidentification");
    }
    
    /**
     * Sets up the activation header
     * 
     * @return an ActivationHeader object @see
     *         dk.bankconnect.schema._2014.ActivationHeader
     * @throws DatatypeConfigurationException
     *              Data type configuration exception
     */
    protected ActivationHeader getActivationHeader() throws DatatypeConfigurationException {
        ActivationHeader ah = bankConnectFactory.createActivationHeader();
        ah.setCreateDateTime(getNow());
        ah.setErpInformation(bankConnectFactory.createErpInformation());
        ah.setEndToEndMessageId(getMessageId());
        ah.setFunctionIdentification(FUNCTION_ID);
        OrganisationIdentification oi = bankConnectFactory.createOrganisationIdentification();
        oi.setIsoCountryCode("DK");
        oi.setMainRegistrationNumber("8079");
        ah.setOrganisationIdentification(oi);
        return ah;
    }

    /**
     * Sets up the service header
     * 
     * @return a ServiceHeader object @see
     *         dk.bankconnect.schema._2014.ServiceHeader
     * @throws DatatypeConfigurationException
     *              Data type configuration exception
     */
    protected ServiceHeader getServiceHeader() throws DatatypeConfigurationException {
        ServiceHeader serviceHeader = new ServiceHeader();
        OrganisationIdentification oi = new OrganisationIdentification();
        oi.setMainRegistrationNumber("10");
        oi.setIsoCountryCode("DK");
        serviceHeader.setOrganisationIdentification(oi);
        ErpInformation erpInformation = bankConnectFactory.createErpInformation();
        erpInformation.setErpsystem("Client");
        erpInformation.setErpversion("1.0");
        serviceHeader.setErpInformation(erpInformation);
        serviceHeader.setFormat("ISO20022");
        serviceHeader.setFunctionIdentification(FUNCTION_ID);
        serviceHeader.setEndToEndMessageId(getMessageId());
        serviceHeader.setCreateDateTime(getNow());
        return serviceHeader;
    }

    /**
     * Returns the technical address to be used in the header
     * 
     * @return the technical address object
     */
    protected TechnicalAddress getTechnicalAddress() {
        TechnicalAddress technicalAddress = bankConnectFactory.createTechnicalAddress();
        return technicalAddress;
    }
    
    /**
     * Returns the end-to-end message id
     * 
     * @return the message id
     */
    protected String getMessageId() {
        UUID endToEndMessageId = UUID.randomUUID();
        return endToEndMessageId.toString();
    }
    
    /**
     * Enable debug logging
     * @param factory
     *              The factory object
     * @throws FileNotFoundException
     *              File not found exception
     */
    protected void enableDebugLogging(JaxWsProxyFactoryBean factory) throws FileNotFoundException {
        File soapOut = new File("soap-out.log");
        logger.info("Logging enabled - see soap-out.log and soap-in.log in folder: "+soapOut.getAbsolutePath());
        LoggingOutInterceptor loggingOuterceptor = new LoggingOutInterceptor(new PrintWriter(soapOut));
        LoggingInInterceptor loggingInterceptor = new LoggingInInterceptor(new PrintWriter(new File("soap-in.log")));
        factory.getInInterceptors().add(loggingInterceptor);
        factory.getOutInterceptors().add(loggingOuterceptor);
    }

    /**
     * Returns "now" - an XML formated gregorian calendar date
     * 
     * @return date of "now"
     * @throws DatatypeConfigurationException
     *              Data type configuration exception
     */
    protected XMLGregorianCalendar getNow() throws DatatypeConfigurationException {
        GregorianCalendar gregorianCalendar = new GregorianCalendar();
        XMLGregorianCalendar now = DatatypeFactory.newInstance().newXMLGregorianCalendar(gregorianCalendar);
        return now;
    }
}
