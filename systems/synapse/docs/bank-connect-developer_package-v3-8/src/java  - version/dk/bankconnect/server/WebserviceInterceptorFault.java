package dk.bankconnect.server;

import java.io.IOException;
import java.io.InputStream;
import java.security.Key;
import java.security.cert.X509Certificate;
import java.util.Properties;

import javax.xml.bind.JAXBException;
import javax.xml.parsers.ParserConfigurationException;
import javax.xml.transform.stream.StreamSource;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.cxf.binding.soap.SoapFault;
import org.apache.log4j.Logger;
import org.springframework.core.io.support.PropertiesLoaderUtils;
import org.w3c.dom.Document;
import org.xml.sax.SAXException;

import dk.bankconnect.BankConnectConstants;
import dk.bankconnect.certificate.CertificateService;
import dk.bankconnect.certificate.CertificateServiceImpl;
import dk.bankconnect.schema._2014.ServiceHeader;
import dk.bankconnect.security.MessageChangeInterceptor;
import dk.bankconnect.security.SecurityException;
import dk.bankconnect.security.SecurityServiceImpl;
import dk.bankconnect.server.config.Constants;

/**
 * The WebserviceInterceptorInFault class extends the AbstractSoapInterceptor
 * class.
 */
public class WebserviceInterceptorFault extends MessageChangeInterceptor {
    private Log logger = LogFactory.getFactory().getInstance(WebserviceInterceptorFault.class);

    protected byte[] encryptionCertificate;
    protected byte[] signingCertificate;
    protected byte[] signingKey;

    /**
     * Get the logger object from this class.
     */
    @Override
    protected Logger getLogger() {
        return Logger.getLogger(this.getClass());
    }    
    
    /**
     * Validate the service header.
     * 
     * @param serviceHeader
     *            Head information
     * @throws IOException
     * @see IOException
     * @throws JAXBException
     *             JAXBException
     * @throws ParserConfigurationException
     *             ParserConfigurationException
     * @throws SoapFault
     *             SoapFault
     * @throws SAXException
     *             SAXException
     */
    private void checkHeader(ServiceHeader serviceHeader) throws JAXBException {
        if (serviceHeader.getFunctionIdentification().contains("exception")) {
            SoapFault sf = readExceptionFromFile(serviceHeader.getFunctionIdentification() + ".xml");
            throw sf;
        }
    }

    /**
     * Read exception from file.
     * 
     * @param fileName
     *            The from file
     * @return SoapFault
     * @throws JAXBException
     *             JAXBException
     */
    private SoapFault readExceptionFromFile(String fileName) throws JAXBException {
        SoapFault sf =  new SoapFault("BankConnect",SoapFault.FAULT_CODE_SERVER);
        StreamSource fileInput = null;
        InputStream inputStream = this.getClass().getClassLoader()
                .getResourceAsStream(Constants.MOCKSERVERPATH + "output/" + fileName);
        if (inputStream != null) {
            logger.debug("File found: " + fileName);
            fileInput = new StreamSource(inputStream);
        } else {
            logger.debug("File NOT found: " + fileName);
            fileName = Constants.MOCKSERVERPATH + "output/default-exception.xml";
            fileInput = new StreamSource(this.getClass().getClassLoader().getResourceAsStream(fileName));
            logger.debug("Setting to default file : " + fileName);
        }
        sf.setMessage("500##Internal error – contact Bank Connect support");
        return sf; 
    }

    @Override
    protected Document changeOutboundMessage(Document currentEnvelope, Boolean addSecurity) throws SecurityException {
        Document securedMessage = null;
        if (addSecurity) {
            getLogger().debug(this.getClass().getName() + " has been invoked");
            try {
                CertificateService csi = new CertificateServiceImpl();
                SecurityServiceImpl si = new SecurityServiceImpl();
                Properties properties = PropertiesLoaderUtils.loadAllProperties(Constants.PROPERTY_FILE);
                String signingCertificate = properties
                        .getProperty("dk.bankconnect.security.bankconnectcrypto.signing.certificate");
                String signingKey = properties.getProperty("dk.bankconnect.security.bankconnectcrypto.private.key");

                X509Certificate signCert = csi.getCertificateFromKeystore(null, signingCertificate);
                Key signKey = csi.getKeyFromKeystore(null, signingKey);
                if (encryptionCertificate == null) {
                    String encryptionKey = properties.getProperty("dk.bankconnect.security.bankconnectcrypto.decryption.certificate");
                    encryptionCertificate = csi.getCertificateFromKeystore(null, encryptionKey).getEncoded();
                }
                securedMessage = si.wrapServerSoapMessage(currentEnvelope, signCert.getEncoded(), signKey.getEncoded(),
                        encryptionCertificate);
            } catch (Exception e) {
                getLogger().error(e);
                SecurityException securityException = new SecurityException(e);
                securityException.setErrorcode(BankConnectConstants.INTERNAL_SERVER);
                throw securityException.getAsSoapFault();
            }
        }
        return securedMessage;
    }

    @Override
    protected String changeInboundMessage(String currentEnvelope) {
        // TODO Auto-generated method stub
        return null;
    }
}
